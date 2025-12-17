#pragma once

#include "drape/gl_includes.hpp"
#include "drape/oglcontext.hpp"
#include "drape/graphics_context_factory.hpp"

#include <EGL/egl.h>
#include <android/native_window.h>
#include <atomic>
#include <condition_variable>
#include <mutex>

namespace agus
{
  class AgusOGLContext : public dp::OGLContext
  {
  public:
    AgusOGLContext(EGLDisplay display, EGLSurface surface, EGLConfig config, AgusOGLContext * contextToShareWith);
    ~AgusOGLContext();

    void MakeCurrent() override;
    void DoneCurrent() override;
    void Present() override;
    void SetFramebuffer(ref_ptr<dp::BaseFramebuffer> framebuffer) override;
    void SetRenderingEnabled(bool enabled) override;
    void SetPresentAvailable(bool available) override;
    bool Validate() override;

    void SetSurface(EGLSurface surface);
    void ResetSurface();
    void ClearCurrent();

  private:
    EGLContext m_nativeContext;
    EGLSurface m_surface;
    EGLDisplay m_display;
    std::atomic<bool> m_presentAvailable;
  };

  class AgusOGLContextFactory : public dp::GraphicsContextFactory
  {
  public:
    AgusOGLContextFactory(ANativeWindow* window);
    ~AgusOGLContextFactory();

    bool IsValid() const;

    dp::GraphicsContext * GetDrawContext() override;
    dp::GraphicsContext * GetResourcesUploadContext() override;
    bool IsDrawContextCreated() const override;
    bool IsUploadContextCreated() const override;
    void WaitForInitialization(dp::GraphicsContext * context) override;
    void SetPresentAvailable(bool available) override;

    void SetSurface(ANativeWindow* window);
    void ResetSurface();

    int GetWidth() const;
    int GetHeight() const;
    void UpdateSurfaceSize(int w, int h);

  private:
    bool QuerySurfaceSize();
    bool CreateWindowSurface();
    bool CreatePixelbufferSurface();

    AgusOGLContext * m_drawContext;
    AgusOGLContext * m_uploadContext;

    EGLSurface m_windowSurface;
    EGLSurface m_pixelbufferSurface;
    EGLConfig m_config;

    ANativeWindow * m_nativeWindow;
    EGLDisplay m_display;

    int m_surfaceWidth;
    int m_surfaceHeight;

    bool m_windowSurfaceValid;
    bool m_isInitialized = false;
    size_t m_initializationCounter = 0;
    std::condition_variable m_initializationCondition;
    std::mutex m_initializationMutex;
  };
} // namespace agus
