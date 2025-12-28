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

  return glGenFramebuffers && glDeleteFramebuffers && glBindFramebuffer &&
         glFramebufferTexture2D && glCheckFramebufferStatus &&
         glGenRenderbuffers && glDeleteRenderbuffers && glBindRenderbuffer &&
         glRenderbufferStorage && glFramebufferRenderbuffer;
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

  GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
  if (status != GL_FRAMEBUFFER_COMPLETE)
  {
    LOG(LERROR, ("Framebuffer incomplete:", status));
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    wglMakeCurrent(nullptr, nullptr);
    return false;
  }

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

  // Recreate OpenGL resources
  wglMakeCurrent(m_hdc, m_drawGlrc);

  // Update render texture
  glBindTexture(GL_TEXTURE_2D, m_renderTexture);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
  glBindTexture(GL_TEXTURE_2D, 0);

  // Update depth buffer
  glBindRenderbuffer(GL_RENDERBUFFER, m_depthBuffer);
  glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, width, height);
  glBindRenderbuffer(GL_RENDERBUFFER, 0);

  // Restore previous context
  if (prevContext != nullptr)
    wglMakeCurrent(prevDC, prevContext);
  else
    wglMakeCurrent(nullptr, nullptr);

  // Update dimensions
  m_width = width;
  m_height = height;

  // Recreate D3D11 shared texture
  CreateSharedTexture(width, height);
}

void AgusWglContextFactory::OnFrameReady()
{
  CopyToSharedTexture();

  if (m_frameCallback)
    m_frameCallback();
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

  // Bind framebuffer and read pixels
  glBindFramebuffer(GL_FRAMEBUFFER, m_framebuffer);

  // Read pixels from OpenGL
  std::vector<uint8_t> pixels(m_width * m_height * 4);
  glReadPixels(0, 0, m_width, m_height, GL_BGRA_EXT, GL_UNSIGNED_BYTE, pixels.data());

  // Check if we got any non-zero pixels (for debugging blank frames)
  if (s_frameCount % kLogEveryNFrames == 0)
  {
    bool hasContent = false;
    // Sample some pixels to see if we have content
    for (size_t i = 0; i < pixels.size() && !hasContent; i += 1000)
    {
      // BGRA format - check if not black and not the clear color
      if (pixels[i] != 0 || pixels[i+1] != 0 || pixels[i+2] != 0)
        hasContent = true;
    }
    LOG(LINFO, ("Frame", s_frameCount, "size:", m_width, "x", m_height, "hasContent:", hasContent));
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

  // Copy to D3D11 staging texture
  D3D11_MAPPED_SUBRESOURCE mapped;
  HRESULT hr = m_d3dContext->Map(m_stagingTexture.Get(), 0, D3D11_MAP_WRITE, 0, &mapped);
  if (SUCCEEDED(hr))
  {
    // OpenGL has flipped Y, so we copy rows in reverse
    uint8_t * dst = static_cast<uint8_t *>(mapped.pData);
    for (int y = 0; y < m_height; ++y)
    {
      int srcY = m_height - 1 - y;  // Flip Y
      memcpy(dst + y * mapped.RowPitch, pixels.data() + srcY * m_width * 4, m_width * 4);
    }
    m_d3dContext->Unmap(m_stagingTexture.Get(), 0);

    // Copy staging to shared texture
    m_d3dContext->CopyResource(m_sharedTexture.Get(), m_stagingTexture.Get());
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

void AgusWglContext::SetFramebuffer(ref_ptr<dp::BaseFramebuffer> framebuffer)
{
  // Not used for default framebuffer
}

void AgusWglContext::ForgetFramebuffer(ref_ptr<dp::BaseFramebuffer> framebuffer)
{
  // Not used for default framebuffer
}

void AgusWglContext::ApplyFramebuffer(std::string const & framebufferLabel)
{
  // Apply the default framebuffer
  if (m_isDraw && m_factory)
  {
    glBindFramebuffer(GL_FRAMEBUFFER, m_factory->m_framebuffer);
  }
}

void AgusWglContext::Init(dp::ApiVersion apiVersion)
{
  // GL functions already initialized in factory
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
  glClearColor(color.GetRedF(), color.GetGreenF(), color.GetBlueF(), color.GetAlphaF());
}

void AgusWglContext::Clear(uint32_t clearBits, uint32_t storeBits)
{
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

void AgusWglContext::SetViewport(uint32_t x, uint32_t y, uint32_t w, uint32_t h)
{
  glViewport(x, y, w, h);
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
