#pragma once

/// AgusVulkanContextFactory.hpp
/// 
/// Windows Vulkan context factory for agus_maps_flutter.
/// This extends CoMaps' VulkanContextFactory to render to a D3D11 shared texture
/// for zero-copy integration with Flutter's texture system.

#ifdef _WIN32

#include "drape/vulkan/vulkan_context_factory.hpp"
#include "drape/vulkan/vulkan_base_context.hpp"
#include "drape/pointers.hpp"

#include <wrl/client.h>
#include <d3d11.h>
#include <dxgi1_2.h>

#include <vulkan/vulkan.h>
#include <vulkan/vulkan_win32.h>

#include <cstdint>

namespace agus {

/// Windows Vulkan context factory that renders to a D3D11 shared texture.
/// 
/// Architecture:
/// 1. Creates a D3D11 device and shared texture with NT handle
/// 2. Imports the D3D11 texture into Vulkan via VK_KHR_external_memory_win32
/// 3. DrapeEngine renders to VkImage backed by the shared memory
/// 4. Flutter reads from D3D11 texture for compositing (zero-copy)
/// 
/// This pattern mirrors iOS/macOS Metal implementation which uses
/// CVPixelBuffer + IOSurface for zero-copy texture sharing.
class AgusVulkanContextFactory : public dp::vulkan::VulkanContextFactory
{
public:
    /// Create context factory with specified surface dimensions
    /// @param width Surface width in pixels
    /// @param height Surface height in pixels
    AgusVulkanContextFactory(uint32_t width, uint32_t height);
    
    ~AgusVulkanContextFactory() override;
    
    /// Check if factory was successfully initialized
    bool IsValid() const;
    
    /// Get D3D11 shared texture handle for Flutter
    /// Flutter will open this handle to sample the rendered content
    HANDLE GetSharedTextureHandle() const { return m_sharedHandle; }
    
    /// Get D3D11 device (for Flutter interop)
    ID3D11Device* GetD3D11Device() const { return m_d3dDevice.Get(); }
    
    /// Get D3D11 texture (for Flutter GPU surface descriptor)
    ID3D11Texture2D* GetD3D11Texture() const { return m_d3dTexture.Get(); }
    
    /// Update surface size (recreates textures)
    /// @param width New width in pixels
    /// @param height New height in pixels
    void UpdateSurfaceSize(uint32_t width, uint32_t height);
    
    /// Get current surface dimensions
    int GetWidth() const { return static_cast<int>(m_width); }
    int GetHeight() const { return static_cast<int>(m_height); }
    
    /// dp::GraphicsContextFactory overrides
    dp::GraphicsContext* GetDrawContext() override;
    dp::GraphicsContext* GetResourcesUploadContext() override;
    bool IsDrawContextCreated() const override;
    bool IsUploadContextCreated() const override;
    void SetPresentAvailable(bool available) override;
    
private:
    /// Initialize D3D11 device and shared texture
    bool InitializeD3D11();
    
    /// Create D3D11 shared texture
    bool CreateSharedTexture(uint32_t width, uint32_t height);
    
    /// Import D3D11 texture into Vulkan
    bool ImportTextureToVulkan();
    
    /// Create Vulkan image view and framebuffer
    bool CreateVulkanImageView();
    
    /// Cleanup all resources
    void Cleanup();
    
    /// Cleanup texture resources only (for resize)
    void CleanupTexture();
    
private:
    // Dimensions
    uint32_t m_width = 0;
    uint32_t m_height = 0;
    
    // D3D11 resources
    Microsoft::WRL::ComPtr<ID3D11Device> m_d3dDevice;
    Microsoft::WRL::ComPtr<ID3D11DeviceContext> m_d3dContext;
    Microsoft::WRL::ComPtr<ID3D11Texture2D> m_d3dTexture;
    HANDLE m_sharedHandle = nullptr;
    
    // Vulkan imported resources
    VkImage m_vulkanImage = VK_NULL_HANDLE;
    VkDeviceMemory m_vulkanMemory = VK_NULL_HANDLE;
    VkImageView m_vulkanImageView = VK_NULL_HANDLE;
    
    // Vulkan extension function pointers
    PFN_vkGetMemoryWin32HandlePropertiesKHR m_vkGetMemoryWin32HandlePropertiesKHR = nullptr;
    
    // Initialization state
    bool m_d3dInitialized = false;
    bool m_vulkanImported = false;
    
    // Initial frame counter for ensuring first frames are displayed
    int m_initialFrameCount = 120;  // ~2 seconds at 60fps
};

} // namespace agus

#endif // _WIN32
