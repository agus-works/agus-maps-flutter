// Copyright 2025 The Agus Maps Flutter Authors
// SPDX-License-Identifier: MIT

#ifndef NOMINMAX
#define NOMINMAX
#endif

#include "include/agus_maps_flutter/agus_maps_flutter_plugin_c_api.h"
#include "agus_maps_api.g.h"
#include "../src/agus_maps_flutter.h"

#include <flutter/plugin_registrar.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/texture_registrar.h>

#include <ShlObj.h>
#include <windows.h>

#include <cmath>
#include <cstdint>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <stdexcept>
#include <string>

namespace agus_maps_flutter {

namespace fs = std::filesystem;

class AgusMapsFlutterPlugin;

static HMODULE GetNativeLibraryHandle();

using CreateSurfaceFn = void (*)(int32_t, int32_t, float);
using OnSizeChangedFn = void (*)(int32_t, int32_t);
using SetVisualScaleFn = void (*)(float);
using OnSurfaceDestroyedFn = void (*)();
using GetSharedTextureHandleFn = void* (*)();
using GetD3D11DeviceFn = void* (*)();
using GetD3D11TextureFn = void* (*)();
using RenderFrameFn = void (*)();
using SetFrameReadyCallbackFn = void (*)(FrameReadyCallback);

static HMODULE g_ffiModule = nullptr;
static bool g_ffiLoaded = false;

static CreateSurfaceFn g_fnCreateSurface = nullptr;
static OnSizeChangedFn g_fnOnSizeChanged = nullptr;
static SetVisualScaleFn g_fnSetVisualScale = nullptr;
static OnSurfaceDestroyedFn g_fnOnSurfaceDestroyed = nullptr;
static GetSharedTextureHandleFn g_fnGetSharedTextureHandle = nullptr;
static GetD3D11DeviceFn g_fnGetD3D11Device = nullptr;
static GetD3D11TextureFn g_fnGetD3D11Texture = nullptr;
static RenderFrameFn g_fnRenderFrame = nullptr;
static SetFrameReadyCallbackFn g_fnSetFrameReadyCallback = nullptr;

static AgusMapsFlutterPlugin* g_pluginInstance = nullptr;

static bool LoadFfiLibrary() {
    if (g_ffiLoaded) {
        return g_ffiModule != nullptr;
    }

    g_ffiLoaded = true;
    g_ffiModule = GetNativeLibraryHandle();
    if (!g_ffiModule) {
        OutputDebugStringA("[AgusMapsFlutter] ERROR: Failed to load agus_maps_flutter.dll\n");
        return false;
    }

    g_fnCreateSurface = reinterpret_cast<CreateSurfaceFn>(
        GetProcAddress(g_ffiModule, "agus_native_create_surface"));
    g_fnOnSizeChanged = reinterpret_cast<OnSizeChangedFn>(
        GetProcAddress(g_ffiModule, "agus_native_on_size_changed"));
    g_fnSetVisualScale = reinterpret_cast<SetVisualScaleFn>(
        GetProcAddress(g_ffiModule, "agus_native_set_visual_scale"));
    g_fnOnSurfaceDestroyed = reinterpret_cast<OnSurfaceDestroyedFn>(
        GetProcAddress(g_ffiModule, "agus_native_on_surface_destroyed"));
    g_fnGetSharedTextureHandle = reinterpret_cast<GetSharedTextureHandleFn>(
        GetProcAddress(g_ffiModule, "agus_get_shared_texture_handle"));
    g_fnGetD3D11Device = reinterpret_cast<GetD3D11DeviceFn>(
        GetProcAddress(g_ffiModule, "agus_get_d3d11_device"));
    g_fnGetD3D11Texture = reinterpret_cast<GetD3D11TextureFn>(
        GetProcAddress(g_ffiModule, "agus_get_d3d11_texture"));
    g_fnRenderFrame = reinterpret_cast<RenderFrameFn>(
        GetProcAddress(g_ffiModule, "agus_render_frame"));
    g_fnSetFrameReadyCallback = reinterpret_cast<SetFrameReadyCallbackFn>(
        GetProcAddress(g_ffiModule, "agus_set_frame_ready_callback"));

    if (!g_fnCreateSurface) {
        OutputDebugStringA("[AgusMapsFlutter] WARN: Missing agus_native_create_surface\n");
    }
    if (!g_fnOnSizeChanged) {
        OutputDebugStringA("[AgusMapsFlutter] WARN: Missing agus_native_on_size_changed\n");
    }
    if (!g_fnGetSharedTextureHandle) {
        OutputDebugStringA("[AgusMapsFlutter] WARN: Missing agus_get_shared_texture_handle\n");
    }

    return true;
}

std::string WideToUtf8(const std::wstring& wide) {
    if (wide.empty()) return std::string();
    int size = WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), static_cast<int>(wide.length()),
                                   nullptr, 0, nullptr, nullptr);
    std::string result(size, 0);
    WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), static_cast<int>(wide.length()),
                        &result[0], size, nullptr, nullptr);
    return result;
}

// Helper: Convert std::string (UTF-8) to std::wstring
std::wstring Utf8ToWide(const std::string& utf8) {
    if (utf8.empty()) return std::wstring();
    int size = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), static_cast<int>(utf8.length()),
                                   nullptr, 0);
    std::wstring result(size, 0);
    MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), static_cast<int>(utf8.length()),
                        &result[0], size);
    return result;
}

// Get Windows Documents directory path
std::string GetDocumentsPath() {
    wchar_t* path = nullptr;
    if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_Documents, 0, nullptr, &path))) {
        std::wstring widePath(path);
        CoTaskMemFree(path);
        return WideToUtf8(widePath);
    }
    return "";
}

// Get the application data directory (AppData/Local)
std::string GetAppDataLocalPath() {
    wchar_t* path = nullptr;
    if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &path))) {
        std::wstring widePath(path);
        CoTaskMemFree(path);
        return WideToUtf8(widePath);
    }
    return "";
}

// Get the directory where the application executable is located
std::string GetExecutableDir() {
    wchar_t path[MAX_PATH];
    DWORD length = GetModuleFileNameW(nullptr, path, MAX_PATH);
    if (length > 0 && length < MAX_PATH) {
        std::wstring widePath(path, length);
        auto pos = widePath.find_last_of(L"\\/");
        if (pos != std::wstring::npos) {
            return WideToUtf8(widePath.substr(0, pos));
        }
    }
    return "";
}

using PlacePageHasDataFn = int (*)();
using PlacePageCopyFn = AgusPlacePageData* (*)();
using PlacePageFreeFn = void (*)(AgusPlacePageData*);
using PlacePageClearSelectionFn = void (*)();

static PlacePageHasDataFn g_fnPlacePageHasData = nullptr;
static PlacePageCopyFn g_fnPlacePageCopy = nullptr;
static PlacePageFreeFn g_fnPlacePageFree = nullptr;
static PlacePageClearSelectionFn g_fnPlacePageClearSelection = nullptr;

static HMODULE GetNativeLibraryHandle() {
    HMODULE module = GetModuleHandleW(L"agus_maps_flutter.dll");
    if (!module) {
        module = LoadLibraryW(L"agus_maps_flutter.dll");
    }
    return module;
}

static bool EnsurePlacePageFunctionsLoaded() {
    if (g_fnPlacePageHasData && g_fnPlacePageCopy && g_fnPlacePageFree &&
        g_fnPlacePageClearSelection) {
        return true;
    }

    if (!LoadFfiLibrary()) {
        return false;
    }

    HMODULE module = GetNativeLibraryHandle();
    if (!module) {
        return false;
    }

    g_fnPlacePageHasData = reinterpret_cast<PlacePageHasDataFn>(
        GetProcAddress(module, "comaps_place_page_has_data"));
    g_fnPlacePageCopy = reinterpret_cast<PlacePageCopyFn>(
        GetProcAddress(module, "comaps_place_page_copy"));
    g_fnPlacePageFree = reinterpret_cast<PlacePageFreeFn>(
        GetProcAddress(module, "comaps_place_page_free"));
    g_fnPlacePageClearSelection = reinterpret_cast<PlacePageClearSelectionFn>(
        GetProcAddress(module, "comaps_place_page_clear_selection"));

    return g_fnPlacePageHasData && g_fnPlacePageCopy && g_fnPlacePageFree &&
           g_fnPlacePageClearSelection;
}

static PlacePageData BuildPlacePageData(const AgusPlacePageData* data) {
    const auto mwm_name = data->feature_id.mwm_name ? data->feature_id.mwm_name : "";
    PlacePageFeatureId feature_id(
        mwm_name,
        data->feature_id.mwm_version,
        data->feature_id.index);

    std::optional<std::string> decimal = data->coordinates.decimal
        ? std::optional<std::string>(data->coordinates.decimal)
        : std::nullopt;
    std::optional<std::string> dms = data->coordinates.dms
        ? std::optional<std::string>(data->coordinates.dms)
        : std::nullopt;
    std::optional<std::string> osm = data->coordinates.osm
        ? std::optional<std::string>(data->coordinates.osm)
        : std::nullopt;
    std::optional<std::string> olc = data->coordinates.olc
        ? std::optional<std::string>(data->coordinates.olc)
        : std::nullopt;
    std::optional<std::string> utm = data->coordinates.utm
        ? std::optional<std::string>(data->coordinates.utm)
        : std::nullopt;
    std::optional<std::string> mgrs = data->coordinates.mgrs
        ? std::optional<std::string>(data->coordinates.mgrs)
        : std::nullopt;

    const std::string* decimal_ptr = decimal ? &*decimal : nullptr;
    const std::string* dms_ptr = dms ? &*dms : nullptr;
    const std::string* osm_ptr = osm ? &*osm : nullptr;
    const std::string* olc_ptr = olc ? &*olc : nullptr;
    const std::string* utm_ptr = utm ? &*utm : nullptr;
    const std::string* mgrs_ptr = mgrs ? &*mgrs : nullptr;

    PlacePageCoordinates coordinates(
        decimal_ptr,
        dms_ptr,
        osm_ptr,
        olc_ptr,
        utm_ptr,
        mgrs_ptr);

    flutter::EncodableList raw_types;
    raw_types.reserve(data->raw_types_count);
    for (int32_t i = 0; i < data->raw_types_count; ++i) {
        const char* type = data->raw_types[i] ? data->raw_types[i] : "";
        raw_types.push_back(flutter::EncodableValue(std::string(type)));
    }

    flutter::EncodableList metadata;
    metadata.reserve(data->metadata_count);
    for (int32_t i = 0; i < data->metadata_count; ++i) {
        const char* value = data->metadata[i].value ? data->metadata[i].value : "";
        PlacePageIntMetadataEntry entry(data->metadata[i].key, value);
        metadata.push_back(
            flutter::EncodableValue(flutter::CustomEncodableValue(entry)));
    }

    flutter::EncodableList metadata_tags;
    metadata_tags.reserve(data->metadata_tags_count);
    for (int32_t i = 0; i < data->metadata_tags_count; ++i) {
        const char* key = data->metadata_tags[i].key ? data->metadata_tags[i].key : "";
        const char* value = data->metadata_tags[i].value ? data->metadata_tags[i].value : "";
        PlacePageStringMetadataEntry entry(key, value);
        metadata_tags.push_back(
            flutter::EncodableValue(flutter::CustomEncodableValue(entry)));
    }

    int64_t bookmark_id_value = data->bookmark_id;
    int64_t bookmark_category_id_value = data->bookmark_category_id;
    int64_t track_id_value = data->track_id;
    int64_t* bookmark_id = data->has_bookmark_id ? &bookmark_id_value : nullptr;
    int64_t* bookmark_category_id =
        data->has_bookmark_category_id ? &bookmark_category_id_value : nullptr;
    int64_t* track_id = data->has_track_id ? &track_id_value : nullptr;

    return PlacePageData(
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

/// AgusMapsFlutterPlugin - Windows implementation
/// 
/// Handles Pigeon host API calls for:
/// - extractMap: Copy map assets from bundle to Documents
/// - extractDataFiles: Extract CoMaps data files
/// - getApkPath: Return executable directory (Windows equivalent)
/// - createMapSurface/resizeMapSurface/destroyMapSurface: Texture management
class AgusMapsFlutterPlugin : public flutter::Plugin, public AgusMapsHostApi {
public:
    static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

    AgusMapsFlutterPlugin(flutter::PluginRegistrarWindows* registrar);
    virtual ~AgusMapsFlutterPlugin();

    // Disallow copy/move
    AgusMapsFlutterPlugin(const AgusMapsFlutterPlugin&) = delete;
    AgusMapsFlutterPlugin& operator=(const AgusMapsFlutterPlugin&) = delete;
    
    // Called when native code renders a new frame
    void OnFrameReady();

private:
    // Pigeon Host API implementations
    void ExtractMap(
        const std::string& asset_path,
        std::function<void(ErrorOr<std::string> reply)> result) override;
    void ExtractDataFiles(
        std::function<void(ErrorOr<std::string> reply)> result) override;
    void GetApkPath(
        std::function<void(ErrorOr<std::string> reply)> result) override;
    void CreateMapSurface(
        const CreateMapSurfaceRequest& request,
        std::function<void(ErrorOr<int64_t> reply)> result) override;
    void ResizeMapSurface(
        const ResizeMapSurfaceRequest& request,
        std::function<void(ErrorOr<bool> reply)> result) override;
    void DestroyMapSurface(
        std::function<void(ErrorOr<bool> reply)> result) override;
    void GetCurrentPlacePage(
        std::function<void(ErrorOr<std::optional<PlacePageData>> reply)> result) override;
    void ClearPlacePageSelection(
        std::function<void(ErrorOr<bool> reply)> result) override;

    // Helper methods
    std::string ExtractMapAsset(const std::string& assetPath);
    std::string ExtractAllDataFiles();
    void ExtractDirectory(const fs::path& sourcePath, const fs::path& destPath);
    bool DataDirLooksComplete(const fs::path& dataDir);

    flutter::PluginRegistrarWindows* registrar_;
    flutter::TextureRegistrar* texture_registrar_;
    std::unique_ptr<AgusMapsFlutterApi> flutter_api_;
    bool map_ready_sent_ = false;
    
    // Texture state
    int64_t texture_id_ = -1;
    std::unique_ptr<flutter::TextureVariant> texture_;
    int32_t surface_width_ = 0;
    int32_t surface_height_ = 0;
    double last_density_ = 0.0;
    
    // GPU surface descriptor - member to avoid static variable issues
    FlutterDesktopGpuSurfaceDescriptor gpu_surface_desc_ = {};
    
    std::mutex mutex_;
};

// Frame ready callback (called from native rendering thread)
static void OnNativeFrameReady() {
    if (g_pluginInstance) {
        g_pluginInstance->OnFrameReady();
    }
}

// Static registration
void AgusMapsFlutterPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
    
    // Pre-load FFI library
    LoadFfiLibrary();
    
    auto plugin = std::make_unique<AgusMapsFlutterPlugin>(registrar);
    g_pluginInstance = plugin.get();

    AgusMapsHostApi::SetUp(registrar->messenger(), plugin.get());

    registrar->AddPlugin(std::move(plugin));
    
    OutputDebugStringA("[AgusMapsFlutter] Windows plugin registered\n");
}

AgusMapsFlutterPlugin::AgusMapsFlutterPlugin(
    flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar)
    , texture_registrar_(registrar->texture_registrar()) {
    flutter_api_ = std::make_unique<AgusMapsFlutterApi>(registrar->messenger());
    OutputDebugStringA("[AgusMapsFlutter] Plugin constructed\n");
}

AgusMapsFlutterPlugin::~AgusMapsFlutterPlugin() {
    // Cleanup texture if registered
    if (texture_id_ >= 0 && texture_registrar_) {
        texture_registrar_->UnregisterTexture(texture_id_);
    }
    
    // Destroy native surface
    if (g_fnOnSurfaceDestroyed) {
        g_fnOnSurfaceDestroyed();
    }
    
    g_pluginInstance = nullptr;
    
    OutputDebugStringA("[AgusMapsFlutter] Plugin destroyed\n");
}

void AgusMapsFlutterPlugin::OnFrameReady() {
    // Mark texture as needing update (called from native render thread)
    if (texture_id_ >= 0 && texture_registrar_) {
        texture_registrar_->MarkTextureFrameAvailable(texture_id_);
        if (!map_ready_sent_ && flutter_api_) {
            map_ready_sent_ = true;
            flutter_api_->OnMapReady(
                texture_id_,
                []() {},
                [](const FlutterError& error) {
                    OutputDebugStringA("[AgusMapsFlutter] onMapReady failed\n");
                });
        }
    }
}
void AgusMapsFlutterPlugin::ExtractMap(
    const std::string& asset_path,
    std::function<void(ErrorOr<std::string> reply)> result) {
    try {
        std::string extractedPath = ExtractMapAsset(asset_path);
        result(ErrorOr<std::string>(extractedPath));
    } catch (const std::exception& e) {
        result(ErrorOr<std::string>(FlutterError("EXTRACTION_FAILED", e.what())));
    }
}

std::string AgusMapsFlutterPlugin::ExtractMapAsset(const std::string& assetPath) {
    OutputDebugStringA(("[AgusMapsFlutter] Extracting asset: " + assetPath + "\n").c_str());

    // Get executable directory (where flutter_assets is located)
    std::string exeDir = GetExecutableDir();
    if (exeDir.empty()) {
        throw std::runtime_error("Failed to get executable directory");
    }

    // Flutter assets are in data/flutter_assets relative to executable
    fs::path assetsDir = fs::path(exeDir) / "data" / "flutter_assets";
    fs::path sourcePath = assetsDir / assetPath;

    // Destination: Documents/agus_maps_flutter for resources CoMaps opens via
    // Platform::GetReader(), and maps/ for regular country maps.
    fs::path documentsDir = fs::path(GetDocumentsPath());
    fs::path dataDir = documentsDir / "agus_maps_flutter";
    fs::path mapsDir = dataDir / "maps";
    
    // Create directories if needed
    fs::create_directories(dataDir);
    fs::create_directories(mapsDir);

    // Extract filename from asset path
    fs::path fileName = fs::path(assetPath).filename();
    const std::string fileNameString = fileName.string();
    const bool rootResource =
        fileNameString == "World.mwm" ||
        fileNameString == "WorldCoasts.mwm" ||
        fileNameString == "icudt75l.dat";
    fs::path destPath = (rootResource ? dataDir : mapsDir) / fileName;

    // Check if already extracted
    if (fs::exists(destPath)) {
        OutputDebugStringA(("[AgusMapsFlutter] Map already exists at: " + destPath.string() + "\n").c_str());
        return destPath.string();
    }

    // Verify source exists
    if (!fs::exists(sourcePath)) {
        throw std::runtime_error("Asset not found: " + sourcePath.string());
    }

    // Copy file
    fs::copy_file(sourcePath, destPath, fs::copy_options::overwrite_existing);

    OutputDebugStringA(("[AgusMapsFlutter] Map extracted to: " + destPath.string() + "\n").c_str());
    return destPath.string();
}

void AgusMapsFlutterPlugin::ExtractDataFiles(
    std::function<void(ErrorOr<std::string> reply)> result) {
    try {
        std::string dataPath = ExtractAllDataFiles();
        result(ErrorOr<std::string>(dataPath));
    } catch (const std::exception& e) {
        result(ErrorOr<std::string>(FlutterError("EXTRACTION_FAILED", e.what())));
    }
}

std::string AgusMapsFlutterPlugin::ExtractAllDataFiles() {
    OutputDebugStringA("[AgusMapsFlutter] Extracting CoMaps data files...\n");

    // Destination: Documents/agus_maps_flutter
    fs::path documentsDir = fs::path(GetDocumentsPath());
    fs::path dataDir = documentsDir / "agus_maps_flutter";
    fs::create_directories(dataDir);

    // Marker file to track extraction
    fs::path markerFile = dataDir / ".comaps_data_extracted";

    // If we previously extracted but the directory is missing required files
    // (common when assets list changes), re-extract.
    if (fs::exists(markerFile) && DataDirLooksComplete(dataDir)) {
        OutputDebugStringA(("[AgusMapsFlutter] Data already extracted at: " + dataDir.string() + "\n").c_str());
        return dataDir.string();
    }

    // Get executable directory
    std::string exeDir = GetExecutableDir();
    if (exeDir.empty()) {
        throw std::runtime_error("Failed to get executable directory");
    }

    // Flutter assets directory
    fs::path assetsDir = fs::path(exeDir) / "data" / "flutter_assets";
    fs::path sourceDataDir = assetsDir / "assets" / "comaps_data";

    if (!fs::exists(sourceDataDir) || !fs::is_directory(sourceDataDir)) {
        throw std::runtime_error("CoMaps data assets directory not found in flutter_assets: " + sourceDataDir.string());
    }

    ExtractDirectory(sourceDataDir, dataDir);

    // Create marker file
    std::ofstream marker(markerFile);
    marker.close();

    OutputDebugStringA(("[AgusMapsFlutter] Data files extracted to: " + dataDir.string() + "\n").c_str());
    return dataDir.string();
}

void AgusMapsFlutterPlugin::ExtractDirectory(
    const fs::path& sourcePath, const fs::path& destPath) {
    for (const auto& entry : fs::directory_iterator(sourcePath)) {
        fs::path destItem = destPath / entry.path().filename();

        if (entry.is_directory()) {
            fs::create_directories(destItem);
            ExtractDirectory(entry.path(), destItem);
        } else if (entry.is_regular_file()) {
            // Always overwrite to keep extracted data in sync with bundled assets.
            fs::copy_file(entry.path(), destItem, fs::copy_options::overwrite_existing);
        }
    }
}

bool AgusMapsFlutterPlugin::DataDirLooksComplete(const fs::path& dataDir) {
    // Keep this list small and representative.
    // If any are missing, we force a re-extract.
    const fs::path requiredFiles[] = {
        dataDir / "classificator.txt",
        dataDir / "types.txt",
        dataDir / "categories_brands.txt",
        dataDir / "drules_proto.bin",
        dataDir / "packed_polygons.bin",
        dataDir / "transit_colors.txt",
        dataDir / "symbols" / "xxhdpi" / "light" / "symbols.sdf",
        dataDir / "symbols" / "xxhdpi" / "light" / "symbols.png",
        dataDir / "symbols" / "xxhdpi" / "dark" / "symbols.sdf",
        dataDir / "symbols" / "xxhdpi" / "dark" / "symbols.png",
        dataDir / "countries-strings" / "en.json" / "localize.json",
        dataDir / "categories-strings" / "en.json" / "localize.json",
        dataDir / "sound-strings" / "en.json" / "localize.json",
        // Localized type names (e.g., "Gas Station" instead of "amenity-fuel")
        dataDir / "localized_types" / "en.lproj" / "LocalizableTypes.strings",
    };

    for (const auto& p : requiredFiles) {
        if (!fs::exists(p)) {
            OutputDebugStringA(("[AgusMapsFlutter] Data incomplete, missing: " + p.string() + "\n").c_str());
            return false;
        }
    }

    // Guardrail: reject stale placeholder/tiny symbol atlas files.
    // Valid atlas files are significantly larger than placeholders.
    struct SizedCheck {
        fs::path path;
        uintmax_t minBytes;
    };
    const SizedCheck sizedChecks[] = {
        {dataDir / "symbols" / "xxhdpi" / "light" / "symbols.png", 100000},
        {dataDir / "symbols" / "xxhdpi" / "dark" / "symbols.png", 100000},
        {dataDir / "symbols" / "xxhdpi" / "light" / "symbols.sdf", 1000},
        {dataDir / "symbols" / "xxhdpi" / "dark" / "symbols.sdf", 1000},
    };

    for (const auto& check : sizedChecks) {
        std::error_code ec;
        const auto size = fs::file_size(check.path, ec);
        if (ec || size < check.minBytes) {
            OutputDebugStringA((
                "[AgusMapsFlutter] Data incomplete, suspicious symbol atlas size: " +
                check.path.string() + " (size=" + std::to_string(size) + ")\n").c_str());
            return false;
        }
    }

    return true;
}

void AgusMapsFlutterPlugin::GetApkPath(
    std::function<void(ErrorOr<std::string> reply)> result) {
    std::string exeDir = GetExecutableDir();
    if (exeDir.empty()) {
        result(ErrorOr<std::string>(FlutterError("PATH_ERROR", "Failed to get executable directory")));
        return;
    }
    result(ErrorOr<std::string>(exeDir));
}

void AgusMapsFlutterPlugin::CreateMapSurface(
    const CreateMapSurfaceRequest& request,
    std::function<void(ErrorOr<int64_t> reply)> result) {
    OutputDebugStringA("[AgusMapsFlutter] createMapSurface called\n");

    int32_t width = request.width() ? static_cast<int32_t>(*request.width()) : 800;
    int32_t height = request.height() ? static_cast<int32_t>(*request.height()) : 600;
    double density = request.density() ? *request.density() : 1.0;
    
    char msg[256];
    snprintf(msg, sizeof(msg), "[AgusMapsFlutter] Creating surface: %dx%d, density=%.2f\n", 
             width, height, density);
    OutputDebugStringA(msg);
    
    // Ensure FFI library is loaded
    if (!LoadFfiLibrary()) {
        OutputDebugStringA("[AgusMapsFlutter] ERROR: Failed to load FFI library\n");
        result(ErrorOr<int64_t>(FlutterError("FFI_ERROR", "Failed to load native FFI library")));
        return;
    }
    
    // Create native surface (this creates Framework, DrapeEngine, OpenGL context)
    if (g_fnCreateSurface) {
        OutputDebugStringA("[AgusMapsFlutter] Calling agus_native_create_surface...\n");
        g_fnCreateSurface(width, height, static_cast<float>(density));
        OutputDebugStringA("[AgusMapsFlutter] agus_native_create_surface returned\n");
    } else {
        OutputDebugStringA("[AgusMapsFlutter] ERROR: agus_native_create_surface not available\n");
        result(ErrorOr<int64_t>(FlutterError("FFI_ERROR", "agus_native_create_surface function not found")));
        return;
    }
    
    // Set up frame ready callback
    if (g_fnSetFrameReadyCallback) {
        g_fnSetFrameReadyCallback(&OnNativeFrameReady);
        OutputDebugStringA("[AgusMapsFlutter] Frame ready callback set\n");
    }
    
    // Get the D3D11 texture from native code
    void* d3d11Device = nullptr;
    void* d3d11Texture = nullptr;
    void* sharedHandle = nullptr;
    
    if (g_fnGetD3D11Device) {
        d3d11Device = g_fnGetD3D11Device();
    }
    if (g_fnGetD3D11Texture) {
        d3d11Texture = g_fnGetD3D11Texture();
    }
    if (g_fnGetSharedTextureHandle) {
        sharedHandle = g_fnGetSharedTextureHandle();
    }
    
    snprintf(msg, sizeof(msg), "[AgusMapsFlutter] D3D11: device=%p, texture=%p, handle=%p\n",
             d3d11Device, d3d11Texture, sharedHandle);
    OutputDebugStringA(msg);
    
    // Store surface dimensions
    surface_width_ = width;
    surface_height_ = height;
    last_density_ = density;
    
    // Create Flutter texture using GPU surface descriptor
    if (sharedHandle && texture_registrar_) {
        // Create texture variant with GPU surface callback
        // IMPORTANT: We query the current handle dynamically because it changes on resize
        texture_ = std::make_unique<flutter::TextureVariant>(
            flutter::GpuSurfaceTexture(
                kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle,
                [this](size_t w, size_t h) -> const FlutterDesktopGpuSurfaceDescriptor* {
                    // Query the CURRENT shared handle - it may have changed due to resize
                    void* currentHandle = nullptr;
                    if (g_fnGetSharedTextureHandle) {
                        currentHandle = g_fnGetSharedTextureHandle();
                    }
                    
                    if (!currentHandle) {
                        OutputDebugStringA("[AgusMapsFlutter] WARNING: No current shared handle available\n");
                        return nullptr;
                    }
                    
                    // Debug logging (once per 60 samples to avoid spam)
                    static int sampleCount = 0;
                    if (sampleCount % 60 == 0) {
                        char dbg[256];
                        snprintf(dbg, sizeof(dbg),
                            "[AgusMapsFlutter] GpuSurfaceTexture callback: requested=%zux%zu, surface=%dx%d, handle=%p\n",
                            w, h, this->surface_width_, this->surface_height_, currentHandle);
                        OutputDebugStringA(dbg);

                        if (w != static_cast<size_t>(this->surface_width_) ||
                            h != static_cast<size_t>(this->surface_height_)) {
                            char mismatch[256];
                            snprintf(mismatch, sizeof(mismatch),
                                "[AgusMapsFlutter] WARNING: Flutter requested size differs from surface (requested=%zux%zu, surface=%dx%d)\n",
                                w, h, this->surface_width_, this->surface_height_);
                            OutputDebugStringA(mismatch);
                        }
                    }
                    sampleCount++;
                    
                    // Use a member descriptor instead of static to avoid race conditions
                    this->gpu_surface_desc_.struct_size = sizeof(FlutterDesktopGpuSurfaceDescriptor);
                    this->gpu_surface_desc_.handle = currentHandle;
                    this->gpu_surface_desc_.width = static_cast<size_t>(this->surface_width_);
                    this->gpu_surface_desc_.height = static_cast<size_t>(this->surface_height_);
                    this->gpu_surface_desc_.visible_width = static_cast<size_t>(this->surface_width_);
                    this->gpu_surface_desc_.visible_height = static_cast<size_t>(this->surface_height_);
                    this->gpu_surface_desc_.format = kFlutterDesktopPixelFormatBGRA8888;
                    this->gpu_surface_desc_.release_context = nullptr;
                    this->gpu_surface_desc_.release_callback = nullptr;
                    return &this->gpu_surface_desc_;
                }
            )
        );
        
        // Register texture with Flutter
        texture_id_ = texture_registrar_->RegisterTexture(texture_.get());
        
        snprintf(msg, sizeof(msg), "[AgusMapsFlutter] Texture registered with ID: %lld\n", texture_id_);
        OutputDebugStringA(msg);
        
        map_ready_sent_ = false;
        result(ErrorOr<int64_t>(texture_id_));
        if (flutter_api_) {
            flutter_api_->OnRenderStateChanged(
                RenderState::kActive,
                &texture_id_,
                []() {},
                [](const FlutterError&) {});
        }
    } else {
        // Fallback: return -1 if texture creation failed
        OutputDebugStringA("[AgusMapsFlutter] WARN: No D3D11 texture available, returning -1\n");
        result(ErrorOr<int64_t>(static_cast<int64_t>(-1)));
    }
}

void AgusMapsFlutterPlugin::ResizeMapSurface(
    const ResizeMapSurfaceRequest& request,
    std::function<void(ErrorOr<bool> reply)> result) {
    std::fprintf(stderr, "[AgusMapsFlutter] resizeMapSurface method call received\n");
    std::fflush(stderr);

    int32_t width = static_cast<int32_t>(request.width());
    int32_t height = static_cast<int32_t>(request.height());
    double density = request.density() ? *request.density() : 0.0;

    if (density > 0.0) {
        std::fprintf(stderr, "[AgusMapsFlutter] Resizing surface to %dx%d (density=%.2f)\n", width, height, density);
    } else {
        std::fprintf(stderr, "[AgusMapsFlutter] Resizing surface to %dx%d\n", width, height);
    }
    std::fflush(stderr);

    surface_width_ = width;
    surface_height_ = height;

    if (g_fnOnSizeChanged) {
        std::fprintf(stderr, "[AgusMapsFlutter] Calling g_fnOnSizeChanged(%d, %d)\n", width, height);
        std::fflush(stderr);
        g_fnOnSizeChanged(width, height);

        if (density > 0.0 && g_fnSetVisualScale) {
            if (std::fabs(density - last_density_) > 0.001) {
                std::fprintf(stderr, "[AgusMapsFlutter] Calling g_fnSetVisualScale(%.2f)\n", density);
                std::fflush(stderr);
                g_fnSetVisualScale(static_cast<float>(density));
                last_density_ = density;
            }
        }

        if (texture_id_ >= 0 && texture_registrar_) {
            texture_registrar_->MarkTextureFrameAvailable(texture_id_);
            std::fprintf(stderr, "[AgusMapsFlutter] MarkTextureFrameAvailable called after resize\n");
            std::fflush(stderr);
        }
    } else {
        std::fprintf(stderr, "[AgusMapsFlutter] WARNING: g_fnOnSizeChanged is null!\n");
        std::fflush(stderr);
    }

    result(ErrorOr<bool>(true));
}

void AgusMapsFlutterPlugin::DestroyMapSurface(
    std::function<void(ErrorOr<bool> reply)> result) {
    OutputDebugStringA("[AgusMapsFlutter] destroyMapSurface called\n");

    if (texture_id_ >= 0 && texture_registrar_) {
        texture_registrar_->UnregisterTexture(texture_id_);
        texture_id_ = -1;
    }

    texture_.reset();
    map_ready_sent_ = false;

    if (g_fnOnSurfaceDestroyed) {
        g_fnOnSurfaceDestroyed();
    }

    if (flutter_api_) {
        flutter_api_->OnRenderStateChanged(
            RenderState::kIdle,
            nullptr,
            []() {},
            [](const FlutterError&) {});
    }

    result(ErrorOr<bool>(true));
}

void AgusMapsFlutterPlugin::GetCurrentPlacePage(
    std::function<void(ErrorOr<std::optional<PlacePageData>> reply)> result) {
    if (!EnsurePlacePageFunctionsLoaded()) {
        OutputDebugStringA("[AgusMapsFlutter] getCurrentPlacePage unavailable (FFI missing)\n");
        result(ErrorOr<std::optional<PlacePageData>>(std::nullopt));
        return;
    }

    if (!g_fnPlacePageHasData || g_fnPlacePageHasData() == 0) {
        result(ErrorOr<std::optional<PlacePageData>>(std::nullopt));
        return;
    }

    AgusPlacePageData* native_data = g_fnPlacePageCopy ? g_fnPlacePageCopy() : nullptr;
    if (!native_data) {
        result(ErrorOr<std::optional<PlacePageData>>(std::nullopt));
        return;
    }

    PlacePageData place_page = BuildPlacePageData(native_data);
    if (g_fnPlacePageFree) {
        g_fnPlacePageFree(native_data);
    }

    result(ErrorOr<std::optional<PlacePageData>>(
        std::optional<PlacePageData>(std::move(place_page))));
}

void AgusMapsFlutterPlugin::ClearPlacePageSelection(
    std::function<void(ErrorOr<bool> reply)> result) {
    if (!EnsurePlacePageFunctionsLoaded()) {
        OutputDebugStringA("[AgusMapsFlutter] clearPlacePageSelection unavailable (FFI missing)\n");
        result(ErrorOr<bool>(false));
        return;
    }

    if (g_fnPlacePageClearSelection) {
        g_fnPlacePageClearSelection();
        result(ErrorOr<bool>(true));
        return;
    }

    result(ErrorOr<bool>(false));
}

}  // namespace agus_maps_flutter

// C API implementation for plugin registration
void AgusMapsFlutterPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
    agus_maps_flutter::AgusMapsFlutterPlugin::RegisterWithRegistrar(
        flutter::PluginRegistrarManager::GetInstance()
            ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
