#if defined(_WIN32) || defined(_WIN64)

#include "AgusWglContextFactory.hpp"

#include "drape/gl_functions.hpp"

#include "base/assert.hpp"
#include "base/logging.hpp"

#include <vector>
#include <cstring>

// OpenGL Extension constants and types for FBO (not in Windows gl.h)
#ifndef GL_FRAMEBUFFER
#define GL_FRAMEBUFFER                    0x8D40
#define GL_RENDERBUFFER                   0x8D41
#define GL_FRAMEBUFFER_COMPLETE           0x8CD5
#define GL_COLOR_ATTACHMENT0              0x8CE0
#define GL_DEPTH_ATTACHMENT               0x8D00
#define GL_STENCIL_ATTACHMENT             0x8D20
#define GL_DEPTH_STENCIL_ATTACHMENT       0x821A
#define GL_DEPTH24_STENCIL8               0x88F0
#define GL_DEPTH_STENCIL                  0x84F9
#endif

// Some Windows OpenGL headers omit this enum even when FBO functions are available.
#ifndef GL_FRAMEBUFFER_BINDING
#define GL_FRAMEBUFFER_BINDING            0x8CA6
#endif

// GL_BGRA_EXT for reading pixels in BGRA format (needed for D3D11 texture)
#ifndef GL_BGRA_EXT
#define GL_BGRA_EXT                       0x80E1
#endif

// OpenGL FBO function pointer types
typedef void (APIENTRY *PFNGLGENFRAMEBUFFERSPROC)(GLsizei n, GLuint *framebuffers);
typedef void (APIENTRY *PFNGLDELETEFRAMEBUFFERSPROC)(GLsizei n, const GLuint *framebuffers);
typedef void (APIENTRY *PFNGLBINDFRAMEBUFFERPROC)(GLenum target, GLuint framebuffer);
typedef void (APIENTRY *PFNGLFRAMEBUFFERTEXTURE2DPROC)(GLenum target, GLenum attachment, GLenum textarget, GLuint texture, GLint level);
typedef GLenum (APIENTRY *PFNGLCHECKFRAMEBUFFERSTATUSPROC)(GLenum target);
typedef void (APIENTRY *PFNGLGENRENDERBUFFERSPROC)(GLsizei n, GLuint *renderbuffers);
typedef void (APIENTRY *PFNGLDELETERENDERBUFFERSPROC)(GLsizei n, const GLuint *renderbuffers);
typedef void (APIENTRY *PFNGLBINDRENDERBUFFERPROC)(GLenum target, GLuint renderbuffer);
typedef void (APIENTRY *PFNGLRENDERBUFFERSTORAGEPROC)(GLenum target, GLenum internalformat, GLsizei width, GLsizei height);
typedef void (APIENTRY *PFNGLFRAMEBUFFERRENDERBUFFERPROC)(GLenum target, GLenum attachment, GLenum renderbuffertarget, GLuint renderbuffer);
typedef void (APIENTRY *PFNGLDRAWBUFFERSPROC)(GLsizei n, const GLenum *bufs);

// Global function pointers for OpenGL FBO operations
static PFNGLGENFRAMEBUFFERSPROC glGenFramebuffers = nullptr;
static PFNGLDELETEFRAMEBUFFERSPROC glDeleteFramebuffers = nullptr;
static PFNGLBINDFRAMEBUFFERPROC glBindFramebuffer = nullptr;
static PFNGLFRAMEBUFFERTEXTURE2DPROC glFramebufferTexture2D = nullptr;
static PFNGLCHECKFRAMEBUFFERSTATUSPROC glCheckFramebufferStatus = nullptr;
static PFNGLGENRENDERBUFFERSPROC glGenRenderbuffers = nullptr;
static PFNGLDELETERENDERBUFFERSPROC glDeleteRenderbuffers = nullptr;
static PFNGLBINDRENDERBUFFERPROC glBindRenderbuffer = nullptr;
static PFNGLRENDERBUFFERSTORAGEPROC glRenderbufferStorage = nullptr;
static PFNGLFRAMEBUFFERRENDERBUFFERPROC glFramebufferRenderbuffer = nullptr;
static PFNGLDRAWBUFFERSPROC glDrawBuffers = nullptr;

// Helper to load OpenGL FBO extensions
static bool LoadFBOExtensions()
{
  glGenFramebuffers = (PFNGLGENFRAMEBUFFERSPROC)wglGetProcAddress("glGenFramebuffers");
  glDeleteFramebuffers = (PFNGLDELETEFRAMEBUFFERSPROC)wglGetProcAddress("glDeleteFramebuffers");
  glBindFramebuffer = (PFNGLBINDFRAMEBUFFERPROC)wglGetProcAddress("glBindFramebuffer");
  glFramebufferTexture2D = (PFNGLFRAMEBUFFERTEXTURE2DPROC)wglGetProcAddress("glFramebufferTexture2D");
  glCheckFramebufferStatus = (PFNGLCHECKFRAMEBUFFERSTATUSPROC)wglGetProcAddress("glCheckFramebufferStatus");
  glGenRenderbuffers = (PFNGLGENRENDERBUFFERSPROC)wglGetProcAddress("glGenRenderbuffers");
  glDeleteRenderbuffers = (PFNGLDELETERENDERBUFFERSPROC)wglGetProcAddress("glDeleteRenderbuffers");
  glBindRenderbuffer = (PFNGLBINDRENDERBUFFERPROC)wglGetProcAddress("glBindRenderbuffer");
  glRenderbufferStorage = (PFNGLRENDERBUFFERSTORAGEPROC)wglGetProcAddress("glRenderbufferStorage");
  glFramebufferRenderbuffer = (PFNGLFRAMEBUFFERRENDERBUFFERPROC)wglGetProcAddress("glFramebufferRenderbuffer");
  glDrawBuffers = (PFNGLDRAWBUFFERSPROC)wglGetProcAddress("glDrawBuffers");

  return glGenFramebuffers && glDeleteFramebuffers && glBindFramebuffer &&
         glFramebufferTexture2D && glCheckFramebufferStatus &&
         glGenRenderbuffers && glDeleteRenderbuffers && glBindRenderbuffer &&
         glRenderbufferStorage && glFramebufferRenderbuffer && glDrawBuffers;
}

namespace agus
{

namespace
{
// Window class name for hidden window
const wchar_t * kWindowClassName = L"AgusWglHiddenWindow";
bool g_windowClassRegistered = false;

LRESULT CALLBACK HiddenWindowProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
  return DefWindowProcW(hwnd, msg, wParam, lParam);
}

bool RegisterWindowClass()
{
  if (g_windowClassRegistered)
    return true;

  WNDCLASSEXW wc = {};
  wc.cbSize = sizeof(WNDCLASSEXW);
  wc.style = CS_OWNDC;
  wc.lpfnWndProc = HiddenWindowProc;
  wc.hInstance = GetModuleHandleW(nullptr);
  wc.lpszClassName = kWindowClassName;

  if (RegisterClassExW(&wc) == 0)
  {
    LOG(LERROR, ("Failed to register window class:", GetLastError()));
    return false;
  }

  g_windowClassRegistered = true;
  return true;
}

}  // namespace

// ============================================================================
// AgusWglContextFactory
// ============================================================================

AgusWglContextFactory::AgusWglContextFactory(int width, int height)
  : m_width(width)
  , m_height(height)
{
  LOG(LINFO, ("Creating WGL context factory:", width, "x", height));
  
  // Initialize rendered size to match initial dimensions
  m_renderedWidth.store(width);
  m_renderedHeight.store(height);

  if (!InitializeWGL())
  {
    LOG(LERROR, ("Failed to initialize WGL"));
    return;
  }

  if (!InitializeD3D11())
  {
    LOG(LERROR, ("Failed to initialize D3D11"));
    CleanupWGL();
    return;
  }

  if (!CreateSharedTexture(width, height))
  {
    LOG(LERROR, ("Failed to create shared texture"));
    CleanupD3D11();
    CleanupWGL();
    return;
  }

  LOG(LINFO, ("WGL context factory created successfully"));
}

AgusWglContextFactory::~AgusWglContextFactory()
{
  m_drawContext.reset();
  m_uploadContext.reset();

  // Delete OpenGL resources
  if (m_drawGlrc)
  {
    wglMakeCurrent(m_hdc, m_drawGlrc);
    if (m_framebuffer)
      glDeleteFramebuffers(1, &m_framebuffer);
    if (m_renderTexture)
      glDeleteTextures(1, &m_renderTexture);
    if (m_depthBuffer)
      glDeleteRenderbuffers(1, &m_depthBuffer);
    wglMakeCurrent(nullptr, nullptr);
  }

  CleanupWGL();
  CleanupD3D11();
}

bool AgusWglContextFactory::InitializeWGL()
{
  if (!RegisterWindowClass())
    return false;

  // Create hidden window for OpenGL context
  m_hiddenWindow = CreateWindowExW(
    0,
    kWindowClassName,
    L"AgusWglHiddenWindow",
    WS_POPUP,
    0, 0, 1, 1,
    nullptr, nullptr,
    GetModuleHandleW(nullptr),
    nullptr
  );

  if (!m_hiddenWindow)
  {
    LOG(LERROR, ("Failed to create hidden window:", GetLastError()));
    return false;
  }

  m_hdc = GetDC(m_hiddenWindow);
  if (!m_hdc)
  {
    LOG(LERROR, ("Failed to get DC"));
    DestroyWindow(m_hiddenWindow);
    m_hiddenWindow = nullptr;
    return false;
  }

  // Set pixel format
  PIXELFORMATDESCRIPTOR pfd = {};
  pfd.nSize = sizeof(PIXELFORMATDESCRIPTOR);
  pfd.nVersion = 1;
  pfd.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER;
  pfd.iPixelType = PFD_TYPE_RGBA;
  pfd.cColorBits = 32;
  pfd.cDepthBits = 24;
  pfd.cStencilBits = 8;
  pfd.iLayerType = PFD_MAIN_PLANE;

  int pixelFormat = ChoosePixelFormat(m_hdc, &pfd);
  if (pixelFormat == 0)
  {
    LOG(LERROR, ("Failed to choose pixel format:", GetLastError()));
    ReleaseDC(m_hiddenWindow, m_hdc);
    DestroyWindow(m_hiddenWindow);
    m_hdc = nullptr;
    m_hiddenWindow = nullptr;
    return false;
  }

  if (!SetPixelFormat(m_hdc, pixelFormat, &pfd))
  {
    LOG(LERROR, ("Failed to set pixel format:", GetLastError()));
    ReleaseDC(m_hiddenWindow, m_hdc);
    DestroyWindow(m_hiddenWindow);
    m_hdc = nullptr;
    m_hiddenWindow = nullptr;
    return false;
  }

  // Create draw context
  m_drawGlrc = wglCreateContext(m_hdc);
  if (!m_drawGlrc)
  {
    LOG(LERROR, ("Failed to create draw GL context:", GetLastError()));
    ReleaseDC(m_hiddenWindow, m_hdc);
    DestroyWindow(m_hiddenWindow);
    m_hdc = nullptr;
    m_hiddenWindow = nullptr;
    return false;
  }

  // Create upload context that shares with draw context
  m_uploadGlrc = wglCreateContext(m_hdc);
  if (!m_uploadGlrc)
  {
    LOG(LERROR, ("Failed to create upload GL context:", GetLastError()));
    wglDeleteContext(m_drawGlrc);
    m_drawGlrc = nullptr;
    ReleaseDC(m_hiddenWindow, m_hdc);
    DestroyWindow(m_hiddenWindow);
    m_hdc = nullptr;
    m_hiddenWindow = nullptr;
    return false;
  }

  // Share resources between contexts
  if (!wglShareLists(m_drawGlrc, m_uploadGlrc))
  {
    LOG(LWARNING, ("Failed to share GL lists between contexts:", GetLastError()));
    // Continue anyway, resource sharing may still work
  }

  // Create framebuffer for offscreen rendering
  wglMakeCurrent(m_hdc, m_drawGlrc);

  // Load FBO extensions (must be done after context is current)
  if (!LoadFBOExtensions())
  {
    LOG(LERROR, ("Failed to load OpenGL FBO extensions"));
    wglMakeCurrent(nullptr, nullptr);
    return false;
  }

  // Initialize GL functions
  GLFunctions::Init(dp::ApiVersion::OpenGLES3);

  // Create framebuffer
  glGenFramebuffers(1, &m_framebuffer);
  glGenTextures(1, &m_renderTexture);
  glGenRenderbuffers(1, &m_depthBuffer);

  // Setup render texture
  glBindTexture(GL_TEXTURE_2D, m_renderTexture);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, m_width, m_height, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glBindTexture(GL_TEXTURE_2D, 0);

  // Setup depth buffer
  glBindRenderbuffer(GL_RENDERBUFFER, m_depthBuffer);
  glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, m_width, m_height);
  glBindRenderbuffer(GL_RENDERBUFFER, 0);

  // Attach to framebuffer
  glBindFramebuffer(GL_FRAMEBUFFER, m_framebuffer);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, m_renderTexture, 0);
  glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER, m_depthBuffer);
  
  // Explicitly set draw buffer to COLOR_ATTACHMENT0 (required for custom FBOs)
  GLenum drawBuffers[] = { GL_COLOR_ATTACHMENT0 };
  glDrawBuffers(1, drawBuffers);

  GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
  if (status != GL_FRAMEBUFFER_COMPLETE)
  {
    LOG(LERROR, ("Framebuffer incomplete:", status));
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    wglMakeCurrent(nullptr, nullptr);
    return false;
  }

  // Initialize viewport and scissor to full framebuffer size
  // CRITICAL: Scissor test will be enabled in Init(), and if scissor rect
  // is not set, it defaults to (0,0,0,0) which clips all rendering!
  glViewport(0, 0, m_width, m_height);
  glScissor(0, 0, m_width, m_height);
  LOG(LINFO, ("Initialized viewport/scissor to:", m_width, m_height));

  glBindFramebuffer(GL_FRAMEBUFFER, 0);
  wglMakeCurrent(nullptr, nullptr);

  LOG(LINFO, ("WGL initialized successfully"));
  return true;
}

bool AgusWglContextFactory::InitializeD3D11()
{
  UINT createFlags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;
#ifdef DEBUG
  createFlags |= D3D11_CREATE_DEVICE_DEBUG;
#endif

  D3D_FEATURE_LEVEL featureLevels[] = {
    D3D_FEATURE_LEVEL_11_1,
    D3D_FEATURE_LEVEL_11_0,
    D3D_FEATURE_LEVEL_10_1,
    D3D_FEATURE_LEVEL_10_0,
  };

  D3D_FEATURE_LEVEL featureLevel;
  HRESULT hr = D3D11CreateDevice(
    nullptr,
    D3D_DRIVER_TYPE_HARDWARE,
    nullptr,
    createFlags,
    featureLevels,
    ARRAYSIZE(featureLevels),
    D3D11_SDK_VERSION,
    &m_d3dDevice,
    &featureLevel,
    &m_d3dContext
  );

  if (FAILED(hr))
  {
    LOG(LERROR, ("Failed to create D3D11 device:", hr));
    return false;
  }

  LOG(LINFO, ("D3D11 device created, feature level:", featureLevel));
  return true;
}

bool AgusWglContextFactory::CreateSharedTexture(int width, int height)
{
  // Close existing handle
  if (m_sharedHandle)
  {
    CloseHandle(m_sharedHandle);
    m_sharedHandle = nullptr;
  }

  m_sharedTexture.Reset();
  m_stagingTexture.Reset();

  // Create shared texture for Flutter
  D3D11_TEXTURE2D_DESC sharedDesc = {};
  sharedDesc.Width = width;
  sharedDesc.Height = height;
  sharedDesc.MipLevels = 1;
  sharedDesc.ArraySize = 1;
  sharedDesc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  sharedDesc.SampleDesc.Count = 1;
  sharedDesc.SampleDesc.Quality = 0;
  sharedDesc.Usage = D3D11_USAGE_DEFAULT;
  sharedDesc.BindFlags = D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_RENDER_TARGET;
  sharedDesc.CPUAccessFlags = 0;
  sharedDesc.MiscFlags = D3D11_RESOURCE_MISC_SHARED;

  HRESULT hr = m_d3dDevice->CreateTexture2D(&sharedDesc, nullptr, &m_sharedTexture);
  if (FAILED(hr))
  {
    LOG(LERROR, ("Failed to create shared texture:", hr));
    return false;
  }

  // Get shared handle
  Microsoft::WRL::ComPtr<IDXGIResource> dxgiResource;
  hr = m_sharedTexture.As(&dxgiResource);
  if (FAILED(hr))
  {
    LOG(LERROR, ("Failed to get DXGI resource:", hr));
    return false;
  }

  hr = dxgiResource->GetSharedHandle(&m_sharedHandle);
  if (FAILED(hr))
  {
    LOG(LERROR, ("Failed to get shared handle:", hr));
    return false;
  }

  // Create staging texture for CPU copy
  D3D11_TEXTURE2D_DESC stagingDesc = sharedDesc;
  stagingDesc.Usage = D3D11_USAGE_STAGING;
  stagingDesc.BindFlags = 0;
  stagingDesc.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
  stagingDesc.MiscFlags = 0;

  hr = m_d3dDevice->CreateTexture2D(&stagingDesc, nullptr, &m_stagingTexture);
  if (FAILED(hr))
  {
    LOG(LERROR, ("Failed to create staging texture:", hr));
    return false;
  }

  m_width = width;
  m_height = height;

  LOG(LINFO, ("Shared texture created:", width, "x", height, "handle:", m_sharedHandle));
  return true;
}

void AgusWglContextFactory::CleanupWGL()
{
  if (m_uploadGlrc)
  {
    wglDeleteContext(m_uploadGlrc);
    m_uploadGlrc = nullptr;
  }

  if (m_drawGlrc)
  {
    wglDeleteContext(m_drawGlrc);
    m_drawGlrc = nullptr;
  }

  if (m_hdc && m_hiddenWindow)
  {
    ReleaseDC(m_hiddenWindow, m_hdc);
    m_hdc = nullptr;
  }

  if (m_hiddenWindow)
  {
    DestroyWindow(m_hiddenWindow);
    m_hiddenWindow = nullptr;
  }
}

void AgusWglContextFactory::CleanupD3D11()
{
  if (m_sharedHandle)
  {
    CloseHandle(m_sharedHandle);
    m_sharedHandle = nullptr;
  }

  m_stagingTexture.Reset();
  m_sharedTexture.Reset();
  m_d3dContext.Reset();
  m_d3dDevice.Reset();
}

dp::GraphicsContext * AgusWglContextFactory::GetDrawContext()
{
  if (!m_drawContext)
  {
    m_drawContext = std::make_unique<AgusWglContext>(m_hdc, m_drawGlrc, this, true);
  }
  return m_drawContext.get();
}

dp::GraphicsContext * AgusWglContextFactory::GetResourcesUploadContext()
{
  if (!m_uploadContext)
  {
    m_uploadContext = std::make_unique<AgusWglContext>(m_hdc, m_uploadGlrc, this, false);
  }
  return m_uploadContext.get();
}

void AgusWglContextFactory::SetSurfaceSize(int width, int height)
{
  std::lock_guard<std::mutex> lock(m_mutex);

  if (m_width == width && m_height == height)
    return;

  LOG(LINFO, ("Resizing surface:", width, "x", height));

  // Save current context to restore after
  HGLRC prevContext = wglGetCurrentContext();
  HDC prevDC = wglGetCurrentDC();

  // Make our draw context current for GL operations
  if (!wglMakeCurrent(m_hdc, m_drawGlrc))
  {
    DWORD err = GetLastError();
    LOG(LERROR, ("SetSurfaceSize: wglMakeCurrent failed", err));
    return;
  }

  // CRITICAL: After resizing textures attached to an FBO, we must re-attach them
  // to the framebuffer. In OpenGL, glTexImage2D with different dimensions creates
  // new texture storage, and the FBO attachment may become invalid or reference
  // old dimensions. Re-attaching ensures the FBO uses the new texture storage.

  // Update render texture size
  glBindTexture(GL_TEXTURE_2D, m_renderTexture);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
  glBindTexture(GL_TEXTURE_2D, 0);

  // Update depth/stencil buffer size
  glBindRenderbuffer(GL_RENDERBUFFER, m_depthBuffer);
  glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, width, height);
  glBindRenderbuffer(GL_RENDERBUFFER, 0);

  // CRITICAL: Re-attach resized textures to the framebuffer
  // This is necessary because the texture storage changed when we called glTexImage2D.
  // Without this, the FBO may still reference the old texture dimensions.
  glBindFramebuffer(GL_FRAMEBUFFER, m_framebuffer);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, m_renderTexture, 0);
  glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER, m_depthBuffer);

  // Ensure the draw buffer points at COLOR_ATTACHMENT0 after re-attachment.
  GLenum drawBuffers[] = { GL_COLOR_ATTACHMENT0 };
  glDrawBuffers(1, drawBuffers);

  // Verify FBO is complete after resize
  GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
  if (status != GL_FRAMEBUFFER_COMPLETE)
  {
    LOG(LERROR, ("Framebuffer incomplete after resize:", status, "width:", width, "height:", height));
  }
  else
  {
    LOG(LINFO, ("Framebuffer verified complete after resize:", width, "x", height));
  }

  // Set viewport and scissor for the new size while FBO is bound
  // NOTE: These state changes apply to the current context. When rendering happens,
  // CoMaps will call SetViewport() which sets both viewport and scissor.
  glViewport(0, 0, width, height);
  glScissor(0, 0, width, height);
  LOG(LINFO, ("Updated viewport/scissor on resize to:", width, height));

  glBindFramebuffer(GL_FRAMEBUFFER, 0);

  // Restore previous context
  if (prevContext != nullptr)
    wglMakeCurrent(prevDC, prevContext);
  else
    wglMakeCurrent(nullptr, nullptr);

  // Update dimensions
  m_width = width;
  m_height = height;

  // Recreate D3D11 shared texture at new size
  CreateSharedTexture(width, height);
}

void AgusWglContextFactory::OnFrameReady()
{
  CopyToSharedTexture();

  if (m_frameCallback)
    m_frameCallback();
}

void AgusWglContextFactory::RequestActiveFrame()
{
  // Call the registered keep-alive callback to mark the next frame as active.
  // This prevents the render loop from suspending during initial tile loading.
  if (m_keepAliveCallback)
    m_keepAliveCallback();
}

// Static counter for frame logging (limit spam)
static int s_frameCount = 0;
static const int kLogEveryNFrames = 60;  // Log once per second at 60fps

void AgusWglContextFactory::CopyToSharedTexture()
{
  std::lock_guard<std::mutex> lock(m_mutex);

  if (!m_stagingTexture || !m_sharedTexture)
  {
    if (s_frameCount % kLogEveryNFrames == 0)
      LOG(LWARNING, ("CopyToSharedTexture: staging or shared texture missing"));
    return;
  }

  // Save current context state - the render thread should have context current
  HGLRC prevContext = wglGetCurrentContext();
  HDC prevDC = wglGetCurrentDC();
  bool wasOurContext = (prevContext == m_drawGlrc);

  // Make OpenGL context current if not already
  if (!wasOurContext)
    wglMakeCurrent(m_hdc, m_drawGlrc);

  // Bind the framebuffer that CoMaps most recently rendered into.
  // CoMaps may bind a provided (postprocess) FBO; reading only from m_framebuffer
  // can result in consistently blank frames even though rendering is happening.
  GLuint fboToRead = m_lastBoundFramebuffer.load();
  if (fboToRead == 0)
    fboToRead = m_framebuffer;
  glBindFramebuffer(GL_FRAMEBUFFER, fboToRead);

  // CRITICAL: Query the current viewport to determine the actual rendered size.
  // During resize, m_width/m_height may already be updated to the NEW size,
  // but the frame being presented was rendered at the OLD size (as indicated
  // by the viewport). Reading pixels at m_width/m_height when the frame was
  // rendered at a smaller viewport causes black/garbage pixels in the
  // expanded region.
  GLint viewport[4];
  glGetIntegerv(GL_VIEWPORT, viewport);
  int readWidth = viewport[2];
  int readHeight = viewport[3];
  
  // Sanity check: viewport should be positive and not exceed target dimensions
  if (readWidth <= 0 || readHeight <= 0)
  {
    readWidth = m_width;
    readHeight = m_height;
  }
  // Clamp to target dimensions in case of weird state
  if (readWidth > m_width) readWidth = m_width;
  if (readHeight > m_height) readHeight = m_height;

  // Check FBO completeness and GL errors (debugging)
  if (s_frameCount % kLogEveryNFrames == 0)
  {
    GLenum fboStatus = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    GLenum glErr = glGetError();
    if (fboStatus != GL_FRAMEBUFFER_COMPLETE || glErr != GL_NO_ERROR)
    {
      LOG(LERROR, ("FBO status:", fboStatus, "GL error:", glErr, "for FBO", fboToRead));
    }
    
    // Log current scissor and viewport state
    GLint scissorBox[4];
    glGetIntegerv(GL_SCISSOR_BOX, scissorBox);
    LOG(LINFO, ("CopyToSharedTexture scissor:", scissorBox[0], scissorBox[1], scissorBox[2], scissorBox[3],
                "viewport:", viewport[0], viewport[1], viewport[2], viewport[3],
                "readSize:", readWidth, "x", readHeight, "targetSize:", m_width, "x", m_height));
  }

  // CRITICAL: Ensure all OpenGL rendering commands are complete before reading.
  // Without this, glReadPixels may read incomplete/stale framebuffer content.
  glFinish();

  // Update rendered size tracking - this represents the actual rendered dimensions
  m_renderedWidth.store(readWidth);
  m_renderedHeight.store(readHeight);

  // Read pixels from OpenGL at the RENDERED size, not the target size
  // (use GL_RGBA for maximum compatibility)
  std::vector<uint8_t> pixels(readWidth * readHeight * 4);
  glReadPixels(0, 0, readWidth, readHeight, GL_RGBA, GL_UNSIGNED_BYTE, pixels.data());
  
  // Check for GL errors after read
  if (s_frameCount % kLogEveryNFrames == 0)
  {
    GLenum glErr = glGetError();
    if (glErr != GL_NO_ERROR)
    {
      LOG(LERROR, ("glReadPixels error:", glErr));
    }
  }

  // Check if we got any non-zero pixels (for debugging blank frames)
  if (s_frameCount % kLogEveryNFrames == 0)
  {
    bool hasContent = false;
    uint32_t uniqueColors = 0;
    uint32_t lastR = 256, lastG = 256, lastB = 256;
    uint8_t firstNonBlackR = 0, firstNonBlackG = 0, firstNonBlackB = 0, firstNonBlackA = 0;
    size_t firstNonBlackIdx = 0;
    
    // Sample some pixels to see if we have content and color variety
    for (size_t i = 0; i < pixels.size() && uniqueColors < 10; i += 4000)
    {
      uint8_t r = pixels[i];
      uint8_t g = pixels[i+1];
      uint8_t b = pixels[i+2];
      uint8_t a = pixels[i+3];
      // RGBA format - check if not black and not the clear color
      if ((r != 0 || g != 0 || b != 0) && !hasContent)
      {
        hasContent = true;
        firstNonBlackR = r;
        firstNonBlackG = g;
        firstNonBlackB = b;
        firstNonBlackA = a;
        firstNonBlackIdx = i / 4;  // Pixel index
      }
      // Count unique colors to detect if we have varied content vs solid fill
      if (r != lastR || g != lastG || b != lastB)
      {
        uniqueColors++;
        lastR = r; lastG = g; lastB = b;
      }
    }
    
    // Sample corner pixels for debugging (use readWidth/readHeight)
    size_t topLeftIdx = 0;
    size_t topRightIdx = (readWidth - 1) * 4;
    size_t bottomLeftIdx = (readHeight - 1) * readWidth * 4;
    size_t bottomRightIdx = ((readHeight - 1) * readWidth + (readWidth - 1)) * 4;
    size_t centerIdx = (readHeight / 2 * readWidth + readWidth / 2) * 4;
    
    uint8_t centerR = pixels[centerIdx];
    uint8_t centerG = pixels[centerIdx + 1];
    uint8_t centerB = pixels[centerIdx + 2];
    uint8_t centerA = pixels[centerIdx + 3];
    
    // Log FBO we read from
    GLuint actualFBO = m_lastBoundFramebuffer.load();
    
    LOG(LINFO, ("Frame", s_frameCount, "readSize:", readWidth, "x", readHeight, 
                "targetSize:", m_width, "x", m_height, "FBO:", actualFBO,
                "hasContent:", hasContent, "uniqueColors:", uniqueColors,
                "centerRGBA:", (int)centerR, (int)centerG, (int)centerB, (int)centerA));
    
    if (hasContent)
    {
      LOG(LINFO, ("  FirstNonBlack at pixel", firstNonBlackIdx, "RGBA:",
                  (int)firstNonBlackR, (int)firstNonBlackG, (int)firstNonBlackB, (int)firstNonBlackA));
    }
    
    // Log corners
    LOG(LINFO, ("  Corners TL:", (int)pixels[topLeftIdx], (int)pixels[topLeftIdx+1], 
                (int)pixels[topLeftIdx+2], (int)pixels[topLeftIdx+3],
                "TR:", (int)pixels[topRightIdx], (int)pixels[topRightIdx+1],
                (int)pixels[topRightIdx+2], (int)pixels[topRightIdx+3]));
    LOG(LINFO, ("  Corners BL:", (int)pixels[bottomLeftIdx], (int)pixels[bottomLeftIdx+1], 
                (int)pixels[bottomLeftIdx+2], (int)pixels[bottomLeftIdx+3],
                "BR:", (int)pixels[bottomRightIdx], (int)pixels[bottomRightIdx+1],
                (int)pixels[bottomRightIdx+2], (int)pixels[bottomRightIdx+3]));
  }
  s_frameCount++;

  glBindFramebuffer(GL_FRAMEBUFFER, 0);
  
  // Restore previous context state
  if (!wasOurContext)
  {
    if (prevContext != nullptr)
      wglMakeCurrent(prevDC, prevContext);
    else
      wglMakeCurrent(nullptr, nullptr);
  }
  // If it was our context, leave it current

  // CRITICAL: Handle size mismatch during resize transition.
  // If the viewport (rendered size) doesn't match the target size, we have two options:
  // 1. Skip the copy entirely (causes visible stutter)
  // 2. Copy what we have and let Flutter scale it (smooth but momentary distortion)
  // 
  // We choose option 2: copy the rendered content to the D3D11 texture.
  // When readWidth/readHeight < m_width/m_height, we fill the rendered portion
  // and clear the rest to the clear color to avoid garbage.
  
  // Copy to D3D11 staging texture
  D3D11_MAPPED_SUBRESOURCE mapped;
  HRESULT hr = m_d3dContext->Map(m_stagingTexture.Get(), 0, D3D11_MAP_WRITE, 0, &mapped);
  if (SUCCEEDED(hr))
  {
    uint8_t * dst = static_cast<uint8_t *>(mapped.pData);
    
    // If sizes match, use the fast path
    if (readWidth == m_width && readHeight == m_height)
    {
      // OpenGL has flipped Y, and we need to convert RGBA to BGRA for D3D11
      for (int y = 0; y < m_height; ++y)
      {
        int srcY = m_height - 1 - y;  // Flip Y
        const uint8_t * srcRow = pixels.data() + srcY * m_width * 4;
        uint8_t * dstRow = dst + y * mapped.RowPitch;
        for (int x = 0; x < m_width; ++x)
        {
          // Convert RGBA to BGRA
          dstRow[x * 4 + 0] = srcRow[x * 4 + 2];  // B <- R
          dstRow[x * 4 + 1] = srcRow[x * 4 + 1];  // G <- G
          dstRow[x * 4 + 2] = srcRow[x * 4 + 0];  // R <- B
          dstRow[x * 4 + 3] = srcRow[x * 4 + 3];  // A <- A
        }
      }
    }
    else
    {
      // Size mismatch - copy rendered portion and clear the rest
      // Clear entire texture first (BGRA black with alpha 255)
      for (int y = 0; y < m_height; ++y)
      {
        uint8_t * dstRow = dst + y * mapped.RowPitch;
        memset(dstRow, 0, m_width * 4);  // Clear to black
        // Set alpha to 255 for all pixels
        for (int x = 0; x < m_width; ++x)
        {
          dstRow[x * 4 + 3] = 255;
        }
      }
      
      // Now copy the rendered portion with Y flip and RGBA->BGRA conversion
      // The rendered content goes to top-left corner of target texture
      for (int y = 0; y < readHeight && y < m_height; ++y)
      {
        int srcY = readHeight - 1 - y;  // Flip Y (relative to readHeight)
        const uint8_t * srcRow = pixels.data() + srcY * readWidth * 4;
        uint8_t * dstRow = dst + y * mapped.RowPitch;
        for (int x = 0; x < readWidth && x < m_width; ++x)
        {
          // Convert RGBA to BGRA
          dstRow[x * 4 + 0] = srcRow[x * 4 + 2];  // B <- R
          dstRow[x * 4 + 1] = srcRow[x * 4 + 1];  // G <- G
          dstRow[x * 4 + 2] = srcRow[x * 4 + 0];  // R <- B
          dstRow[x * 4 + 3] = srcRow[x * 4 + 3];  // A <- A
        }
      }
      
      if (s_frameCount % kLogEveryNFrames == 0)
      {
        LOG(LINFO, ("CopyToSharedTexture: size mismatch, read:", readWidth, "x", readHeight,
                    "target:", m_width, "x", m_height, "- copied partial frame"));
      }
    }
    
    m_d3dContext->Unmap(m_stagingTexture.Get(), 0);

    // Copy staging to shared texture
    m_d3dContext->CopyResource(m_sharedTexture.Get(), m_stagingTexture.Get());
    
    // CRITICAL: Flush the D3D11 context to ensure the copy is complete
    // before Flutter's GPU process samples the shared texture.
    // Without this, Flutter may sample stale/incomplete data.
    m_d3dContext->Flush();
  }
  else
  {
    if (s_frameCount % kLogEveryNFrames == 0)
      LOG(LERROR, ("Failed to map staging texture:", hr));
  }
}

// ============================================================================
// AgusWglContext
// ============================================================================

AgusWglContext::AgusWglContext(HDC hdc, HGLRC glrc, AgusWglContextFactory * factory, bool isDraw)
  : m_hdc(hdc)
  , m_glrc(glrc)
  , m_factory(factory)
  , m_isDraw(isDraw)
{
}

AgusWglContext::~AgusWglContext()
{
}

bool AgusWglContext::BeginRendering()
{
  return true;
}

void AgusWglContext::EndRendering()
{
}

void AgusWglContext::Present()
{
  if (m_isDraw && m_factory)
  {
    m_factory->OnFrameReady();
    
    // For the first few frames after DrapeEngine creation, ALSO call MakeFrameActive
    // to keep the render loop running. This ensures tiles load properly even when
    // the render loop would otherwise suspend due to no "active" content.
    // Without this, the render loop suspends after kMaxInactiveFrames (2) inactive
    // frames, before tiles have a chance to arrive from the BackendRenderer.
    if (m_initialFrameCount > 0)
    {
      m_initialFrameCount--;
      // Request another active frame to keep the render loop running
      // This is done by calling the factory's KeepAlive function
      m_factory->RequestActiveFrame();
    }
  }
}

void AgusWglContext::MakeCurrent()
{
  if (!wglMakeCurrent(m_hdc, m_glrc))
  {
    DWORD error = GetLastError();
    LOG(LERROR, ("wglMakeCurrent failed:", error, "hdc:", m_hdc, "glrc:", m_glrc));
  }
  else
  {
    // Verify context is actually current
    HGLRC current = wglGetCurrentContext();
    if (current != m_glrc)
    {
      LOG(LERROR, ("wglMakeCurrent succeeded but context mismatch! expected:", m_glrc, "got:", current));
    }
  }

  // For draw context, bind offscreen framebuffer
  if (m_isDraw && m_factory)
  {
    glBindFramebuffer(GL_FRAMEBUFFER, m_factory->m_framebuffer);
  }
}

void AgusWglContext::DoneCurrent()
{
  if (m_isDraw)
  {
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
  }
  wglMakeCurrent(nullptr, nullptr);
}

// Static counter for SetFramebuffer logging (limit spam)
static int s_setFramebufferLogCount = 0;
static const int kSetFramebufferLogEveryN = 120;  // Log twice per second at 60fps

void AgusWglContext::SetFramebuffer(ref_ptr<dp::BaseFramebuffer> framebuffer)
{
  // CRITICAL: When framebuffer is nullptr, CoMaps expects the "default" framebuffer
  // to be bound. For desktop GL with window surface, this is FBO 0.
  // But for our offscreen rendering setup, the "default" is our custom FBO.
  // This is similar to how Qt's qtoglcontext.cpp handles it by binding m_backFrame.
  if (framebuffer)
  {
    framebuffer->Bind();
    if (s_setFramebufferLogCount % kSetFramebufferLogEveryN == 0)
      LOG(LINFO, ("SetFramebuffer: Binding provided FBO (postprocess pass)"));

    if (m_isDraw && m_factory)
    {
      GLint bound = 0;
      glGetIntegerv(GL_FRAMEBUFFER_BINDING, &bound);
      m_factory->m_lastBoundFramebuffer.store(static_cast<GLuint>(bound));
    }
  }
  else if (m_isDraw && m_factory)
  {
    // Bind our offscreen FBO as the "default" framebuffer
    GLuint fbo = m_factory->m_framebuffer;
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    if (s_setFramebufferLogCount % kSetFramebufferLogEveryN == 0)
      LOG(LINFO, ("SetFramebuffer(nullptr): Bound offscreen FBO", fbo, "isDraw:", m_isDraw));

    m_factory->m_lastBoundFramebuffer.store(fbo);
  }
  else
  {
    // Not a draw context or no factory - bind FBO 0
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    if (s_setFramebufferLogCount % kSetFramebufferLogEveryN == 0)
      LOG(LINFO, ("SetFramebuffer(nullptr): Upload context, binding FBO 0"));
  }
  s_setFramebufferLogCount++;
}

void AgusWglContext::ForgetFramebuffer(ref_ptr<dp::BaseFramebuffer> framebuffer)
{
  // Not used for default framebuffer
}

void AgusWglContext::ApplyFramebuffer(std::string const & framebufferLabel)
{
  // IMPORTANT: ApplyFramebuffer should NOT re-bind a framebuffer.
  // SetFramebuffer() already handles binding the correct FBO (either our offscreen
  // FBO or the postprocess FBO). ApplyFramebuffer is called AFTER SetFramebuffer
  // and is primarily for Metal/Vulkan to do encoding setup. For OpenGL, this
  // should be a no-op.
  // 
  // The Qt implementation (qtoglcontext.cpp) also has an empty ApplyFramebuffer.
  // 
  // Previously, this code was re-binding m_factory->m_framebuffer which was
  // overriding the postprocess FBO that was just bound by SetFramebuffer,
  // causing all rendering to go to our FBO instead of the postprocess FBO,
  // resulting in only the clear color being visible.
}

void AgusWglContext::Init(dp::ApiVersion apiVersion)
{
  // GLFunctions already initialized in factory constructor via GLFunctions::Init()
  // But we need to set up the initial GL state like OGLContext::Init() does
  
  // Pixel alignment for texture uploads
  glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
  
  // Depth testing setup
  glClearDepth(1.0);
  glDepthFunc(GL_LEQUAL);
  glDepthMask(GL_TRUE);
  
  // Face culling - important for proper rendering
  glFrontFace(GL_CW);
  glCullFace(GL_BACK);
  glEnable(GL_CULL_FACE);
  
  // Scissor test - CRITICAL: CoMaps expects scissor to be enabled
  glEnable(GL_SCISSOR_TEST);
  
  // CRITICAL: Set initial scissor and viewport to full framebuffer size
  // Without this, the scissor rect defaults to (0,0,0,0) or (0,0,1,1)
  // which clips all rendering!
  if (m_factory)
  {
    int w = m_factory->m_width;
    int h = m_factory->m_height;
    glViewport(0, 0, w, h);
    glScissor(0, 0, w, h);
    LOG(LINFO, ("AgusWglContext::Init - set viewport/scissor to:", w, "x", h));
  }
  
  // Log current scissor box to verify
  GLint scissorBox[4];
  glGetIntegerv(GL_SCISSOR_BOX, scissorBox);
  LOG(LINFO, ("AgusWglContext::Init completed, scissor box:", 
              scissorBox[0], scissorBox[1], scissorBox[2], scissorBox[3]));
}

std::string AgusWglContext::GetRendererName() const
{
  // Don't change context state - caller should have already made context current
  // If not current, make it current but don't release it
  HGLRC current = wglGetCurrentContext();
  bool needsRestore = (current != m_glrc);
  
  if (needsRestore)
    wglMakeCurrent(m_hdc, m_glrc);
  
  const char * renderer = reinterpret_cast<const char *>(glGetString(GL_RENDERER));
  std::string result = renderer ? renderer : "Unknown";
  
  // Only restore if we changed it, and restore to previous state
  if (needsRestore && current != nullptr)
    wglMakeCurrent(m_hdc, current);
  // If we changed it and there was no previous context, leave our context current
  
  return result;
}

std::string AgusWglContext::GetRendererVersion() const
{
  // Don't change context state - caller should have already made context current
  // If not current, make it current but don't release it
  HGLRC current = wglGetCurrentContext();
  bool needsRestore = (current != m_glrc);
  
  if (needsRestore)
    wglMakeCurrent(m_hdc, m_glrc);
  
  const char * version = reinterpret_cast<const char *>(glGetString(GL_VERSION));
  std::string result = version ? version : "Unknown";
  
  // Only restore if we changed it, and restore to previous state
  if (needsRestore && current != nullptr)
    wglMakeCurrent(m_hdc, current);
  // If we changed it and there was no previous context, leave our context current
  
  return result;
}

void AgusWglContext::SetClearColor(dp::Color const & color)
{
  // Log clear color periodically
  static int s_clearColorLogCount = 0;
  if (s_clearColorLogCount++ % 60 == 0)
  {
    LOG(LINFO, ("SetClearColor RGBA:", (int)(color.GetRedF() * 255), 
                (int)(color.GetGreenF() * 255), (int)(color.GetBlueF() * 255), 
                (int)(color.GetAlphaF() * 255)));
  }
  glClearColor(color.GetRedF(), color.GetGreenF(), color.GetBlueF(), color.GetAlphaF());
}

void AgusWglContext::Clear(uint32_t clearBits, uint32_t storeBits)
{
  // Log which FBO we're clearing - helps diagnose rendering issues
  static int s_clearLogCount = 0;
  if (s_clearLogCount++ % 60 == 0)
  {
    GLint boundFBO = 0;
    glGetIntegerv(GL_FRAMEBUFFER_BINDING, &boundFBO);
    LOG(LINFO, ("Clear: FBO", boundFBO, "bits", clearBits, "store", storeBits));
  }
  
  GLbitfield mask = 0;
  if (clearBits & dp::ClearBits::ColorBit)
    mask |= GL_COLOR_BUFFER_BIT;
  if (clearBits & dp::ClearBits::DepthBit)
    mask |= GL_DEPTH_BUFFER_BIT;
  if (clearBits & dp::ClearBits::StencilBit)
    mask |= GL_STENCIL_BUFFER_BIT;
  glClear(mask);
}

void AgusWglContext::Flush()
{
  glFlush();
}

void AgusWglContext::Resize(uint32_t w, uint32_t h)
{
  // Called by FrontendRenderer::OnResize() when the viewport changes.
  // We delegate to the factory's SetSurfaceSize which handles all the
  // GL resource recreation (render texture, depth buffer, D3D11 shared texture).
  if (m_factory)
  {
    LOG(LINFO, ("AgusWglContext::Resize:", w, "x", h, "isDraw:", m_isDraw));
    m_factory->SetSurfaceSize(static_cast<int>(w), static_cast<int>(h));
  }
}

void AgusWglContext::SetViewport(uint32_t x, uint32_t y, uint32_t w, uint32_t h)
{
  // NOTE: SetViewport is called very frequently (many times per frame).
  // Logging disabled to reduce noise. Enable for debugging viewport issues.
  // LOG(LINFO, ("SetViewport:", x, y, w, h));
  
  // CRITICAL: CoMaps' OGLContext::SetViewport() sets BOTH viewport AND scissor
  // (see drape/oglcontext.cpp:175-178). When the viewport changes (e.g., on resize),
  // the scissor must also be updated or rendering will be clipped to the old size.
  glViewport(x, y, w, h);
  glScissor(static_cast<GLint>(x), static_cast<GLint>(y),
            static_cast<GLsizei>(w), static_cast<GLsizei>(h));
}

void AgusWglContext::SetDepthTestEnabled(bool enabled)
{
  if (enabled)
    glEnable(GL_DEPTH_TEST);
  else
    glDisable(GL_DEPTH_TEST);
}

void AgusWglContext::SetDepthTestFunction(dp::TestFunction depthFunction)
{
  GLenum func = GL_LESS;
  switch (depthFunction)
  {
  case dp::TestFunction::Never: func = GL_NEVER; break;
  case dp::TestFunction::Less: func = GL_LESS; break;
  case dp::TestFunction::Equal: func = GL_EQUAL; break;
  case dp::TestFunction::LessOrEqual: func = GL_LEQUAL; break;
  case dp::TestFunction::Greater: func = GL_GREATER; break;
  case dp::TestFunction::NotEqual: func = GL_NOTEQUAL; break;
  case dp::TestFunction::GreaterOrEqual: func = GL_GEQUAL; break;
  case dp::TestFunction::Always: func = GL_ALWAYS; break;
  }
  glDepthFunc(func);
}

void AgusWglContext::SetStencilTestEnabled(bool enabled)
{
  if (enabled)
    glEnable(GL_STENCIL_TEST);
  else
    glDisable(GL_STENCIL_TEST);
}

void AgusWglContext::SetStencilFunction(dp::StencilFace face, dp::TestFunction stencilFunction)
{
  // Simplified implementation
}

void AgusWglContext::SetStencilActions(dp::StencilFace face, dp::StencilAction stencilFailAction,
                                       dp::StencilAction depthFailAction, dp::StencilAction passAction)
{
  // Simplified implementation
}

void AgusWglContext::SetStencilReferenceValue(uint32_t stencilReferenceValue)
{
  // Simplified implementation
}

void AgusWglContext::PushDebugLabel(std::string const & label)
{
  // Debug labels not implemented - would require GL_KHR_debug extension
}

void AgusWglContext::PopDebugLabel()
{
  // Debug labels not implemented
}

void AgusWglContext::SetScissor(uint32_t x, uint32_t y, uint32_t w, uint32_t h)
{
  // NOTE: SetScissor may be called frequently.
  // Logging disabled to reduce noise. Enable for debugging scissor issues.
  // LOG(LINFO, ("SetScissor:", x, y, w, h));
  glScissor(static_cast<GLint>(x), static_cast<GLint>(y),
            static_cast<GLsizei>(w), static_cast<GLsizei>(h));
}

void AgusWglContext::SetCullingEnabled(bool enabled)
{
  if (enabled)
    glEnable(GL_CULL_FACE);
  else
    glDisable(GL_CULL_FACE);
}

}  // namespace agus

#endif  // _WIN32 || _WIN64
