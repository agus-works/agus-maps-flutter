#import "AgusMetalContextFactory.h"

#include "base/assert.hpp"
#include "base/logging.hpp"

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

// Forward declaration for frame ready notification
extern "C" void agus_notify_frame_ready(void);

#pragma mark - AgusMetalDrawable

/// Fake CAMetalDrawable that wraps our CVPixelBuffer-backed texture
/// This allows us to use MetalBaseContext's rendering pipeline while
/// rendering to a texture instead of a CAMetalLayer.
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

- (void)present {
    // No-op: We don't present to a layer, Flutter will read from CVPixelBuffer
}

- (void)presentAtTime:(CFTimeInterval)presentationTime {
    // No-op
}

- (void)presentAfterMinimumDuration:(CFTimeInterval)duration {
    // No-op
}

- (void)addPresentedHandler:(MTLDrawablePresentedHandler)block {
    // Call the handler immediately since we're not presenting to screen
    if (block) {
        dispatch_async(dispatch_get_main_queue(), ^{
            block(self);
        });
    }
}

// Internal method called by MTLCommandBuffer's presentDrawable:
// This is a private API that CAMetalDrawable implements
- (void)addPresentScheduledHandler:(void (^)(id<MTLDrawable>))block {
    // Call the handler immediately since we don't schedule presentation
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
    
    /// Override Present() - no longer notifies Flutter here
    /// Frame notifications are now handled via df::SetActiveFrameCallback
    /// which only triggers when isActiveFrame is true in FrontendRenderer
    void Present() override
    {
        // Call base class Present() to do the actual Metal rendering
        dp::metal::MetalBaseContext::Present();
        
        // Note: Frame notification moved to df::SetActiveFrameCallback
        // This ensures we only notify Flutter when map content actually changed,
        // not on every Present() call (which happens even when suspended)
    }
    
private:
    id<MTLTexture> m_renderTexture;
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
