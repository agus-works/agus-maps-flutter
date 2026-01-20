#if defined(_WIN32) || defined(_WIN64)

#include "AgusWglContextFactory.hpp"

#include "drape/gl_functions.hpp"

#include "base/assert.hpp"
#include "base/logging.hpp"

#include <vector>
#include <cstring>
#include <cstdlib>
#include <string>
#include <algorithm>
#include <cctype>

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

// Missing GL definitions for Windows
#ifndef GL_READ_FRAMEBUFFER
#define GL_READ_FRAMEBUFFER 0x8CA8
#endif
#ifndef GL_DRAW_FRAMEBUFFER
#define GL_DRAW_FRAMEBUFFER 0x8CA9
#endif

// Some Windows OpenGL headers omit this enum even when FBO functions are available.
#ifndef GL_FRAMEBUFFER_BINDING
#define GL_FRAMEBUFFER_BINDING            0x8CA6
#endif

// GL_BGRA_EXT for reading pixels in BGRA format (needed for D3D11 texture)
#ifndef GL_BGRA_EXT
#define GL_BGRA_EXT                       0x80E1
#endif

// GL_CLAMP_TO_EDGE is not defined in legacy Windows GL headers
#ifndef GL_CLAMP_TO_EDGE
#define GL_CLAMP_TO_EDGE                  0x812F
#endif

static const char * FramebufferStatusToString(GLenum status)
{
  switch (status)
  {
  case GL_FRAMEBUFFER_COMPLETE:
    return "GL_FRAMEBUFFER_COMPLETE";
  case 0x8CD6:  // GL_FRAMEBUFFER_INCOMPLETE_ATTACHMENT
    return "GL_FRAMEBUFFER_INCOMPLETE_ATTACHMENT";
  case 0x8CD7:  // GL_FRAMEBUFFER_INCOMPLETE_MISSING_ATTACHMENT
    return "GL_FRAMEBUFFER_INCOMPLETE_MISSING_ATTACHMENT";
  case 0x8CDB:  // GL_FRAMEBUFFER_INCOMPLETE_DRAW_BUFFER
    return "GL_FRAMEBUFFER_INCOMPLETE_DRAW_BUFFER";
  case 0x8CDC:  // GL_FRAMEBUFFER_INCOMPLETE_READ_BUFFER
    return "GL_FRAMEBUFFER_INCOMPLETE_READ_BUFFER";
  case 0x8CDD:  // GL_FRAMEBUFFER_UNSUPPORTED
    return "GL_FRAMEBUFFER_UNSUPPORTED";
  case 0x8D56:  // GL_FRAMEBUFFER_INCOMPLETE_MULTISAMPLE
    return "GL_FRAMEBUFFER_INCOMPLETE_MULTISAMPLE";
  default:
    return "GL_FRAMEBUFFER_INCOMPLETE_UNKNOWN";
  }
}

// WGL extension query function types
typedef const char * (WINAPI * PFNWGLGETEXTENSIONSSTRINGARBPROC)(HDC hdc);
typedef const char * (WINAPI * PFNWGLGETEXTENSIONSSTRINGEXTPROC)(void);

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
typedef void (APIENTRY *PFNGLBLITFRAMEBUFFERPROC) (GLint srcX0, GLint srcY0, GLint srcX1, GLint srcY1, GLint dstX0, GLint dstY0, GLint dstX1, GLint dstY1, GLbitfield mask, GLenum filter);

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
static PFNGLBLITFRAMEBUFFERPROC glBlitFramebuffer = nullptr;

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

  // Load GL 3.0+ functions
  glBlitFramebuffer = (PFNGLBLITFRAMEBUFFERPROC)wglGetProcAddress("glBlitFramebuffer");

  return glGenFramebuffers && glDeleteFramebuffers && glBindFramebuffer &&
         glFramebufferTexture2D && glCheckFramebufferStatus &&
         glGenRenderbuffers && glDeleteRenderbuffers && glBindRenderbuffer &&
         glRenderbufferStorage && glFramebufferRenderbuffer && glDrawBuffers;
}


static std::string WideToUtf8(const wchar_t * input)
{
  if (!input)
    return std::string();

  int required = WideCharToMultiByte(CP_UTF8, 0, input, -1, nullptr, 0, nullptr, nullptr);
  if (required <= 0)
    return std::string();

  std::string result(static_cast<size_t>(required - 1), '\0');
  WideCharToMultiByte(CP_UTF8, 0, input, -1, result.data(), required, nullptr, nullptr);
  return result;
}

namespace agus
{

namespace
{
// Window class name for hidden window
const wchar_t * kWindowClassName = L"AgusWglHiddenWindow";
bool g_windowClassRegistered = false;

bool ShouldEnableKeyedMutex()
{
  const char * env = std::getenv("AGUS_MAPS_WIN_KEYED_MUTEX");
  if (!env)
    return false;

  return std::strcmp(env, "1") == 0 || std::strcmp(env, "true") == 0 || std::strcmp(env, "TRUE") == 0;
}

bool ShouldEnableOverlay()
{
  const char * env = std::getenv("AGUS_MAPS_WIN_OVERLAY");
  if (!env)
    return true;

  return !(std::strcmp(env, "0") == 0 || std::strcmp(env, "false") == 0 || std::strcmp(env, "FALSE") == 0);
}

static std::string ToLower(std::string value)
{
  std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) {
    return static_cast<char>(std::tolower(c));
  });
  return value;
}

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
  m_overlayEnabled = ShouldEnableOverlay();
  
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
    if (m_interopRenderbuffer)
    {
      glDeleteRenderbuffers(1, &m_interopRenderbuffer);
      m_interopRenderbuffer = 0;
    }
    if (m_overlayFontBase)
    {
      glDeleteLists(m_overlayFontBase, 96);
      m_overlayFontBase = 0;
    }
    wglMakeCurrent(nullptr, nullptr);
  }

  if (m_overlayFont)
  {
    DeleteObject(m_overlayFont);
    m_overlayFont = nullptr;
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

  // Load WGL_NV_DX_interop functions
  m_wglDXOpenDeviceNV = (PFNWGLDXOPENDEVICENVPROC)wglGetProcAddress("wglDXOpenDeviceNV");
  m_wglDXCloseDeviceNV = (PFNWGLDXCLOSEDEVICENVPROC)wglGetProcAddress("wglDXCloseDeviceNV");
  m_wglDXRegisterObjectNV = (PFNWGLDXREGISTEROBJECTNVPROC)wglGetProcAddress("wglDXRegisterObjectNV");
  m_wglDXUnregisterObjectNV = (PFNWGLDXUNREGISTEROBJECTNVPROC)wglGetProcAddress("wglDXUnregisterObjectNV");
  m_wglDXLockObjectsNV = (PFNWGLDXLOCKOBJECTSNVPROC)wglGetProcAddress("wglDXLockObjectsNV");
  m_wglDXUnlockObjectsNV = (PFNWGLDXUNLOCKOBJECTSNVPROC)wglGetProcAddress("wglDXUnlockObjectsNV");

  // Initialize GL functions
  GLFunctions::Init(dp::ApiVersion::OpenGLES3);

  if (const GLubyte * renderer = glGetString(GL_RENDERER))
    m_glRenderer = reinterpret_cast<const char *>(renderer);
  if (const GLubyte * vendor = glGetString(GL_VENDOR))
    m_glVendor = reinterpret_cast<const char *>(vendor);


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

  glBindFramebuffer(GL_FRAMEBUFFER, 0);
  wglMakeCurrent(nullptr, nullptr);

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
  HRESULT hr = E_FAIL;

  Microsoft::WRL::ComPtr<IDXGIAdapter> preferredAdapter;
  if (!m_glRenderer.empty())
  {
    Microsoft::WRL::ComPtr<IDXGIFactory1> factory;
    if (SUCCEEDED(CreateDXGIFactory1(IID_PPV_ARGS(&factory))) && factory)
    {
      std::string rendererLower = ToLower(m_glRenderer);
      for (UINT index = 0; ; ++index)
      {
        Microsoft::WRL::ComPtr<IDXGIAdapter> adapter;
        if (factory->EnumAdapters(index, &adapter) == DXGI_ERROR_NOT_FOUND)
          break;
        DXGI_ADAPTER_DESC desc = {};
        if (FAILED(adapter->GetDesc(&desc)))
          continue;

        std::string adapterName = WideToUtf8(desc.Description);
        std::string adapterLower = ToLower(adapterName);
        if (rendererLower.find(adapterLower) != std::string::npos ||
            adapterLower.find(rendererLower) != std::string::npos)
        {
          preferredAdapter = adapter;
          break;
        }
      }
    }
  }

  if (preferredAdapter)
  {
    hr = D3D11CreateDevice(
      preferredAdapter.Get(),
      D3D_DRIVER_TYPE_UNKNOWN,
      nullptr,
      createFlags,
      featureLevels,
      ARRAYSIZE(featureLevels),
      D3D11_SDK_VERSION,
      &m_d3dDevice,
      &featureLevel,
      &m_d3dContext
    );
  }

  if (FAILED(hr))
  {
    hr = D3D11CreateDevice(
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
  }

  if (FAILED(hr))
  {
    LOG(LERROR, ("Failed to create D3D11 device:", hr));
    return false;
  }

  return true;
}

bool AgusWglContextFactory::CreateSharedTexture(int width, int height)
{
  // Ensure a valid GL context is current for interop registration.
  HGLRC prevContext = wglGetCurrentContext();
  HDC prevDC = wglGetCurrentDC();
  bool madeCurrent = false;
  if (prevContext != m_drawGlrc || prevDC != m_hdc)
  {
    madeCurrent = wglMakeCurrent(m_hdc, m_drawGlrc) == TRUE;
    if (!madeCurrent)
    {
      LOG(LERROR, ("CreateSharedTexture: Failed to make GL context current:", GetLastError()));
      return false;
    }
  }
  // Cleanup existing interop
  if (m_interopDevice)
  {
    if (m_interopObject)
    {
      if (m_wglDXUnregisterObjectNV)
        m_wglDXUnregisterObjectNV(m_interopDevice, m_interopObject);
      m_interopObject = nullptr;
    }
    if (m_wglDXCloseDeviceNV)
      m_wglDXCloseDeviceNV(m_interopDevice);
    m_interopDevice = nullptr;
  }
  
  if (m_interopFramebuffer)
  {
      glDeleteFramebuffers(1, &m_interopFramebuffer);
      m_interopFramebuffer = 0;
  }
    if (m_interopRenderbuffer)
    {
      glDeleteRenderbuffers(1, &m_interopRenderbuffer);
      m_interopRenderbuffer = 0;
    }
  
  if (m_interopTexture)
  {
      glDeleteTextures(1, &m_interopTexture);
      m_interopTexture = 0;
  }

  // Close existing handle
  if (m_sharedHandle)
  {
    CloseHandle(m_sharedHandle);
    m_sharedHandle = nullptr;
  }

  m_sharedTexture.Reset();
  m_stagingTexture.Reset();
  m_keyedMutex.Reset();

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
  // Default to a simple shared handle; enable Keyed Mutex only if explicitly requested.
  m_useKeyedMutex = ShouldEnableKeyedMutex();
  sharedDesc.MiscFlags = m_useKeyedMutex ? D3D11_RESOURCE_MISC_SHARED_KEYEDMUTEX
                                         : D3D11_RESOURCE_MISC_SHARED;

  HRESULT hr = m_d3dDevice->CreateTexture2D(&sharedDesc, nullptr, &m_sharedTexture);
  if (FAILED(hr))
  {
    LOG(LERROR, ("Failed to create shared texture:", hr));
    // Fallback? For now, fail.
    return false;
  }

  // Get shared handle
  Microsoft::WRL::ComPtr<IDXGIResource1> dxgiResource;
  hr = m_sharedTexture.As(&dxgiResource);
  if (FAILED(hr))
  {
    LOG(LERROR, ("Failed to get DXGI resource:", hr));
    return false;
  }

  // GetSharedHandle is mandatory for Flutter integration
  hr = dxgiResource->GetSharedHandle(&m_sharedHandle);
  if (FAILED(hr))
  {
    LOG(LERROR, ("Failed to get shared handle:", hr));
    return false;
  }

  // Get KeyedMutex interface if enabled
  if (m_useKeyedMutex)
  {
    hr = m_sharedTexture.As(&m_keyedMutex);
    if (FAILED(hr))
    {
      LOG(LERROR, ("Failed to get KeyedMutex interface:", hr));
      return false;
    }
  }

  //
  // PROMPT CHECK: "Consumer (Flutter): The Flutter engine (or the plugin's D3D side) calls AcquireSync(0)... It waits for the key to be 0".
  // Note: "or the plugin's D3D side". The plugin C++ code *hands* the texture to Flutter. Flutter compositor uses it.
  // IF the generic Flutter engine does NOT support Keyed Mutex (only basic shared handle), then *I* must act as the Consumer Synchronization Proxy if I use `TextureVariant`?
  // But `TextureVariant` takes a `FlutterDesktopGpuSurfaceDescriptor`.
  // If Flutter Engine supports Keyed Mutex, it must know what Keys to use.
  //
  // BUT... The "Zero-Copy" guide says "The mechanism... is derived from analyzing... media_kit".
  // In `media_kit`, they might be doing the rendering *and* display logic differently.
  //
  // Let's stick to the prompt's explicit sequence: "Producer... AcquireSync(1)... ReleaseSync(0)".
  // I will assume the Flutter Engine (or my setup of it) respects this.
  //
  // WGL Interop setup:
  // WGL Interop setup:
  if (m_wglDXOpenDeviceNV)
  {
      // Open Device
      m_interopDevice = m_wglDXOpenDeviceNV(m_d3dDevice.Get());
      if (m_interopDevice)
      {
          auto cleanupInterop = [&]() {
            if (m_interopFramebuffer)
            {
              glDeleteFramebuffers(1, &m_interopFramebuffer);
              m_interopFramebuffer = 0;
            }
            if (m_interopRenderbuffer)
            {
              glDeleteRenderbuffers(1, &m_interopRenderbuffer);
              m_interopRenderbuffer = 0;
            }
            if (m_interopTexture)
            {
              glDeleteTextures(1, &m_interopTexture);
              m_interopTexture = 0;
            }
            if (m_wglDXUnregisterObjectNV && m_interopDevice && m_interopObject)
            {
              m_wglDXUnregisterObjectNV(m_interopDevice, m_interopObject);
              m_interopObject = nullptr;
            }
          };

          auto tryTextureInterop = [&]() -> bool {
            glGenTextures(1, &m_interopTexture);
            glBindTexture(GL_TEXTURE_2D, m_interopTexture);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
            glBindTexture(GL_TEXTURE_2D, 0);

            m_interopObject = m_wglDXRegisterObjectNV(m_interopDevice, m_sharedTexture.Get(),
                                                      m_interopTexture, GL_TEXTURE_2D, WGL_ACCESS_READ_WRITE_NV);
            if (!m_interopObject)
              return false;

            if (!m_wglDXLockObjectsNV(m_interopDevice, 1, &m_interopObject))
            {
              return false;
            }

            glGenFramebuffers(1, &m_interopFramebuffer);
            glBindFramebuffer(GL_FRAMEBUFFER, m_interopFramebuffer);
            glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, m_interopTexture, 0);

            // Explicitly set draw/read buffers for user FBOs
            GLenum drawBuffers[] = { GL_COLOR_ATTACHMENT0 };
            glDrawBuffers(1, drawBuffers);
            glReadBuffer(GL_COLOR_ATTACHMENT0);

            GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
            if (status != GL_FRAMEBUFFER_COMPLETE)
            {
              glBindFramebuffer(GL_FRAMEBUFFER, 0);
              m_wglDXUnlockObjectsNV(m_interopDevice, 1, &m_interopObject);
              return false;
            }

            glBindFramebuffer(GL_FRAMEBUFFER, 0);
            m_wglDXUnlockObjectsNV(m_interopDevice, 1, &m_interopObject);
            return true;
          };

          auto tryRenderbufferInterop = [&]() -> bool {
            glGenRenderbuffers(1, &m_interopRenderbuffer);
            glBindRenderbuffer(GL_RENDERBUFFER, m_interopRenderbuffer);
            glBindRenderbuffer(GL_RENDERBUFFER, 0);

            m_interopObject = m_wglDXRegisterObjectNV(m_interopDevice, m_sharedTexture.Get(),
                                                      m_interopRenderbuffer, GL_RENDERBUFFER, WGL_ACCESS_READ_WRITE_NV);
            if (!m_interopObject)
              return false;

            if (!m_wglDXLockObjectsNV(m_interopDevice, 1, &m_interopObject))
            {
              return false;
            }

            glGenFramebuffers(1, &m_interopFramebuffer);
            glBindFramebuffer(GL_FRAMEBUFFER, m_interopFramebuffer);
            glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, m_interopRenderbuffer);

            // Explicitly set draw/read buffers for user FBOs
            GLenum drawBuffers[] = { GL_COLOR_ATTACHMENT0 };
            glDrawBuffers(1, drawBuffers);
            glReadBuffer(GL_COLOR_ATTACHMENT0);

            GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
            if (status != GL_FRAMEBUFFER_COMPLETE)
            {
              glBindFramebuffer(GL_FRAMEBUFFER, 0);
              m_wglDXUnlockObjectsNV(m_interopDevice, 1, &m_interopObject);
              return false;
            }

            glBindFramebuffer(GL_FRAMEBUFFER, 0);
            m_wglDXUnlockObjectsNV(m_interopDevice, 1, &m_interopObject);
            return true;
          };

          bool interopOk = tryTextureInterop();
          if (!interopOk)
          {
            cleanupInterop();
            interopOk = tryRenderbufferInterop();
          }

          if (!interopOk)
          {
            cleanupInterop();
            if (m_wglDXCloseDeviceNV)
              m_wglDXCloseDeviceNV(m_interopDevice);
            m_interopDevice = nullptr;
          }
      }
      else
      {
           LOG(LERROR, ("WGL Interop: Failed to open device:", GetLastError()));
      }
  }

  // Restore previous GL context
  if (madeCurrent)
  {
    if (prevContext != nullptr)
      wglMakeCurrent(prevDC, prevContext);
    else
      wglMakeCurrent(nullptr, nullptr);
  }

  // Create staging texture as fallback (always created to support fallback switch at runtime if needed)
  // Let's keep staging texture code just in case interop failed but D3D succeeded (partial failure), 
  // although with KeyedMutex, standard copy might hang if we don't sync.
  // Best to only fallback if shared texture creation itself failed (which we handle).
  // If interop fails, we might still be able to Map/Copy if we acquire the mutex on D3D context first.
  
  // For safety, I'll keep the staging texture creation but only use it if m_interopObject is null.
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

void AgusWglContextFactory::SetOverlayCustomLines(std::vector<std::string> lines)
{
  std::lock_guard<std::mutex> lock(m_mutex);
  m_overlayCustomLines = std::move(lines);
}

bool AgusWglContextFactory::EnsureOverlayFont()
{
  if (!m_overlayEnabled)
    return false;
  if (m_overlayInitialized)
    return true;
  if (!m_hdc)
    return false;

  HFONT font = CreateFontA(
      -m_overlayFontHeight,
      0, 0, 0,
      FW_NORMAL,
      FALSE,
      FALSE,
      FALSE,
      DEFAULT_CHARSET,
      OUT_DEFAULT_PRECIS,
      CLIP_DEFAULT_PRECIS,
      ANTIALIASED_QUALITY,
      FF_DONTCARE,
      "Segoe UI");
  if (!font)
  {
    return false;
  }

  HGDIOBJ oldFont = SelectObject(m_hdc, font);
  GLuint base = glGenLists(96);
  if (base == 0)
  {
    SelectObject(m_hdc, oldFont);
    DeleteObject(font);
    return false;
  }

  if (!wglUseFontBitmapsA(m_hdc, 32, 96, base))
  {
    SelectObject(m_hdc, oldFont);
    glDeleteLists(base, 96);
    DeleteObject(font);
    return false;
  }

  SelectObject(m_hdc, oldFont);

  m_overlayFont = font;
  m_overlayFontBase = base;
  m_overlayInitialized = true;
  return true;
}

int AgusWglContextFactory::MeasureOverlayTextWidth(std::string const & text) const
{
  if (!m_hdc || !m_overlayFont)
    return static_cast<int>(text.size()) * 8;

  HGDIOBJ oldFont = SelectObject(m_hdc, m_overlayFont);
  SIZE size = {};
  BOOL ok = GetTextExtentPoint32A(m_hdc, text.c_str(), static_cast<int>(text.size()), &size);
  SelectObject(m_hdc, oldFont);
  if (!ok)
    return static_cast<int>(text.size()) * 8;

  return static_cast<int>(size.cx);
}

std::vector<std::string> AgusWglContextFactory::BuildOverlayLines(bool useInterop) const
{
  std::vector<std::string> lines;
  lines.emplace_back("Renderer: OpenGL (WGL)");
  if (useInterop)
    lines.emplace_back("Transfer: Zero-copy (WGL_NV_DX_interop)");
  else
    lines.emplace_back("Transfer: CPU copy (glReadPixels)");

  const int renderedWidth = m_renderedWidth.load();
  const int renderedHeight = m_renderedHeight.load();
  lines.emplace_back("Surface: " + std::to_string(m_width) + "x" + std::to_string(m_height));
  lines.emplace_back("Rendered: " + std::to_string(renderedWidth) + "x" + std::to_string(renderedHeight));
  if (renderedWidth > 0 && renderedHeight > 0 &&
      (renderedWidth != m_width || renderedHeight != m_height))
  {
    lines.emplace_back("Size mismatch: YES");
  }

  lines.emplace_back(std::string("Keyed mutex: ") + (m_keyedMutex ? "On" : "Off"));

  for (auto const & line : m_overlayCustomLines)
    lines.push_back(line);

  return lines;
}

void AgusWglContextFactory::DrawOverlayText(GLuint targetFbo, int width, int height,
                                           std::vector<std::string> const & lines, bool originTopLeft)
{
  if (!m_overlayEnabled || lines.empty())
    return;
  if (!EnsureOverlayFont())
    return;

  GLint prevViewport[4] = {};
  glGetIntegerv(GL_VIEWPORT, prevViewport);

  GLint prevMatrixMode = 0;
  glGetIntegerv(GL_MATRIX_MODE, &prevMatrixMode);

  GLboolean depthEnabled = glIsEnabled(GL_DEPTH_TEST);
  GLboolean scissorEnabled = glIsEnabled(GL_SCISSOR_TEST);
  GLboolean blendEnabled = glIsEnabled(GL_BLEND);

  GLint prevFbo = 0;
  glGetIntegerv(GL_FRAMEBUFFER_BINDING, &prevFbo);

  glBindFramebuffer(GL_FRAMEBUFFER, targetFbo);
  glViewport(0, 0, width, height);
  glDisable(GL_DEPTH_TEST);
  glDisable(GL_SCISSOR_TEST);
  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

  glMatrixMode(GL_PROJECTION);
  glPushMatrix();
  glLoadIdentity();
  if (originTopLeft)
    glOrtho(0, width, height, 0, -1, 1);
  else
    glOrtho(0, width, 0, height, -1, 1);
  glMatrixMode(GL_MODELVIEW);
  glPushMatrix();
  glLoadIdentity();

  int maxWidth = 0;
  for (auto const & line : lines)
    maxWidth = std::max(maxWidth, MeasureOverlayTextWidth(line));

  int lineSpacing = m_overlayFontHeight + 2;
  int totalHeight = static_cast<int>(lines.size()) * lineSpacing + m_overlayPadding * 2;

  int right = width - m_overlayPadding;
  int left = right - maxWidth - m_overlayPadding * 2;
  int top = originTopLeft ? m_overlayPadding : (height - m_overlayPadding);
  int bottom = originTopLeft ? (top + totalHeight) : (top - totalHeight);

  glColor4f(0.0f, 0.0f, 0.0f, 0.55f);
  glBegin(GL_QUADS);
  glVertex2i(left, bottom);
  glVertex2i(right, bottom);
  glVertex2i(right, top);
  glVertex2i(left, top);
  glEnd();

  glColor4f(1.0f, 1.0f, 1.0f, 1.0f);
  glListBase(m_overlayFontBase - 32);

  int y = originTopLeft
              ? (top + m_overlayPadding + m_overlayFontHeight)
              : (top - m_overlayPadding - m_overlayFontHeight);
  for (auto const & line : lines)
  {
    int lineWidth = MeasureOverlayTextWidth(line);
    int x = right - m_overlayPadding - lineWidth;
    glRasterPos2i(x, y);
    glCallLists(static_cast<GLsizei>(line.size()), GL_UNSIGNED_BYTE, line.c_str());
    y += originTopLeft ? lineSpacing : -lineSpacing;
  }

  glPopMatrix();
  glMatrixMode(GL_PROJECTION);
  glPopMatrix();
  glMatrixMode(prevMatrixMode);

  if (!blendEnabled)
    glDisable(GL_BLEND);
  if (depthEnabled)
    glEnable(GL_DEPTH_TEST);
  if (scissorEnabled)
    glEnable(GL_SCISSOR_TEST);

  glBindFramebuffer(GL_FRAMEBUFFER, prevFbo);
  glViewport(prevViewport[0], prevViewport[1], prevViewport[2], prevViewport[3]);
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

  // Set viewport and scissor for the new size while FBO is bound
  // NOTE: These state changes apply to the current context. When rendering happens,
  // CoMaps will call SetViewport() which sets both viewport and scissor.
  glViewport(0, 0, width, height);
  glScissor(0, 0, width, height);

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

void AgusWglContextFactory::CopyToSharedTexture()
{
  std::lock_guard<std::mutex> lock(m_mutex);

  // If we have interop object, use Zero-Copy path
  bool hasInteropFns = m_wglDXLockObjectsNV && m_wglDXUnlockObjectsNV;
  bool useInterop = (m_interopObject != nullptr && m_interopFramebuffer != 0 &&
                     m_interopDevice != nullptr && hasInteropFns);

  if (!useInterop && (!m_stagingTexture || !m_sharedTexture))
  {
    return;
  }

  // Save current context state
  HGLRC prevContext = wglGetCurrentContext();
  HDC prevDC = wglGetCurrentDC();
  bool wasOurContext = (prevContext == m_drawGlrc);

  if (!wasOurContext)
    wglMakeCurrent(m_hdc, m_drawGlrc);

  GLuint fboToRead = m_lastBoundFramebuffer.load();
  if (fboToRead == 0)
    fboToRead = m_framebuffer;

  // Determine size
  GLint viewport[4];
  glGetIntegerv(GL_VIEWPORT, viewport);
  int readWidth = viewport[2];
  int readHeight = viewport[3];

  if (readWidth <= 0 || readHeight <= 0) {
      readWidth = m_width;
      readHeight = m_height;
  }
  if (readWidth > m_width) readWidth = m_width;
  if (readHeight > m_height) readHeight = m_height;
  
  m_renderedWidth.store(readWidth);
  m_renderedHeight.store(readHeight);

  if (useInterop)
  {
      // ZERO-COPY PATH
      // Ensure previous GL commands (rendering to FBO) are done.
      glFinish();

      bool locked = true;
      if (m_keyedMutex)
      {
        // Producer acquires key 0, releases key 1 for the consumer.
        HRESULT hr = m_keyedMutex->AcquireSync(0, 100);
        if (hr == WAIT_TIMEOUT)
        {
          locked = false;
        }
        else if (FAILED(hr))
        {
          locked = false;
          LOG(LERROR, ("CopyToSharedTexture: AcquireSync failed:", hr));
        }
      }

      if (locked)
      {
        // Lock GL Interop Object
        if (m_wglDXLockObjectsNV(m_interopDevice, 1, &m_interopObject))
        {
          DrawOverlayText(fboToRead, readWidth, readHeight, BuildOverlayLines(true), false);

          // Blit from Render FBO to Interop FBO
          glBindFramebuffer(GL_READ_FRAMEBUFFER, fboToRead);
          glBindFramebuffer(GL_DRAW_FRAMEBUFFER, m_interopFramebuffer);

          // CRITICAL: Flip Y (OpenGL is Y-up, D3D is Y-down).
          glBlitFramebuffer(0, 0, readWidth, readHeight,
                            0, readHeight, readWidth, 0,
                            GL_COLOR_BUFFER_BIT, GL_NEAREST);

          // Unlock GL Interop Object
          m_wglDXUnlockObjectsNV(m_interopDevice, 1, &m_interopObject);
        }
        else
        {
          LOG(LERROR, ("CopyToSharedTexture: wglDXLockObjectsNV failed"));
        }

        if (m_keyedMutex)
        {
          // Release key 1 for consumer.
          m_keyedMutex->ReleaseSync(1);
        }
      }
  }
  else
  {
      // FALBACK PATH (CPU COPY)
      // Read pixels from OpenGL
      glBindFramebuffer(GL_FRAMEBUFFER, fboToRead);
      GLenum fboStatus = glCheckFramebufferStatus(GL_FRAMEBUFFER);
      if (fboStatus != GL_FRAMEBUFFER_COMPLETE) {
          LOG(LERROR, ("FBO incomplete:", fboStatus));
      }

        DrawOverlayText(fboToRead, readWidth, readHeight, BuildOverlayLines(false), false);
      
      glFinish();

      std::vector<uint8_t> pixels(readWidth * readHeight * 4);
      glReadPixels(0, 0, readWidth, readHeight, GL_RGBA, GL_UNSIGNED_BYTE, pixels.data());
      glBindFramebuffer(GL_FRAMEBUFFER, 0);

      // Copy to D3D11 staging texture
      D3D11_MAPPED_SUBRESOURCE mapped;
      HRESULT hr = m_d3dContext->Map(m_stagingTexture.Get(), 0, D3D11_MAP_WRITE, 0, &mapped);
      if (SUCCEEDED(hr))
      {
        uint8_t * dst = static_cast<uint8_t *>(mapped.pData);

        // Clear the staging buffer to avoid stale pixels when sizes differ
        std::memset(dst, 0, static_cast<size_t>(mapped.RowPitch) * m_height);

        for (int y = 0; y < readHeight; ++y)
        {
          const uint8_t * srcRow = pixels.data() + ((readHeight - 1 - y) * readWidth * 4);
          uint8_t * dstRow = dst + (y * mapped.RowPitch);
          for (int x = 0; x < readWidth; ++x)
          {
            const uint8_t * src = srcRow + (x * 4);
            uint8_t * out = dstRow + (x * 4);
            // Swizzle RGBA -> BGRA
            out[0] = src[2];
            out[1] = src[1];
            out[2] = src[0];
            out[3] = src[3];
          }
        }
        m_d3dContext->Unmap(m_stagingTexture.Get(), 0);
        
        // Handle KeyedMutex for shared texture even in fallback
        if (m_keyedMutex) m_keyedMutex->AcquireSync(0, 100);
        m_d3dContext->CopyResource(m_sharedTexture.Get(), m_stagingTexture.Get());
        if (m_keyedMutex) m_keyedMutex->ReleaseSync(1);
      }
  }

  // Restore previous context state
  if (!wasOurContext)
  {
    if (prevContext != nullptr)
      wglMakeCurrent(prevDC, prevContext);
    else
      wglMakeCurrent(nullptr, nullptr);
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

void AgusWglContext::SetFramebuffer(ref_ptr<dp::BaseFramebuffer> framebuffer)
{
  // CRITICAL: When framebuffer is nullptr, CoMaps expects the "default" framebuffer
  // to be bound. For desktop GL with window surface, this is FBO 0.
  // But for our offscreen rendering setup, the "default" is our custom FBO.
  // This is similar to how Qt's qtoglcontext.cpp handles it by binding m_backFrame.
  if (framebuffer)
  {
    framebuffer->Bind();

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

    m_factory->m_lastBoundFramebuffer.store(fbo);
  }
  else
  {
    // Not a draw context or no factory - bind FBO 0
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
  }
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
  }
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

void AgusWglContext::Resize(uint32_t w, uint32_t h)
{
  // Called by FrontendRenderer::OnResize() when the viewport changes.
  // We delegate to the factory's SetSurfaceSize which handles all the
  // GL resource recreation (render texture, depth buffer, D3D11 shared texture).
  if (m_factory)
  {
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
