/// agus_maps_flutter_ios.mm
/// 
/// iOS FFI implementation for agus_maps_flutter.
/// This provides the C FFI functions that Dart FFI calls on iOS.
/// 
/// NOTE: This file provides stub implementations that forward to the 
/// Swift plugin or native code. The actual CoMaps integration happens
/// through the XCFramework which is already linked.

#include "../src/agus_maps_flutter.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#include <string>

// Forward declarations for AgusPlatformIOS (defined in AgusPlatformIOS.mm)
extern "C" void AgusPlatformIOS_InitPaths(const char* resourcePath, const char* writablePath);
extern "C" void* AgusPlatformIOS_GetInstance(void);

#pragma mark - Global State

static bool g_initialized = false;
static std::string g_resourcePath;
static std::string g_writablePath;

#pragma mark - FFI Functions

FFI_PLUGIN_EXPORT int sum(int a, int b) { 
    return a + b; 
}

FFI_PLUGIN_EXPORT int sum_long_running(int a, int b) {
    [NSThread sleepForTimeInterval:5.0];
    return a + b;
}

FFI_PLUGIN_EXPORT void comaps_init(const char* apkPath, const char* storagePath) {
    // iOS doesn't use APK paths - redirect to comaps_init_paths
    comaps_init_paths(apkPath, storagePath);
}

FFI_PLUGIN_EXPORT void comaps_init_paths(const char* resourcePath, const char* writablePath) {
    NSLog(@"[AgusMapsFlutter FFI] comaps_init_paths: resource=%s, writable=%s", resourcePath, writablePath);
    
    // Store paths
    g_resourcePath = resourcePath ? resourcePath : "";
    g_writablePath = writablePath ? writablePath : "";
    
    // Initialize platform paths via AgusPlatformIOS
    AgusPlatformIOS_InitPaths(resourcePath, writablePath);
    
    g_initialized = true;
    NSLog(@"[AgusMapsFlutter FFI] Platform initialized");
}

FFI_PLUGIN_EXPORT void comaps_load_map_path(const char* path) {
    NSLog(@"[AgusMapsFlutter FFI] comaps_load_map_path: %s", path);
    // TODO: Implement via Framework when ready
}

FFI_PLUGIN_EXPORT void comaps_set_view(double lat, double lon, int zoom) {
    NSLog(@"[AgusMapsFlutter FFI] comaps_set_view: lat=%.6f, lon=%.6f, zoom=%d", lat, lon, zoom);
    // TODO: Implement via Framework when ready
}

FFI_PLUGIN_EXPORT void comaps_touch(int type, int id1, float x1, float y1, int id2, float x2, float y2) {
    // TODO: Implement via Framework when ready
}

FFI_PLUGIN_EXPORT int comaps_register_single_map(const char* fullPath) {
    NSLog(@"[AgusMapsFlutter FFI] comaps_register_single_map: %s", fullPath);
    // TODO: Implement via Framework when ready
    // Return 0 for now (success) since Framework isn't active yet
    return 0;
}

FFI_PLUGIN_EXPORT int comaps_deregister_map(const char* fullPath) {
    NSLog(@"[AgusMapsFlutter FFI] comaps_deregister_map: %s", fullPath);
    // TODO: Implement via Framework when ready
    return 0;
}

FFI_PLUGIN_EXPORT int comaps_get_registered_maps_count(void) {
    // TODO: Implement via Framework when ready
    return 0;
}

FFI_PLUGIN_EXPORT void comaps_debug_list_mwms(void) {
    NSLog(@"[AgusMapsFlutter FFI] comaps_debug_list_mwms: Framework not yet active on iOS");
    // TODO: Implement via Framework when ready
}

FFI_PLUGIN_EXPORT void comaps_debug_check_point(double lat, double lon) {
    NSLog(@"[AgusMapsFlutter FFI] comaps_debug_check_point: lat=%.6f, lon=%.6f (Framework not yet active)", lat, lon);
    // TODO: Implement via Framework when ready
}

#pragma mark - Native Surface Functions (called from Swift)

// These functions are called by AgusMapsFlutterPlugin.swift to manage the rendering surface

/// Called when Swift creates a new map surface
/// @param textureId Flutter texture ID
/// @param pixelBuffer CVPixelBuffer for rendering target
/// @param width Surface width in pixels
/// @param height Surface height in pixels
/// @param density Screen density
extern "C" FFI_PLUGIN_EXPORT void agus_native_set_surface(
    int64_t textureId,
    CVPixelBufferRef pixelBuffer,
    int32_t width,
    int32_t height,
    float density
) {
    NSLog(@"[AgusMapsFlutter FFI] agus_native_set_surface: texture=%lld, %dx%d, density=%.2f",
          textureId, width, height, density);
    
    // TODO: Create Framework with Metal context
    // This will involve:
    // 1. Creating AgusMetalContextFactory with pixelBuffer
    // 2. Setting up visual params (density, screen size)
    // 3. Creating Framework
    // 4. Creating DrapeEngine
}

/// Called when Swift resizes the surface
extern "C" FFI_PLUGIN_EXPORT void agus_native_on_size_changed(int32_t width, int32_t height) {
    NSLog(@"[AgusMapsFlutter FFI] agus_native_on_size_changed: %dx%d", width, height);
    // TODO: Notify Framework of size change
}

/// Called when Swift destroys the surface
extern "C" FFI_PLUGIN_EXPORT void agus_native_on_surface_destroyed(void) {
    NSLog(@"[AgusMapsFlutter FFI] agus_native_on_surface_destroyed");
    // TODO: Clean up Framework
}

/// Called by native code to notify Swift that a new frame is ready
/// This should trigger textureRegistry.textureFrameAvailable(textureId)
typedef void (*FrameReadyCallback)(void);
static FrameReadyCallback g_frameReadyCallback = nullptr;

extern "C" FFI_PLUGIN_EXPORT void agus_set_frame_ready_callback(FrameReadyCallback callback) {
    g_frameReadyCallback = callback;
}

extern "C" void agus_notify_frame_ready(void) {
    if (g_frameReadyCallback) {
        g_frameReadyCallback();
    }
}
