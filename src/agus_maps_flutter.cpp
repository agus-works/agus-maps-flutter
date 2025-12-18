#include "agus_maps_flutter.h"

// A very short-lived native function.
//
// For very short-lived functions, it is fine to call them on the main isolate.
// They will block the Dart execution while running the native function, so
// only do this for native functions which are guaranteed to be short-lived.
FFI_PLUGIN_EXPORT int sum(int a, int b) { return a + b; }

// A longer-lived native function, which occupies the thread calling it.
//
// Do not call these kind of native functions in the main isolate. They will
// block Dart execution. This will cause dropped frames in Flutter applications.
// Instead, call these native functions on a separate isolate.
FFI_PLUGIN_EXPORT int sum_long_running(int a, int b) {
  // Simulate work.
#if _WIN32
  Sleep(5000);
#else
  usleep(5000 * 1000);
#endif
  return a + b;
}

#include <android/log.h>
#include <jni.h>
#include <android/native_window_jni.h>

#include "base/logging.hpp"
#include "map/framework.hpp"
#include "drape/graphics_context_factory.hpp"
#include "drape_frontend/visual_params.hpp"
#include "drape_frontend/user_event_stream.hpp"
#include "geometry/mercator.hpp"
#include "agus_ogl.hpp"

extern "C" void AgusPlatform_Init(const char* apkPath, const char* storagePath);
extern "C" void AgusPlatform_InitPaths(const char* resourcePath, const char* writablePath);

// Custom log handler that redirects to Android logcat without aborting on ERROR
static void AgusLogMessage(base::LogLevel level, base::SrcPoint const & src, std::string const & msg) {
    android_LogPriority pr = ANDROID_LOG_SILENT;
    
    switch (level) {
    case base::LDEBUG: pr = ANDROID_LOG_DEBUG; break;
    case base::LINFO: pr = ANDROID_LOG_INFO; break;
    case base::LWARNING: pr = ANDROID_LOG_WARN; break;
    case base::LERROR: pr = ANDROID_LOG_ERROR; break;
    case base::LCRITICAL: pr = ANDROID_LOG_FATAL; break;
    default: break;
    }
    
    std::string out = DebugPrint(src) + msg;
    __android_log_print(pr, "CoMaps", "%s", out.c_str());
    
    // Only abort on CRITICAL, not ERROR
    if (level >= base::LCRITICAL) {
        __android_log_print(ANDROID_LOG_FATAL, "CoMaps", "CRITICAL ERROR - Aborting");
        abort();
    }
}

// Globals
static std::unique_ptr<Framework> g_framework;
static drape_ptr<dp::ThreadSafeFactory> g_factory;
static std::string g_resourcePath;
static std::string g_writablePath;
static bool g_platformInitialized = false;

// Old init function for backwards compatibility (uses APK path)
FFI_PLUGIN_EXPORT void comaps_init(const char* apkPath, const char* storagePath) {
    __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", "comaps_init: apk=%s, storage=%s", apkPath, storagePath);
    AgusPlatform_Init(apkPath, storagePath);
    
    // Note: Framework initialization requires many data files (categories.txt, etc.)
    // For now we just initialize the platform; full Framework will be created when surface is ready
    __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", "comaps_init: Platform initialized, Framework deferred");
}

// New init function with explicit resource and writable paths
// NOTE: This just stores paths. Framework creation is deferred to nativeSetSurface
// to ensure Framework and CreateDrapeEngine happen on the same thread.
FFI_PLUGIN_EXPORT void comaps_init_paths(const char* resourcePath, const char* writablePath) {
    __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", "comaps_init_paths: resource=%s, writable=%s", resourcePath, writablePath);
    
    // Set up our custom log handler before doing anything else
    base::SetLogMessageFn(&AgusLogMessage);
    // Set abort level to LCRITICAL so ERROR logs don't crash
    base::g_LogAbortLevel = base::LCRITICAL;
    __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", "comaps_init_paths: Custom logging initialized");
    
    // Store paths for later use
    g_resourcePath = resourcePath;
    g_writablePath = writablePath;
    
    // Initialize platform now (sets up directories, thread infrastructure)
    AgusPlatform_InitPaths(resourcePath, writablePath);
    g_platformInitialized = true;
    
    __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", "comaps_init_paths: Platform initialized, Framework deferred to render thread");
}

FFI_PLUGIN_EXPORT void comaps_load_map_path(const char* path) {
    __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", "comaps_load_map_path: %s", path);
    
    if (g_framework) {
        // Register maps from the writable directory
        // The framework will scan the writable path for .mwm files
        g_framework->RegisterAllMaps();
        __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", "comaps_load_map_path: Maps registered");
    } else {
        __android_log_print(ANDROID_LOG_WARN, "AgusMapsFlutterNative", "comaps_load_map_path: Framework not yet initialized, maps will be loaded later");
    }
}

// Store current surface dimensions
static int g_surfaceWidth = 0;
static int g_surfaceHeight = 0;
static float g_density = 2.0f;
static bool g_drapeEngineCreated = false;

static void createDrapeEngineIfNeeded(int width, int height, float density) {
    if (g_drapeEngineCreated || !g_framework) {
        return;
    }
    
    if (width <= 0 || height <= 0) {
        __android_log_print(ANDROID_LOG_WARN, "AgusMapsFlutterNative", "createDrapeEngine: Invalid dimensions %dx%d", width, height);
        return;
    }
    
    if (!g_factory) {
        __android_log_print(ANDROID_LOG_WARN, "AgusMapsFlutterNative", "createDrapeEngine: Factory not valid");
        return;
    }
    
    Framework::DrapeCreationParams p;
    p.m_apiVersion = dp::ApiVersion::OpenGLES3;
    p.m_surfaceWidth = width;
    p.m_surfaceHeight = height;
    p.m_visualScale = density;
    
    // Disable all widgets for now (require symbols.sdf which needs Qt6 to generate)
    // TODO: Generate symbols.sdf and enable widgets
    
    __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", "createDrapeEngine: Creating with %dx%d, scale=%.2f", width, height, density);
    g_framework->CreateDrapeEngine(make_ref(g_factory), std::move(p));
    g_drapeEngineCreated = true;
    __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", "createDrapeEngine: Drape engine created successfully");
}

extern "C" JNIEXPORT void JNICALL
Java_app_agus_maps_agus_1maps_1flutter_AgusMapsFlutterPlugin_nativeSetSurface(
    JNIEnv* env, jobject thiz, jlong textureId, jobject surface, jint width, jint height, jfloat density) {
    
    ANativeWindow* window = ANativeWindow_fromSurface(env, surface);
    __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", 
        "nativeSetSurface: textureId=%ld, window=%p, size=%dx%d, density=%.2f", 
        textureId, window, width, height, density);
    
    if (!g_platformInitialized) {
       __android_log_print(ANDROID_LOG_ERROR, "AgusMapsFlutterNative", "Platform not initialized! Call comaps_init_paths first.");
       if (window) ANativeWindow_release(window);
       return;
    }
    
    g_surfaceWidth = width;
    g_surfaceHeight = height;
    g_density = density;

    // Create Framework on this thread if not already created
    // This ensures Framework and CreateDrapeEngine are on the same thread,
    // avoiding ThreadChecker assertion failures in BookmarkManager etc.
    if (!g_framework) {
        __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", "nativeSetSurface: Creating Framework...");
        
        FrameworkParams params;
        params.m_enableDiffs = false;
        params.m_numSearchAPIThreads = 1;
        
        // Create framework, defer map loading
        g_framework = std::make_unique<Framework>(params, false /* loadMaps */);
        
        __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", "nativeSetSurface: Framework created");
        
        // Now register maps
        g_framework->RegisterAllMaps();
        __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", "nativeSetSurface: Maps registered");
    }

    // Create the OGL context factory with the native window
    auto oglFactory = new agus::AgusOGLContextFactory(window);
    if (!oglFactory->IsValid()) {
        __android_log_print(ANDROID_LOG_ERROR, "AgusMapsFlutterNative", "nativeSetSurface: Invalid OGL context");
        delete oglFactory;
        return;
    }
    
    // Update surface size from what we received (ANativeWindow might report different size)
    oglFactory->UpdateSurfaceSize(width, height);
    
    // Wrap our context factory in ThreadSafeFactory for thread-safe context creation
    g_factory = make_unique_dp<dp::ThreadSafeFactory>(oglFactory);
    
    // Create DrapeEngine with proper dimensions
    createDrapeEngineIfNeeded(width, height, density);
}

extern "C" JNIEXPORT void JNICALL
Java_app_agus_maps_agus_1maps_1flutter_AgusMapsFlutterPlugin_nativeOnSurfaceChanged(
    JNIEnv* env, jobject thiz, jlong textureId, jobject surface, jint width, jint height, jfloat density) {
    
    __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", 
        "nativeOnSurfaceChanged: size=%dx%d", width, height);
    
    ANativeWindow* window = ANativeWindow_fromSurface(env, surface);
    
    g_surfaceWidth = width;
    g_surfaceHeight = height;
    g_density = density;
    
    if (g_factory && g_framework) {
        // Re-enable rendering with new surface
        auto* rawFactory = static_cast<dp::ThreadSafeFactory*>(g_factory.get());
        if (rawFactory) {
            // Get the underlying factory and reset surface
            // Note: This is a simplified approach - may need more work for proper surface recreation
            g_framework->SetRenderingEnabled(make_ref(g_factory));
            g_framework->OnSize(width, height);
        }
    }
    
    if (window) ANativeWindow_release(window);
}

extern "C" JNIEXPORT void JNICALL
Java_app_agus_maps_agus_1maps_1flutter_AgusMapsFlutterPlugin_nativeOnSurfaceDestroyed(JNIEnv* env, jobject thiz) {
    __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", "nativeOnSurfaceDestroyed");
    
    if (g_framework) {
        g_framework->SetRenderingDisabled(true /* destroySurface */);
    }
}

extern "C" JNIEXPORT void JNICALL
Java_app_agus_maps_agus_1maps_1flutter_AgusMapsFlutterPlugin_nativeOnSizeChanged(
    JNIEnv* env, jobject thiz, jint width, jint height) {
    
    __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", 
        "nativeOnSizeChanged: %dx%d", width, height);
    
    g_surfaceWidth = width;
    g_surfaceHeight = height;
    
    if (g_framework && g_drapeEngineCreated) {
        g_framework->OnSize(width, height);
    }
}

FFI_PLUGIN_EXPORT void comaps_set_view(double lat, double lon, int zoom) {
     __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", "comaps_set_view: lat=%f, lon=%f, zoom=%d", lat, lon, zoom);
     if (g_framework) {
         g_framework->SetViewportCenter(m2::PointD(mercator::FromLatLon(lat, lon)), zoom);
     }
}
// Touch event types matching df::TouchEvent::ETouchType
// 0 = TOUCH_NONE, 1 = TOUCH_DOWN, 2 = TOUCH_MOVE, 3 = TOUCH_UP, 4 = TOUCH_CANCEL
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