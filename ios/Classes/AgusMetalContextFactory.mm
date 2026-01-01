#import "AgusMetalContextFactory.h"

#include "base/assert.hpp"
#include "base/logging.hpp"

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

// Forward declaration for frame ready notification
extern "C" void agus_notify_frame_ready(void);

#pragma mark - AgusMetalDrawable

/// Fake CAMetalDrawable that wraps our CVPixelBuffer-backed texture.
/// 
/// This allows us to use MetalBaseContext's rendering pipeline while
/// rendering to a texture instead of a CAMetalLayer.
///
/// IMPORTANT: CAMetalDrawable is normally created by CAMetalLayer and has
/// many private/internal methods that Metal framework calls. Apple's docs
/// explicitly say "Don't implement this protocol yourself." We do it anyway
/// because we need to render to a CVPixelBuffer for Flutter's FlutterTexture.
///
/// The private methods below were discovered through crash logs showing
/// "unrecognized selector" errors. They are called by Metal's internal
/// command buffer submission and drawable lifecycle management.
///
/// WHY CRASHES ONLY ON SECOND LAUNCH:
/// On first launch, the Framework and DrapeEngine are created fresh. Metal
/// initializes its internal state and may cache certain drawable behaviors.
/// On second launch (app reopened from background or cold start with cached
/// settings), Metal's internal state may take different code paths that
/// call these private methods. Additionally, Framework recreation triggers
/// different initialization sequences that exercise more of Metal's API.
@interface AgusMetalDrawable : NSObject <CAMetalDrawable>
@property (nonatomic, strong) id<MTLTexture> texture;
@property (nonatomic, strong) CAMetalLayer *layer;
- (instancetype)initWithTexture:(id<MTLTexture>)texture;
@end

@implementation AgusMetalDrawable

- (instancetype)initWithTexture:(id<MTLTexture>)texture {
    self = [super init];
    if (self) {
        _texture = texture;
        _layer = nil;  // We don't have a layer - rendering to texture
    }
    return self;
}

#pragma mark - MTLDrawable Protocol (Public)

- (void)present {
    // No-op: We don't present to a layer, Flutter will read from CVPixelBuffer
}

- (void)presentAtTime:(CFTimeInterval)presentationTime {
    // No-op: No vsync-based presentation needed
}

- (void)presentAfterMinimumDuration:(CFTimeInterval)duration {
    // No-op: No minimum duration presentation needed
}

- (void)addPresentedHandler:(MTLDrawablePresentedHandler)block {
    // Call the handler immediately since we're not presenting to screen
    if (block) {
        dispatch_async(dispatch_get_main_queue(), ^{
            block(self);
        });
    }
}

- (CFTimeInterval)presentedTime {
    return CACurrentMediaTime();
}

- (NSUInteger)drawableID {
    return 0;
}

#pragma mark - Private Methods (Metal Framework Internal)

// These methods are called internally by Metal framework during command buffer
// submission, drawable lifecycle management, and GPU synchronization.
// They are not documented but are required for a fake CAMetalDrawable to work.

/// Called by Metal to schedule presentation. Part of internal drawable queue management.
- (void)addPresentScheduledHandler:(void (^)(id<MTLDrawable>))block {
    if (block) {
        dispatch_async(dispatch_get_main_queue(), ^{
            block(self);
        });
    }
}

/// Called by Metal to mark the drawable as "touched" or in-use.
/// Part of drawable lifecycle tracking.
- (void)touch {
    // No-op: We manage our own lifecycle via CVPixelBuffer
}

/// Called by Metal to get the underlying object for internal management.
/// Returns self since we are the base object.
- (id)baseObject {
    return self;
}

/// Called by Metal to get the drawable's size for internal calculations.
- (CGSize)drawableSize {
    if (_texture) {
        return CGSizeMake(_texture.width, _texture.height);
    }
    return CGSizeZero;
}

/// Called by Metal for internal synchronization. Returns nil since we don't
/// use a CAMetalLayer's internal synchronization primitives.
- (id)iosurface {
    // Return nil - we manage IOSurface through CVPixelBuffer separately
    return nil;
}

/// Called by Metal to check if drawable is still valid for rendering.
- (BOOL)isValid {
    return _texture != nil;
}

/// Called by Metal for GPU-CPU synchronization during presentation.
- (void)setDrawableAvailableSemaphore:(dispatch_semaphore_t)semaphore {
    // No-op: We don't use semaphore-based synchronization
}

/// Called by Metal to get synchronization semaphore.
- (dispatch_semaphore_t)drawableAvailableSemaphore {
    return nil;
}

// Note: retainCount cannot be overridden under ARC - it's managed by the runtime

/// Called by Metal for drawable identification in debugging/profiling.
- (NSString *)description {
    return [NSString stringWithFormat:@"<AgusMetalDrawable: %p texture=%@>", self, _texture];
}

/// Called by Metal for debugging purposes.
- (NSString *)debugDescription {
    return [self description];
}

@end

#pragma mark - C++ Context Classes

// Static drawable holder for the draw context
static AgusMetalDrawable* g_currentDrawable = nil;

namespace
{

/// Draw context that renders to a CVPixelBuffer-backed texture
/// This enables zero-copy texture sharing with Flutter
class DrawMetalContext : public dp::metal::MetalBaseContext
{
public:
    DrawMetalContext(id<MTLDevice> device, id<MTLTexture> renderTexture, m2::PointU const & screenSize)
        : dp::metal::MetalBaseContext(device, screenSize, []() -> id<CAMetalDrawable> {
            // IMPORTANT: Always return the current global drawable.
            // Do NOT capture renderTexture by value here - SetRenderTexture updates
            // g_currentDrawable when the pixel buffer is resized, and we must use
            // the updated drawable, not recreate one from a stale captured texture.
            return g_currentDrawable;
        })
        , m_renderTexture(renderTexture)
    {
        // Initialize the global drawable with the initial texture
        g_currentDrawable = [[AgusMetalDrawable alloc] initWithTexture:renderTexture];
        LOG(LINFO, ("DrawMetalContext created:", screenSize.x, "x", screenSize.y));
    }
    
    void SetRenderTexture(id<MTLTexture> texture, m2::PointU const & screenSize)
    {
        m_renderTexture = texture;
        // Update the global drawable
        g_currentDrawable = [[AgusMetalDrawable alloc] initWithTexture:texture];
        Resize(screenSize.x, screenSize.y);
        
        // Reset initial frame count to ensure we notify Flutter for the first few frames
        // after a resize/texture update. This is crucial for preventing white screens
        // when the surface is recreated (e.g. keyboard toggle).
        m_initialFrameCount = 120;
        
        LOG(LINFO, ("DrawMetalContext::SetRenderTexture updated to", screenSize.x, "x", screenSize.y));
    }
    
    void Resize(uint32_t w, uint32_t h) override
    {
        // For CVPixelBuffer-backed texture, resize is handled by recreating the buffer
        // The texture size is fixed once created
        dp::metal::MetalBaseContext::Resize(w, h);
        LOG(LDEBUG, ("DrawMetalContext resized:", w, "x", h));
    }
    
    id<MTLTexture> GetRenderTexture() const
    {
        return m_renderTexture;
    }
    
    bool Validate() override
    {
        static int validateCount = 0;
        validateCount++;
        if (validateCount <= 5 || validateCount % 300 == 0) {
            LOG(LINFO, ("DrawMetalContext::Validate() count:", validateCount, "returning true"));
        }
        return true;  // Always valid
    }
    
    bool BeginRendering() override
    {
        static int beginCount = 0;
        beginCount++;
        
        // Track that we started a render cycle - Present should be called
        m_renderCycleActive = true;
        
        if (beginCount <= 5 || beginCount % 300 == 0) {
            LOG(LINFO, ("DrawMetalContext::BeginRendering() count:", beginCount, "returning true"));
        }
        return dp::metal::MetalBaseContext::BeginRendering();
    }
    
    void EndRendering() override
    {
        static int endCount = 0;
        endCount++;
        
        // Track EndRendering count for Present() diagnostic
        m_lastEndRenderingCount = endCount;
        
        if (endCount <= 5 || endCount % 300 == 0) {
            LOG(LINFO, ("DrawMetalContext::EndRendering() count:", endCount, "active render cycles:", m_activeRenderCycles));
        }
        dp::metal::MetalBaseContext::EndRendering();
        
        // Increment active render cycle count - this should be decremented by Present()
        m_activeRenderCycles++;
        
        // NOTE: Do NOT call Present() here on iOS!
        // DrapeEngine uses multiple render passes per frame:
        //   Pass 1: Background/land color
        //   Pass 2: Roads, boundaries
        //   Pass 3: Labels, icons
        //   ... etc
        // Each pass calls BeginRendering → EndRendering.
        // Present() should only be called ONCE after ALL passes are done.
        // 
        // DrapeEngine DOES call Present() after the frame is complete.
        // Our Present() override handles the iOS-specific workarounds.
    }
    
    /// Override Present() - also notifies Flutter for initial frames
    /// This ensures the initial map content is displayed even if isActiveFrame
    /// isn't set during the very first few render cycles.
    void Present() override
    {
        // Debug: log present calls
        static int presentCount = 0;
        presentCount++;
        m_lastPresentCount = presentCount;
        
        // Mark render cycle complete
        m_renderCycleActive = false;
        
        // Decrement active render cycle count
        if (m_activeRenderCycles > 0)
            m_activeRenderCycles--;
        
        if (presentCount <= 5 || presentCount % 300 == 0) {
            LOG(LINFO, ("DrawMetalContext::Present() ENTER, count:", presentCount, 
                        "lastEndRendering:", m_lastEndRenderingCount,
                        "activeRenderCycles:", m_activeRenderCycles));
        }
        
        // WORKAROUND for iOS: We're rendering to an offscreen CVPixelBuffer-backed texture,
        // NOT to a CAMetalLayer/screen. The base MetalBaseContext::Present() does:
        // 1. presentDrawable - schedules drawable for screen presentation (BLOCKS for us!)
        // 2. commit - commits the command buffer
        // 3. waitUntilCompleted - waits for GPU (also blocks)
        //
        // For offscreen rendering, we:
        // 1. SKIP presentDrawable (it blocks on iOS)
        // 2. Add a completion handler to notify Flutter when GPU is DONE
        // 3. Commit the command buffer (non-blocking)
        
        // Request the frame drawable to ensure the base class state is consistent
        RequestFrameDrawable();
        
        // Check if we have a command buffer
        if (!m_frameCommandBuffer) {
            if (presentCount <= 5) {
                NSLog(@"[AgusMapsFlutter] Present() WARNING: No command buffer at count=%d", presentCount);
            }
            m_frameDrawable = nil;
            
            // Still notify Flutter for initial frames
            if (m_initialFrameCount > 0) {
                m_initialFrameCount--;
                agus_notify_frame_ready();
            }
            return;
        }
        
        // DO NOT call presentDrawable - it blocks on iOS because our fake drawable
        // doesn't properly integrate with the display system.
        // [m_frameCommandBuffer presentDrawable:m_frameDrawable]; // SKIP THIS!
        
        // Capture count for completion handler
        int currentCount = presentCount;
        bool notifyFlutter = (m_initialFrameCount > 0);
        if (notifyFlutter) {
            m_initialFrameCount--;
        }
        
        // Notify Flutter only after the GPU finishes the full command buffer.
        // Previously we signaled after waitUntilScheduled(), which fired while
        // later render passes were still executing. That showed only the land
        // fill color (first pass) without roads/labels on iOS. Using a
        // completion handler guarantees Flutter samples a fully rendered frame
        // without blocking the render thread.
        bool shouldNotify = (notifyFlutter || currentCount <= 120);
        if (shouldNotify) {
            id<MTLCommandBuffer> completionBuffer = m_frameCommandBuffer;
            [completionBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    agus_notify_frame_ready();
                });
            }];
        }
        
        // Commit the command buffer - this starts GPU execution
        [m_frameCommandBuffer commit];
        
        // Wait until scheduled so the IOSurface is queued before we clear it.
        [m_frameCommandBuffer waitUntilScheduled];
        
        // Clear for next frame (after waiting, so we don't nil before GPU uses it)
        m_frameDrawable = nil;
        m_frameCommandBuffer = nil;
        
        if (presentCount <= 5 || presentCount % 300 == 0) {
            LOG(LINFO, ("DrawMetalContext::Present() EXIT, count:", presentCount));
        }
    }
    
    /// Check if a render cycle was started but not completed with Present()
    bool IsRenderCycleIncomplete() const { return m_renderCycleActive; }
    
private:
    id<MTLTexture> m_renderTexture;
    int m_initialFrameCount = 120;  // Notify for ~2 seconds at 60fps to ensure initial content shows
    bool m_renderCycleActive = false;  // Track if BeginRendering was called without Present
    int m_activeRenderCycles = 0;  // Track number of render cycles that haven't completed Present()
    int m_lastEndRenderingCount = 0;  // Last EndRendering count for diagnostics
    int m_lastPresentCount = 0;  // Last Present count for diagnostics
};

/// Upload context for background texture uploads
/// Shares the Metal device with DrawMetalContext
/// This context is used for uploading textures/resources in background threads
class UploadMetalContext : public dp::metal::MetalBaseContext
{
public:
    explicit UploadMetalContext(id<MTLDevice> device)
        : dp::metal::MetalBaseContext(device, {}, []() -> id<CAMetalDrawable> {
            // Upload context should never request a drawable
            return nil;
        })
    {
        LOG(LINFO, ("UploadMetalContext created"));
    }
    
    // Upload context doesn't need presentation
    void Present() override {}
    
    // Upload context doesn't need to be made current (Metal has no context binding)
    void MakeCurrent() override {}
};

} // anonymous namespace

namespace agus {

AgusMetalContextFactory::AgusMetalContextFactory(CVPixelBufferRef pixelBuffer, m2::PointU const & screenSize)
    : m_metalDevice(nil)
    , m_textureCache(nullptr)
    , m_cvMetalTexture(nullptr)
    , m_renderTexture(nil)
    , m_screenSize(screenSize)
{
    LOG(LINFO, ("AgusMetalContextFactory: creating for", screenSize.x, "x", screenSize.y));
    
    // Create Metal device
    m_metalDevice = MTLCreateSystemDefaultDevice();
    if (!m_metalDevice)
    {
        LOG(LERROR, ("Failed to create Metal device"));
        return;
    }
    
    // Create texture cache for CVPixelBuffer -> MTLTexture conversion
    CVReturn status = CVMetalTextureCacheCreate(
        kCFAllocatorDefault,
        nil,
        m_metalDevice,
        nil,
        &m_textureCache
    );
    
    if (status != kCVReturnSuccess)
    {
        LOG(LERROR, ("Failed to create Metal texture cache:", status));
        return;
    }
    
    // Create texture from pixel buffer
    CreateTextureFromPixelBuffer(pixelBuffer, screenSize);
    
    // Create contexts
    if (m_renderTexture)
    {
        m_drawContext = make_unique_dp<DrawMetalContext>(m_metalDevice, m_renderTexture, screenSize);
        m_uploadContext = make_unique_dp<UploadMetalContext>(m_metalDevice);
    }
    
    LOG(LINFO, ("AgusMetalContextFactory: initialization complete"));
}

AgusMetalContextFactory::~AgusMetalContextFactory()
{
    CleanupTexture();
    
    if (m_textureCache)
    {
        CVMetalTextureCacheFlush(m_textureCache, 0);
        CFRelease(m_textureCache);
        m_textureCache = nullptr;
    }
    
    m_drawContext.reset();
    m_uploadContext.reset();
    m_metalDevice = nil;
    
    LOG(LINFO, ("AgusMetalContextFactory destroyed"));
}

void AgusMetalContextFactory::CreateTextureFromPixelBuffer(CVPixelBufferRef pixelBuffer, m2::PointU const & screenSize)
{
    if (!pixelBuffer || !m_textureCache)
    {
        LOG(LERROR, ("Cannot create texture: pixelBuffer or textureCache is null"));
        return;
    }
    
    CleanupTexture();
    
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    
    // Create Metal texture from CVPixelBuffer (zero-copy via IOSurface)
    CVReturn status = CVMetalTextureCacheCreateTextureFromImage(
        kCFAllocatorDefault,
        m_textureCache,
        pixelBuffer,
        nil,
        MTLPixelFormatBGRA8Unorm,
        width,
        height,
        0,  // plane index
        &m_cvMetalTexture
    );
    
    if (status != kCVReturnSuccess)
    {
        LOG(LERROR, ("Failed to create Metal texture from CVPixelBuffer:", status));
        return;
    }
    
    m_renderTexture = CVMetalTextureGetTexture(m_cvMetalTexture);
    m_screenSize = screenSize;
    
    LOG(LINFO, ("Metal texture created from CVPixelBuffer:", width, "x", height));
}

void AgusMetalContextFactory::CleanupTexture()
{
    m_renderTexture = nil;
    
    if (m_cvMetalTexture)
    {
        CFRelease(m_cvMetalTexture);
        m_cvMetalTexture = nullptr;
    }
}

void AgusMetalContextFactory::SetPixelBuffer(CVPixelBufferRef pixelBuffer, m2::PointU const & screenSize)
{
    CreateTextureFromPixelBuffer(pixelBuffer, screenSize);
    
    // Update draw context with new texture
    if (m_drawContext && m_renderTexture)
    {
        auto * drawCtx = static_cast<DrawMetalContext *>(m_drawContext.get());
        drawCtx->SetRenderTexture(m_renderTexture, screenSize);
    }
}

dp::GraphicsContext * AgusMetalContextFactory::GetDrawContext()
{
    return m_drawContext.get();
}

dp::GraphicsContext * AgusMetalContextFactory::GetResourcesUploadContext()
{
    return m_uploadContext.get();
}

void AgusMetalContextFactory::SetPresentAvailable(bool available)
{
    if (m_drawContext)
    {
        m_drawContext->SetPresentAvailable(available);
    }
}

id<MTLDevice> AgusMetalContextFactory::GetMetalDevice() const
{
    return m_metalDevice;
}

} // namespace agus
