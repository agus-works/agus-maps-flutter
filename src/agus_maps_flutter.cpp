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

#include "map/framework.hpp"
#include "drape_frontend/visual_params.hpp"
#include "geometry/mercator.hpp"
#include "agus_ogl.hpp"

extern "C" void AgusPlatform_Init(const char* apkPath, const char* storagePath);
extern "C" void AgusPlatform_InitPaths(const char* resourcePath, const char* writablePath);

// Globals
static std::unique_ptr<Framework> g_framework;
static std::unique_ptr<agus::AgusOGLContextFactory> g_factory;

// Old init function for backwards compatibility (uses APK path)
FFI_PLUGIN_EXPORT void comaps_init(const char* apkPath, const char* storagePath) {
    __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", "comaps_init: apk=%s, storage=%s", apkPath, storagePath);
    AgusPlatform_Init(apkPath, storagePath);
    
    // Note: Framework initialization requires many data files (categories.txt, etc.)
    // For now we just initialize the platform; full Framework will be created when surface is ready
    __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", "comaps_init: Platform initialized, Framework deferred");
}

// New init function with explicit resource and writable paths
FFI_PLUGIN_EXPORT void comaps_init_paths(const char* resourcePath, const char* writablePath) {
    __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", "comaps_init_paths: resource=%s, writable=%s", resourcePath, writablePath);
    AgusPlatform_InitPaths(resourcePath, writablePath);
    
    __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", "comaps_init_paths: Platform initialized with extracted data files");
    
    // Defer Framework creation - will be created when surface is ready
    // Framework has many dependencies that need to be validated first
    __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", "comaps_init_paths: Framework deferred until surface ready");
}

FFI_PLUGIN_EXPORT void comaps_load_map_path(const char* path) {
    __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", "comaps_load_map_path: %s", path);
    // TODO: Register map file
}

extern "C" JNIEXPORT void JNICALL
Java_app_agus_maps_agus_1maps_1flutter_AgusMapsFlutterPlugin_nativeSetSurface(JNIEnv* env, jobject thiz, jlong textureId, jobject surface) {
    ANativeWindow* window = ANativeWindow_fromSurface(env, surface);
    __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", "nativeSetSurface: textureId=%ld, window=%p", textureId, window);
    
    if (!g_framework) {
       __android_log_print(ANDROID_LOG_ERROR, "AgusMapsFlutterNative", "Framework not initialized!");
       return;
    }

    g_factory = std::make_unique<agus::AgusOGLContextFactory>(window);
    
    Framework::DrapeCreationParams p;
    p.m_apiVersion = dp::ApiVersion::OpenGLES3;
    p.m_surfaceWidth = g_factory->GetWidth();
    p.m_surfaceHeight = g_factory->GetHeight();
    p.m_visualScale = 2.0f; // Hardcoded density for now
    
    // Minimal widgets init info to avoid assertion failure in Framework
    p.m_widgetsInitInfo[gui::EWidget::WIDGET_RULER] = gui::Position(m2::PointF(10, 10), dp::Anchor::LeftBottom);
    p.m_widgetsInitInfo[gui::EWidget::WIDGET_COMPASS] = gui::Position(m2::PointF(10, 100), dp::Anchor::LeftBottom);
    p.m_widgetsInitInfo[gui::EWidget::WIDGET_COPYRIGHT] = gui::Position(m2::PointF(100, 10), dp::Anchor::RightBottom);

    g_framework->CreateDrapeEngine(make_ref(g_factory), std::move(p));
}

FFI_PLUGIN_EXPORT void comaps_set_view(double lat, double lon, int zoom) {
     __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", "comaps_set_view: lat=%f, lon=%f, zoom=%d", lat, lon, zoom);
     if (g_framework) {
         g_framework->SetViewportCenter(m2::PointD(mercator::FromLatLon(lat, lon)), zoom);
     }
}
