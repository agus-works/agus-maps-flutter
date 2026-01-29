/// AgusBridge.h
/// 
/// C interface declarations for Swift to call native rendering functions.
/// These functions are implemented in agus_maps_flutter_macos.mm

#pragma once

#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>
#include <stdint.h>

// Note: We don't include agus_maps_flutter.h here because it gets copied to
// a different location in the final framework headers, breaking the relative path.
// All needed declarations are provided directly in this file.

#ifdef __cplusplus
extern "C" {
#endif

// ============================================================================
// Place Page Data Structures (from agus_maps_flutter.h)
// ============================================================================

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

/// Returns a heap-allocated snapshot of the current place page data, or NULL.
/// Call comaps_place_page_free when done.
AgusPlacePageData* comaps_place_page_copy(void);

/// Frees a snapshot allocated by comaps_place_page_copy.
void comaps_place_page_free(AgusPlacePageData* data);

/// Returns 1 if a place page is available, 0 otherwise
int comaps_place_page_has_data(void);

/// Clear the current place page selection
void comaps_place_page_clear_selection(void);

// ============================================================================
// Surface / Rendering Functions
// ============================================================================

/// Called when Swift creates a new map surface
/// @param textureId Flutter texture ID
/// @param pixelBuffer CVPixelBuffer for rendering target
/// @param width Surface width in pixels
/// @param height Surface height in pixels
/// @param density Screen density
void agus_native_set_surface(
    int64_t textureId,
    CVPixelBufferRef pixelBuffer,
    int32_t width,
    int32_t height,
    float density
);

/// Called when Swift resizes the surface (legacy - does not update pixel buffer)
void agus_native_on_size_changed(int32_t width, int32_t height);

/// Called when Swift resizes the surface with new pixel buffer (macOS-specific)
/// This properly updates the Metal texture for resize operations
void agus_native_resize_surface(
    CVPixelBufferRef pixelBuffer,
    int32_t width,
    int32_t height
);

/// Update visual scale without resizing the surface
void agus_native_set_visual_scale(float density);

/// Called when Swift destroys the surface
void agus_native_on_surface_destroyed(void);

/// Frame ready callback type
typedef void (*AgusFrameReadyCallback)(void);

/// Set the callback for frame ready notifications
void agus_set_frame_ready_callback(AgusFrameReadyCallback callback);

/// Called to render a single frame - this is triggered by Flutter's texture system
void agus_render_frame(void);

/// Scale the map around a focal point (desktop zoom)
void comaps_scale(double factor, double pixelX, double pixelY, int animated);

#ifdef __cplusplus
}
#endif
