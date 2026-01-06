#pragma once

#if defined(__linux__) && !defined(__ANDROID__)

#include "drape/graphics_context_factory.hpp"
#include "drape/drape_global.hpp"
#include "geometry/screenbase.hpp"

#include <EGL/egl.h>
#include <GLES3/gl3.h>

#include <memory>
#include <functional>
#include <atomic>
#include <mutex>
#include <cstdint>

namespace agus
{

/**
 * @brief Linux EGL Context Factory for Flutter integration.
 * 
 * This class manages EGL contexts for offscreen OpenGL rendering on Linux,
 * providing texture sharing with Flutter via FlTextureGL.
 * 
 * Architecture:
 * - Creates offscreen EGL contexts using pbuffer surfaces
 * - Renders CoMaps to a Framebuffer Object (FBO) backed by an OpenGL texture
 * - Provides the GL texture ID to Flutter for texture sharing
 * - Flutter's GTK/GDK context reads from this shared texture
 * 
 * Note: Context sharing between CoMaps EGL context and Flutter's GDK GL context
 * must be configured if sharing textures directly. For simplicity, this initial
 * implementation uses pixel buffer copy as a fallback.
 */
class AgusEglContext;  // Forward declaration

class AgusEglContextFactory : public dp::GraphicsContextFactory
{
  friend class AgusEglContext;

public:
  AgusEglContextFactory(int width, int height, float density);
  ~AgusEglContextFactory() override;

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
  float GetDensity() const { return m_density; }

  // OpenGL texture for Flutter integration
  uint32_t GetTextureId() const { return m_renderTexture; }
  uint32_t GetFramebufferId() const { return m_framebuffer; }

  // Frame synchronization
  void SetFrameCallback(std::function<void()> callback) { m_frameCallback = callback; }
  void SetKeepAliveCallback(std::function<void()> callback) { m_keepAliveCallback = callback; }
  void OnFrameReady();
  void RequestActiveFrame();

  // Validation
  bool IsValid() const { return m_initialized; }
  
  // Copy pixel data for Flutter (returns cached buffer from last Present())
  bool CopyToPixelBuffer(uint8_t* buffer, int bufferSize);

  // Get rendered dimensions (may differ from requested during resize)
  int GetRenderedWidth() const { return m_renderedWidth.load(); }
  int GetRenderedHeight() const { return m_renderedHeight.load(); }

  // Called from AgusEglContext::Present() to capture frame pixels
  void CaptureFramePixels();

  // Called from AgusEglContext::Present() to apply deferred resize
  // (resize must happen on render thread where EGL context is current)
  void CheckPendingResize();

private:
  // Deferred resize - actual resize happens on render thread in CheckPendingResize()
  void ApplyPendingResize();
  bool InitializeEGL();
  bool CreateFramebuffer(int width, int height);
  void CleanupEGL();
  void CleanupFramebuffer();

  // EGL resources
  EGLDisplay m_display = EGL_NO_DISPLAY;
  EGLConfig m_config = nullptr;
  EGLContext m_drawEglContext = EGL_NO_CONTEXT;
  EGLContext m_uploadEglContext = EGL_NO_CONTEXT;
  EGLSurface m_drawSurface = EGL_NO_SURFACE;
  EGLSurface m_uploadSurface = EGL_NO_SURFACE;

  // OpenGL FBO resources
  uint32_t m_framebuffer = 0;
  uint32_t m_renderTexture = 0;
  uint32_t m_depthStencilBuffer = 0;

  // Context wrappers
  std::unique_ptr<AgusEglContext> m_drawContext;
  std::unique_ptr<AgusEglContext> m_uploadContext;

  // Dimensions
  int m_width = 0;
  int m_height = 0;
  float m_density = 1.0f;
  std::atomic<int> m_renderedWidth{0};
  std::atomic<int> m_renderedHeight{0};

  // State flags
  bool m_initialized = false;
  bool m_presentAvailable = true;
  bool m_useSurfaceless = false;  // EGL_KHR_surfaceless_context mode for WSL2/headless
  bool m_glFunctionsInitialized = false;  // Deferred GL init (avoid EGL_BAD_ACCESS on main thread)
  bool m_framebufferDeferred = false;  // Framebuffer creation deferred until GetDrawContext()

  // Callbacks
  std::function<void()> m_frameCallback;
  std::function<void()> m_keepAliveCallback;

  // Thread safety
  std::mutex m_mutex;
  
  // Staging buffer for pixel data (captured in Present, read by Flutter)
  std::vector<uint8_t> m_pixelBuffer;
  std::mutex m_pixelBufferMutex;

  // Deferred resize state (EGL doesn't allow context stealing like WGL)
  // SetSurfaceSize() sets these, CheckPendingResize() applies them on render thread
  std::atomic<bool> m_pendingResize{false};
  std::atomic<int> m_pendingWidth{0};
  std::atomic<int> m_pendingHeight{0};
};

}  // namespace agus

#endif  // defined(__linux__) && !defined(__ANDROID__)
