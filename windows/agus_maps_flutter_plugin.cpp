// Copyright 2025 The Agus Maps Flutter Authors
// SPDX-License-Identifier: MIT

#include "include/agus_maps_flutter/agus_maps_flutter_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter/encodable_value.h>
#include <flutter/texture_registrar.h>

#include <windows.h>
#include <shlobj.h>
#include <d3d11.h>
#include <dxgi.h>

#include <memory>
#include <string>
#include <filesystem>
#include <fstream>
#include <mutex>

namespace fs = std::filesystem;

namespace agus_maps_flutter {

// =============================================================================
// FFI Function Types (from agus_maps_flutter.dll)
// =============================================================================

typedef void (*FnAgusNativeCreateSurface)(int32_t width, int32_t height, float density);
typedef void (*FnAgusNativeOnSizeChanged)(int32_t width, int32_t height);
typedef void (*FnAgusNativeOnSurfaceDestroyed)(void);
typedef void* (*FnAgusGetSharedTextureHandle)(void);
typedef void* (*FnAgusGetD3D11Device)(void);
typedef void* (*FnAgusGetD3D11Texture)(void);
typedef void (*FnAgusRenderFrame)(void);
typedef void (*FnAgusSetFrameReadyCallback)(void (*callback)(void));

// Global FFI function pointers
static HMODULE g_ffiLibrary = nullptr;
static FnAgusNativeCreateSurface g_fnCreateSurface = nullptr;
static FnAgusNativeOnSizeChanged g_fnOnSizeChanged = nullptr;
static FnAgusNativeOnSurfaceDestroyed g_fnOnSurfaceDestroyed = nullptr;
static FnAgusGetSharedTextureHandle g_fnGetSharedTextureHandle = nullptr;
static FnAgusGetD3D11Device g_fnGetD3D11Device = nullptr;
static FnAgusGetD3D11Texture g_fnGetD3D11Texture = nullptr;
static FnAgusRenderFrame g_fnRenderFrame = nullptr;
static FnAgusSetFrameReadyCallback g_fnSetFrameReadyCallback = nullptr;

// Forward declaration
class AgusMapsFlutterPlugin;
static AgusMapsFlutterPlugin* g_pluginInstance = nullptr;

// Helper: Load FFI library and get function pointers
static bool LoadFfiLibrary() {
    if (g_ffiLibrary) return true;
    
    // Get executable directory
    wchar_t path[MAX_PATH];
    DWORD length = GetModuleFileNameW(nullptr, path, MAX_PATH);
    if (length == 0 || length >= MAX_PATH) {
        OutputDebugStringA("[AgusMapsFlutter] Failed to get module path\n");
        return false;
    }
    
    std::wstring exeDir(path, length);
    auto pos = exeDir.find_last_of(L"\\/");
    if (pos != std::wstring::npos) {
        exeDir = exeDir.substr(0, pos);
    }
    
    // FFI library should be in the same directory
    std::wstring dllPath = exeDir + L"\\agus_maps_flutter.dll";
    
    OutputDebugStringW((L"[AgusMapsFlutter] Loading FFI library: " + dllPath + L"\n").c_str());
    
    g_ffiLibrary = LoadLibraryW(dllPath.c_str());
    if (!g_ffiLibrary) {
        DWORD error = GetLastError();
        char msg[256];
        snprintf(msg, sizeof(msg), "[AgusMapsFlutter] Failed to load FFI library, error=%lu\n", error);
        OutputDebugStringA(msg);
        return false;
    }
    
    // Get function pointers
    g_fnCreateSurface = (FnAgusNativeCreateSurface)GetProcAddress(g_ffiLibrary, "agus_native_create_surface");
    g_fnOnSizeChanged = (FnAgusNativeOnSizeChanged)GetProcAddress(g_ffiLibrary, "agus_native_on_size_changed");
    g_fnOnSurfaceDestroyed = (FnAgusNativeOnSurfaceDestroyed)GetProcAddress(g_ffiLibrary, "agus_native_on_surface_destroyed");
    g_fnGetSharedTextureHandle = (FnAgusGetSharedTextureHandle)GetProcAddress(g_ffiLibrary, "agus_get_shared_texture_handle");
    g_fnGetD3D11Device = (FnAgusGetD3D11Device)GetProcAddress(g_ffiLibrary, "agus_get_d3d11_device");
    g_fnGetD3D11Texture = (FnAgusGetD3D11Texture)GetProcAddress(g_ffiLibrary, "agus_get_d3d11_texture");
    g_fnRenderFrame = (FnAgusRenderFrame)GetProcAddress(g_ffiLibrary, "agus_render_frame");
    g_fnSetFrameReadyCallback = (FnAgusSetFrameReadyCallback)GetProcAddress(g_ffiLibrary, "agus_set_frame_ready_callback");
    
    char msg[512];
    snprintf(msg, sizeof(msg), 
             "[AgusMapsFlutter] FFI functions: create=%p, size=%p, destroy=%p, handle=%p, device=%p, tex=%p, render=%p, callback=%p\n",
             g_fnCreateSurface, g_fnOnSizeChanged, g_fnOnSurfaceDestroyed, 
             g_fnGetSharedTextureHandle, g_fnGetD3D11Device, g_fnGetD3D11Texture,
             g_fnRenderFrame, g_fnSetFrameReadyCallback);
    OutputDebugStringA(msg);
    
    if (!g_fnCreateSurface) {
        OutputDebugStringA("[AgusMapsFlutter] WARN: agus_native_create_surface not found\n");
    }
    
    return true;
}

// Helper: Convert std::wstring to std::string (UTF-8)
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

// Type aliases for Flutter types
using FlutterMethodCall = flutter::MethodCall<flutter::EncodableValue>;
using FlutterMethodResult = flutter::MethodResult<flutter::EncodableValue>;
using FlutterMethodChannel = flutter::MethodChannel<flutter::EncodableValue>;

/// AgusMapsFlutterPlugin - Windows implementation
/// 
/// Handles MethodChannel calls for:
/// - extractMap: Copy map assets from bundle to Documents
/// - extractDataFiles: Extract CoMaps data files
/// - getApkPath: Return executable directory (Windows equivalent)
/// - createMapSurface/resizeMapSurface/destroyMapSurface: Texture management
class AgusMapsFlutterPlugin : public flutter::Plugin {
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
    void HandleMethodCall(const FlutterMethodCall& method_call,
                          std::unique_ptr<FlutterMethodResult> result);

    // Method handlers
    void HandleExtractMap(const FlutterMethodCall& call,
                          std::unique_ptr<FlutterMethodResult> result);
    void HandleExtractDataFiles(std::unique_ptr<FlutterMethodResult> result);
    void HandleGetApkPath(std::unique_ptr<FlutterMethodResult> result);
    void HandleCreateMapSurface(const FlutterMethodCall& call,
                                std::unique_ptr<FlutterMethodResult> result);
    void HandleResizeMapSurface(const FlutterMethodCall& call,
                                std::unique_ptr<FlutterMethodResult> result);
    void HandleDestroyMapSurface(std::unique_ptr<FlutterMethodResult> result);

    // Helper methods
    std::string ExtractMapAsset(const std::string& assetPath);
    std::string ExtractAllDataFiles();
    void ExtractDirectory(const fs::path& sourcePath, const fs::path& destPath);
    bool DataDirLooksComplete(const fs::path& dataDir);

    flutter::PluginRegistrarWindows* registrar_;
    flutter::TextureRegistrar* texture_registrar_;
    
    // Texture state
    int64_t texture_id_ = -1;
    std::unique_ptr<flutter::TextureVariant> texture_;
    int32_t surface_width_ = 0;
    int32_t surface_height_ = 0;
    
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
    
    auto channel = std::make_unique<FlutterMethodChannel>(
        registrar->messenger(), "agus_maps_flutter",
        &flutter::StandardMethodCodec::GetInstance());

    auto plugin = std::make_unique<AgusMapsFlutterPlugin>(registrar);
    g_pluginInstance = plugin.get();

    channel->SetMethodCallHandler(
        [plugin_pointer = plugin.get()](const auto& call, auto result) {
            plugin_pointer->HandleMethodCall(call, std::move(result));
        });

    registrar->AddPlugin(std::move(plugin));
    
    OutputDebugStringA("[AgusMapsFlutter] Windows plugin registered\n");
}

AgusMapsFlutterPlugin::AgusMapsFlutterPlugin(
    flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar)
    , texture_registrar_(registrar->texture_registrar()) {
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
    }
}

void AgusMapsFlutterPlugin::HandleMethodCall(
    const FlutterMethodCall& method_call,
    std::unique_ptr<FlutterMethodResult> result) {
    
    const std::string& method = method_call.method_name();
    
    if (method == "extractMap") {
        HandleExtractMap(method_call, std::move(result));
    } else if (method == "extractDataFiles") {
        HandleExtractDataFiles(std::move(result));
    } else if (method == "getApkPath") {
        HandleGetApkPath(std::move(result));
    } else if (method == "createMapSurface") {
        HandleCreateMapSurface(method_call, std::move(result));
    } else if (method == "resizeMapSurface") {
        HandleResizeMapSurface(method_call, std::move(result));
    } else if (method == "destroyMapSurface") {
        HandleDestroyMapSurface(std::move(result));
    } else {
        result->NotImplemented();
    }
}

void AgusMapsFlutterPlugin::HandleExtractMap(
    const FlutterMethodCall& call,
    std::unique_ptr<FlutterMethodResult> result) {
    
    const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
    if (!arguments) {
        result->Error("INVALID_ARGUMENT", "Expected map arguments");
        return;
    }

    auto asset_it = arguments->find(flutter::EncodableValue("assetPath"));
    if (asset_it == arguments->end()) {
        result->Error("INVALID_ARGUMENT", "assetPath is required");
        return;
    }

    const auto* assetPath = std::get_if<std::string>(&asset_it->second);
    if (!assetPath) {
        result->Error("INVALID_ARGUMENT", "assetPath must be a string");
        return;
    }

    try {
        std::string extractedPath = ExtractMapAsset(*assetPath);
        result->Success(flutter::EncodableValue(extractedPath));
    } catch (const std::exception& e) {
        result->Error("EXTRACTION_FAILED", e.what());
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

    // Destination: Documents/agus_maps_flutter/maps
    fs::path documentsDir = fs::path(GetDocumentsPath());
    fs::path mapsDir = documentsDir / "agus_maps_flutter" / "maps";
    
    // Create maps directory if needed
    fs::create_directories(mapsDir);

    // Extract filename from asset path
    fs::path fileName = fs::path(assetPath).filename();
    fs::path destPath = mapsDir / fileName;

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

void AgusMapsFlutterPlugin::HandleExtractDataFiles(
    std::unique_ptr<FlutterMethodResult> result) {
    try {
        std::string dataPath = ExtractAllDataFiles();
        result->Success(flutter::EncodableValue(dataPath));
    } catch (const std::exception& e) {
        result->Error("EXTRACTION_FAILED", e.what());
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
        dataDir / "drules_proto.bin",
        dataDir / "packed_polygons.bin",
        dataDir / "transit_colors.txt",
        dataDir / "countries-strings" / "en.json" / "localize.json",
        dataDir / "categories-strings" / "en.json" / "localize.json",
    };

    for (const auto& p : requiredFiles) {
        if (!fs::exists(p)) {
            OutputDebugStringA(("[AgusMapsFlutter] Data incomplete, missing: " + p.string() + "\n").c_str());
            return false;
        }
    }
    return true;
}

void AgusMapsFlutterPlugin::HandleGetApkPath(
    std::unique_ptr<FlutterMethodResult> result) {
    // Windows equivalent: return executable directory (where data/ folder is)
    std::string exeDir = GetExecutableDir();
    if (exeDir.empty()) {
        result->Error("PATH_ERROR", "Failed to get executable directory");
        return;
    }
    result->Success(flutter::EncodableValue(exeDir));
}

void AgusMapsFlutterPlugin::HandleCreateMapSurface(
    const FlutterMethodCall& call,
    std::unique_ptr<FlutterMethodResult> result) {
    
    OutputDebugStringA("[AgusMapsFlutter] createMapSurface called\n");
    
    // Parse arguments
    const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
    if (!arguments) {
        result->Error("INVALID_ARGUMENT", "Expected map arguments");
        return;
    }
    
    // Get width, height, density from arguments
    int32_t width = 800;  // defaults
    int32_t height = 600;
    double density = 1.0;
    
    auto width_it = arguments->find(flutter::EncodableValue("width"));
    if (width_it != arguments->end()) {
        if (auto* intVal = std::get_if<int32_t>(&width_it->second)) {
            width = *intVal;
        } else if (auto* dblVal = std::get_if<double>(&width_it->second)) {
            width = static_cast<int32_t>(*dblVal);
        }
    }
    
    auto height_it = arguments->find(flutter::EncodableValue("height"));
    if (height_it != arguments->end()) {
        if (auto* intVal = std::get_if<int32_t>(&height_it->second)) {
            height = *intVal;
        } else if (auto* dblVal = std::get_if<double>(&height_it->second)) {
            height = static_cast<int32_t>(*dblVal);
        }
    }
    
    auto density_it = arguments->find(flutter::EncodableValue("density"));
    if (density_it != arguments->end()) {
        if (auto* dblVal = std::get_if<double>(&density_it->second)) {
            density = *dblVal;
        }
    }
    
    char msg[256];
    snprintf(msg, sizeof(msg), "[AgusMapsFlutter] Creating surface: %dx%d, density=%.2f\n", 
             width, height, density);
    OutputDebugStringA(msg);
    
    // Ensure FFI library is loaded
    if (!LoadFfiLibrary()) {
        OutputDebugStringA("[AgusMapsFlutter] ERROR: Failed to load FFI library\n");
        result->Error("FFI_ERROR", "Failed to load native FFI library");
        return;
    }
    
    // Create native surface (this creates Framework, DrapeEngine, OpenGL context)
    if (g_fnCreateSurface) {
        OutputDebugStringA("[AgusMapsFlutter] Calling agus_native_create_surface...\n");
        g_fnCreateSurface(width, height, static_cast<float>(density));
        OutputDebugStringA("[AgusMapsFlutter] agus_native_create_surface returned\n");
    } else {
        OutputDebugStringA("[AgusMapsFlutter] ERROR: agus_native_create_surface not available\n");
        result->Error("FFI_ERROR", "agus_native_create_surface function not found");
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
        
        result->Success(flutter::EncodableValue(texture_id_));
    } else {
        // Fallback: return -1 if texture creation failed
        OutputDebugStringA("[AgusMapsFlutter] WARN: No D3D11 texture available, returning -1\n");
        result->Success(flutter::EncodableValue(static_cast<int64_t>(-1)));
    }
}

void AgusMapsFlutterPlugin::HandleResizeMapSurface(
    const FlutterMethodCall& call,
    std::unique_ptr<FlutterMethodResult> result) {
    
    std::fprintf(stderr, "[AgusMapsFlutter] resizeMapSurface method call received\n");
    std::fflush(stderr);
    
    // Parse arguments
    const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
    if (!arguments) {
        std::fprintf(stderr, "[AgusMapsFlutter] resizeMapSurface: Invalid arguments\n");
        std::fflush(stderr);
        result->Error("INVALID_ARGUMENT", "Expected map arguments");
        return;
    }
    
    int32_t width = surface_width_;
    int32_t height = surface_height_;
    
    auto width_it = arguments->find(flutter::EncodableValue("width"));
    if (width_it != arguments->end()) {
        if (auto* intVal = std::get_if<int32_t>(&width_it->second)) {
            width = *intVal;
        } else if (auto* dblVal = std::get_if<double>(&width_it->second)) {
            width = static_cast<int32_t>(*dblVal);
        }
    }
    
    auto height_it = arguments->find(flutter::EncodableValue("height"));
    if (height_it != arguments->end()) {
        if (auto* intVal = std::get_if<int32_t>(&height_it->second)) {
            height = *intVal;
        } else if (auto* dblVal = std::get_if<double>(&height_it->second)) {
            height = static_cast<int32_t>(*dblVal);
        }
    }
    
    std::fprintf(stderr, "[AgusMapsFlutter] Resizing surface to %dx%d\n", width, height);
    std::fflush(stderr);
    
    // Update stored dimensions
    surface_width_ = width;
    surface_height_ = height;
    
    // Call native resize function
    if (g_fnOnSizeChanged) {
        std::fprintf(stderr, "[AgusMapsFlutter] Calling g_fnOnSizeChanged(%d, %d)\n", width, height);
        std::fflush(stderr);
        g_fnOnSizeChanged(width, height);
    } else {
        std::fprintf(stderr, "[AgusMapsFlutter] WARNING: g_fnOnSizeChanged is null!\n");
        std::fflush(stderr);
    }
    
    result->Success(flutter::EncodableValue(true));
}

void AgusMapsFlutterPlugin::HandleDestroyMapSurface(
    std::unique_ptr<FlutterMethodResult> result) {
    
    OutputDebugStringA("[AgusMapsFlutter] destroyMapSurface called\n");
    
    // Unregister texture
    if (texture_id_ >= 0 && texture_registrar_) {
        texture_registrar_->UnregisterTexture(texture_id_);
        texture_id_ = -1;
    }
    
    texture_.reset();
    
    // Destroy native surface
    if (g_fnOnSurfaceDestroyed) {
        g_fnOnSurfaceDestroyed();
    }
    
    result->Success(flutter::EncodableValue(true));
}

}  // namespace agus_maps_flutter

// C API implementation for plugin registration
void AgusMapsFlutterPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
    agus_maps_flutter::AgusMapsFlutterPlugin::RegisterWithRegistrar(
        flutter::PluginRegistrarManager::GetInstance()
            ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
