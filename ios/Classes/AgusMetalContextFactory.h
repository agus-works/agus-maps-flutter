#pragma once

#import <MetalKit/MetalKit.h>
#import <CoreVideo/CoreVideo.h>

#include "drape/graphics_context_factory.hpp"
#include "drape/metal/metal_base_context.hpp"
#include "drape/pointers.hpp"

namespace agus {

/// Metal context factory for Flutter integration
/// 
/// Unlike the standard CoMaps MetalContextFactory which renders to a CAMetalLayer,
/// this factory renders to a CVPixelBuffer-backed MTLTexture for zero-copy
/// sharing with Flutter's texture registry.
///
/// Architecture:
/// 1. Flutter creates CVPixelBuffer with kCVPixelBufferMetalCompatibilityKey
/// 2. This factory creates MTLTexture from CVPixelBuffer via CVMetalTextureCache
/// 3. CoMaps DrapeEngine renders to the MTLTexture
/// 4. Flutter samples the CVPixelBuffer directly (zero-copy via IOSurface)
class AgusMetalContextFactory : public dp::GraphicsContextFactory
{
public:
    /// Create factory with CVPixelBuffer target for Flutter texture sharing
    /// @param pixelBuffer CVPixelBuffer created by Flutter plugin (must have Metal compatibility)
    /// @param screenSize Initial screen size in pixels
    AgusMetalContextFactory(CVPixelBufferRef pixelBuffer, m2::PointU const & screenSize);
    
    ~AgusMetalContextFactory() override;
    
    // GraphicsContextFactory interface
    dp::GraphicsContext * GetDrawContext() override;
    dp::GraphicsContext * GetResourcesUploadContext() override;
    bool IsDrawContextCreated() const override { return m_drawContext != nullptr; }
    bool IsUploadContextCreated() const override { return m_uploadContext != nullptr; }
    void WaitForInitialization(dp::GraphicsContext * context) override {}
    void SetPresentAvailable(bool available) override;
    
    /// Update the pixel buffer target (e.g., on resize)
    void SetPixelBuffer(CVPixelBufferRef pixelBuffer, m2::PointU const & screenSize);
    
    /// Get the Metal device used by this factory
    id<MTLDevice> GetMetalDevice() const;
    
private:
    void CreateTextureFromPixelBuffer(CVPixelBufferRef pixelBuffer, m2::PointU const & screenSize);
    void CleanupTexture();
    
    drape_ptr<dp::metal::MetalBaseContext> m_drawContext;
    drape_ptr<dp::metal::MetalBaseContext> m_uploadContext;
    
    id<MTLDevice> m_metalDevice;
    CVMetalTextureCacheRef m_textureCache;
    CVMetalTextureRef m_cvMetalTexture;
    id<MTLTexture> m_renderTexture;
    
    m2::PointU m_screenSize;
};

} // namespace agus
