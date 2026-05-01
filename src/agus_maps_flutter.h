#pragma once

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

/// Set the locale for native POI type localization.
/// Must be called after comaps_init_paths() for proper localization.
/// If not called, the system locale is auto-detected.
/// Can be called at any time to change locale (affects subsequent place page requests).
/// @param localeTag BCP 47 locale tag (e.g., "en-US", "zh-Hans", "de")
FFI_PLUGIN_EXPORT void comaps_set_locale(const char* localeTag);

FFI_PLUGIN_EXPORT void comaps_set_view(double lat, double lon, int zoom);

// Get current viewport center coordinates in WGS84.
// Returns 1 when values were written, 0 when the framework is not ready.
FFI_PLUGIN_EXPORT int comaps_get_viewport_center(double* lat, double* lon);

// Get the current integer draw scale/zoom level, or -1 when unavailable.
FFI_PLUGIN_EXPORT int comaps_get_current_zoom(void);

// Relative zoom controls centered on the visible viewport.
FFI_PLUGIN_EXPORT void comaps_zoom_in(int animated);
FFI_PLUGIN_EXPORT void comaps_zoom_out(int animated);

// Map bearing in degrees where 0 is north-up.
FFI_PLUGIN_EXPORT double comaps_get_current_bearing(void);
FFI_PLUGIN_EXPORT void comaps_set_bearing(double degrees, int animated);
FFI_PLUGIN_EXPORT void comaps_reset_bearing(int animated);

// Enable/disable 3D map mode with 3D buildings.
FFI_PLUGIN_EXPORT void comaps_set_3d_buildings_enabled(int enabled);
FFI_PLUGIN_EXPORT int comaps_get_3d_buildings_enabled(void);

// Map theme: 0 = light, 1 = dark. Auto mode is resolved by Dart.
FFI_PLUGIN_EXPORT void comaps_set_map_theme(int dark);
FFI_PLUGIN_EXPORT int comaps_get_map_theme_is_dark(void);

// Overlay/style layers matching CoMaps mobile behavior:
// outdoors and isolines may be enabled together; subway/transit disables both.
FFI_PLUGIN_EXPORT void comaps_set_outdoors_enabled(int enabled);
FFI_PLUGIN_EXPORT void comaps_set_isolines_enabled(int enabled);
FFI_PLUGIN_EXPORT void comaps_set_subway_enabled(int enabled);
FFI_PLUGIN_EXPORT void comaps_get_map_layer_state(int* outdoors, int* isolines, int* subway);

// Map label language code. Empty/null = auto; "default" = local/native names.
FFI_PLUGIN_EXPORT void comaps_set_map_language(const char* languageCode);

// Invalidate the current viewport to force tile reload
FFI_PLUGIN_EXPORT void comaps_invalidate(void);

// Force complete redraw by triggering UpdateMapStyle
// This clears all render groups and forces complete tile re-request
// Call after registering maps to ensure tiles are loaded
FFI_PLUGIN_EXPORT void comaps_force_redraw(void);

// Touch event handling
// type: 1=TOUCH_DOWN, 2=TOUCH_MOVE, 3=TOUCH_UP, 4=TOUCH_CANCEL
// id1, x1, y1: first touch pointer
// id2, x2, y2: second touch pointer (use -1 for id2 if single touch)
FFI_PLUGIN_EXPORT void comaps_touch(int type, int id1, float x1, float y1, int id2, float x2, float y2);

// Place page (POI) information
// Returns 1 if a place page is available, 0 otherwise
FFI_PLUGIN_EXPORT int comaps_place_page_has_data(void);

// Structured place page payload for native consumers.
typedef struct {
	const char* mwm_name;
	int64_t mwm_version;
	int64_t index;
} AgusPlacePageFeatureId;

typedef struct {
	const char* decimal;
	const char* dms;
	const char* osm;
	const char* olc;
	const char* utm;
	const char* mgrs;
} AgusPlacePageCoordinates;

typedef struct {
	int64_t key;
	const char* value;
} AgusPlacePageIntMetadataEntry;

typedef struct {
	const char* key;
	const char* value;
} AgusPlacePageStringMetadataEntry;

typedef struct {
	AgusPlacePageFeatureId feature_id;
	int32_t object_type;
	int32_t opening_mode;
	const char* title;
	const char* secondary_title;
	const char* subtitle;
	const char* address;
	double lat;
	double lon;
	const char* wiki_description_html;
	int32_t road_type;
	int32_t is_route_point;
	AgusPlacePageCoordinates coordinates;
	const char** raw_types;
	int32_t raw_types_count;
	AgusPlacePageIntMetadataEntry* metadata;
	int32_t metadata_count;
	AgusPlacePageStringMetadataEntry* metadata_tags;
	int32_t metadata_tags_count;
	int32_t has_bookmark_id;
	int64_t bookmark_id;
	int32_t has_bookmark_category_id;
	int64_t bookmark_category_id;
	int32_t has_track_id;
	int64_t track_id;
} AgusPlacePageData;

// Returns a heap-allocated snapshot of the current place page data, or NULL.
// Call comaps_place_page_free when done.
FFI_PLUGIN_EXPORT AgusPlacePageData* comaps_place_page_copy(void);

// Frees a snapshot allocated by comaps_place_page_copy.
FFI_PLUGIN_EXPORT void comaps_place_page_free(AgusPlacePageData* data);

// Clear the current place page selection
FFI_PLUGIN_EXPORT void comaps_place_page_clear_selection(void);

// Search result types mirrored from search::Result::Type.
// 0=Feature, 1=LatLon, 2=PureSuggest, 3=SuggestFromFeature, 4=Postcode.
typedef struct {
	int32_t index;
	int32_t result_type;
	int32_t is_suggestion;
	int32_t has_point;
	const char* title;
	const char* subtitle;
	const char* address;
	const char* suggestion;
	double lat;
	double lon;
} AgusSearchResult;

// Search snapshot status values:
// 0=idle, 1=running, 2=completed, 3=cancelled, 4=error.
typedef struct {
	int32_t generation;
	int32_t status;
	int32_t result_count;
	AgusSearchResult* results;
} AgusSearchResults;

// Start native CoMaps search. Returns the search generation, or a negative
// value if the framework/query is not ready. When interactive is non-zero,
// CoMaps also starts search-in-viewport for native map result marks.
FFI_PLUGIN_EXPORT int32_t comaps_search_start(
	const char* query,
	const char* locale,
	int32_t interactive,
	int32_t isCategory);

// Returns a heap-allocated snapshot of the latest native search state.
// Call comaps_search_results_free when done.
FFI_PLUGIN_EXPORT AgusSearchResults* comaps_search_copy_results(void);

// Frees a snapshot allocated by comaps_search_copy_results.
FFI_PLUGIN_EXPORT void comaps_search_results_free(AgusSearchResults* data);

// Selects a non-suggestion result from the latest native search result list.
// Returns 1 on success, 0 if the index points to a suggestion, or negative on
// invalid state/index.
FFI_PLUGIN_EXPORT int32_t comaps_search_show_result(int32_t index);

// Cancels active native search requests and clears cached search results.
FFI_PLUGIN_EXPORT void comaps_search_cancel(void);

// Scale (zoom) the map by a factor, centered on a specific pixel point.
// factor: Zoom factor (>1 zooms in, <1 zooms out). Use exp(scrollDelta) for smooth zooming.
// pixelX, pixelY: Screen coordinates to zoom towards (in physical pixels)
// animated: Whether to animate the zoom transition
// This is the preferred method for scroll wheel zoom on desktop platforms.
FFI_PLUGIN_EXPORT void comaps_scale(double factor, double pixelX, double pixelY, int animated);

// Scroll/pan the map by pixel distance
// distanceX, distanceY: Distance to scroll in physical pixels
FFI_PLUGIN_EXPORT void comaps_scroll(double distanceX, double distanceY);

// Register a single MWM map file directly by full path.
// This bypasses the version folder scanning and registers the map file
// directly with the rendering engine.
// Returns: 0 on success, -1 if framework not ready, -2 on exception, 
//          or MwmSet::RegResult value on registration failure
FFI_PLUGIN_EXPORT int comaps_register_single_map(const char* fullPath);

// Register a single MWM map file directly by full path, with an explicit
// snapshot version (e.g. 251209).
//
// IMPORTANT: LocalCountryFile::MakeTemporary() sets version=0, which can lead
// to MwmSet::RegResult::VersionTooOld when the engine expects a non-zero
// snapshot version for a given country/world file.
FFI_PLUGIN_EXPORT int comaps_register_single_map_with_version(const char* fullPath, int64_t version);

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
// @return On Linux: returns 0 on success, negative on error. On other platforms: void.
#if defined(__linux__) && !defined(__ANDROID__)
FFI_PLUGIN_EXPORT int64_t agus_native_create_surface(int32_t width, int32_t height, float density);
#else
FFI_PLUGIN_EXPORT void agus_native_create_surface(int32_t width, int32_t height, float density);
#endif

// Called when the surface size changes
FFI_PLUGIN_EXPORT void agus_native_on_size_changed(int32_t width, int32_t height);

// Called when the display scale (DPI) changes at runtime
FFI_PLUGIN_EXPORT void agus_native_set_visual_scale(float density);

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