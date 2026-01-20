// Copyright 2025 The Agus Maps Flutter Authors
// SPDX-License-Identifier: MIT

#include "include/agus_maps_flutter/agus_maps_flutter_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <epoxy/gl.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>
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
  FlMethodChannel* channel;
  FlTextureRegistrar* texture_registrar;
  AgusMapTexture* texture;
  int64_t texture_id;
  gboolean surface_created;
};

G_DEFINE_TYPE(AgusMapsFlutterPlugin, agus_maps_flutter_plugin, g_object_get_type())

// Global plugin instance for frame callback
static AgusMapsFlutterPlugin* g_plugin_instance = nullptr;

// Frame callback - called from native code when a new frame is ready
static void on_frame_ready() {
  if (g_plugin_instance && g_plugin_instance->texture_registrar && g_plugin_instance->texture) {
    fl_texture_registrar_mark_texture_frame_available(
        g_plugin_instance->texture_registrar,
        FL_TEXTURE(g_plugin_instance->texture));
  }
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

// Called when a method call is received from Flutter.
static void agus_maps_flutter_plugin_handle_method_call(
    AgusMapsFlutterPlugin* self,
    FlMethodCall* method_call) {
  g_autoptr(FlMethodResponse) response = nullptr;
  
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);
  
  std::fprintf(stderr, "[AgusMapsFlutter] Method call: %s\n", method);
  
  if (strcmp(method, "extractMap") == 0) {
    FlValue* asset_path_value = fl_value_lookup_string(args, "assetPath");
    if (asset_path_value == nullptr || fl_value_get_type(asset_path_value) != FL_VALUE_TYPE_STRING) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "INVALID_ARGUMENT", "assetPath is required", nullptr));
    } else {
      const char* asset_path = fl_value_get_string(asset_path_value);
      try {
        std::string extracted_path = extract_map(asset_path);
        g_autoptr(FlValue) result = fl_value_new_string(extracted_path.c_str());
        response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
      } catch (const std::exception& e) {
        response = FL_METHOD_RESPONSE(fl_method_error_response_new(
            "EXTRACTION_FAILED", e.what(), nullptr));
      }
    }
  } else if (strcmp(method, "extractDataFiles") == 0) {
    try {
      std::string data_path = extract_data_files();
      g_autoptr(FlValue) result = fl_value_new_string(data_path.c_str());
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    } catch (const std::exception& e) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "EXTRACTION_FAILED", e.what(), nullptr));
    }
  } else if (strcmp(method, "getApkPath") == 0) {
    std::string exe_dir = get_executable_dir();
    g_autoptr(FlValue) result = fl_value_new_string(exe_dir.c_str());
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (strcmp(method, "createMapSurface") == 0) {
    // Extract parameters
    FlValue* width_value = fl_value_lookup_string(args, "width");
    FlValue* height_value = fl_value_lookup_string(args, "height");
    FlValue* density_value = fl_value_lookup_string(args, "density");
    
    int32_t width = (width_value && fl_value_get_type(width_value) == FL_VALUE_TYPE_INT) 
                    ? static_cast<int32_t>(fl_value_get_int(width_value)) : 800;
    int32_t height = (height_value && fl_value_get_type(height_value) == FL_VALUE_TYPE_INT)
                     ? static_cast<int32_t>(fl_value_get_int(height_value)) : 600;
    float density = (density_value && fl_value_get_type(density_value) == FL_VALUE_TYPE_FLOAT)
                    ? static_cast<float>(fl_value_get_float(density_value)) : 1.0f;
    
    std::fprintf(stderr, "[AgusMapsFlutter] createMapSurface: %dx%d density=%.2f\n", 
                 width, height, density);
    
    // Create our pixel buffer texture for Flutter
    if (!self->texture) {
      self->texture = agus_map_texture_new(width, height);
      
      // Register with Flutter's texture registrar
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
          response = FL_METHOD_RESPONSE(fl_method_error_response_new(
              "TEXTURE_ERROR", "Failed to register texture", nullptr));
          fl_method_call_respond(method_call, response, nullptr);
          return;
        }
      }
    }
    
    // Create native surface (EGL context + FBO)
    int64_t native_result = agus_native_create_surface(width, height, density);
    if (native_result < 0) {
      std::fprintf(stderr, "[AgusMapsFlutter] ERROR: Failed to create native surface\n");
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "SURFACE_ERROR", "Failed to create native surface", nullptr));
    } else {
      self->surface_created = TRUE;
      
      // Set up frame callback to mark texture dirty when native renders new frame
      agus_set_frame_ready_callback(on_frame_ready);
      
      std::fprintf(stderr, "[AgusMapsFlutter] Surface created, returning texture ID: %lld\n",
                   static_cast<long long>(self->texture_id));
      g_autoptr(FlValue) result = fl_value_new_int(self->texture_id);
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
    }
  } else if (strcmp(method, "resizeMapSurface") == 0) {
    FlValue* width_value = fl_value_lookup_string(args, "width");
    FlValue* height_value = fl_value_lookup_string(args, "height");
    FlValue* density_value = fl_value_lookup_string(args, "density");
    
    int32_t width = (width_value && fl_value_get_type(width_value) == FL_VALUE_TYPE_INT)
                    ? static_cast<int32_t>(fl_value_get_int(width_value)) : 0;
    int32_t height = (height_value && fl_value_get_type(height_value) == FL_VALUE_TYPE_INT)
                     ? static_cast<int32_t>(fl_value_get_int(height_value)) : 0;
    float density = (density_value && fl_value_get_type(density_value) == FL_VALUE_TYPE_FLOAT)
                    ? static_cast<float>(fl_value_get_float(density_value)) : 0.0f;
    
    std::fprintf(stderr, "[AgusMapsFlutter] resizeMapSurface: %dx%d\n", width, height);
    
    if (width > 0 && height > 0) {
      // Resize pixel buffer texture
      if (self->texture) {
        agus_map_texture_resize(self->texture, width, height);
      }
      
      // Resize native surface
      agus_native_on_size_changed(width, height);
      if (density > 0) {
        agus_native_set_visual_scale(density);
      }
    }
    
    g_autoptr(FlValue) result = fl_value_new_bool(TRUE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (strcmp(method, "destroyMapSurface") == 0) {
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
    
    g_autoptr(FlValue) result = fl_value_new_bool(TRUE);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  
  fl_method_call_respond(method_call, response, nullptr);
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
  
  G_OBJECT_CLASS(agus_maps_flutter_plugin_parent_class)->dispose(object);
}

static void agus_maps_flutter_plugin_class_init(AgusMapsFlutterPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = agus_maps_flutter_plugin_dispose;
}

static void agus_maps_flutter_plugin_init(AgusMapsFlutterPlugin* self) {
  self->registrar = nullptr;
  self->channel = nullptr;
  self->texture_registrar = nullptr;
  self->texture = nullptr;
  self->texture_id = -1;
  self->surface_created = FALSE;
}

static void method_call_cb(FlMethodChannel* channel, FlMethodCall* method_call,
                           gpointer user_data) {
  AgusMapsFlutterPlugin* plugin = AGUS_MAPS_FLUTTER_PLUGIN(user_data);
  agus_maps_flutter_plugin_handle_method_call(plugin, method_call);
}

void agus_maps_flutter_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  AgusMapsFlutterPlugin* plugin = AGUS_MAPS_FLUTTER_PLUGIN(
      g_object_new(agus_maps_flutter_plugin_get_type(), nullptr));

  plugin->registrar = registrar;
  plugin->texture_registrar = fl_plugin_registrar_get_texture_registrar(registrar);
  
  // Set global instance for frame callback
  g_plugin_instance = plugin;

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "agus_maps_flutter",
                            FL_METHOD_CODEC(codec));
  plugin->channel = FL_METHOD_CHANNEL(g_object_ref(channel));
  
  fl_method_channel_set_method_call_handler(channel, method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);

  g_object_unref(plugin);
  
  std::fprintf(stderr, "[AgusMapsFlutter] Linux plugin registered with texture support\n");
}
