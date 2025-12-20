#import "AgusMetalContextFactory.h"

#include "base/assert.hpp"
#include "base/logging.hpp"

namespace
{

/// Draw context that renders to a CVPixelBuffer-backed texture
/// This enables zero-copy texture sharing with Flutter
/// 
/// MetalBaseContext expects a DrawableRequest callback that returns
/// a CAMetalDrawable. Since we render to a texture (not a CAMetalLayer),
/// we provide a null callback and manage our render target directly.
class DrawMetalContext : public dp::metal::MetalBaseContext
{
public:
    DrawMetalContext(id<MTLDevice> device, id<MTLTexture> renderTexture, m2::PointU const & screenSize)
        : dp::metal::MetalBaseContext(device, screenSize, nullptr)  // null drawable request - we use texture
        , m_renderTexture(renderTexture)
    {
        LOG(LINFO, ("DrawMetalContext created:", screenSize.x, "x", screenSize.y));
    }
    
    void SetRenderTexture(id<MTLTexture> texture, m2::PointU const & screenSize)
    {
        m_renderTexture = texture;
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
        : dp::metal::MetalBaseContext(device, {}, nullptr)  // null drawable request - upload only
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
