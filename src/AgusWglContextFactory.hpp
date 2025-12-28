#pragma once

#if defined(_WIN32) || defined(_WIN64)

#include "drape/graphics_context_factory.hpp"
#include "drape/drape_global.hpp"

#include <windows.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <wrl/client.h>
#include <GL/gl.h>

#include <memory>
#include <functional>
#include <atomic>
#include <mutex>

namespace agus
{

/**
 * @brief Windows OpenGL Context Factory for Flutter integration.
 * 
 * This class manages WGL (Windows OpenGL) contexts and provides
 * D3D11 shared texture interop for zero-copy Flutter texture sharing.
 * 
 * Architecture:
 * - Creates offscreen OpenGL context using WGL
 * - Renders CoMaps to an OpenGL texture
 * - Uses WGL_NV_DX_interop or pixel buffer copy to share with D3D11
 * - D3D11 texture shared with Flutter via DXGI handle
 */
class AgusWglContext;  // Forward declaration

class AgusWglContextFactory : public dp::GraphicsContextFactory
{
  friend class AgusWglContext;  // Allow AgusWglContext to access private members

public:
  AgusWglContextFactory(int width, int height);
  ~AgusWglContextFactory() override;

  // dp::GraphicsContextFactory interface
  dp::GraphicsContext * GetDrawContext() override;
  dp::GraphicsContext * GetResourcesUploadContext() override;
  bool IsDrawContextCreated() const override { return m_drawContext != nullptr; }
  bool IsUploadContextCreated() const override { return m_uploadContext != nullptr; }
  void WaitForInitialization(dp::GraphicsContext * context) override {}
  void SetPresentAvailable(bool available) override { m_presentAvailable = available; }

  // Surface management
  void SetSurfaceSize(int width, int height);
  int GetWidth() const { return m_width; }
  int GetHeight() const { return m_height; }

  // D3D11 interop for Flutter texture sharing
  HANDLE GetSharedTextureHandle() const { return m_sharedHandle; }
  ID3D11Device * GetD3D11Device() const { return m_d3dDevice.Get(); }
  ID3D11Texture2D * GetD3D11Texture() const { return m_sharedTexture.Get(); }

  // Frame synchronization
  void SetFrameCallback(std::function<void()> callback) { m_frameCallback = callback; }
  void OnFrameReady();

  // Copy rendered content to shared texture
  void CopyToSharedTexture();

  // Accessor for framebuffer ID (used by AgusWglContext)
  GLuint GetFramebufferID() const { return m_framebuffer; }

private:
  bool InitializeWGL();
  bool InitializeD3D11();
  bool CreateSharedTexture(int width, int height);
  void CleanupWGL();
  void CleanupD3D11();

  // WGL context
  HWND m_hiddenWindow = nullptr;
  HDC m_hdc = nullptr;
  HGLRC m_drawGlrc = nullptr;
  HGLRC m_uploadGlrc = nullptr;
  
  // OpenGL resources
  GLuint m_framebuffer = 0;
  GLuint m_renderTexture = 0;
  GLuint m_depthBuffer = 0;

  // D3D11 interop
  Microsoft::WRL::ComPtr<ID3D11Device> m_d3dDevice;
  Microsoft::WRL::ComPtr<ID3D11DeviceContext> m_d3dContext;
  Microsoft::WRL::ComPtr<ID3D11Texture2D> m_sharedTexture;
  Microsoft::WRL::ComPtr<ID3D11Texture2D> m_stagingTexture;
  HANDLE m_sharedHandle = nullptr;

  // Graphics contexts
  std::unique_ptr<dp::GraphicsContext> m_drawContext;
  std::unique_ptr<dp::GraphicsContext> m_uploadContext;

  // State
  int m_width = 0;
  int m_height = 0;
  std::atomic<bool> m_presentAvailable{true};
  std::function<void()> m_frameCallback;
  std::mutex m_mutex;
};

/**
 * @brief OpenGL graphics context wrapper for Windows WGL.
 */
class AgusWglContext : public dp::GraphicsContext
{
public:
  AgusWglContext(HDC hdc, HGLRC glrc, AgusWglContextFactory * factory, bool isDraw);
  ~AgusWglContext() override;

  // dp::GraphicsContext interface
  bool BeginRendering() override;
  void EndRendering() override;
  void Present() override;
  void MakeCurrent() override;
  void DoneCurrent() override;
  void SetFramebuffer(ref_ptr<dp::BaseFramebuffer> framebuffer) override;
  void ForgetFramebuffer(ref_ptr<dp::BaseFramebuffer> framebuffer) override;
  void ApplyFramebuffer(std::string const & framebufferLabel) override;
  void Init(dp::ApiVersion apiVersion) override;
  dp::ApiVersion GetApiVersion() const override { return dp::ApiVersion::OpenGLES3; }
  std::string GetRendererName() const override;
  std::string GetRendererVersion() const override;
  void PushDebugLabel(std::string const & label) override;
  void PopDebugLabel() override;
  void SetClearColor(dp::Color const & color) override;
  void Clear(uint32_t clearBits, uint32_t storeBits) override;
  void Flush() override;
  void SetViewport(uint32_t x, uint32_t y, uint32_t w, uint32_t h) override;
  void SetScissor(uint32_t x, uint32_t y, uint32_t w, uint32_t h) override;
  void SetDepthTestEnabled(bool enabled) override;
  void SetDepthTestFunction(dp::TestFunction depthFunction) override;
  void SetStencilTestEnabled(bool enabled) override;
  void SetStencilFunction(dp::StencilFace face, dp::TestFunction stencilFunction) override;
  void SetStencilActions(dp::StencilFace face, dp::StencilAction stencilFailAction,
                         dp::StencilAction depthFailAction, dp::StencilAction passAction) override;
  void SetStencilReferenceValue(uint32_t stencilReferenceValue) override;
  void SetCullingEnabled(bool enabled) override;

private:
  HDC m_hdc;
  HGLRC m_glrc;
  AgusWglContextFactory * m_factory;
  bool m_isDraw;
};

}  // namespace agus

#endif  // _WIN32 || _WIN64
