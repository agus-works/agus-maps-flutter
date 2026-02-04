// Copyright 2025 The Agus Maps Flutter Authors
// SPDX-License-Identifier: MIT

#include "include/agus_maps_flutter/agus_maps_flutter_plugin.h"
#include "agus_maps_api.g.h"
#include "../src/agus_maps_flutter.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <epoxy/gl.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <dlfcn.h>
#include <string>
#include <filesystem>
#include <fstream>
#include <mutex>
#include <atomic>

namespace fs = std::filesystem;

// FFI function declarations - implemented in agus_maps_flutter_linux.cpp
extern "C" {
  int64_t agus_native_create_surface(int32_t width, int32_t height, float density);
  void agus_native_on_size_changed(int32_t width, int32_t height);
  void agus_native_set_visual_scale(float density);
  void agus_native_on_surface_destroyed(void);
  uint32_t agus_get_texture_id(void);
  int32_t agus_get_rendered_width(void);
  int32_t agus_get_rendered_height(void);
  int agus_copy_pixels(uint8_t* buffer, int32_t bufferSize);
  void agus_set_frame_ready_callback(void (*callback)(void));
  void comaps_shutdown(void);
}

// ============================================================================
// AgusMapTexture - Custom FlTextureGL implementation for CoMaps rendering
// ============================================================================

#define AGUS_MAP_TEXTURE(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), agus_map_texture_get_type(), AgusMapTexture))
#define AGUS_MAP_TEXTURE_CLASS(klass) \
  (G_TYPE_CHECK_CLASS_CAST((klass), agus_map_texture_get_type(), AgusMapTextureClass))
#define IS_AGUS_MAP_TEXTURE(obj) \
  (G_TYPE_CHECK_INSTANCE_TYPE((obj), agus_map_texture_get_type()))

typedef struct _AgusMapTexture AgusMapTexture;
typedef struct _AgusMapTextureClass AgusMapTextureClass;

struct _AgusMapTexture {
  FlPixelBufferTexture parent_instance;
  int32_t width;
  int32_t height;
  uint8_t* pixel_buffer;
  size_t buffer_size;
  std::mutex* mutex;
  std::atomic<bool>* dirty;
};

struct _AgusMapTextureClass {
  FlPixelBufferTextureClass parent_class;
};

GType agus_map_texture_get_type(void);

G_DEFINE_TYPE(AgusMapTexture, agus_map_texture, fl_pixel_buffer_texture_get_type())

static gboolean agus_map_texture_copy_pixels(FlPixelBufferTexture* texture,
                                              const uint8_t** out_buffer,
                                              uint32_t* width,
                                              uint32_t* height,
                                              GError** error) {
  AgusMapTexture* self = AGUS_MAP_TEXTURE(texture);
  
  if (!self->pixel_buffer || self->buffer_size == 0) {
    g_set_error(error, g_quark_from_string("agus-map-texture"), 1,
                "No pixel buffer allocated");
    return FALSE;
  }
  
  // Copy pixels from native renderer
  if (self->mutex) {
    std::lock_guard<std::mutex> lock(*self->mutex);
    
    int result = agus_copy_pixels(self->pixel_buffer, static_cast<int32_t>(self->buffer_size));
    if (result != 1) {
      // If copy failed, return existing buffer content (may be stale)
      std::fprintf(stderr, "[AgusMapTexture] Warning: Pixel copy failed\n");
    }
  }
  
  *out_buffer = self->pixel_buffer;
  *width = static_cast<uint32_t>(self->width);
  *height = static_cast<uint32_t>(self->height);
  
  return TRUE;
}

static void agus_map_texture_dispose(GObject* object) {
  AgusMapTexture* self = AGUS_MAP_TEXTURE(object);
  
  if (self->pixel_buffer) {
    g_free(self->pixel_buffer);
    self->pixel_buffer = nullptr;
  }
  
  if (self->mutex) {
    delete self->mutex;
    self->mutex = nullptr;
  }
  
  if (self->dirty) {
    delete self->dirty;
    self->dirty = nullptr;
  }
  
  G_OBJECT_CLASS(agus_map_texture_parent_class)->dispose(object);
}

static void agus_map_texture_class_init(AgusMapTextureClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = agus_map_texture_dispose;
  FL_PIXEL_BUFFER_TEXTURE_CLASS(klass)->copy_pixels = agus_map_texture_copy_pixels;
}

static void agus_map_texture_init(AgusMapTexture* self) {
  self->width = 0;
  self->height = 0;
  self->pixel_buffer = nullptr;
  self->buffer_size = 0;
  self->mutex = new std::mutex();
  self->dirty = new std::atomic<bool>(false);
}

static AgusMapTexture* agus_map_texture_new(int32_t width, int32_t height) {
  AgusMapTexture* self = AGUS_MAP_TEXTURE(g_object_new(agus_map_texture_get_type(), nullptr));
  self->width = width;
  self->height = height;
  self->buffer_size = static_cast<size_t>(width) * height * 4;  // RGBA
  self->pixel_buffer = static_cast<uint8_t*>(g_malloc(self->buffer_size));
  
  // Initialize with a dark blue color for debugging
  for (size_t i = 0; i < self->buffer_size; i += 4) {
    self->pixel_buffer[i + 0] = 30;   // R
    self->pixel_buffer[i + 1] = 30;   // G
    self->pixel_buffer[i + 2] = 60;   // B
    self->pixel_buffer[i + 3] = 255;  // A
  }
  
  return self;
}

static void agus_map_texture_resize(AgusMapTexture* self, int32_t width, int32_t height) {
  if (self->width == width && self->height == height) {
    return;
  }
  
  std::lock_guard<std::mutex> lock(*self->mutex);
  
  self->width = width;
  self->height = height;
  self->buffer_size = static_cast<size_t>(width) * height * 4;
  
  if (self->pixel_buffer) {
    g_free(self->pixel_buffer);
  }
  self->pixel_buffer = static_cast<uint8_t*>(g_malloc(self->buffer_size));
  
  // Initialize with dark blue
  for (size_t i = 0; i < self->buffer_size; i += 4) {
    self->pixel_buffer[i + 0] = 30;
    self->pixel_buffer[i + 1] = 30;
    self->pixel_buffer[i + 2] = 60;
    self->pixel_buffer[i + 3] = 255;
  }
}

// ============================================================================
// AgusMapsFlutterPlugin
// ============================================================================

#define AGUS_MAPS_FLUTTER_PLUGIN(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), agus_maps_flutter_plugin_get_type(), \
                              AgusMapsFlutterPlugin))

struct _AgusMapsFlutterPlugin {
  GObject parent_instance;
  FlPluginRegistrar* registrar;
  FlTextureRegistrar* texture_registrar;
  AgusMapTexture* texture;
  int64_t texture_id;
  gboolean surface_created;
  gboolean map_ready_sent;
  agus_maps_flutterAgusMapsFlutterApi* flutter_api;
};

G_DEFINE_TYPE(AgusMapsFlutterPlugin, agus_maps_flutter_plugin, g_object_get_type())

// Global plugin instance for frame callback
static AgusMapsFlutterPlugin* g_plugin_instance = nullptr;
static std::atomic<bool> g_shutdown_called{false};

using PlacePageHasDataFn = int (*)();
using PlacePageCopyFn = AgusPlacePageData* (*)();
using PlacePageFreeFn = void (*)(AgusPlacePageData* data);
using PlacePageClearSelectionFn = void (*)();

static PlacePageHasDataFn g_fnPlacePageHasData = nullptr;
static PlacePageCopyFn g_fnPlacePageCopy = nullptr;
static PlacePageFreeFn g_fnPlacePageFree = nullptr;
static PlacePageClearSelectionFn g_fnPlacePageClearSelection = nullptr;
static bool g_place_page_checked = false;

static bool EnsurePlacePageFunctionsLoaded() {
  if (g_place_page_checked) {
    return g_fnPlacePageHasData && g_fnPlacePageCopy && g_fnPlacePageFree &&
        g_fnPlacePageClearSelection;
  }

  g_place_page_checked = true;

  g_fnPlacePageHasData = reinterpret_cast<PlacePageHasDataFn>(
      dlsym(RTLD_DEFAULT, "comaps_place_page_has_data"));
  g_fnPlacePageCopy = reinterpret_cast<PlacePageCopyFn>(
      dlsym(RTLD_DEFAULT, "comaps_place_page_copy"));
  g_fnPlacePageFree = reinterpret_cast<PlacePageFreeFn>(
      dlsym(RTLD_DEFAULT, "comaps_place_page_free"));
  g_fnPlacePageClearSelection = reinterpret_cast<PlacePageClearSelectionFn>(
      dlsym(RTLD_DEFAULT, "comaps_place_page_clear_selection"));

  if (!g_fnPlacePageHasData || !g_fnPlacePageCopy || !g_fnPlacePageFree ||
      !g_fnPlacePageClearSelection) {
    std::fprintf(stderr,
                 "[AgusMapsFlutter] Place page FFI symbols not found; "
                 "place page APIs disabled.\n");
    return false;
  }

  return true;
}

static agus_maps_flutterPlacePageData* build_place_page_data(
  const AgusPlacePageData* data) {
  if (!data) {
  return nullptr;
  }

  g_autoptr(agus_maps_flutterPlacePageFeatureId) feature_id =
    agus_maps_flutter_place_page_feature_id_new(
      data->feature_id.mwm_name ? data->feature_id.mwm_name : "",
      data->feature_id.mwm_version,
      data->feature_id.index);

  g_autoptr(agus_maps_flutterPlacePageCoordinates) coordinates =
    agus_maps_flutter_place_page_coordinates_new(
      data->coordinates.decimal,
      data->coordinates.dms,
      data->coordinates.osm,
      data->coordinates.olc,
      data->coordinates.utm,
      data->coordinates.mgrs);

  g_autoptr(FlValue) raw_types = fl_value_new_list();
  for (int32_t i = 0; i < data->raw_types_count; ++i) {
  const char* type = data->raw_types[i] ? data->raw_types[i] : "";
  fl_value_append_take(raw_types, fl_value_new_string(type));
  }

  g_autoptr(FlValue) metadata = fl_value_new_list();
  for (int32_t i = 0; i < data->metadata_count; ++i) {
  g_autoptr(agus_maps_flutterPlacePageIntMetadataEntry) entry =
    agus_maps_flutter_place_page_int_metadata_entry_new(
      data->metadata[i].key,
      data->metadata[i].value ? data->metadata[i].value : "");
  fl_value_append_take(
    metadata,
    fl_value_new_custom_object(
      agus_maps_flutter_place_page_int_metadata_entry_type_id,
      G_OBJECT(entry)));
  }

  g_autoptr(FlValue) metadata_tags = fl_value_new_list();
  for (int32_t i = 0; i < data->metadata_tags_count; ++i) {
  g_autoptr(agus_maps_flutterPlacePageStringMetadataEntry) entry =
    agus_maps_flutter_place_page_string_metadata_entry_new(
      data->metadata_tags[i].key ? data->metadata_tags[i].key : "",
      data->metadata_tags[i].value ? data->metadata_tags[i].value : "");
  fl_value_append_take(
    metadata_tags,
    fl_value_new_custom_object(
      agus_maps_flutter_place_page_string_metadata_entry_type_id,
      G_OBJECT(entry)));
  }

  int64_t bookmark_id_value = data->bookmark_id;
  int64_t bookmark_category_id_value = data->bookmark_category_id;
  int64_t track_id_value = data->track_id;
  int64_t* bookmark_id = data->has_bookmark_id ? &bookmark_id_value : nullptr;
  int64_t* bookmark_category_id =
    data->has_bookmark_category_id ? &bookmark_category_id_value : nullptr;
  int64_t* track_id = data->has_track_id ? &track_id_value : nullptr;

  return agus_maps_flutter_place_page_data_new(
    feature_id,
    data->object_type,
    data->opening_mode,
    data->title ? data->title : "",
    data->secondary_title ? data->secondary_title : "",
    data->subtitle ? data->subtitle : "",
    data->address ? data->address : "",
    data->lat,
    data->lon,
    data->wiki_description_html ? data->wiki_description_html : "",
    data->road_type,
    data->is_route_point != 0,
    coordinates,
    raw_types,
    metadata,
    metadata_tags,
    bookmark_id,
    bookmark_category_id,
    track_id);
}

// Frame callback - called from native code when a new frame is ready
static void on_frame_ready() {
  if (g_plugin_instance && g_plugin_instance->texture_registrar && g_plugin_instance->texture) {
    fl_texture_registrar_mark_texture_frame_available(
        g_plugin_instance->texture_registrar,
        FL_TEXTURE(g_plugin_instance->texture));
  }
}

static void send_render_state_changed(AgusMapsFlutterPlugin* self,
                                      agus_maps_flutterRenderState state,
                                      int64_t* surface_id) {
  if (!self || !self->flutter_api) {
    return;
  }
  agus_maps_flutter_agus_maps_flutter_api_on_render_state_changed(
      self->flutter_api,
      state,
      surface_id,
      nullptr,
      nullptr,
      nullptr);
}

// Get the data directory for the app (similar to Android's filesDir)
static std::string get_data_dir() {
  const char* home = getenv("HOME");
  if (home) {
    fs::path data_dir = fs::path(home) / ".local" / "share" / "agus_maps_flutter";
    return data_dir.string();
  }
  return "/tmp/agus_maps_flutter";
}

// Get the executable directory
static std::string get_executable_dir() {
  char result[PATH_MAX];
  ssize_t count = readlink("/proc/self/exe", result, PATH_MAX);
  if (count != -1) {
    std::string exe_path(result, count);
    size_t pos = exe_path.find_last_of('/');
    if (pos != std::string::npos) {
      return exe_path.substr(0, pos);
    }
  }
  return ".";
}

// Extract a map file from flutter assets to data directory
static std::string extract_map(const char* asset_path) {
  std::fprintf(stderr, "[AgusMapsFlutter] Extracting asset: %s\n", asset_path);
  
  // Get source and destination paths
  std::string exe_dir = get_executable_dir();
  fs::path source_path = fs::path(exe_dir) / "data" / "flutter_assets" / asset_path;
  
  // Extract directly to data_dir (NOT to maps/ subdirectory)
  // This matches iOS/macOS behavior and how CoMaps Platform searches for files
  fs::path data_dir_path = fs::path(get_data_dir());
  fs::create_directories(data_dir_path);
  
  // Extract filename from asset path
  fs::path filename = fs::path(asset_path).filename();
  fs::path dest_path = data_dir_path / filename;
  
  // Check if already extracted
  if (fs::exists(dest_path)) {
    std::fprintf(stderr, "[AgusMapsFlutter] Map already exists at: %s\n", dest_path.string().c_str());
    return dest_path.string();
  }
  
  // Verify source exists
  if (!fs::exists(source_path)) {
    std::fprintf(stderr, "[AgusMapsFlutter] ERROR: Asset not found at: %s\n", source_path.string().c_str());
    throw std::runtime_error("Asset not found: " + source_path.string());
  }
  
  // Copy file
  fs::copy_file(source_path, dest_path, fs::copy_options::overwrite_existing);
  
  std::fprintf(stderr, "[AgusMapsFlutter] Map extracted to: %s\n", dest_path.string().c_str());
  return dest_path.string();
}

// Extract directory recursively
static void extract_directory(const fs::path& source_path, const fs::path& dest_path) {
  for (const auto& entry : fs::directory_iterator(source_path)) {
    fs::path dest_item = dest_path / entry.path().filename();
    
    if (entry.is_directory()) {
      fs::create_directories(dest_item);
      extract_directory(entry.path(), dest_item);
    } else if (entry.is_regular_file()) {
      fs::copy_file(entry.path(), dest_item, fs::copy_options::overwrite_existing);
    }
  }
}

// Check if data directory looks complete
static bool data_dir_looks_complete(const fs::path& dir) {
  const fs::path required_files[] = {
    dir / "classificator.txt",
    dir / "types.txt",
    dir / "drules_proto.bin",
    dir / "packed_polygons.bin",
    dir / "transit_colors.txt",
    // Localized type names (e.g., "Gas Station" instead of "amenity-fuel")
    dir / "localized_types" / "en.lproj" / "LocalizableTypes.strings",
  };
  
  for (const auto& p : required_files) {
    if (!fs::exists(p)) {
      std::fprintf(stderr, "[AgusMapsFlutter] Data incomplete, missing: %s\n", p.string().c_str());
      return false;
    }
  }
  return true;
}

// Extract all data files from flutter assets
static std::string extract_data_files() {
  std::fprintf(stderr, "[AgusMapsFlutter] Extracting CoMaps data files...\n");
  
  fs::path data_dir_path = fs::path(get_data_dir());
  fs::create_directories(data_dir_path);
  
  // Marker file to track extraction
  fs::path marker_file = data_dir_path / ".comaps_data_extracted";
  
  // If already extracted and complete, skip
  if (fs::exists(marker_file) && data_dir_looks_complete(data_dir_path)) {
    std::fprintf(stderr, "[AgusMapsFlutter] Data already extracted at: %s\n", data_dir_path.string().c_str());
    return data_dir_path.string();
  }
  
  // Get executable directory
  std::string exe_dir = get_executable_dir();
  if (exe_dir.empty()) {
    throw std::runtime_error("Failed to get executable directory");
  }
  
  // Flutter assets directory
  fs::path assets_dir = fs::path(exe_dir) / "data" / "flutter_assets";
  fs::path source_data_dir = assets_dir / "assets" / "comaps_data";
  
  if (!fs::exists(source_data_dir) || !fs::is_directory(source_data_dir)) {
    throw std::runtime_error("CoMaps data assets directory not found: " + source_data_dir.string());
  }
  
  extract_directory(source_data_dir, data_dir_path);
  
  // Create marker file
  std::ofstream marker(marker_file);
  marker.close();
  
  std::fprintf(stderr, "[AgusMapsFlutter] Data files extracted to: %s\n", data_dir_path.string().c_str());
  return data_dir_path.string();
}

static void handle_extract_map(const gchar* asset_path,
                               agus_maps_flutterAgusMapsHostApiResponseHandle* response_handle,
                               gpointer user_data) {
  try {
    std::string extracted_path = extract_map(asset_path);
    agus_maps_flutter_agus_maps_host_api_respond_extract_map(
        response_handle,
        extracted_path.c_str());
  } catch (const std::exception& e) {
    agus_maps_flutter_agus_maps_host_api_respond_error_extract_map(
        response_handle,
        "EXTRACTION_FAILED",
        e.what(),
        nullptr);
  }
}

static void handle_extract_data_files(
    agus_maps_flutterAgusMapsHostApiResponseHandle* response_handle,
    gpointer user_data) {
  try {
    std::string data_path = extract_data_files();
    agus_maps_flutter_agus_maps_host_api_respond_extract_data_files(
        response_handle,
        data_path.c_str());
  } catch (const std::exception& e) {
    agus_maps_flutter_agus_maps_host_api_respond_error_extract_data_files(
        response_handle,
        "EXTRACTION_FAILED",
        e.what(),
        nullptr);
  }
}

static void handle_get_apk_path(
    agus_maps_flutterAgusMapsHostApiResponseHandle* response_handle,
    gpointer user_data) {
  std::string exe_dir = get_executable_dir();
  agus_maps_flutter_agus_maps_host_api_respond_get_apk_path(
      response_handle,
      exe_dir.c_str());
}

static void handle_create_map_surface(
    agus_maps_flutterCreateMapSurfaceRequest* request,
    agus_maps_flutterAgusMapsHostApiResponseHandle* response_handle,
    gpointer user_data) {
  AgusMapsFlutterPlugin* self = AGUS_MAPS_FLUTTER_PLUGIN(user_data);
  int64_t* width_ptr = agus_maps_flutter_create_map_surface_request_get_width(request);
  int64_t* height_ptr = agus_maps_flutter_create_map_surface_request_get_height(request);
  double* density_ptr = agus_maps_flutter_create_map_surface_request_get_density(request);

  int32_t width = width_ptr ? static_cast<int32_t>(*width_ptr) : 800;
  int32_t height = height_ptr ? static_cast<int32_t>(*height_ptr) : 600;
  float density = density_ptr ? static_cast<float>(*density_ptr) : 1.0f;

  std::fprintf(stderr, "[AgusMapsFlutter] createMapSurface: %dx%d density=%.2f\n",
               width, height, density);

  if (!self->texture) {
    self->texture = agus_map_texture_new(width, height);
    if (self->texture_registrar) {
      gboolean registered = fl_texture_registrar_register_texture(
          self->texture_registrar, FL_TEXTURE(self->texture));
      if (registered) {
        self->texture_id = fl_texture_get_id(FL_TEXTURE(self->texture));
        std::fprintf(stderr, "[AgusMapsFlutter] Texture registered with ID: %lld\n",
                     static_cast<long long>(self->texture_id));
      } else {
        std::fprintf(stderr, "[AgusMapsFlutter] ERROR: Failed to register texture\n");
        g_object_unref(self->texture);
        self->texture = nullptr;
        agus_maps_flutter_agus_maps_host_api_respond_error_create_map_surface(
            response_handle,
            "TEXTURE_ERROR",
            "Failed to register texture",
            nullptr);
        return;
      }
    }
  }

  int64_t native_result = agus_native_create_surface(width, height, density);
  if (native_result < 0) {
    std::fprintf(stderr, "[AgusMapsFlutter] ERROR: Failed to create native surface\n");
    agus_maps_flutter_agus_maps_host_api_respond_error_create_map_surface(
        response_handle,
        "SURFACE_ERROR",
        "Failed to create native surface",
        nullptr);
  } else {
    self->surface_created = TRUE;
    self->map_ready_sent = FALSE;
    agus_set_frame_ready_callback(on_frame_ready);
    std::fprintf(stderr, "[AgusMapsFlutter] Surface created, returning texture ID: %lld\n",
                 static_cast<long long>(self->texture_id));
    agus_maps_flutter_agus_maps_host_api_respond_create_map_surface(
        response_handle,
        self->texture_id);
    int64_t surface_id = self->texture_id;
    send_render_state_changed(self, AGUS_MAPS_FLUTTER_RENDER_STATE_ACTIVE, &surface_id);
    if (self->flutter_api && !self->map_ready_sent) {
      self->map_ready_sent = TRUE;
      agus_maps_flutter_agus_maps_flutter_api_on_map_ready(
          self->flutter_api,
          self->texture_id,
          nullptr,
          nullptr,
          nullptr);
    }
  }
}

static void handle_resize_map_surface(
    agus_maps_flutterResizeMapSurfaceRequest* request,
    agus_maps_flutterAgusMapsHostApiResponseHandle* response_handle,
    gpointer user_data) {
  AgusMapsFlutterPlugin* self = AGUS_MAPS_FLUTTER_PLUGIN(user_data);
  int32_t width = static_cast<int32_t>(agus_maps_flutter_resize_map_surface_request_get_width(request));
  int32_t height = static_cast<int32_t>(agus_maps_flutter_resize_map_surface_request_get_height(request));
  double* density_ptr = agus_maps_flutter_resize_map_surface_request_get_density(request);

  float density = density_ptr ? static_cast<float>(*density_ptr) : 0.0f;

  std::fprintf(stderr, "[AgusMapsFlutter] resizeMapSurface: %dx%d\n", width, height);

  if (width > 0 && height > 0) {
    if (self->texture) {
      agus_map_texture_resize(self->texture, width, height);
    }
    agus_native_on_size_changed(width, height);
    if (density > 0) {
      agus_native_set_visual_scale(density);
    }
  }

  agus_maps_flutter_agus_maps_host_api_respond_resize_map_surface(
      response_handle,
      TRUE);
}

static void handle_destroy_map_surface(
    agus_maps_flutterAgusMapsHostApiResponseHandle* response_handle,
    gpointer user_data) {
  AgusMapsFlutterPlugin* self = AGUS_MAPS_FLUTTER_PLUGIN(user_data);
  std::fprintf(stderr, "[AgusMapsFlutter] destroyMapSurface\n");

  agus_set_frame_ready_callback(nullptr);
  agus_native_on_surface_destroyed();

  if (self->texture && self->texture_registrar) {
    fl_texture_registrar_unregister_texture(self->texture_registrar,
                                             FL_TEXTURE(self->texture));
    g_object_unref(self->texture);
    self->texture = nullptr;
  }
  self->surface_created = FALSE;
  self->map_ready_sent = FALSE;

  send_render_state_changed(self, AGUS_MAPS_FLUTTER_RENDER_STATE_IDLE, nullptr);
  agus_maps_flutter_agus_maps_host_api_respond_destroy_map_surface(
      response_handle,
      TRUE);
}

static void handle_get_current_place_page(
    agus_maps_flutterAgusMapsHostApiResponseHandle* response_handle,
    gpointer user_data) {
  (void)user_data;
  if (!EnsurePlacePageFunctionsLoaded() || g_fnPlacePageHasData() == 0) {
    agus_maps_flutter_agus_maps_host_api_respond_get_current_place_page(
        response_handle,
        nullptr);
    return;
  }

  AgusPlacePageData* native_data = g_fnPlacePageCopy();
  if (!native_data) {
    agus_maps_flutter_agus_maps_host_api_respond_get_current_place_page(
        response_handle,
        nullptr);
    return;
  }

  g_autoptr(agus_maps_flutterPlacePageData) place_page =
      build_place_page_data(native_data);
  g_fnPlacePageFree(native_data);

  agus_maps_flutter_agus_maps_host_api_respond_get_current_place_page(
      response_handle,
      place_page);
}

static void handle_clear_place_page_selection(
    agus_maps_flutterAgusMapsHostApiResponseHandle* response_handle,
    gpointer user_data) {
  (void)user_data;
  if (!EnsurePlacePageFunctionsLoaded()) {
    agus_maps_flutter_agus_maps_host_api_respond_clear_place_page_selection(
        response_handle,
        FALSE);
    return;
  }

  g_fnPlacePageClearSelection();
  agus_maps_flutter_agus_maps_host_api_respond_clear_place_page_selection(
      response_handle,
      TRUE);
}

static void agus_maps_flutter_plugin_dispose(GObject* object) {
  AgusMapsFlutterPlugin* self = AGUS_MAPS_FLUTTER_PLUGIN(object);
  
  // Clear global instance
  if (g_plugin_instance == self) {
    g_plugin_instance = nullptr;
  }
  
  // Clean up texture
  if (self->texture && self->texture_registrar) {
    agus_set_frame_ready_callback(nullptr);
    fl_texture_registrar_unregister_texture(self->texture_registrar,
                                             FL_TEXTURE(self->texture));
    g_object_unref(self->texture);
    self->texture = nullptr;
  }
  
  // Destroy native surface
  if (self->surface_created) {
    agus_native_on_surface_destroyed();
    self->surface_created = FALSE;
  }

  if (!g_shutdown_called.exchange(true)) {
    comaps_shutdown();
  }

  if (self->registrar) {
    FlBinaryMessenger* messenger = fl_plugin_registrar_get_messenger(self->registrar);
    agus_maps_flutter_agus_maps_host_api_clear_method_handlers(messenger, nullptr);
  }

  if (self->flutter_api) {
    g_object_unref(self->flutter_api);
    self->flutter_api = nullptr;
  }
  
  G_OBJECT_CLASS(agus_maps_flutter_plugin_parent_class)->dispose(object);
}

static void agus_maps_flutter_plugin_class_init(AgusMapsFlutterPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = agus_maps_flutter_plugin_dispose;
}

static void agus_maps_flutter_plugin_init(AgusMapsFlutterPlugin* self) {
  self->registrar = nullptr;
  self->texture_registrar = nullptr;
  self->texture = nullptr;
  self->texture_id = -1;
  self->surface_created = FALSE;
  self->map_ready_sent = FALSE;
  self->flutter_api = nullptr;
}

void agus_maps_flutter_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  AgusMapsFlutterPlugin* plugin = AGUS_MAPS_FLUTTER_PLUGIN(
      g_object_new(agus_maps_flutter_plugin_get_type(), nullptr));

  plugin->registrar = registrar;
  plugin->texture_registrar = fl_plugin_registrar_get_texture_registrar(registrar);
  plugin->flutter_api = agus_maps_flutter_agus_maps_flutter_api_new(
      fl_plugin_registrar_get_messenger(registrar),
      nullptr);
  
  // Set global instance for frame callback
  g_plugin_instance = plugin;

    static const agus_maps_flutterAgusMapsHostApiVTable vtable = {
      .extract_map = handle_extract_map,
      .extract_data_files = handle_extract_data_files,
      .get_apk_path = handle_get_apk_path,
      .create_map_surface = handle_create_map_surface,
      .resize_map_surface = handle_resize_map_surface,
      .destroy_map_surface = handle_destroy_map_surface,
      .get_current_place_page = handle_get_current_place_page,
      .clear_place_page_selection = handle_clear_place_page_selection,
    };
    agus_maps_flutter_agus_maps_host_api_set_method_handlers(
      fl_plugin_registrar_get_messenger(registrar),
      nullptr,
      &vtable,
        g_object_ref(plugin),
      g_object_unref);

  g_object_unref(plugin);

  std::fprintf(stderr, "[AgusMapsFlutter] Linux plugin registered with texture support\n");
}
