/// agus_maps_flutter_ios.mm
/// 
/// iOS FFI implementation for agus_maps_flutter.
/// This provides the C FFI functions that Dart FFI calls on iOS.
/// 
/// This file implements the full CoMaps Framework integration for iOS,
/// using Metal for rendering via CVPixelBuffer/IOSurface zero-copy texture sharing.

#include "../src/agus_maps_flutter.h"

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreVideo/CoreVideo.h>

#include <string>
#include <memory>
#include <atomic>
#include <chrono>

// CoMaps Framework includes
#include "base/logging.hpp"
#include "map/framework.hpp"
#include "platform/local_country_file.hpp"
#include "drape/graphics_context_factory.hpp"
#include "drape_frontend/visual_params.hpp"
#include "drape_frontend/user_event_stream.hpp"
#include "drape_frontend/active_frame_callback.hpp"
#include "geometry/mercator.hpp"

// Our Metal context factory
#include "AgusMetalContextFactory.h"

// Forward declarations for AgusPlatformIOS (defined in AgusPlatformIOS.mm)
extern "C" void AgusPlatformIOS_InitPaths(const char* resourcePath, const char* writablePath);
extern "C" void* AgusPlatformIOS_GetInstance(void);

#pragma mark - Global State

static std::unique_ptr<Framework> g_framework;
static drape_ptr<dp::ThreadSafeFactory> g_threadSafeFactory;
static std::string g_resourcePath;
static std::string g_writablePath;
static bool g_platformInitialized = false;
static bool g_drapeEngineCreated = false;

// Surface state
static int32_t g_surfaceWidth = 0;
static int32_t g_surfaceHeight = 0;
static float g_density = 2.0f;
static int64_t g_textureId = -1;

// Frame ready callback
typedef void (*FrameReadyCallback)(void);
static FrameReadyCallback g_frameReadyCallback = nullptr;

// Forward declaration for active frame notification
static void notifyFlutterFrameReady(void);

#pragma mark - Logging

// Custom log handler that redirects to NSLog
static void AgusLogMessage(base::LogLevel level, base::SrcPoint const & src, std::string const & msg) {
    NSString* levelStr;
    switch (level) {
        case base::LDEBUG: levelStr = @"DEBUG"; break;
        case base::LINFO: levelStr = @"INFO"; break;
        case base::LWARNING: levelStr = @"WARN"; break;
        case base::LERROR: levelStr = @"ERROR"; break;
        case base::LCRITICAL: levelStr = @"CRITICAL"; break;
        default: levelStr = @"???"; break;
    }
    
    NSLog(@"[CoMaps %@] %s %s", levelStr, 
          DebugPrint(src).c_str(), msg.c_str());
    
    // Only abort on CRITICAL, not ERROR
    if (level >= base::LCRITICAL) {
        NSLog(@"[CoMaps CRITICAL] Aborting...");
        abort();
    }
}

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
    NSLog(@"[AgusMapsFlutter] comaps_init_paths: resource=%s, writable=%s", resourcePath, writablePath);
    
    // Set up custom log handler before doing anything else
    base::SetLogMessageFn(&AgusLogMessage);
    base::g_LogAbortLevel = base::LCRITICAL;
    
    // Store paths
    g_resourcePath = resourcePath ? resourcePath : "";
    g_writablePath = writablePath ? writablePath : "";
    
    // Initialize platform paths via AgusPlatformIOS
    AgusPlatformIOS_InitPaths(resourcePath, writablePath);
    g_platformInitialized = true;
    
    NSLog(@"[AgusMapsFlutter] Platform initialized, Framework deferred to surface creation");
}

FFI_PLUGIN_EXPORT void comaps_load_map_path(const char* path) {
    NSLog(@"[AgusMapsFlutter] comaps_load_map_path: %s", path);
    
    if (g_framework) {
        g_framework->RegisterAllMaps();
        NSLog(@"[AgusMapsFlutter] Maps registered");
    } else {
        NSLog(@"[AgusMapsFlutter] Framework not yet initialized, maps will be loaded later");
    }
}

FFI_PLUGIN_EXPORT void comaps_set_view(double lat, double lon, int zoom) {
    NSLog(@"[AgusMapsFlutter] comaps_set_view: lat=%.6f, lon=%.6f, zoom=%d", lat, lon, zoom);
    
    if (g_framework) {
        g_framework->SetViewportCenter(m2::PointD(mercator::FromLatLon(lat, lon)), zoom);
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

FFI_PLUGIN_EXPORT int comaps_register_single_map(const char* fullPath) {
    NSLog(@"[AgusMapsFlutter] comaps_register_single_map: %s", fullPath);
    
    if (!g_framework) {
        NSLog(@"[AgusMapsFlutter] Framework not initialized");
        return -1;
    }
    
    try {
        platform::LocalCountryFile file = platform::LocalCountryFile::MakeTemporary(fullPath);
        file.SyncWithDisk();
        
        auto result = g_framework->RegisterMap(file);
        if (result.second == MwmSet::RegResult::Success) {
            NSLog(@"[AgusMapsFlutter] Successfully registered %s", fullPath);
            return 0;
        } else {
            NSLog(@"[AgusMapsFlutter] Failed to register %s, result=%d", 
                  fullPath, static_cast<int>(result.second));
            return static_cast<int>(result.second);
        }
    } catch (std::exception const & e) {
        NSLog(@"[AgusMapsFlutter] Exception registering map: %s", e.what());
        return -2;
    }
}

FFI_PLUGIN_EXPORT int comaps_deregister_map(const char* fullPath) {
    NSLog(@"[AgusMapsFlutter] comaps_deregister_map: %s (not implemented)", fullPath);
    
    // TODO: Implement map deregistration when needed
    // Framework only exposes const DataSource, and DeregisterMap requires non-const
    // For MVP, maps are registered at startup and not deregistered at runtime
    
    return -1;  // Not implemented
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
    NSLog(@"[AgusMapsFlutter] === DEBUG: Listing all registered MWMs ===");
    
    if (!g_framework) {
        NSLog(@"[AgusMapsFlutter] Framework not initialized");
        return;
    }
    
    auto const & dataSource = g_framework->GetDataSource();
    std::vector<std::shared_ptr<MwmInfo>> mwms;
    dataSource.GetMwmsInfo(mwms);
    
    NSLog(@"[AgusMapsFlutter] Total MWMs registered: %lu", mwms.size());
    
    for (auto const & mwmInfo : mwms) {
        if (mwmInfo) {
            auto const & rect = mwmInfo->m_bordersRect;
            NSLog(@"[AgusMapsFlutter]   MWM: %s, bounds: [%.4f, %.4f] - [%.4f, %.4f]",
                  mwmInfo->GetCountryName().c_str(),
                  rect.minX(), rect.minY(), rect.maxX(), rect.maxY());
        }
    }
}

FFI_PLUGIN_EXPORT void comaps_debug_check_point(double lat, double lon) {
    NSLog(@"[AgusMapsFlutter] comaps_debug_check_point: lat=%.6f, lon=%.6f", lat, lon);
    
    if (!g_framework) {
        NSLog(@"[AgusMapsFlutter] Framework not initialized");
        return;
    }
    
    m2::PointD const mercatorPt = mercator::FromLatLon(lat, lon);
    NSLog(@"[AgusMapsFlutter] Mercator coords: (%.4f, %.4f)", mercatorPt.x, mercatorPt.y);
    
    auto const & dataSource = g_framework->GetDataSource();
    std::vector<std::shared_ptr<MwmInfo>> mwms;
    dataSource.GetMwmsInfo(mwms);
    
    for (auto const & mwmInfo : mwms) {
        if (mwmInfo && mwmInfo->m_bordersRect.IsPointInside(mercatorPt)) {
            NSLog(@"[AgusMapsFlutter] Point IS covered by MWM: %s", 
                  mwmInfo->GetCountryName().c_str());
            return;
        }
    }
    
    NSLog(@"[AgusMapsFlutter] Point is NOT covered by any registered MWM");
}

#pragma mark - DrapeEngine Creation

static void createDrapeEngineIfNeeded(int width, int height, float density) {
    if (g_drapeEngineCreated || !g_framework || !g_threadSafeFactory) {
        return;
    }
    
    if (width <= 0 || height <= 0) {
        NSLog(@"[AgusMapsFlutter] createDrapeEngine: Invalid dimensions %dx%d", width, height);
        return;
    }
    
    // Register active frame callback BEFORE creating DrapeEngine
    // This callback is invoked only when isActiveFrame is true (Option 3)
    df::SetActiveFrameCallback([]() {
        notifyFlutterFrameReady();
    });
    NSLog(@"[AgusMapsFlutter] Active frame callback registered");
    
    Framework::DrapeCreationParams p;
    p.m_apiVersion = dp::ApiVersion::Metal;  // Use Metal on iOS
    p.m_surfaceWidth = width;
    p.m_surfaceHeight = height;
    p.m_visualScale = density;
    
    NSLog(@"[AgusMapsFlutter] createDrapeEngine: Creating with %dx%d, scale=%.2f, API=Metal", 
          width, height, density);
    
    g_framework->CreateDrapeEngine(make_ref(g_threadSafeFactory), std::move(p));
    g_drapeEngineCreated = true;
    
    NSLog(@"[AgusMapsFlutter] DrapeEngine created successfully");
}

#pragma mark - Native Surface Functions (called from Swift)

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
    NSLog(@"[AgusMapsFlutter] agus_native_set_surface: texture=%lld, %dx%d, density=%.2f",
          textureId, width, height, density);
    
    if (!g_platformInitialized) {
        NSLog(@"[AgusMapsFlutter] ERROR: Platform not initialized! Call comaps_init_paths first.");
        return;
    }
    
    g_textureId = textureId;
    g_surfaceWidth = width;
    g_surfaceHeight = height;
    g_density = density;
    
    // Create Framework on this thread if not already created
    if (!g_framework) {
        NSLog(@"[AgusMapsFlutter] Creating Framework...");
        
        FrameworkParams params;
        params.m_enableDiffs = false;
        params.m_numSearchAPIThreads = 1;
        
        g_framework = std::make_unique<Framework>(params, false /* loadMaps */);
        NSLog(@"[AgusMapsFlutter] Framework created");
        
        // Register maps
        g_framework->RegisterAllMaps();
        NSLog(@"[AgusMapsFlutter] Maps registered");
    }
    
    // Create Metal context factory with the CVPixelBuffer
    m2::PointU screenSize(static_cast<uint32_t>(width), static_cast<uint32_t>(height));
    auto metalFactory = new agus::AgusMetalContextFactory(pixelBuffer, screenSize);
    
    if (!metalFactory->IsDrawContextCreated()) {
        NSLog(@"[AgusMapsFlutter] ERROR: Failed to create Metal context");
        delete metalFactory;
        return;
    }
    
    // Wrap in ThreadSafeFactory for thread-safe context access
    g_threadSafeFactory = make_unique_dp<dp::ThreadSafeFactory>(metalFactory);
    
    // Create DrapeEngine
    createDrapeEngineIfNeeded(width, height, density);
    
    // Enable rendering
    if (g_framework && g_drapeEngineCreated) {
        g_framework->SetRenderingEnabled(make_ref(g_threadSafeFactory));
        NSLog(@"[AgusMapsFlutter] Rendering enabled");
    }
}

/// Called when Swift resizes the surface
extern "C" FFI_PLUGIN_EXPORT void agus_native_on_size_changed(int32_t width, int32_t height) {
    NSLog(@"[AgusMapsFlutter] agus_native_on_size_changed: %dx%d", width, height);
    
    g_surfaceWidth = width;
    g_surfaceHeight = height;
    
    if (g_framework && g_drapeEngineCreated) {
        g_framework->OnSize(width, height);
    }
}

/// Called when Swift destroys the surface
extern "C" FFI_PLUGIN_EXPORT void agus_native_on_surface_destroyed(void) {
    NSLog(@"[AgusMapsFlutter] agus_native_on_surface_destroyed");
    
    if (g_framework) {
        g_framework->SetRenderingDisabled(true /* destroySurface */);
    }
    
    g_threadSafeFactory.reset();
    g_drapeEngineCreated = false;
}

/// Called by native code to notify Swift that a new frame is ready
/// This should trigger textureRegistry.textureFrameAvailable(textureId)
extern "C" FFI_PLUGIN_EXPORT void agus_set_frame_ready_callback(FrameReadyCallback callback) {
    g_frameReadyCallback = callback;
}

// Frame notification timing for 60fps rate limiting (Option 2)
static std::chrono::steady_clock::time_point g_lastFrameNotification;
static constexpr auto kMinFrameInterval = std::chrono::milliseconds(16); // ~60fps

// Throttling flag to prevent queuing too many frame notifications
static std::atomic<bool> g_frameNotificationPending{false};

/// Internal function to notify Flutter about a new frame
/// Called from the DrapeEngine render thread via df::SetActiveFrameCallback
static void notifyFlutterFrameReady(void) {
    // Rate limiting (Option 2): Enforce 60fps max
    auto now = std::chrono::steady_clock::now();
    auto elapsed = now - g_lastFrameNotification;
    if (elapsed < kMinFrameInterval) {
        return;  // Too soon, skip this notification
    }
    
    // Throttle: if a notification is already pending, skip this one
    // This prevents memory buildup from queued dispatch_async calls
    bool expected = false;
    if (!g_frameNotificationPending.compare_exchange_strong(expected, true)) {
        return;  // Already a notification pending, skip
    }
    
    g_lastFrameNotification = now;
    
    if (g_frameReadyCallback) {
        dispatch_async(dispatch_get_main_queue(), ^{
            g_frameNotificationPending.store(false);
            g_frameReadyCallback();
        });
    } else {
        // Fallback: call Swift static method directly if no callback is set
        dispatch_async(dispatch_get_main_queue(), ^{
            g_frameNotificationPending.store(false);
            // Use NSClassFromString to avoid direct Swift dependency
            Class pluginClass = NSClassFromString(@"agus_maps_flutter.AgusMapsFlutterPlugin");
            if (pluginClass) {
                SEL selector = NSSelectorFromString(@"notifyFrameReadyFromNative");
                if ([pluginClass respondsToSelector:selector]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                    [pluginClass performSelector:selector];
#pragma clang diagnostic pop
                }
            }
        });
    }
}

/// Legacy function for backward compatibility - now only used if Present() still calls it
extern "C" void agus_notify_frame_ready(void) {
    // This is now a no-op because we use df::SetActiveFrameCallback instead
    // The callback is only invoked when isActiveFrame is true in FrontendRenderer
}

#pragma mark - Render Frame

/// Called to render a single frame - this is triggered by Flutter's texture system
extern "C" FFI_PLUGIN_EXPORT void agus_render_frame(void) {
    if (!g_framework || !g_drapeEngineCreated) {
        return;
    }
    
    // The DrapeEngine handles rendering internally
    // We just need to ensure the render loop is running
    // Frame completion will trigger agus_notify_frame_ready
}
