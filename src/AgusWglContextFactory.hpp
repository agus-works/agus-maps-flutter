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
#include <string>
#include <vector>

// WGL_NV_DX_interop definitions
#ifndef WGL_NV_DX_interop
#define WGL_NV_DX_interop 1
#define WGL_ACCESS_READ_ONLY_NV           0x0000
#define WGL_ACCESS_READ_WRITE_NV          0x0001
#define WGL_ACCESS_WRITE_DISCARD_NV       0x0002

typedef BOOL (WINAPI * PFNWGLDXSETRESOURCESHAREHANDLENVPROC) (void *dxObject, HANDLE shareHandle);
typedef HANDLE (WINAPI * PFNWGLDXOPENDEVICENVPROC) (void *dxDevice);
typedef BOOL (WINAPI * PFNWGLDXCLOSEDEVICENVPROC) (HANDLE hDevice);
typedef HANDLE (WINAPI * PFNWGLDXREGISTEROBJECTNVPROC) (HANDLE hDevice, void *dxObject, GLuint name, GLenum type, GLenum access);
typedef BOOL (WINAPI * PFNWGLDXUNREGISTEROBJECTNVPROC) (HANDLE hDevice, HANDLE hObject);
typedef BOOL (WINAPI * PFNWGLDXLOCKOBJECTSNVPROC) (HANDLE hDevice, GLint count, HANDLE *hObjects);
typedef BOOL (WINAPI * PFNWGLDXUNLOCKOBJECTSNVPROC) (HANDLE hDevice, GLint count, HANDLE *hObjects);
#endif



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
  void SetKeepAliveCallback(std::function<void()> callback) { m_keepAliveCallback = callback; }
  void OnFrameReady();
  
  /// Request an active frame to keep render loop running during tile loading.
  /// This calls the registered keep-alive callback (typically Framework::MakeFrameActive)
  void RequestActiveFrame();

  // Copy rendered content to shared texture
  void CopyToSharedTexture();

  // Diagnostics overlay (Windows-only)
  void SetOverlayEnabled(bool enabled) { m_overlayEnabled = enabled; }
  void SetOverlayCustomLines(std::vector<std::string> lines);

  // Accessor for framebuffer ID (used by AgusWglContext)
  GLuint GetFramebufferID() const { return m_framebuffer; }

private:
  bool InitializeWGL();
  bool InitializeD3D11();
  bool CreateSharedTexture(int width, int height);
  void CleanupWGL();
  void CleanupD3D11();

  bool EnsureOverlayFont();
  void DrawOverlayText(GLuint targetFbo, int width, int height, std::vector<std::string> const & lines, bool originTopLeft);
  std::vector<std::string> BuildOverlayLines(bool useInterop) const;
  int MeasureOverlayTextWidth(std::string const & text) const;

  // WGL context
  HWND m_hiddenWindow = nullptr;
  HDC m_hdc = nullptr;
  HGLRC m_drawGlrc = nullptr;
  HGLRC m_uploadGlrc = nullptr;
  
  // OpenGL resources
  GLuint m_framebuffer = 0;
  GLuint m_renderTexture = 0;
  GLuint m_depthBuffer = 0;

  // The most recently bound framebuffer on the draw context.
  // CoMaps may bind its own internal FBOs during postprocess passes; we must
  // read back from the actual final draw target rather than assuming m_framebuffer.
  std::atomic<GLuint> m_lastBoundFramebuffer{0};

  // D3D11 interop
  Microsoft::WRL::ComPtr<ID3D11Device> m_d3dDevice;
  Microsoft::WRL::ComPtr<ID3D11DeviceContext> m_d3dContext;
  Microsoft::WRL::ComPtr<ID3D11Texture2D> m_sharedTexture;
  Microsoft::WRL::ComPtr<ID3D11Texture2D> m_stagingTexture;
  HANDLE m_sharedHandle = nullptr;
  Microsoft::WRL::ComPtr<IDXGIKeyedMutex> m_keyedMutex;
  bool m_useKeyedMutex = false;

  // WGL Interop
  HANDLE m_interopDevice = nullptr;
  HANDLE m_interopObject = nullptr;
  GLuint m_interopTexture = 0;
  GLuint m_interopRenderbuffer = 0;
  GLuint m_interopFramebuffer = 0;

  // Function pointers for WGL_NV_DX_interop
  // Function pointers for WGL_NV_DX_interop
  PFNWGLDXOPENDEVICENVPROC m_wglDXOpenDeviceNV = nullptr;
  PFNWGLDXCLOSEDEVICENVPROC m_wglDXCloseDeviceNV = nullptr;
  PFNWGLDXREGISTEROBJECTNVPROC m_wglDXRegisterObjectNV = nullptr;
  PFNWGLDXUNREGISTEROBJECTNVPROC m_wglDXUnregisterObjectNV = nullptr;
  PFNWGLDXLOCKOBJECTSNVPROC m_wglDXLockObjectsNV = nullptr;
  PFNWGLDXUNLOCKOBJECTSNVPROC m_wglDXUnlockObjectsNV = nullptr;

  // Graphics contexts
  std::unique_ptr<dp::GraphicsContext> m_drawContext;
  std::unique_ptr<dp::GraphicsContext> m_uploadContext;

  // State
  int m_width = 0;
  int m_height = 0;

  // OpenGL renderer/vendor strings (for adapter matching/logging)
  std::string m_glRenderer;
  std::string m_glVendor;
  
  // Track the size at which the most recent frame was ACTUALLY rendered.
  // This is critical for resize handling: when SetSurfaceSize() is called,
  // m_width/m_height are updated immediately to the target size, but the
  // FBO still contains content rendered at the OLD size until the DrapeEngine
  // completes a new frame at the new size.
  // CopyToSharedTexture() must read pixels at m_renderedWidth/m_renderedHeight,
  // not at m_width/m_height, to avoid reading garbage/black pixels beyond
  // the actually-rendered content.
  std::atomic<int> m_renderedWidth{0};
  std::atomic<int> m_renderedHeight{0};
  
  std::atomic<bool> m_presentAvailable{true};
  std::function<void()> m_frameCallback;
  std::function<void()> m_keepAliveCallback;  // Called to keep render loop active
  std::mutex m_mutex;

  // Diagnostics overlay state
  bool m_overlayEnabled = true;
  bool m_overlayInitialized = false;
  GLuint m_overlayFontBase = 0;
  HFONT m_overlayFont = nullptr;
  int m_overlayFontHeight = 12;
  int m_overlayPadding = 6;
  std::vector<std::string> m_overlayCustomLines;
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
  void Resize(uint32_t w, uint32_t h) override;
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
  /// Counter for initial frames - forces Flutter notification for first N frames
  /// This ensures tiles load properly even when render loop would otherwise suspend
  int m_initialFrameCount = 120;  // ~2 seconds at 60fps
};

}  // namespace agus

#endif  // _WIN32 || _WIN64
