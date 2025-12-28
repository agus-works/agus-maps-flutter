#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#if _WIN32
#include <windows.h>
#else
#include <pthread.h>
#include <unistd.h>
#endif

#if _WIN32
#define FFI_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// A very short-lived native function.
//
// For very short-lived functions, it is fine to call them on the main isolate.
// They will block the Dart execution while running the native function, so
// only do this for native functions which are guaranteed to be short-lived.
FFI_PLUGIN_EXPORT int sum(int a, int b);

// A longer lived native function, which occupies the thread calling it.
//
// Do not call these kind of native functions in the main isolate. They will
// block Dart execution. This will cause dropped frames in Flutter applications.
// Instead, call these native functions on a separate isolate.
FFI_PLUGIN_EXPORT int sum_long_running(int a, int b);

FFI_PLUGIN_EXPORT void comaps_init(const char* apkPath, const char* storagePath);
FFI_PLUGIN_EXPORT void comaps_init_paths(const char* resourcePath, const char* writablePath);
FFI_PLUGIN_EXPORT void comaps_load_map_path(const char* path);

FFI_PLUGIN_EXPORT void comaps_set_view(double lat, double lon, int zoom);

// Touch event handling
// type: 1=TOUCH_DOWN, 2=TOUCH_MOVE, 3=TOUCH_UP, 4=TOUCH_CANCEL
// id1, x1, y1: first touch pointer
// id2, x2, y2: second touch pointer (use -1 for id2 if single touch)
FFI_PLUGIN_EXPORT void comaps_touch(int type, int id1, float x1, float y1, int id2, float x2, float y2);

// Register a single MWM map file directly by full path.
// This bypasses the version folder scanning and registers the map file
// directly with the rendering engine.
// Returns: 0 on success, -1 if framework not ready, -2 on exception, 
//          or MwmSet::RegResult value on registration failure
FFI_PLUGIN_EXPORT int comaps_register_single_map(const char* fullPath);

// Explicitly shutdown the CoMaps framework.
// Call this before app termination to ensure clean shutdown and avoid crashes.
FFI_PLUGIN_EXPORT void comaps_shutdown(void);

// Debug: List all registered MWMs and their bounds to logcat
FFI_PLUGIN_EXPORT void comaps_debug_list_mwms();

// Debug: Check if a lat/lon point is covered by any registered MWM
FFI_PLUGIN_EXPORT void comaps_debug_check_point(double lat, double lon);

// Deregister a map file by path
FFI_PLUGIN_EXPORT int comaps_deregister_map(const char* fullPath);

// Get the count of registered maps
FFI_PLUGIN_EXPORT int comaps_get_registered_maps_count(void);

// =============================================================================
// Native Surface Functions (for Windows/Desktop)
// =============================================================================

// Create the native rendering surface
// This creates the Framework, DrapeEngine, and OpenGL context
// @param width Surface width in physical pixels
// @param height Surface height in physical pixels
// @param density Screen DPI scale factor
FFI_PLUGIN_EXPORT void agus_native_create_surface(int32_t width, int32_t height, float density);

// Called when the surface size changes
FFI_PLUGIN_EXPORT void agus_native_on_size_changed(int32_t width, int32_t height);

// Called when the surface is destroyed
FFI_PLUGIN_EXPORT void agus_native_on_surface_destroyed(void);

// Get the D3D11 shared texture handle for Flutter (Windows only)
// Returns HANDLE that can be used to open the shared texture
FFI_PLUGIN_EXPORT void* agus_get_shared_texture_handle(void);

// Get the D3D11 device pointer (Windows only)
FFI_PLUGIN_EXPORT void* agus_get_d3d11_device(void);

// Get the D3D11 texture pointer (Windows only)
FFI_PLUGIN_EXPORT void* agus_get_d3d11_texture(void);

// Render a single frame (triggers frame ready callback)
FFI_PLUGIN_EXPORT void agus_render_frame(void);

// Set the frame ready callback
typedef void (*FrameReadyCallback)(void);
FFI_PLUGIN_EXPORT void agus_set_frame_ready_callback(FrameReadyCallback callback);

#ifdef __cplusplus
}
#endif