#include "agus_ogl.hpp"
#include "base/assert.hpp"
#include "base/logging.hpp"
#include <algorithm>
#include <vector>

#define CHECK_EGL_CALL() \
  do { \
    EGLint const err = eglGetError(); \
    if (err != EGL_SUCCESS) { \
      LOG(LERROR, ("EGL error 0x", std::hex, err, "at line", __LINE__)); \
    } \
  } while (false)

namespace agus
{
  // --- AgusOGLContext ---

  static EGLint * getContextAttributesList()
  {
    static EGLint contextAttrList[] = {EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE};
    return contextAttrList;
  }

  AgusOGLContext::AgusOGLContext(EGLDisplay display, EGLSurface surface, EGLConfig config, AgusOGLContext * contextToShareWith)
    : m_nativeContext(EGL_NO_CONTEXT)
    , m_surface(surface)
    , m_display(display)
    , m_presentAvailable(true)
  {
    EGLContext sharedContext = (contextToShareWith == NULL) ? EGL_NO_CONTEXT : contextToShareWith->m_nativeContext;
    m_nativeContext = eglCreateContext(m_display, config, sharedContext, getContextAttributesList());
    
    if (m_nativeContext == EGL_NO_CONTEXT) {
      EGLint error = eglGetError();
      LOG(LERROR, ("eglCreateContext failed with error:", std::hex, error));
    } else {
      LOG(LINFO, ("AgusOGLContext created: context=", m_nativeContext, 
                  "surface=", m_surface, "shared=", sharedContext));
    }
  }

  AgusOGLContext::~AgusOGLContext()
  {
    if (m_nativeContext != EGL_NO_CONTEXT)
      eglDestroyContext(m_display, m_nativeContext);
  }

  void AgusOGLContext::MakeCurrent()
  {
    if (m_surface != EGL_NO_SURFACE) {
      EGLBoolean result = eglMakeCurrent(m_display, m_surface, m_surface, m_nativeContext);
      if (result != EGL_TRUE) {
        EGLint error = eglGetError();
        LOG(LERROR, ("eglMakeCurrent failed with error:", std::hex, error,
                     "display:", m_display, "surface:", m_surface, "context:", m_nativeContext));
      } else {
        LOG(LDEBUG, ("eglMakeCurrent succeeded for context:", m_nativeContext, "surface:", m_surface));
      }
    } else {
      LOG(LWARNING, ("MakeCurrent called but m_surface is EGL_NO_SURFACE"));
    }
  }

  void AgusOGLContext::DoneCurrent()
  {
    eglMakeCurrent(m_display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
  }

  void AgusOGLContext::Present()
  {
    if (m_presentAvailable && m_surface != EGL_NO_SURFACE)
      eglSwapBuffers(m_display, m_surface);
  }

  void AgusOGLContext::SetFramebuffer(ref_ptr<dp::BaseFramebuffer> framebuffer)
  {
    if (framebuffer) framebuffer->Bind();
    else glBindFramebuffer(GL_FRAMEBUFFER, 0);
  }

  void AgusOGLContext::SetRenderingEnabled(bool enabled)
  {
    if (enabled) MakeCurrent();
    else DoneCurrent();
  }

  void AgusOGLContext::SetPresentAvailable(bool available) { m_presentAvailable = available; }

  bool AgusOGLContext::Validate()
  {
    return m_presentAvailable && eglGetCurrentContext() != EGL_NO_CONTEXT;
  }

  void AgusOGLContext::SetSurface(EGLSurface surface) { m_surface = surface; }
  void AgusOGLContext::ResetSurface() { m_surface = EGL_NO_SURFACE; }
  void AgusOGLContext::ClearCurrent() { DoneCurrent(); }


  // --- AgusOGLContextFactory ---

  static EGLint * getConfigAttributesListRGB8()
  {
    static EGLint attr_list[] = {
      EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 0,
      EGL_STENCIL_SIZE, 0, EGL_DEPTH_SIZE, 16,
      EGL_RENDERABLE_TYPE, 0x00000040, // EGL_OPENGL_ES3_BIT
      EGL_SURFACE_TYPE, EGL_PBUFFER_BIT | EGL_WINDOW_BIT,
      EGL_NONE
    };
    return attr_list;
  }
  
  // Custom comparator for EGL configs (implied from AndroidOGLContextFactory source but not shown)
  // Simplified: standard sort not strictly needed if we just pick first valid.
  // We'll rely on eglChooseConfig returning sorted usable configs.

  AgusOGLContextFactory::AgusOGLContextFactory(ANativeWindow* window)
    : m_drawContext(NULL), m_uploadContext(NULL)
    , m_windowSurface(EGL_NO_SURFACE), m_pixelbufferSurface(EGL_NO_SURFACE)
    , m_config(NULL), m_nativeWindow(NULL), m_display(EGL_NO_DISPLAY)
    , m_surfaceWidth(0), m_surfaceHeight(0), m_windowSurfaceValid(false)
  {
    m_display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (m_display == EGL_NO_DISPLAY) return;

    EGLint version[2] = {0};
    if (!eglInitialize(m_display, &version[0], &version[1])) return;

    SetSurface(window);
    CreatePixelbufferSurface();
  }

  AgusOGLContextFactory::~AgusOGLContextFactory()
  {
    ResetSurface();
    if (m_pixelbufferSurface != EGL_NO_SURFACE)
       eglDestroySurface(m_display, m_pixelbufferSurface);
    if (m_drawContext) delete m_drawContext;
    if (m_uploadContext) delete m_uploadContext;
    if (m_display != EGL_NO_DISPLAY) eglTerminate(m_display);
  }

  void AgusOGLContextFactory::SetSurface(ANativeWindow* window)
  {
    m_nativeWindow = window;
    if (!m_nativeWindow) return;
    
    if (CreateWindowSurface() && QuerySurfaceSize()) {
       if (m_drawContext) m_drawContext->SetSurface(m_windowSurface);
       m_windowSurfaceValid = true;
    }
  }

  void AgusOGLContextFactory::ResetSurface()
  {
    if (m_drawContext) m_drawContext->ResetSurface();
    if (m_windowSurface != EGL_NO_SURFACE) {
      eglDestroySurface(m_display, m_windowSurface);
      m_windowSurface = EGL_NO_SURFACE;
    }
    // Note: We do NOT own ANativeWindow, so usually don't release it unless we acquired a ref.
    // JNI usually passes us a window we should just use.
    // Original code calls ANativeWindow_release(m_nativeWindow) if it did ANativeWindow_fromSurface.
    // Since we receive the pointer, we assume ownership sharing or standard JNI window semantics.
    // Safest is to NOT release if we didn't call _fromSurface, OR replicate logic if passing it in already implies we have the ref.
    // ANativeWindow_fromSurface returns a reference, so comaps_set_surface must manage it.
    if (m_nativeWindow) {
        ANativeWindow_release(m_nativeWindow);
        m_nativeWindow = NULL;
    }
    m_windowSurfaceValid = false;
  }
  
  bool AgusOGLContextFactory::IsValid() const { return m_windowSurfaceValid && m_pixelbufferSurface != EGL_NO_SURFACE; }
  int AgusOGLContextFactory::GetWidth() const { return m_surfaceWidth; }
  int AgusOGLContextFactory::GetHeight() const { return m_surfaceHeight; }

  void AgusOGLContextFactory::UpdateSurfaceSize(int w, int h) {
      m_surfaceWidth = w;
      m_surfaceHeight = h;
  }
  
  bool AgusOGLContextFactory::QuerySurfaceSize() {
      EGLint w, h;
      eglQuerySurface(m_display, m_windowSurface, EGL_WIDTH, &w);
      eglQuerySurface(m_display, m_windowSurface, EGL_HEIGHT, &h);
      m_surfaceWidth = w;
      m_surfaceHeight = h;
      return true;
  }

  bool AgusOGLContextFactory::CreateWindowSurface() {
      EGLConfig configs[40];
      int count = 0;
      if (!eglChooseConfig(m_display, getConfigAttributesListRGB8(), configs, 40, &count) || count == 0) return false;
      m_config = configs[0]; // Pick first
      
      EGLint format;
      eglGetConfigAttrib(m_display, m_config, EGL_NATIVE_VISUAL_ID, &format);
      ANativeWindow_setBuffersGeometry(m_nativeWindow, 0, 0, format);
      
      EGLint nb_attribs[] = { EGL_RENDER_BUFFER, EGL_BACK_BUFFER, EGL_NONE };
      m_windowSurface = eglCreateWindowSurface(m_display, m_config, m_nativeWindow, nb_attribs);
      return m_windowSurface != EGL_NO_SURFACE;
  }
  
  bool AgusOGLContextFactory::CreatePixelbufferSurface() {
       EGLint pbuf_attribs[] = { EGL_WIDTH, 1, EGL_HEIGHT, 1, EGL_NONE };
       m_pixelbufferSurface = eglCreatePbufferSurface(m_display, m_config, pbuf_attribs);
       return m_pixelbufferSurface != EGL_NO_SURFACE;
  }

  dp::GraphicsContext * AgusOGLContextFactory::GetDrawContext() {
      LOG(LINFO, ("GetDrawContext called, m_drawContext=", m_drawContext, "m_uploadContext=", m_uploadContext));
      if (!m_drawContext) {
          m_drawContext = new AgusOGLContext(m_display, m_windowSurface, m_config, m_uploadContext);
          LOG(LINFO, ("Created draw context"));
      }
      return m_drawContext;
  }
  
  dp::GraphicsContext * AgusOGLContextFactory::GetResourcesUploadContext() {
      LOG(LINFO, ("GetResourcesUploadContext called, m_uploadContext=", m_uploadContext, "m_drawContext=", m_drawContext));
      if (!m_uploadContext) {
          m_uploadContext = new AgusOGLContext(m_display, m_pixelbufferSurface, m_config, m_drawContext);
          LOG(LINFO, ("Created upload context"));
      }
      return m_uploadContext;
  }

  bool AgusOGLContextFactory::IsDrawContextCreated() const { return m_drawContext != nullptr; }
  bool AgusOGLContextFactory::IsUploadContextCreated() const { return m_uploadContext != nullptr; }
  
  void AgusOGLContextFactory::WaitForInitialization(dp::GraphicsContext * context) {
      // Simplistic sync
      return;
  }
  
  void AgusOGLContextFactory::SetPresentAvailable(bool available) {
      if (m_drawContext) m_drawContext->SetPresentAvailable(available);
  }

}
