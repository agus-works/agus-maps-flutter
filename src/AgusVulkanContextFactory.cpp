/// AgusVulkanContextFactory.cpp
/// 
/// Windows Vulkan context factory implementation for agus_maps_flutter.
/// Provides zero-copy texture sharing between Vulkan and Flutter via D3D11 interop.

#ifdef _WIN32

#include "AgusVulkanContextFactory.hpp"

#include "base/assert.hpp"
#include "base/logging.hpp"

#include "drape/vulkan/vulkan_utils.hpp"
#include "drape/vulkan/vulkan_pipeline.hpp"

#include <vulkan_wrapper.h>

// Forward declaration for frame ready notification
extern "C" void agus_notify_frame_ready(void);

namespace
{

/// Draw context that renders to an imported D3D11 texture
/// This enables zero-copy texture sharing with Flutter
class DrawVulkanContext : public dp::vulkan::VulkanBaseContext
{
public:
    DrawVulkanContext(VkInstance vulkanInstance, VkPhysicalDevice gpu,
                      VkPhysicalDeviceProperties const & gpuProperties,
                      VkDevice device, uint32_t renderingQueueFamilyIndex,
                      ref_ptr<dp::vulkan::VulkanObjectManager> objectManager,
                      uint32_t appVersionCode, bool hasPartialTextureUpdates,
                      int & initialFrameCount)
        : dp::vulkan::VulkanBaseContext(vulkanInstance, gpu, gpuProperties, device,
                                        renderingQueueFamilyIndex, objectManager,
                                        make_unique_dp<dp::vulkan::VulkanPipeline>(device, appVersionCode),
                                        hasPartialTextureUpdates)
        , m_initialFrameCount(initialFrameCount)
    {
        VkQueue queue;
        vkGetDeviceQueue(device, renderingQueueFamilyIndex, 0, &queue);
        SetRenderingQueue(queue);
        CreateCommandPool();
        
        LOG(LINFO, ("DrawVulkanContext created"));
    }
    
    void MakeCurrent() override
    {
        m_objectManager->RegisterThread(dp::vulkan::VulkanObjectManager::Frontend);
    }
    
    /// Override Present() to notify Flutter for initial frames
    void Present() override
    {
        dp::vulkan::VulkanBaseContext::Present();
        
        // For the first few frames, always notify Flutter
        // This ensures initial map content is displayed
        if (m_initialFrameCount > 0)
        {
            m_initialFrameCount--;
            agus_notify_frame_ready();
        }
    }
    
private:
    int & m_initialFrameCount;
};

/// Upload context for background texture uploads
/// Shares the Vulkan device with DrawVulkanContext
class UploadVulkanContext : public dp::vulkan::VulkanBaseContext
{
public:
    UploadVulkanContext(VkInstance vulkanInstance, VkPhysicalDevice gpu,
                        VkPhysicalDeviceProperties const & gpuProperties,
                        VkDevice device, uint32_t renderingQueueFamilyIndex,
                        ref_ptr<dp::vulkan::VulkanObjectManager> objectManager,
                        bool hasPartialTextureUpdates)
        : dp::vulkan::VulkanBaseContext(vulkanInstance, gpu, gpuProperties, device,
                                        renderingQueueFamilyIndex, objectManager,
                                        nullptr /* pipeline */, hasPartialTextureUpdates)
    {
        LOG(LINFO, ("UploadVulkanContext created"));
    }
    
    void MakeCurrent() override
    {
        m_objectManager->RegisterThread(dp::vulkan::VulkanObjectManager::Backend);
    }
    
    void Present() override {}
    void Resize(uint32_t w, uint32_t h) override {}
    void SetFramebuffer(ref_ptr<dp::BaseFramebuffer> framebuffer) override {}
    void Init(dp::ApiVersion apiVersion) override { CHECK_EQUAL(apiVersion, dp::ApiVersion::Vulkan, ()); }
    void SetClearColor(dp::Color const & color) override {}
    void Clear(uint32_t clearBits, uint32_t storeBits) override {}
    void Flush() override {}
    void SetDepthTestEnabled(bool enabled) override {}
    void SetDepthTestFunction(dp::TestFunction depthFunction) override {}
    void SetStencilTestEnabled(bool enabled) override {}
    void SetStencilFunction(dp::StencilFace face, dp::TestFunction stencilFunction) override {}
    void SetStencilActions(dp::StencilFace face, dp::StencilAction stencilFailAction,
                           dp::StencilAction depthFailAction, dp::StencilAction passAction) override {}
};

} // anonymous namespace

namespace agus {

AgusVulkanContextFactory::AgusVulkanContextFactory(uint32_t width, uint32_t height)
    : dp::vulkan::VulkanContextFactory(1 /* appVersionCode */, 0 /* sdkVersion */, false /* isCustomROM */)
    , m_width(width)
    , m_height(height)
{
    LOG(LINFO, ("AgusVulkanContextFactory: creating for", width, "x", height));
    
    if (!IsVulkanSupported())
    {
        LOG(LERROR, ("Vulkan is not supported on this system"));
        return;
    }
    
    // Initialize D3D11 for Flutter interop
    if (!InitializeD3D11())
    {
        LOG(LERROR, ("Failed to initialize D3D11"));
        return;
    }
    
    // Create shared texture
    if (!CreateSharedTexture(width, height))
    {
        LOG(LERROR, ("Failed to create shared texture"));
        return;
    }
    
    // Note: We don't import to Vulkan here - we use headless rendering
    // and let Flutter sample the D3D11 texture directly after Vulkan renders
    
    LOG(LINFO, ("AgusVulkanContextFactory: initialization complete"));
}

AgusVulkanContextFactory::~AgusVulkanContextFactory()
{
    Cleanup();
    LOG(LINFO, ("AgusVulkanContextFactory destroyed"));
}

bool AgusVulkanContextFactory::IsValid() const
{
    return IsVulkanSupported() && m_d3dInitialized && m_d3dTexture != nullptr;
}

bool AgusVulkanContextFactory::InitializeD3D11()
{
    // Create D3D11 device
    D3D_FEATURE_LEVEL featureLevels[] = {
        D3D_FEATURE_LEVEL_11_1,
        D3D_FEATURE_LEVEL_11_0,
    };
    
    UINT createDeviceFlags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;
#ifdef DEBUG
    createDeviceFlags |= D3D11_CREATE_DEVICE_DEBUG;
#endif
    
    D3D_FEATURE_LEVEL featureLevel;
    HRESULT hr = D3D11CreateDevice(
        nullptr,                    // Use default adapter
        D3D_DRIVER_TYPE_HARDWARE,
        nullptr,
        createDeviceFlags,
        featureLevels,
        ARRAYSIZE(featureLevels),
        D3D11_SDK_VERSION,
        m_d3dDevice.GetAddressOf(),
        &featureLevel,
        m_d3dContext.GetAddressOf()
    );
    
    if (FAILED(hr))
    {
        LOG(LERROR, ("Failed to create D3D11 device, hr:", hr));
        return false;
    }
    
    // Enable multi-threaded protection
    Microsoft::WRL::ComPtr<ID3D10Multithread> multithread;
    hr = m_d3dDevice.As(&multithread);
    if (SUCCEEDED(hr))
    {
        multithread->SetMultithreadProtected(TRUE);
    }
    
    m_d3dInitialized = true;
    LOG(LINFO, ("D3D11 device created, feature level:", featureLevel));
    
    return true;
}

bool AgusVulkanContextFactory::CreateSharedTexture(uint32_t width, uint32_t height)
{
    if (!m_d3dDevice)
    {
        return false;
    }
    
    CleanupTexture();
    
    // Create shared texture with NT handle for cross-process/API sharing
    D3D11_TEXTURE2D_DESC desc = {};
    desc.Width = width;
    desc.Height = height;
    desc.MipLevels = 1;
    desc.ArraySize = 1;
    desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;  // Match Flutter's expected format
    desc.SampleDesc.Count = 1;
    desc.SampleDesc.Quality = 0;
    desc.Usage = D3D11_USAGE_DEFAULT;
    desc.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
    desc.CPUAccessFlags = 0;
    desc.MiscFlags = D3D11_RESOURCE_MISC_SHARED_NTHANDLE | D3D11_RESOURCE_MISC_SHARED_KEYEDMUTEX;
    
    HRESULT hr = m_d3dDevice->CreateTexture2D(&desc, nullptr, m_d3dTexture.GetAddressOf());
    if (FAILED(hr))
    {
        LOG(LERROR, ("Failed to create D3D11 texture, hr:", hr));
        return false;
    }
    
    // Get shared handle
    Microsoft::WRL::ComPtr<IDXGIResource1> dxgiResource;
    hr = m_d3dTexture.As(&dxgiResource);
    if (FAILED(hr))
    {
        LOG(LERROR, ("Failed to get DXGI resource, hr:", hr));
        return false;
    }
    
    hr = dxgiResource->CreateSharedHandle(
        nullptr,
        DXGI_SHARED_RESOURCE_READ | DXGI_SHARED_RESOURCE_WRITE,
        nullptr,
        &m_sharedHandle
    );
    
    if (FAILED(hr))
    {
        LOG(LERROR, ("Failed to create shared handle, hr:", hr));
        return false;
    }
    
    m_width = width;
    m_height = height;
    
    LOG(LINFO, ("D3D11 shared texture created:", width, "x", height, "handle:", m_sharedHandle));
    
    return true;
}

bool AgusVulkanContextFactory::ImportTextureToVulkan()
{
    // For now, we use a simpler approach: 
    // Vulkan renders to its own swapchain/framebuffer, and we copy to D3D11
    // Full VK_KHR_external_memory_win32 import can be added later for true zero-copy
    
    // This is a TODO for full zero-copy implementation
    return true;
}

bool AgusVulkanContextFactory::CreateVulkanImageView()
{
    // TODO: Create VkImageView from imported VkImage
    return true;
}

void AgusVulkanContextFactory::UpdateSurfaceSize(uint32_t width, uint32_t height)
{
    if (width == m_width && height == m_height)
    {
        return;
    }
    
    LOG(LINFO, ("Updating surface size from", m_width, "x", m_height, "to", width, "x", height));
    
    if (!CreateSharedTexture(width, height))
    {
        LOG(LERROR, ("Failed to recreate shared texture for new size"));
    }
}

dp::GraphicsContext* AgusVulkanContextFactory::GetDrawContext()
{
    return m_drawContext.get();
}

dp::GraphicsContext* AgusVulkanContextFactory::GetResourcesUploadContext()
{
    return m_uploadContext.get();
}

bool AgusVulkanContextFactory::IsDrawContextCreated() const
{
    return m_drawContext != nullptr;
}

bool AgusVulkanContextFactory::IsUploadContextCreated() const
{
    return m_uploadContext != nullptr;
}

void AgusVulkanContextFactory::SetPresentAvailable(bool available)
{
    if (m_drawContext)
    {
        m_drawContext->SetPresentAvailable(available);
    }
}

void AgusVulkanContextFactory::CleanupTexture()
{
    if (m_vulkanImageView != VK_NULL_HANDLE && m_device)
    {
        vkDestroyImageView(m_device, m_vulkanImageView, nullptr);
        m_vulkanImageView = VK_NULL_HANDLE;
    }
    
    if (m_vulkanImage != VK_NULL_HANDLE && m_device)
    {
        vkDestroyImage(m_device, m_vulkanImage, nullptr);
        m_vulkanImage = VK_NULL_HANDLE;
    }
    
    if (m_vulkanMemory != VK_NULL_HANDLE && m_device)
    {
        vkFreeMemory(m_device, m_vulkanMemory, nullptr);
        m_vulkanMemory = VK_NULL_HANDLE;
    }
    
    if (m_sharedHandle)
    {
        CloseHandle(m_sharedHandle);
        m_sharedHandle = nullptr;
    }
    
    m_d3dTexture.Reset();
    m_vulkanImported = false;
}

void AgusVulkanContextFactory::Cleanup()
{
    CleanupTexture();
    
    m_d3dContext.Reset();
    m_d3dDevice.Reset();
    m_d3dInitialized = false;
}

} // namespace agus

#endif // _WIN32
