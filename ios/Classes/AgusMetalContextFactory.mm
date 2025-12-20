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
        : dp::metal::MetalBaseContext(device, screenSize, [renderTexture]() -> id<CAMetalDrawable> {
            // Return our fake drawable wrapping the texture
            if (!g_currentDrawable || g_currentDrawable.texture != renderTexture) {
                g_currentDrawable = [[AgusMetalDrawable alloc] initWithTexture:renderTexture];
            }
            return g_currentDrawable;
        })
        , m_renderTexture(renderTexture)
    {
        LOG(LINFO, ("DrawMetalContext created:", screenSize.x, "x", screenSize.y));
    }
    
    void SetRenderTexture(id<MTLTexture> texture, m2::PointU const & screenSize)
    {
        m_renderTexture = texture;
        // Update the global drawable
        g_currentDrawable = [[AgusMetalDrawable alloc] initWithTexture:texture];
        Resize(screenSize.x, screenSize.y);
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
    
    /// Override Present() - also notifies Flutter for initial frames
    /// This ensures the initial map content is displayed even if isActiveFrame
    /// isn't set during the very first few render cycles.
    void Present() override
    {
        // Call base class Present() to do the actual Metal rendering
        dp::metal::MetalBaseContext::Present();
        
        // For the first few frames after DrapeEngine creation, always notify Flutter
        // This handles the case where initial tiles are being loaded but isActiveFrame
        // might not be true yet. After initial frames, we rely on df::SetActiveFrameCallback.
        if (m_initialFrameCount > 0) {
            m_initialFrameCount--;
            agus_notify_frame_ready();
        }
    }
    
private:
    id<MTLTexture> m_renderTexture;
    int m_initialFrameCount = 120;  // Notify for ~2 seconds at 60fps to ensure initial content shows
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
