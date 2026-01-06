/**
 * @file AgusEglContextFactory.cpp
 * @brief Linux EGL context factory implementation for Flutter texture sharing.
 * 
 * This file provides the EGL-based OpenGL context factory used for offscreen
 * rendering on Linux. CoMaps renders to an FBO, and the resulting texture
 * is shared with Flutter via the FlTextureGL API.
 * 
 * Platform Support Notes:
 * - Works with Mesa drivers (Intel, AMD, llvmpipe software renderer)
 * - Supports surfaceless contexts (EGL_KHR_surfaceless_context) for headless/WSL2
 * - Falls back to pbuffer surfaces if surfaceless not available
 */

#if defined(__linux__) && !defined(__ANDROID__)

#include "AgusEglContextFactory.hpp"

#include "drape/gl_functions.hpp"
#include "drape/oglcontext.hpp"

#include "base/assert.hpp"
#include "base/logging.hpp"

#include <EGL/eglext.h>
#include <GLES3/gl3.h>
#include <vector>
#include <cstring>
#include <cstdlib>

// EGL platform extensions for surfaceless/GBM support
#ifndef EGL_PLATFORM_SURFACELESS_MESA
#define EGL_PLATFORM_SURFACELESS_MESA     0x31DD
#endif

#ifndef EGL_PLATFORM_GBM_MESA
#define EGL_PLATFORM_GBM_MESA             0x31D7
#endif

// Additional OpenGL FBO constants that may not be defined
#ifndef GL_FRAMEBUFFER
#define GL_FRAMEBUFFER                    0x8D40
#define GL_RENDERBUFFER                   0x8D41
#define GL_FRAMEBUFFER_COMPLETE           0x8CD5
#define GL_COLOR_ATTACHMENT0              0x8CE0
#define GL_DEPTH_ATTACHMENT               0x8D00
#define GL_STENCIL_ATTACHMENT             0x8D20
#define GL_DEPTH_STENCIL_ATTACHMENT       0x821A
#define GL_DEPTH24_STENCIL8               0x88F0
#endif

#ifndef GL_RGBA8
#define GL_RGBA8                          0x8058
#endif

#ifndef GL_FRAMEBUFFER_BINDING
#define GL_FRAMEBUFFER_BINDING            0x8CA6
#endif

namespace agus
{

// ============================================================================
// AgusEglContext - OpenGL context wrapper for Linux EGL
// ============================================================================

class AgusEglContext : public dp::OGLContext
{
public:
  AgusEglContext(EGLDisplay display, EGLSurface surface, EGLContext context,
                 AgusEglContextFactory * factory, bool isDrawContext, bool surfaceless)
    : m_display(display)
    , m_surface(surface)
    , m_context(context)
    , m_factory(factory)
    , m_isDrawContext(isDrawContext)
    , m_surfaceless(surfaceless)
    , m_presentAvailable(true)
  {}

  ~AgusEglContext() override = default;

  void MakeCurrent() override
  {
    if (m_context != EGL_NO_CONTEXT)
    {
      // Surfaceless contexts use EGL_NO_SURFACE for both read and draw
      EGLSurface readSurface = m_surfaceless ? EGL_NO_SURFACE : m_surface;
      EGLSurface drawSurface = m_surfaceless ? EGL_NO_SURFACE : m_surface;
      
      EGLBoolean result = eglMakeCurrent(m_display, drawSurface, readSurface, m_context);
      if (result != EGL_TRUE)
      {
        EGLint error = eglGetError();
        LOG(LERROR, ("eglMakeCurrent failed:", std::hex, error, "surfaceless:", m_surfaceless));
      }
      else
      {
        // Bind our FBO for drawing
        if (m_isDrawContext && m_factory)
        {
          glBindFramebuffer(GL_FRAMEBUFFER, m_factory->GetFramebufferId());
        }
      }
    }
  }

  void DoneCurrent() override
  {
    eglMakeCurrent(m_display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
  }

  void Present() override
  {
    if (!m_presentAvailable)
      return;

    // Check for pending resize BEFORE rendering completes
    // This is the only safe place to resize - on the render thread where context is current
    if (m_isDrawContext && m_factory)
    {
      m_factory->CheckPendingResize();
    }

    // Ensure rendering is complete
    glFinish();

    // Capture frame pixels while context is current (on render thread)
    if (m_isDrawContext && m_factory)
    {
      m_factory->CaptureFramePixels();
      m_factory->OnFrameReady();
    }
  }

  void SetFramebuffer(ref_ptr<dp::BaseFramebuffer> framebuffer) override
  {
    if (framebuffer)
      framebuffer->Bind();
    else if (m_factory)
      glBindFramebuffer(GL_FRAMEBUFFER, m_factory->GetFramebufferId());
    else
      glBindFramebuffer(GL_FRAMEBUFFER, 0);
  }

  void SetRenderingEnabled(bool enabled) override
  {
    if (enabled)
      MakeCurrent();
    else
      DoneCurrent();
  }

  void SetPresentAvailable(bool available) override
  {
    m_presentAvailable = available;
  }

  bool Validate() override
  {
    return m_context != EGL_NO_CONTEXT && eglGetCurrentContext() == m_context;
  }

private:
  EGLDisplay m_display;
  EGLSurface m_surface;
  EGLContext m_context;
  AgusEglContextFactory * m_factory;
  bool m_isDrawContext;
  bool m_surfaceless;
  std::atomic<bool> m_presentAvailable;
};

// ============================================================================
// AgusEglContextFactory Implementation
// ============================================================================

AgusEglContextFactory::AgusEglContextFactory(int width, int height, float density)
  : m_width(width)
  , m_height(height)
  , m_density(density)
{
  LOG(LINFO, ("Creating EGL context factory:", width, "x", height, "density:", density));

  m_renderedWidth.store(width);
  m_renderedHeight.store(height);

  if (!InitializeEGL())
  {
    LOG(LERROR, ("Failed to initialize EGL"));
    return;
  }

  // IMPORTANT: Do NOT create framebuffer here!
  // On Linux, this constructor runs on the main thread where Flutter's EGL context
  // may be current. Calling eglMakeCurrent for our context would conflict.
  // Instead, defer framebuffer creation to the first GetDrawContext() call,
  // which happens on the render thread.
  m_framebufferDeferred = true;

  m_initialized = true;
  LOG(LINFO, ("EGL context factory created successfully (framebuffer deferred)"));
}

AgusEglContextFactory::~AgusEglContextFactory()
{
  LOG(LINFO, ("Destroying EGL context factory"));

  m_drawContext.reset();
  m_uploadContext.reset();

  CleanupFramebuffer();
  CleanupEGL();
}

// Helper function to convert EGL error codes to readable strings
static const char* EglErrorString(EGLint error)
{
  switch (error)
  {
    case EGL_SUCCESS: return "EGL_SUCCESS";
    case EGL_NOT_INITIALIZED: return "EGL_NOT_INITIALIZED";
    case EGL_BAD_ACCESS: return "EGL_BAD_ACCESS";
    case EGL_BAD_ALLOC: return "EGL_BAD_ALLOC";
    case EGL_BAD_ATTRIBUTE: return "EGL_BAD_ATTRIBUTE";
    case EGL_BAD_CONTEXT: return "EGL_BAD_CONTEXT";
    case EGL_BAD_CONFIG: return "EGL_BAD_CONFIG";
    case EGL_BAD_CURRENT_SURFACE: return "EGL_BAD_CURRENT_SURFACE";
    case EGL_BAD_DISPLAY: return "EGL_BAD_DISPLAY";
    case EGL_BAD_SURFACE: return "EGL_BAD_SURFACE";
    case EGL_BAD_MATCH: return "EGL_BAD_MATCH";
    case EGL_BAD_PARAMETER: return "EGL_BAD_PARAMETER";
    case EGL_BAD_NATIVE_PIXMAP: return "EGL_BAD_NATIVE_PIXMAP";
    case EGL_BAD_NATIVE_WINDOW: return "EGL_BAD_NATIVE_WINDOW";
    case EGL_CONTEXT_LOST: return "EGL_CONTEXT_LOST";
    default: return "UNKNOWN_EGL_ERROR";
  }
}

// Check if an EGL extension is supported
static bool HasEglExtension(EGLDisplay display, const char* extension)
{
  const char* extensions = nullptr;
  if (display == EGL_NO_DISPLAY)
  {
    // Query client extensions (before display is created)
    extensions = eglQueryString(EGL_NO_DISPLAY, EGL_EXTENSIONS);
  }
  else
  {
    extensions = eglQueryString(display, EGL_EXTENSIONS);
  }
  
  if (!extensions)
    return false;
    
  return strstr(extensions, extension) != nullptr;
}

bool AgusEglContextFactory::InitializeEGL()
{
  // Check for EGL_EXT_platform_base which provides eglGetPlatformDisplay
  bool hasPlatformBase = HasEglExtension(EGL_NO_DISPLAY, "EGL_EXT_platform_base");
  bool hasSurfaceless = HasEglExtension(EGL_NO_DISPLAY, "EGL_MESA_platform_surfaceless");
  bool hasDeviceExt = HasEglExtension(EGL_NO_DISPLAY, "EGL_EXT_platform_device");
  
  LOG(LINFO, ("EGL client extensions - platform_base:", hasPlatformBase, 
              "surfaceless:", hasSurfaceless, "device:", hasDeviceExt));

  // Strategy: Try DEFAULT display FIRST with pbuffer surfaces
  // 
  // On WSL2 with llvmpipe (software rendering), the MESA surfaceless platform
  // does NOT work reliably - eglMakeCurrent returns EGL_BAD_ACCESS even though
  // the extension is advertised. The default display with pbuffer surfaces
  // works correctly with llvmpipe.
  //
  // Only use surfaceless as a last resort if default display completely fails.
  
  // First, try the default display (works with llvmpipe software rendering)
  m_display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
  if (m_display != EGL_NO_DISPLAY)
  {
    LOG(LINFO, ("Using default EGL display"));
    m_useSurfaceless = false;
  }
  else if (hasPlatformBase && hasSurfaceless)
  {
    // Fallback to surfaceless platform only if default display failed completely
    auto eglGetPlatformDisplayEXT = (PFNEGLGETPLATFORMDISPLAYEXTPROC)
        eglGetProcAddress("eglGetPlatformDisplayEXT");
    
    if (eglGetPlatformDisplayEXT)
    {
      m_display = eglGetPlatformDisplayEXT(EGL_PLATFORM_SURFACELESS_MESA, EGL_DEFAULT_DISPLAY, nullptr);
      if (m_display != EGL_NO_DISPLAY)
      {
        LOG(LINFO, ("Using MESA surfaceless platform (fallback)"));
        m_useSurfaceless = true;
      }
    }
  }
  
  if (m_display == EGL_NO_DISPLAY)
  {
    LOG(LERROR, ("Failed to get any EGL display"));
    return false;
  }

  // Initialize EGL
  EGLint major, minor;
  if (!eglInitialize(m_display, &major, &minor))
  {
    EGLint error = eglGetError();
    LOG(LERROR, ("eglInitialize failed:", EglErrorString(error)));
    return false;
  }
  LOG(LINFO, ("EGL initialized:", major, ".", minor));

  // Check if surfaceless context extension is available on this display
  bool hasSurfacelessContext = HasEglExtension(m_display, "EGL_KHR_surfaceless_context");
  LOG(LINFO, ("EGL_KHR_surfaceless_context:", hasSurfacelessContext));
  
  // If using surfaceless platform, we need surfaceless context support
  if (m_useSurfaceless && !hasSurfacelessContext)
  {
    LOG(LWARNING, ("Surfaceless platform selected but EGL_KHR_surfaceless_context not available"));
    m_useSurfaceless = false;
  }

  // Bind OpenGL ES API first
  if (!eglBindAPI(EGL_OPENGL_ES_API))
  {
    EGLint error = eglGetError();
    LOG(LERROR, ("eglBindAPI failed:", EglErrorString(error)));
    return false;
  }

  // Configure EGL for OpenGL ES 3.0
  // For surfaceless platform, we must explicitly set EGL_SURFACE_TYPE to 0
  // because the surfaceless platform doesn't provide any surface types
  EGLint numConfigs = 0;
  
  // Try progressively more relaxed config requirements
  struct ConfigAttempt {
    const char* description;
    EGLint surfaceType;
    EGLint depthSize;
    EGLint stencilSize;
  };
  
  // Different configs to try in order of preference
  ConfigAttempt attempts[] = {
    { "full (depth24/stencil8)", m_useSurfaceless ? 0 : EGL_PBUFFER_BIT, 24, 8 },
    { "reduced depth (depth16/stencil8)", m_useSurfaceless ? 0 : EGL_PBUFFER_BIT, 16, 8 },
    { "minimal (depth16/stencil0)", m_useSurfaceless ? 0 : EGL_PBUFFER_BIT, 16, 0 },
    { "no depth/stencil", m_useSurfaceless ? 0 : EGL_PBUFFER_BIT, 0, 0 },
  };
  
  for (const auto& attempt : attempts)
  {
    EGLint configAttribs[] = {
      EGL_SURFACE_TYPE, attempt.surfaceType,
      EGL_RED_SIZE, 8,
      EGL_GREEN_SIZE, 8,
      EGL_BLUE_SIZE, 8,
      EGL_ALPHA_SIZE, 8,
      EGL_DEPTH_SIZE, attempt.depthSize,
      EGL_STENCIL_SIZE, attempt.stencilSize,
      EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
      EGL_NONE
    };
    
    if (eglChooseConfig(m_display, configAttribs, &m_config, 1, &numConfigs) && numConfigs > 0)
    {
      LOG(LINFO, ("EGL config selected with", attempt.description, "- numConfigs:", numConfigs));
      break;
    }
    LOG(LWARNING, ("Config attempt failed:", attempt.description));
  }
  
  if (numConfigs == 0)
  {
    // Last resort: try with minimal requirements
    EGLint minimalAttribs[] = {
      EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
      EGL_NONE
    };
    
    if (!eglChooseConfig(m_display, minimalAttribs, &m_config, 1, &numConfigs) || numConfigs == 0)
    {
      EGLint error = eglGetError();
      LOG(LERROR, ("eglChooseConfig failed even with minimal config:", EglErrorString(error)));
      return false;
    }
    LOG(LWARNING, ("Using minimal EGL config - depth/stencil may not work correctly"));
  }

  // Create pbuffer surfaces only if not using surfaceless mode
  if (!m_useSurfaceless)
  {
    const EGLint pbufferAttribs[] = {
      EGL_WIDTH, m_width > 0 ? m_width : 1,
      EGL_HEIGHT, m_height > 0 ? m_height : 1,
      EGL_NONE
    };

    m_drawSurface = eglCreatePbufferSurface(m_display, m_config, pbufferAttribs);
    if (m_drawSurface == EGL_NO_SURFACE)
    {
      EGLint error = eglGetError();
      LOG(LWARNING, ("Failed to create draw pbuffer surface:", EglErrorString(error),
                     "- trying surfaceless fallback"));
      // If pbuffer fails but surfaceless context is available, use surfaceless
      if (hasSurfacelessContext)
      {
        m_useSurfaceless = true;
        LOG(LINFO, ("Falling back to surfaceless context mode"));
      }
      else
      {
        LOG(LERROR, ("No fallback available - pbuffer failed and no surfaceless support"));
        return false;
      }
    }
    else
    {
      // Create second pbuffer for upload context
      m_uploadSurface = eglCreatePbufferSurface(m_display, m_config, pbufferAttribs);
      if (m_uploadSurface == EGL_NO_SURFACE)
      {
        EGLint error = eglGetError();
        LOG(LERROR, ("Failed to create upload pbuffer surface:", EglErrorString(error)));
        eglDestroySurface(m_display, m_drawSurface);
        m_drawSurface = EGL_NO_SURFACE;
        
        // Try surfaceless fallback
        if (hasSurfacelessContext)
        {
          m_useSurfaceless = true;
          LOG(LINFO, ("Falling back to surfaceless context mode"));
        }
        else
        {
          return false;
        }
      }
    }
  }
  
  LOG(LINFO, ("Using surfaceless mode:", m_useSurfaceless));

  // Context attributes for OpenGL ES 3.0
  const EGLint contextAttribs[] = {
    EGL_CONTEXT_CLIENT_VERSION, 3,
    EGL_NONE
  };

  // Create draw context
  m_drawEglContext = eglCreateContext(m_display, m_config, EGL_NO_CONTEXT, contextAttribs);
  if (m_drawEglContext == EGL_NO_CONTEXT)
  {
    EGLint error = eglGetError();
    LOG(LERROR, ("Failed to create draw EGL context:", EglErrorString(error)));
    return false;
  }

  // Create upload context that shares with draw context
  m_uploadEglContext = eglCreateContext(m_display, m_config, m_drawEglContext, contextAttribs);
  if (m_uploadEglContext == EGL_NO_CONTEXT)
  {
    EGLint error = eglGetError();
    LOG(LERROR, ("Failed to create upload EGL context:", EglErrorString(error)));
    eglDestroyContext(m_display, m_drawEglContext);
    m_drawEglContext = EGL_NO_CONTEXT;
    return false;
  }

  // IMPORTANT: Do NOT call eglMakeCurrent here during initialization!
  // On some systems (especially WSL2 with Mesa llvmpipe), calling eglMakeCurrent
  // on the main thread during plugin initialization causes EGL_BAD_ACCESS because
  // Flutter's engine may already have an EGL context current on this thread.
  // 
  // Instead, defer GL function initialization until the first render frame
  // when CreateFramebuffer is called - at that point we're on the render thread.
  m_glFunctionsInitialized = false;

  LOG(LINFO, ("EGL contexts created successfully (GL init deferred)"));
  return true;
}

bool AgusEglContextFactory::CreateFramebuffer(int width, int height)
{
  if (width <= 0 || height <= 0)
  {
    LOG(LERROR, ("Invalid framebuffer dimensions:", width, "x", height));
    return false;
  }

  // Make sure we're in the right context
  // For surfaceless contexts, use EGL_NO_SURFACE
  EGLSurface drawSurf = m_useSurfaceless ? EGL_NO_SURFACE : m_drawSurface;
  EGLSurface readSurf = m_useSurfaceless ? EGL_NO_SURFACE : m_drawSurface;
  
  if (!eglMakeCurrent(m_display, drawSurf, readSurf, m_drawEglContext))
  {
    EGLint error = eglGetError();
    LOG(LERROR, ("Failed to make context current in CreateFramebuffer:", EglErrorString(error),
                 "surfaceless:", m_useSurfaceless));
    return false;
  }

  // Deferred GL function initialization - do it here on first framebuffer creation
  // This avoids EGL_BAD_ACCESS on the main thread during plugin initialization
  if (!m_glFunctionsInitialized)
  {
    GLFunctions::Init(dp::ApiVersion::OpenGLES3);
    m_glFunctionsInitialized = true;
    LOG(LINFO, ("GL functions initialized"));
  }

  // Generate framebuffer
  glGenFramebuffers(1, &m_framebuffer);
  glBindFramebuffer(GL_FRAMEBUFFER, m_framebuffer);

  // Create color texture
  glGenTextures(1, &m_renderTexture);
  glBindTexture(GL_TEXTURE_2D, m_renderTexture);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

  // Attach color texture to framebuffer
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, m_renderTexture, 0);

  // Create depth-stencil renderbuffer
  glGenRenderbuffers(1, &m_depthStencilBuffer);
  glBindRenderbuffer(GL_RENDERBUFFER, m_depthStencilBuffer);
  glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, width, height);
  glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER, m_depthStencilBuffer);

  // Check framebuffer completeness
  GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
  if (status != GL_FRAMEBUFFER_COMPLETE)
  {
    LOG(LERROR, ("Framebuffer incomplete, status:", std::hex, status));
    // Release context before returning
    eglMakeCurrent(m_display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    return false;
  }

  // Clear to a visible color for debugging
  glClearColor(0.1f, 0.1f, 0.2f, 1.0f);
  glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);

  m_renderedWidth.store(width);
  m_renderedHeight.store(height);

  LOG(LINFO, ("Framebuffer created:", width, "x", height, "texture:", m_renderTexture, "fbo:", m_framebuffer));

  // IMPORTANT: Release context so render threads can acquire it
  eglMakeCurrent(m_display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);

  return true;
}

void AgusEglContextFactory::CleanupFramebuffer()
{
  if (m_drawEglContext != EGL_NO_CONTEXT)
  {
    // For surfaceless contexts, use EGL_NO_SURFACE
    EGLSurface drawSurf = m_useSurfaceless ? EGL_NO_SURFACE : m_drawSurface;
    EGLSurface readSurf = m_useSurfaceless ? EGL_NO_SURFACE : m_drawSurface;
    eglMakeCurrent(m_display, drawSurf, readSurf, m_drawEglContext);

    if (m_framebuffer)
    {
      glDeleteFramebuffers(1, &m_framebuffer);
      m_framebuffer = 0;
    }
    if (m_renderTexture)
    {
      glDeleteTextures(1, &m_renderTexture);
      m_renderTexture = 0;
    }
    if (m_depthStencilBuffer)
    {
      glDeleteRenderbuffers(1, &m_depthStencilBuffer);
      m_depthStencilBuffer = 0;
    }

    // Release context so render threads can use it
    eglMakeCurrent(m_display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
  }
}

void AgusEglContextFactory::CleanupEGL()
{
  if (m_display != EGL_NO_DISPLAY)
  {
    eglMakeCurrent(m_display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);

    if (m_drawEglContext != EGL_NO_CONTEXT)
    {
      eglDestroyContext(m_display, m_drawEglContext);
      m_drawEglContext = EGL_NO_CONTEXT;
    }
    if (m_uploadEglContext != EGL_NO_CONTEXT)
    {
      eglDestroyContext(m_display, m_uploadEglContext);
      m_uploadEglContext = EGL_NO_CONTEXT;
    }
    if (m_drawSurface != EGL_NO_SURFACE)
    {
      eglDestroySurface(m_display, m_drawSurface);
      m_drawSurface = EGL_NO_SURFACE;
    }
    if (m_uploadSurface != EGL_NO_SURFACE)
    {
      eglDestroySurface(m_display, m_uploadSurface);
      m_uploadSurface = EGL_NO_SURFACE;
    }

    eglTerminate(m_display);
    m_display = EGL_NO_DISPLAY;
  }
}

dp::GraphicsContext * AgusEglContextFactory::GetDrawContext()
{
  // Deferred framebuffer creation - happens on render thread, not main thread
  // This avoids EGL_BAD_ACCESS when Flutter's context is current on main thread
  if (m_framebufferDeferred && m_framebuffer == 0)
  {
    LOG(LINFO, ("Creating deferred framebuffer on render thread"));
    if (!CreateFramebuffer(m_width, m_height))
    {
      LOG(LERROR, ("Failed to create deferred framebuffer"));
      m_initialized = false;
      return nullptr;
    }
    m_framebufferDeferred = false;
    LOG(LINFO, ("Deferred framebuffer created, texture ID:", m_renderTexture));
  }

  if (!m_drawContext && m_drawEglContext != EGL_NO_CONTEXT)
  {
    m_drawContext = std::make_unique<AgusEglContext>(
      m_display, m_drawSurface, m_drawEglContext, this, true /* isDrawContext */, m_useSurfaceless);
    LOG(LINFO, ("Draw context created, surfaceless:", m_useSurfaceless));
  }
  return m_drawContext.get();
}

dp::GraphicsContext * AgusEglContextFactory::GetResourcesUploadContext()
{
  if (!m_uploadContext && m_uploadEglContext != EGL_NO_CONTEXT)
  {
    m_uploadContext = std::make_unique<AgusEglContext>(
      m_display, m_uploadSurface, m_uploadEglContext, this, false /* isDrawContext */, m_useSurfaceless);
    LOG(LINFO, ("Upload context created, surfaceless:", m_useSurfaceless));
  }
  return m_uploadContext.get();
}

void AgusEglContextFactory::SetSurfaceSize(int width, int height)
{
  if (width <= 0 || height <= 0)
    return;

  if (width == m_width && height == m_height)
    return;

  LOG(LINFO, ("SetSurfaceSize: Scheduling deferred resize:", m_width, "x", m_height, "->", width, "x", height));

  // EGL doesn't allow context stealing like WGL does on Windows.
  // eglMakeCurrent() fails with EGL_BAD_ACCESS (0x3002) when the context
  // is current on another thread (the render thread).
  //
  // Solution: Use deferred resize - store the pending dimensions and
  // apply them on the render thread in CheckPendingResize() which is
  // called from Present() where the EGL context is already current.
  m_pendingWidth.store(width);
  m_pendingHeight.store(height);
  m_pendingResize.store(true);
}

void AgusEglContextFactory::CheckPendingResize()
{
  // Called from Present() on the render thread where EGL context is current
  if (!m_pendingResize.load())
    return;

  int width = m_pendingWidth.load();
  int height = m_pendingHeight.load();
  m_pendingResize.store(false);

  if (width <= 0 || height <= 0)
    return;

  if (width == m_width && height == m_height)
    return;

  LOG(LINFO, ("CheckPendingResize: Applying deferred resize:", m_width, "x", m_height, "->", width, "x", height));

  ApplyPendingResize();
}

void AgusEglContextFactory::ApplyPendingResize()
{
  // Called on render thread where EGL context is already current
  int width = m_pendingWidth.load();
  int height = m_pendingHeight.load();

  std::lock_guard<std::mutex> lock(m_mutex);

  // CRITICAL: After resizing textures attached to an FBO, we must re-attach them
  // to the framebuffer. In OpenGL, glTexImage2D with different dimensions creates
  // new texture storage, and the FBO attachment may become invalid or reference
  // old dimensions. Re-attaching ensures the FBO uses the new texture storage.

  // Resize render texture in-place (NOT delete/recreate)
  glBindTexture(GL_TEXTURE_2D, m_renderTexture);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
  glBindTexture(GL_TEXTURE_2D, 0);

  // Resize depth/stencil buffer in-place
  glBindRenderbuffer(GL_RENDERBUFFER, m_depthStencilBuffer);
  glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, width, height);
  glBindRenderbuffer(GL_RENDERBUFFER, 0);

  // CRITICAL: Re-attach resized textures to framebuffer
  // After glTexImage2D with new dimensions, old FBO attachment becomes invalid
  glBindFramebuffer(GL_FRAMEBUFFER, m_framebuffer);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, m_renderTexture, 0);
  glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER, m_depthStencilBuffer);

  // Verify FBO completeness after resize
  GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
  if (status != GL_FRAMEBUFFER_COMPLETE)
  {
    LOG(LERROR, ("ApplyPendingResize: Framebuffer incomplete:", std::hex, status, "width:", width, "height:", height));
  }
  else
  {
    LOG(LINFO, ("ApplyPendingResize: Framebuffer complete:", width, "x", height));
  }

  // Update viewport and scissor for new size
  glViewport(0, 0, width, height);
  glScissor(0, 0, width, height);

  // Keep FBO bound for subsequent rendering
  // (MakeCurrent will rebind it anyway, but this ensures consistency)

  // Update dimensions
  m_width = width;
  m_height = height;
  m_renderedWidth.store(width);
  m_renderedHeight.store(height);

  LOG(LINFO, ("ApplyPendingResize: Resize complete, dimensions updated to:", width, "x", height));
}

void AgusEglContextFactory::OnFrameReady()
{
  if (m_frameCallback)
    m_frameCallback();
}

void AgusEglContextFactory::RequestActiveFrame()
{
  if (m_keepAliveCallback)
    m_keepAliveCallback();
}

void AgusEglContextFactory::CaptureFramePixels()
{
  // This is called from Present() on the render thread while GL context is current
  int width = m_renderedWidth.load();
  int height = m_renderedHeight.load();
  
  if (width <= 0 || height <= 0)
    return;

  int expectedSize = width * height * 4;  // RGBA

  // Bind framebuffer and read pixels
  glBindFramebuffer(GL_FRAMEBUFFER, m_framebuffer);
  
  // Read pixels into temporary buffer
  std::vector<uint8_t> tempBuffer(expectedSize);
  glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, tempBuffer.data());

  GLenum glError = glGetError();
  if (glError != GL_NO_ERROR)
  {
    LOG(LERROR, ("CaptureFramePixels: glReadPixels failed:", std::hex, glError));
    return;
  }

  // Flip vertically and store in staging buffer
  // (OpenGL origin is bottom-left, Flutter expects top-left)
  std::lock_guard<std::mutex> lock(m_pixelBufferMutex);
  m_pixelBuffer.resize(expectedSize);
  
  int rowSize = width * 4;
  for (int y = 0; y < height; ++y)
  {
    int srcRow = height - 1 - y;  // Bottom-up row
    int dstRow = y;               // Top-down row
    std::memcpy(m_pixelBuffer.data() + dstRow * rowSize, tempBuffer.data() + srcRow * rowSize, rowSize);
  }
}

bool AgusEglContextFactory::CopyToPixelBuffer(uint8_t* buffer, int bufferSize)
{
  // This is called from Flutter's thread - just copy from cached buffer
  // NO GL operations here to avoid context conflicts!
  
  if (!buffer || bufferSize <= 0)
    return false;

  std::lock_guard<std::mutex> lock(m_pixelBufferMutex);
  
  if (m_pixelBuffer.empty())
    return false;

  int copySize = std::min(bufferSize, static_cast<int>(m_pixelBuffer.size()));
  std::memcpy(buffer, m_pixelBuffer.data(), copySize);

  return true;
}

}  // namespace agus

#endif  // defined(__linux__) && !defined(__ANDROID__)
