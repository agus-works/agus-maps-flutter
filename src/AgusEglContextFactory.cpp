/**
 * @file AgusEglContextFactory.cpp
 * @brief Linux EGL context factory implementation for Flutter texture sharing.
 * 
 * This file provides the EGL-based OpenGL context factory used for offscreen
 * rendering on Linux. CoMaps renders to an FBO, and the resulting texture
 * is shared with Flutter via the FlTextureGL API.
 */

#if defined(__linux__) && !defined(__ANDROID__)

#include "AgusEglContextFactory.hpp"

#include "drape/gl_functions.hpp"
#include "drape/oglcontext.hpp"

#include "base/assert.hpp"
#include "base/logging.hpp"

#include <GLES3/gl3.h>
#include <vector>
#include <cstring>

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
                 AgusEglContextFactory * factory, bool isDrawContext)
    : m_display(display)
    , m_surface(surface)
    , m_context(context)
    , m_factory(factory)
    , m_isDrawContext(isDrawContext)
    , m_presentAvailable(true)
  {}

  ~AgusEglContext() override = default;

  void MakeCurrent() override
  {
    if (m_context != EGL_NO_CONTEXT && m_surface != EGL_NO_SURFACE)
    {
      EGLBoolean result = eglMakeCurrent(m_display, m_surface, m_surface, m_context);
      if (result != EGL_TRUE)
      {
        EGLint error = eglGetError();
        LOG(LERROR, ("eglMakeCurrent failed:", std::hex, error));
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

  if (!CreateFramebuffer(width, height))
  {
    LOG(LERROR, ("Failed to create framebuffer"));
    CleanupEGL();
    return;
  }

  m_initialized = true;
  LOG(LINFO, ("EGL context factory created successfully, texture ID:", m_renderTexture));
}

AgusEglContextFactory::~AgusEglContextFactory()
{
  LOG(LINFO, ("Destroying EGL context factory"));

  m_drawContext.reset();
  m_uploadContext.reset();

  CleanupFramebuffer();
  CleanupEGL();
}

bool AgusEglContextFactory::InitializeEGL()
{
  // Get default display
  m_display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
  if (m_display == EGL_NO_DISPLAY)
  {
    LOG(LERROR, ("eglGetDisplay failed"));
    return false;
  }

  // Initialize EGL
  EGLint major, minor;
  if (!eglInitialize(m_display, &major, &minor))
  {
    LOG(LERROR, ("eglInitialize failed"));
    return false;
  }
  LOG(LINFO, ("EGL initialized:", major, ".", minor));

  // Configure EGL for OpenGL ES 3.0
  const EGLint configAttribs[] = {
    EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
    EGL_RED_SIZE, 8,
    EGL_GREEN_SIZE, 8,
    EGL_BLUE_SIZE, 8,
    EGL_ALPHA_SIZE, 8,
    EGL_DEPTH_SIZE, 24,
    EGL_STENCIL_SIZE, 8,
    EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
    EGL_NONE
  };

  EGLint numConfigs;
  if (!eglChooseConfig(m_display, configAttribs, &m_config, 1, &numConfigs) || numConfigs == 0)
  {
    LOG(LERROR, ("eglChooseConfig failed, numConfigs:", numConfigs));
    return false;
  }

  // Create pbuffer surface for draw context
  const EGLint pbufferAttribs[] = {
    EGL_WIDTH, m_width > 0 ? m_width : 1,
    EGL_HEIGHT, m_height > 0 ? m_height : 1,
    EGL_NONE
  };

  m_drawSurface = eglCreatePbufferSurface(m_display, m_config, pbufferAttribs);
  if (m_drawSurface == EGL_NO_SURFACE)
  {
    LOG(LERROR, ("Failed to create draw pbuffer surface"));
    return false;
  }

  // Create second pbuffer for upload context
  m_uploadSurface = eglCreatePbufferSurface(m_display, m_config, pbufferAttribs);
  if (m_uploadSurface == EGL_NO_SURFACE)
  {
    LOG(LERROR, ("Failed to create upload pbuffer surface"));
    eglDestroySurface(m_display, m_drawSurface);
    m_drawSurface = EGL_NO_SURFACE;
    return false;
  }

  // Bind OpenGL ES API
  if (!eglBindAPI(EGL_OPENGL_ES_API))
  {
    LOG(LERROR, ("eglBindAPI failed"));
    return false;
  }

  // Context attributes for OpenGL ES 3.0
  const EGLint contextAttribs[] = {
    EGL_CONTEXT_CLIENT_VERSION, 3,
    EGL_NONE
  };

  // Create draw context
  m_drawEglContext = eglCreateContext(m_display, m_config, EGL_NO_CONTEXT, contextAttribs);
  if (m_drawEglContext == EGL_NO_CONTEXT)
  {
    LOG(LERROR, ("Failed to create draw EGL context"));
    return false;
  }

  // Create upload context that shares with draw context
  m_uploadEglContext = eglCreateContext(m_display, m_config, m_drawEglContext, contextAttribs);
  if (m_uploadEglContext == EGL_NO_CONTEXT)
  {
    LOG(LERROR, ("Failed to create upload EGL context"));
    eglDestroyContext(m_display, m_drawEglContext);
    m_drawEglContext = EGL_NO_CONTEXT;
    return false;
  }

  // Make draw context current temporarily to initialize GL functions
  if (!eglMakeCurrent(m_display, m_drawSurface, m_drawSurface, m_drawEglContext))
  {
    LOG(LERROR, ("Failed to make draw context current"));
    return false;
  }

  // Initialize GL functions
  GLFunctions::Init(dp::ApiVersion::OpenGLES3);

  // IMPORTANT: Release context so render threads can acquire it
  // Without this, MakeCurrent on render threads fails with EGL_BAD_ACCESS
  eglMakeCurrent(m_display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);

  LOG(LINFO, ("EGL contexts created successfully"));
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
  eglMakeCurrent(m_display, m_drawSurface, m_drawSurface, m_drawEglContext);

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
    eglMakeCurrent(m_display, m_drawSurface, m_drawSurface, m_drawEglContext);

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
  if (!m_drawContext && m_drawEglContext != EGL_NO_CONTEXT)
  {
    m_drawContext = std::make_unique<AgusEglContext>(
      m_display, m_drawSurface, m_drawEglContext, this, true /* isDrawContext */);
    LOG(LINFO, ("Draw context created"));
  }
  return m_drawContext.get();
}

dp::GraphicsContext * AgusEglContextFactory::GetResourcesUploadContext()
{
  if (!m_uploadContext && m_uploadEglContext != EGL_NO_CONTEXT)
  {
    m_uploadContext = std::make_unique<AgusEglContext>(
      m_display, m_uploadSurface, m_uploadEglContext, this, false /* isDrawContext */);
    LOG(LINFO, ("Upload context created"));
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
