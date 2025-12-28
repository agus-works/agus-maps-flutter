// Copyright 2025 The Agus Maps Flutter Authors
// SPDX-License-Identifier: MIT

#include "include/agus_maps_flutter/agus_maps_flutter_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter/encodable_value.h>

#include <windows.h>
#include <shlobj.h>

#include <memory>
#include <string>
#include <filesystem>
#include <fstream>

namespace fs = std::filesystem;

namespace agus_maps_flutter {

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

    flutter::PluginRegistrarWindows* registrar_;
};

// Static registration
void AgusMapsFlutterPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
    
    auto channel = std::make_unique<FlutterMethodChannel>(
        registrar->messenger(), "agus_maps_flutter",
        &flutter::StandardMethodCodec::GetInstance());

    auto plugin = std::make_unique<AgusMapsFlutterPlugin>(registrar);

    channel->SetMethodCallHandler(
        [plugin_pointer = plugin.get()](const auto& call, auto result) {
            plugin_pointer->HandleMethodCall(call, std::move(result));
        });

    registrar->AddPlugin(std::move(plugin));
    
    OutputDebugStringA("[AgusMapsFlutter] Windows plugin registered\n");
}

AgusMapsFlutterPlugin::AgusMapsFlutterPlugin(
    flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar) {}

AgusMapsFlutterPlugin::~AgusMapsFlutterPlugin() {}

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

    if (fs::exists(markerFile)) {
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

    if (fs::exists(sourceDataDir) && fs::is_directory(sourceDataDir)) {
        ExtractDirectory(sourceDataDir, dataDir);
    }

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
            if (!fs::exists(destItem)) {
                fs::copy_file(entry.path(), destItem);
            }
        }
    }
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
    // TODO: Implement texture-based surface creation
    // For now, return a placeholder texture ID
    // The actual rendering will be handled by the native FFI library
    
    OutputDebugStringA("[AgusMapsFlutter] createMapSurface called (not yet implemented)\n");
    
    // Return -1 to indicate texture creation is not yet implemented
    // The Dart side should handle this gracefully
    result->Success(flutter::EncodableValue(-1));
}

void AgusMapsFlutterPlugin::HandleResizeMapSurface(
    const FlutterMethodCall& call,
    std::unique_ptr<FlutterMethodResult> result) {
    // TODO: Implement surface resizing
    OutputDebugStringA("[AgusMapsFlutter] resizeMapSurface called (not yet implemented)\n");
    result->Success(flutter::EncodableValue(true));
}

void AgusMapsFlutterPlugin::HandleDestroyMapSurface(
    std::unique_ptr<FlutterMethodResult> result) {
    // TODO: Implement surface destruction
    OutputDebugStringA("[AgusMapsFlutter] destroyMapSurface called (not yet implemented)\n");
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
