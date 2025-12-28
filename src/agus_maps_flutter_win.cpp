/// agus_maps_flutter_win.cpp
/// 
/// Windows FFI implementation for agus_maps_flutter.
/// This provides the C FFI functions that Dart FFI calls on Windows.
/// 
/// This file implements the full CoMaps Framework integration for Windows,
/// using OpenGL (via WGL) for rendering with D3D11 texture sharing for Flutter integration.

#ifdef _WIN32

#include "agus_maps_flutter.h"
#include "AgusWglContextFactory.hpp"

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <shlobj.h>   // For SHGetFolderPathW
#include <dbghelp.h>  // For MiniDumpWriteDump

#pragma comment(lib, "dbghelp.lib")

#include <string>
#include <memory>
#include <atomic>
#include <chrono>
#include <cstdio>
#include <mutex>
#include <sstream>

// CoMaps Framework includes
#include "base/logging.hpp"
#include "map/framework.hpp"
#include "platform/local_country_file.hpp"
#include "drape/graphics_context_factory.hpp"
#include "drape_frontend/visual_params.hpp"
#include "drape_frontend/user_event_stream.hpp"
#include "drape_frontend/active_frame_callback.hpp"
#include "geometry/mercator.hpp"

// Forward declarations for Windows platform (defined in agus_platform_win.cpp)
extern "C" void AgusPlatformWin_InitPaths(const char* resourcePath, const char* writablePath);

#pragma region Crash Dump Handler

/// Crash dump handler for Windows.
/// When enabled, this captures minidumps on unhandled exceptions for debugging.
static bool g_crashHandlerInstalled = false;
static wchar_t g_dumpPath[MAX_PATH] = {0};

/// Generate minidump file on crash
static LONG WINAPI AgusCrashHandler(EXCEPTION_POINTERS* pExceptionInfo)
{
    // Build dump filename with timestamp
    SYSTEMTIME st;
    GetLocalTime(&st);
    
    wchar_t dumpFile[MAX_PATH];
    swprintf_s(dumpFile, MAX_PATH, 
               L"%s\\agus_maps_crash_%04d%02d%02d_%02d%02d%02d.dmp",
               g_dumpPath, st.wYear, st.wMonth, st.wDay, 
               st.wHour, st.wMinute, st.wSecond);
    
    OutputDebugStringW(L"[AgusMapsFlutter] CRASH DETECTED - Writing minidump to: ");
    OutputDebugStringW(dumpFile);
    OutputDebugStringW(L"\n");
    
    HANDLE hFile = CreateFileW(dumpFile, GENERIC_WRITE, 0, NULL, 
                               CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    
    if (hFile != INVALID_HANDLE_VALUE)
    {
        MINIDUMP_EXCEPTION_INFORMATION mdei;
        mdei.ThreadId = GetCurrentThreadId();
        mdei.ExceptionPointers = pExceptionInfo;
        mdei.ClientPointers = FALSE;
        
        // Write minidump with full memory info for debugging
        MINIDUMP_TYPE dumpType = static_cast<MINIDUMP_TYPE>(
            MiniDumpWithDataSegs | 
            MiniDumpWithHandleData |
            MiniDumpWithThreadInfo |
            MiniDumpWithUnloadedModules);
        
        if (MiniDumpWriteDump(GetCurrentProcess(), GetCurrentProcessId(),
                              hFile, dumpType, &mdei, NULL, NULL))
        {
            OutputDebugStringW(L"[AgusMapsFlutter] Minidump written successfully\n");
        }
        else
        {
            OutputDebugStringW(L"[AgusMapsFlutter] Failed to write minidump\n");
        }
        
        CloseHandle(hFile);
    }
    else
    {
        OutputDebugStringW(L"[AgusMapsFlutter] Failed to create dump file\n");
    }
    
    // Log exception details
    char msg[512];
    snprintf(msg, sizeof(msg), 
             "[AgusMapsFlutter] Exception code: 0x%08lX at address: %p\n",
             pExceptionInfo->ExceptionRecord->ExceptionCode,
             pExceptionInfo->ExceptionRecord->ExceptionAddress);
    OutputDebugStringA(msg);
    fprintf(stderr, "%s", msg);
    
    // Let Windows handle the exception (will show crash dialog or terminate)
    return EXCEPTION_CONTINUE_SEARCH;
}

/// Install crash handler. Call early in initialization.
static void installCrashHandler()
{
    if (g_crashHandlerInstalled)
        return;
    
    // Get Documents folder for crash dumps
    wchar_t documentsPath[MAX_PATH];
    if (SUCCEEDED(SHGetFolderPathW(NULL, CSIDL_PERSONAL, NULL, 0, documentsPath)))
    {
        swprintf_s(g_dumpPath, MAX_PATH, L"%s\\agus_maps_flutter", documentsPath);
        CreateDirectoryW(g_dumpPath, NULL);  // Ensure directory exists
    }
    else
    {
        wcscpy_s(g_dumpPath, MAX_PATH, L".");
    }
    
    SetUnhandledExceptionFilter(AgusCrashHandler);
    g_crashHandlerInstalled = true;
    
    OutputDebugStringW(L"[AgusMapsFlutter] Crash handler installed. Dumps will be saved to: ");
    OutputDebugStringW(g_dumpPath);
    OutputDebugStringW(L"\n");
}

#pragma endregion

#pragma region Global State

static std::unique_ptr<Framework> g_framework;
static drape_ptr<dp::ThreadSafeFactory> g_threadSafeFactory;
static agus::AgusWglContextFactory* g_wglFactory = nullptr;  // Raw pointer - owned by g_threadSafeFactory
static std::string g_resourcePath;
static std::string g_writablePath;
static bool g_platformInitialized = false;
static bool g_drapeEngineCreated = false;
static bool g_loggingInitialized = false;

// Surface state
static int32_t g_surfaceWidth = 0;
static int32_t g_surfaceHeight = 0;
static float g_density = 1.0f;
static int64_t g_textureId = -1;

// Frame ready callback
typedef void (*FrameReadyCallback)(void);
static FrameReadyCallback g_frameReadyCallback = nullptr;

// Frame notification timing for 60fps rate limiting
static std::chrono::steady_clock::time_point g_lastFrameNotification;
static constexpr auto kMinFrameInterval = std::chrono::milliseconds(16); // ~60fps
static std::atomic<bool> g_frameNotificationPending{false};

// Mutex for thread safety
static std::mutex g_mutex;

#pragma endregion

#pragma region Logging

/// Custom log handler that redirects to OutputDebugString and stderr
static void AgusLogMessage(base::LogLevel level, base::SrcPoint const & src, std::string const & msg) {
    const char* levelStr;
    switch (level) {
        case base::LDEBUG: levelStr = "DEBUG"; break;
        case base::LINFO: levelStr = "INFO"; break;
        case base::LWARNING: levelStr = "WARN"; break;
        case base::LERROR: levelStr = "ERROR"; break;
        case base::LCRITICAL: levelStr = "CRITICAL"; break;
        default: levelStr = "???"; break;
    }
    
    std::string out = "[CoMaps " + std::string(levelStr) + "] " + DebugPrint(src) + msg + "\n";
    
    OutputDebugStringA(out.c_str());
    std::fprintf(stderr, "%s", out.c_str());
    std::fflush(stderr);
    
    // Only abort on CRITICAL, not ERROR
    if (level >= base::LCRITICAL) {
        OutputDebugStringA("[CoMaps CRITICAL] Aborting...\n");
        std::abort();
    }
}

static void ensureLoggingConfigured() {
    if (!g_loggingInitialized) {
        base::SetLogMessageFn(&AgusLogMessage);
        base::g_LogAbortLevel = base::LCRITICAL;
        g_loggingInitialized = true;
        
        // Install crash handler for better diagnostics
        installCrashHandler();
        
        OutputDebugStringA("[AgusMapsFlutter] Logging initialized\n");
        std::fprintf(stderr, "[AgusMapsFlutter] Logging initialized\n");
        std::fflush(stderr);
    }
}

#pragma endregion

#pragma region Frame Notification

/// Internal function to notify Flutter about a new frame
/// Called from DrapeEngine render thread via df::SetActiveFrameCallback
static void notifyFlutterFrameReady() {
    // Rate limiting: Enforce 60fps max
    auto now = std::chrono::steady_clock::now();
    auto elapsed = now - g_lastFrameNotification;
    if (elapsed < kMinFrameInterval) {
        return;  // Too soon, skip this notification
    }
    
    // Throttle: if a notification is already pending, skip this one
    bool expected = false;
    if (!g_frameNotificationPending.compare_exchange_strong(expected, true)) {
        return;  // Already a notification pending, skip
    }
    
    g_lastFrameNotification = now;
    
    // Call the registered callback
    if (g_frameReadyCallback) {
        g_frameReadyCallback();
    }
    
    g_frameNotificationPending.store(false);
}

/// Called by Present() to notify Flutter that a frame was rendered
/// Exported for AgusWglContextFactory to call
extern "C" void agus_notify_frame_ready(void) {
    notifyFlutterFrameReady();
}

#pragma endregion

#pragma region DrapeEngine

static void createDrapeEngineIfNeeded(int width, int height, float density) {
    if (g_drapeEngineCreated || !g_framework || !g_threadSafeFactory) {
        return;
    }
    
    if (width <= 0 || height <= 0) {
        OutputDebugStringA("[AgusMapsFlutter] createDrapeEngine: Invalid dimensions\n");
        return;
    }
    
    // Register active frame callback BEFORE creating DrapeEngine
    df::SetActiveFrameCallback([]() {
        notifyFlutterFrameReady();
    });
    OutputDebugStringA("[AgusMapsFlutter] Active frame callback registered\n");
    
    Framework::DrapeCreationParams p;
    p.m_apiVersion = dp::ApiVersion::OpenGLES3;  // Use OpenGL on Windows
    p.m_surfaceWidth = width;
    p.m_surfaceHeight = height;
    p.m_visualScale = density;
    
    char msg[256];
    snprintf(msg, sizeof(msg), "[AgusMapsFlutter] Creating DrapeEngine: %dx%d, scale=%.2f, API=OpenGL\n",
             width, height, density);
    OutputDebugStringA(msg);
    std::fprintf(stderr, "%s", msg);
    std::fflush(stderr);
    
    g_framework->CreateDrapeEngine(make_ref(g_threadSafeFactory), std::move(p));
    g_drapeEngineCreated = true;
    
    OutputDebugStringA("[AgusMapsFlutter] DrapeEngine created successfully\n");
    std::fprintf(stderr, "[AgusMapsFlutter] DrapeEngine created successfully\n");
    std::fflush(stderr);
}

#pragma endregion

#pragma region FFI Functions

FFI_PLUGIN_EXPORT int sum(int a, int b) { 
    return a + b; 
}

FFI_PLUGIN_EXPORT int sum_long_running(int a, int b) {
    Sleep(5000);
    return a + b;
}

FFI_PLUGIN_EXPORT void comaps_init(const char* apkPath, const char* storagePath) {
    // Windows doesn't use APK paths - redirect to comaps_init_paths
    comaps_init_paths(apkPath, storagePath);
}

FFI_PLUGIN_EXPORT void comaps_init_paths(const char* resourcePath, const char* writablePath) {
    ensureLoggingConfigured();
    
    char msg[512];
    snprintf(msg, sizeof(msg), "[AgusMapsFlutter] comaps_init_paths: resource=%s, writable=%s\n",
             resourcePath, writablePath);
    OutputDebugStringA(msg);
    std::fprintf(stderr, "%s", msg);
    std::fflush(stderr);
    
    // Store paths
    g_resourcePath = resourcePath ? resourcePath : "";
    g_writablePath = writablePath ? writablePath : "";
    
    // Initialize platform paths via AgusPlatformWin
    AgusPlatformWin_InitPaths(resourcePath, writablePath);
    g_platformInitialized = true;
    
    OutputDebugStringA("[AgusMapsFlutter] Platform initialized, Framework deferred to surface creation\n");
}

FFI_PLUGIN_EXPORT void comaps_load_map_path(const char* path) {
    char msg[512];
    snprintf(msg, sizeof(msg), "[AgusMapsFlutter] comaps_load_map_path: %s\n", path);
    OutputDebugStringA(msg);
    
    if (g_framework) {
        g_framework->RegisterAllMaps();
        OutputDebugStringA("[AgusMapsFlutter] Maps registered\n");
    } else {
        OutputDebugStringA("[AgusMapsFlutter] Framework not yet initialized, maps will be loaded later\n");
    }
}

FFI_PLUGIN_EXPORT void comaps_set_view(double lat, double lon, int zoom) {
    LOG(LINFO, ("comaps_set_view: lat=", lat, " lon=", lon, " zoom=", zoom));
    
    if (g_framework) {
        // Use isAnim=false to set the view synchronously.
        // This ensures the screen is updated immediately so that subsequent
        // tile requests use the correct viewport coordinates.
        // With isAnim=true (default), the view change is animated which delays
        // the actual screen update, causing tile requests to use stale coordinates.
        g_framework->SetViewportCenter(m2::PointD(mercator::FromLatLon(lat, lon)), zoom, false /* isAnim */);
        
        // Wake up the render loop to process the view change event
        g_framework->InvalidateRendering();
        LOG(LINFO, ("comaps_set_view: Viewport set (no animation)"));
    } else {
        LOG(LWARNING, ("comaps_set_view: Framework not ready"));
    }
}

FFI_PLUGIN_EXPORT void comaps_invalidate(void) {
    LOG(LINFO, ("comaps_invalidate called"));
    
    if (g_framework) {
        g_framework->InvalidateRect(g_framework->GetCurrentViewport());
        LOG(LINFO, ("comaps_invalidate: Viewport invalidated"));
    } else {
        LOG(LWARNING, ("comaps_invalidate: Framework not ready"));
    }
}

FFI_PLUGIN_EXPORT void comaps_force_redraw(void) {
    LOG(LINFO, ("comaps_force_redraw called"));
    
    if (g_framework) {
        // UpdateMapStyle clears all render groups and invalidates the read manager,
        // which forces a complete tile reload when the render loop processes it.
        // This is the cleanest way to force a full redraw.
        g_framework->SetMapStyle(g_framework->GetMapStyle());
        
        // MakeFrameActive ensures the render loop stays active (isActiveFrame=true)
        // long enough to process the style update and request new tiles.
        g_framework->MakeFrameActive();
        
        LOG(LINFO, ("comaps_force_redraw: SetMapStyle + MakeFrameActive triggered"));
    } else {
        LOG(LWARNING, ("comaps_force_redraw: Framework not ready"));
    }
}

FFI_PLUGIN_EXPORT void comaps_touch(int type, int id1, float x1, float y1, int id2, float x2, float y2) {
    if (!g_framework || !g_drapeEngineCreated) {
        return;
    }
    
    df::TouchEvent event;
    
    switch (type) {
        case 1: event.SetTouchType(df::TouchEvent::TOUCH_DOWN); break;
        case 2: event.SetTouchType(df::TouchEvent::TOUCH_MOVE); break;
        case 3: event.SetTouchType(df::TouchEvent::TOUCH_UP); break;
        case 4: event.SetTouchType(df::TouchEvent::TOUCH_CANCEL); break;
        default: return;
    }
    
    // Set first touch
    df::Touch t1;
    t1.m_id = id1;
    t1.m_location = m2::PointF(x1, y1);
    event.SetFirstTouch(t1);
    event.SetFirstMaskedPointer(0);
    
    // Set second touch if valid (for multitouch)
    if (id2 >= 0) {
        df::Touch t2;
        t2.m_id = id2;
        t2.m_location = m2::PointF(x2, y2);
        event.SetSecondTouch(t2);
        event.SetSecondMaskedPointer(1);
    }
    
    g_framework->TouchEvent(event);
}

FFI_PLUGIN_EXPORT void comaps_scale(double factor, double pixelX, double pixelY, int animated) {
    if (!g_framework || !g_drapeEngineCreated) {
        return;
    }
    
    // Scale the map by the given factor, centered on the pixel point
    // This is the preferred method for scroll wheel zoom on desktop
    g_framework->Scale(factor, m2::PointD(pixelX, pixelY), animated != 0);
}

FFI_PLUGIN_EXPORT void comaps_scroll(double distanceX, double distanceY) {
    if (!g_framework || !g_drapeEngineCreated) {
        return;
    }
    
    // Scroll the map by the given distance
    g_framework->Scroll(distanceX, distanceY);
}

// Helper function to normalize path separators (convert / to \ on Windows)
static std::string NormalizePath(const char* path) {
    std::string normalized(path);
    for (auto& c : normalized) {
        if (c == '/') {
            c = '\\';
        }
    }
    return normalized;
}

FFI_PLUGIN_EXPORT int comaps_register_single_map(const char* fullPath) {
    char msg[512];
    
    // Normalize path separators (convert / to \ for Windows)
    std::string normalizedPath = NormalizePath(fullPath);
    
    snprintf(msg, sizeof(msg), "[AgusMapsFlutter] comaps_register_single_map: %s (normalized: %s)\n", 
             fullPath, normalizedPath.c_str());
    OutputDebugStringA(msg);
    
    if (!g_framework) {
        OutputDebugStringA("[AgusMapsFlutter] Framework not initialized\n");
        return -1;
    }
    
    try {
        platform::LocalCountryFile file = platform::LocalCountryFile::MakeTemporary(normalizedPath);
        file.SyncWithDisk();
        
        auto result = g_framework->RegisterMap(file);
        if (result.second == MwmSet::RegResult::Success) {
            snprintf(msg, sizeof(msg), "[AgusMapsFlutter] Successfully registered %s\n", fullPath);
            OutputDebugStringA(msg);
            return 0;
        } else {
            snprintf(msg, sizeof(msg), "[AgusMapsFlutter] Failed to register %s, result=%d\n",
                     fullPath, static_cast<int>(result.second));
            OutputDebugStringA(msg);
            return static_cast<int>(result.second);
        }
    } catch (std::exception const & e) {
        snprintf(msg, sizeof(msg), "[AgusMapsFlutter] Exception registering map: %s\n", e.what());
        OutputDebugStringA(msg);
        return -2;
    }
}

FFI_PLUGIN_EXPORT void comaps_shutdown(void) {
    OutputDebugStringA("[AgusMapsFlutter] comaps_shutdown called\n");
    std::fprintf(stderr, "[AgusMapsFlutter] comaps_shutdown called\n");
    std::fflush(stderr);
    
    std::lock_guard<std::mutex> lock(g_mutex);
    
    // Clear active frame callback first
    df::SetActiveFrameCallback(nullptr);
    
    if (g_framework) {
        g_framework->SetRenderingDisabled(true);
    }
    
    g_threadSafeFactory.reset();
    g_wglFactory = nullptr;
    g_framework.reset();
    
    g_drapeEngineCreated = false;
    g_platformInitialized = false;
    
    OutputDebugStringA("[AgusMapsFlutter] Shutdown complete\n");
}

FFI_PLUGIN_EXPORT int comaps_deregister_map(const char* fullPath) {
    OutputDebugStringA("[AgusMapsFlutter] comaps_deregister_map: not implemented\n");
    return -1;
}

FFI_PLUGIN_EXPORT int comaps_get_registered_maps_count(void) {
    if (!g_framework) {
        return 0;
    }
    
    auto const & dataSource = g_framework->GetDataSource();
    std::vector<std::shared_ptr<MwmInfo>> mwms;
    dataSource.GetMwmsInfo(mwms);
    return static_cast<int>(mwms.size());
}

FFI_PLUGIN_EXPORT void comaps_debug_list_mwms(void) {
    OutputDebugStringA("[AgusMapsFlutter] === DEBUG: Listing all registered MWMs ===\n");
    
    if (!g_framework) {
        OutputDebugStringA("[AgusMapsFlutter] Framework not initialized\n");
        return;
    }
    
    auto const & dataSource = g_framework->GetDataSource();
    std::vector<std::shared_ptr<MwmInfo>> mwms;
    dataSource.GetMwmsInfo(mwms);
    
    char msg[256];
    snprintf(msg, sizeof(msg), "[AgusMapsFlutter] Total MWMs registered: %zu\n", mwms.size());
    OutputDebugStringA(msg);
    
    for (auto const & mwmInfo : mwms) {
        if (mwmInfo) {
            auto const & rect = mwmInfo->m_bordersRect;
            snprintf(msg, sizeof(msg), "[AgusMapsFlutter]   MWM: %s, bounds: [%.4f, %.4f] - [%.4f, %.4f]\n",
                     mwmInfo->GetCountryName().c_str(),
                     rect.minX(), rect.minY(), rect.maxX(), rect.maxY());
            OutputDebugStringA(msg);
        }
    }
}

FFI_PLUGIN_EXPORT void comaps_debug_check_point(double lat, double lon) {
    char msg[256];
    snprintf(msg, sizeof(msg), "[AgusMapsFlutter] comaps_debug_check_point: lat=%.6f, lon=%.6f\n", lat, lon);
    OutputDebugStringA(msg);
    
    if (!g_framework) {
        OutputDebugStringA("[AgusMapsFlutter] Framework not initialized\n");
        return;
    }
    
    m2::PointD const mercatorPt = mercator::FromLatLon(lat, lon);
    snprintf(msg, sizeof(msg), "[AgusMapsFlutter] Mercator coords: (%.4f, %.4f)\n", mercatorPt.x, mercatorPt.y);
    OutputDebugStringA(msg);
    
    auto const & dataSource = g_framework->GetDataSource();
    std::vector<std::shared_ptr<MwmInfo>> mwms;
    dataSource.GetMwmsInfo(mwms);
    
    for (auto const & mwmInfo : mwms) {
        if (mwmInfo && mwmInfo->m_bordersRect.IsPointInside(mercatorPt)) {
            snprintf(msg, sizeof(msg), "[AgusMapsFlutter] Point IS covered by MWM: %s\n",
                     mwmInfo->GetCountryName().c_str());
            OutputDebugStringA(msg);
            return;
        }
    }
    
    OutputDebugStringA("[AgusMapsFlutter] Point is NOT covered by any registered MWM\n");
}

#pragma endregion

#pragma region Native Surface Functions

/// Set the frame ready callback
FFI_PLUGIN_EXPORT void agus_set_frame_ready_callback(FrameReadyCallback callback) {
    g_frameReadyCallback = callback;
    OutputDebugStringA("[AgusMapsFlutter] Frame ready callback set\n");
}

/// Called when the native surface is created
/// @param width Surface width in pixels
/// @param height Surface height in pixels
/// @param density Screen density / DPI scale
FFI_PLUGIN_EXPORT void agus_native_create_surface(int32_t width, int32_t height, float density) {
    ensureLoggingConfigured();
    
    char msg[256];
    snprintf(msg, sizeof(msg), "[AgusMapsFlutter] agus_native_create_surface: %dx%d, density=%.2f\n",
             width, height, density);
    OutputDebugStringA(msg);
    std::fprintf(stderr, "%s", msg);
    std::fflush(stderr);
    
    if (!g_platformInitialized) {
        OutputDebugStringA("[AgusMapsFlutter] ERROR: Platform not initialized! Call comaps_init_paths first.\n");
        return;
    }
    
    std::lock_guard<std::mutex> lock(g_mutex);
    
    g_surfaceWidth = width;
    g_surfaceHeight = height;
    g_density = density;
    
    // Create Framework on this thread if not already created
    if (!g_framework) {
        OutputDebugStringA("[AgusMapsFlutter] Creating Framework...\n");
        
        FrameworkParams params;
        params.m_enableDiffs = false;
        params.m_numSearchAPIThreads = 1;
        
        g_framework = std::make_unique<Framework>(params, false /* loadMaps */);
        OutputDebugStringA("[AgusMapsFlutter] Framework created\n");
        
        // Register maps
        g_framework->RegisterAllMaps();
        OutputDebugStringA("[AgusMapsFlutter] Maps registered\n");
    }
    
    // Create WGL context factory for OpenGL rendering
    g_wglFactory = new agus::AgusWglContextFactory(width, height);
    
    if (!g_wglFactory->GetDrawContext()) {
        OutputDebugStringA("[AgusMapsFlutter] ERROR: Failed to create WGL context factory\n");
        delete g_wglFactory;
        g_wglFactory = nullptr;
        return;
    }
    
    // Set frame callback on factory so it notifies Flutter after CopyToSharedTexture()
    g_wglFactory->SetFrameCallback([]() {
        notifyFlutterFrameReady();
    });
    OutputDebugStringA("[AgusMapsFlutter] WGL factory frame callback set\n");
    
    // Set keep-alive callback to prevent render loop from suspending during tile loading.
    // This calls Framework::MakeFrameActive() which sends an ActiveFrameEvent to keep
    // the FrontendRenderer's render loop running. Without this, the render loop would
    // suspend after kMaxInactiveFrames (2) inactive frames, before tiles have arrived.
    g_wglFactory->SetKeepAliveCallback([]() {
        if (g_framework) {
            g_framework->MakeFrameActive();
        }
    });
    OutputDebugStringA("[AgusMapsFlutter] WGL factory keep-alive callback set\n");
    
    // Wrap in ThreadSafeFactory for thread-safe context access
    g_threadSafeFactory = make_unique_dp<dp::ThreadSafeFactory>(g_wglFactory);
    
    // Create DrapeEngine
    createDrapeEngineIfNeeded(width, height, density);
    
    // Enable rendering
    if (g_framework && g_drapeEngineCreated) {
        g_framework->SetRenderingEnabled(make_ref(g_threadSafeFactory));
        OutputDebugStringA("[AgusMapsFlutter] Rendering enabled\n");
    }
}

/// Called when the surface size changes
FFI_PLUGIN_EXPORT void agus_native_on_size_changed(int32_t width, int32_t height) {
    char msg[256];
    snprintf(msg, sizeof(msg), "[AgusMapsFlutter] agus_native_on_size_changed: %dx%d\n", width, height);
    OutputDebugStringA(msg);
    
    g_surfaceWidth = width;
    g_surfaceHeight = height;
    
    if (g_wglFactory) {
        g_wglFactory->SetSurfaceSize(width, height);
    }
    
    if (g_framework && g_drapeEngineCreated) {
        g_framework->OnSize(width, height);
    }
}

/// Called when the surface is destroyed
FFI_PLUGIN_EXPORT void agus_native_on_surface_destroyed(void) {
    OutputDebugStringA("[AgusMapsFlutter] agus_native_on_surface_destroyed\n");
    
    if (g_framework) {
        g_framework->SetRenderingDisabled(true /* destroySurface */);
    }
    
    g_threadSafeFactory.reset();
    g_wglFactory = nullptr;
    g_drapeEngineCreated = false;
}

/// Get the D3D11 shared texture handle for Flutter
/// @return HANDLE that Flutter can use to open the shared texture
FFI_PLUGIN_EXPORT void* agus_get_shared_texture_handle(void) {
    if (g_wglFactory) {
        return g_wglFactory->GetSharedTextureHandle();
    }
    return nullptr;
}

/// Get the D3D11 device pointer for Flutter
/// @return ID3D11Device pointer
FFI_PLUGIN_EXPORT void* agus_get_d3d11_device(void) {
    if (g_wglFactory) {
        return g_wglFactory->GetD3D11Device();
    }
    return nullptr;
}

/// Get the D3D11 texture pointer for Flutter
/// @return ID3D11Texture2D pointer
FFI_PLUGIN_EXPORT void* agus_get_d3d11_texture(void) {
    if (g_wglFactory) {
        return g_wglFactory->GetD3D11Texture();
    }
    return nullptr;
}

/// Render a single frame (called by Flutter's texture system)
FFI_PLUGIN_EXPORT void agus_render_frame(void) {
    if (!g_framework || !g_drapeEngineCreated) {
        return;
    }
    
    // The DrapeEngine handles rendering internally
    // Frame completion will trigger agus_notify_frame_ready
}

#pragma endregion

#endif // _WIN32
