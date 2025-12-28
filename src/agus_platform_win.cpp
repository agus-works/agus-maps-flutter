/// agus_platform_win.cpp
/// 
/// Windows platform abstraction for agus_maps_flutter.
/// Extends CoMaps Platform with custom initialization for Flutter plugin.
/// 
/// NOTE: Some Platform functionality is provided by CoMaps's platform library
/// (platform_win.cpp, localization_dummy.cpp, etc.). This file provides:
/// 1. AgusPlatformWin - derived class with custom path initialization
/// 2. GetPlatform() - returns the singleton instance
/// 3. AgusPlatformWin_InitPaths() - C API for initializing paths from Dart/Flutter
/// 4. Missing Platform methods not provided by CoMaps's platform_win.cpp

#ifdef _WIN32

#include "platform/platform.hpp"
#include "platform/settings.hpp"
#include "platform/measurement_utils.hpp"
#include "platform/constants.hpp"
#include "coding/file_reader.hpp"
#include "base/file_name_utils.hpp"
#include "base/logging.hpp"
#include "base/task_loop.hpp"

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <direct.h>
#include <sys/stat.h>

#include <string>
#include <memory>
#include <filesystem>

#include <boost/regex.hpp>

#pragma region GuiThread

namespace agus {

/// Windows GUI thread implementation
/// Posts tasks to the main thread using Windows message queue
class AgusGuiThreadWin : public base::TaskLoop
{
public:
    AgusGuiThreadWin()
    {
        m_mainThreadId = GetCurrentThreadId();
        LOG(LINFO, ("AgusGuiThreadWin created on thread:", m_mainThreadId));
    }
    
    PushResult Push(Task && task) override
    {
        return PushInternal(std::move(task));
    }
    
    PushResult Push(Task const & task) override
    {
        return PushInternal(task);
    }
    
private:
    PushResult PushInternal(Task task)
    {
        // For now, execute immediately if on main thread, otherwise queue
        if (GetCurrentThreadId() == m_mainThreadId)
        {
            task();
            return {true, kNoId};
        }
        
        // Store task and post message to execute it
        // For simplicity, just execute synchronously for now
        // TODO: Implement proper message queue if needed
        task();
        return {true, kNoId};
    }
    
    DWORD m_mainThreadId = 0;
};

} // namespace agus

#pragma endregion

#pragma region AgusPlatformWin

/// Extended Platform for Flutter plugin
/// Allows custom path initialization from Dart side
class AgusPlatformWin : public Platform
{
public:
    AgusPlatformWin() : Platform() 
    {
        // Set our custom GUI thread
        SetGuiThread(std::make_unique<agus::AgusGuiThreadWin>());
    }
    
    /// Initialize paths from Flutter plugin
    /// Called via AgusPlatformWin_InitPaths() C API
    void InitPaths(std::string const & resourcePath, std::string const & writablePath)
    {
        m_resourcesDir = resourcePath;
        m_writableDir = writablePath;
        m_settingsDir = writablePath;
        m_tmpDir = writablePath + "/tmp/";
        
        // Normalize path separators and ensure trailing slash
        auto normalizePath = [](std::string & path) {
            for (char & c : path)
            {
                if (c == '\\') c = '/';
            }
            if (!path.empty() && path.back() != '/')
                path += '/';
        };
        
        normalizePath(m_resourcesDir);
        normalizePath(m_writableDir);
        normalizePath(m_settingsDir);
        normalizePath(m_tmpDir);
        
        // Create tmp directory if it doesn't exist
        _mkdir(m_tmpDir.c_str());
        
        LOG(LINFO, ("AgusPlatformWin initialized:",
                    "resources =", m_resourcesDir,
                    "writable =", m_writableDir));
    }
};

/// Global platform instance
static AgusPlatformWin g_platform;

/// Override GetPlatform() to return our custom platform
Platform & GetPlatform()
{
    return g_platform;
}

/// C API for initializing paths from Dart/Flutter
extern "C" void AgusPlatformWin_InitPaths(const char* resourcePath, const char* writablePath)
{
    g_platform.InitPaths(resourcePath ? resourcePath : "", writablePath ? writablePath : "");
}

#pragma endregion

#pragma region Platform::SetupMeasurementSystem

/// Required by Framework - not provided by CoMaps platform_win.cpp
void Platform::SetupMeasurementSystem() const
{
    // Use metric by default on Windows
    // This could be enhanced to detect system locale
    settings::Set(settings::kMeasurementUnits, static_cast<uint8_t>(measurement_utils::Units::Metric));
}

#pragma endregion

#pragma region Missing Platform Methods

/// Platform methods not provided by CoMaps's platform_win.cpp

std::unique_ptr<ModelReader> Platform::GetReader(std::string const & file, std::string searchScope) const
{
    return std::make_unique<FileReader>(ReadPathForFile(file, std::move(searchScope)),
                                        READER_CHUNK_LOG_SIZE, READER_CHUNK_LOG_COUNT);
}

bool Platform::GetFileSizeByName(std::string const & fileName, uint64_t & size) const
{
    try
    {
        return GetFileSizeByFullPath(ReadPathForFile(fileName), size);
    }
    catch (RootException const &)
    {
        return false;
    }
}

// static
Platform::EError Platform::MkDir(std::string const & dirName)
{
    if (_mkdir(dirName.c_str()) == 0)
        return Platform::ERR_OK;
    if (errno == EEXIST)
        return Platform::ERR_FILE_ALREADY_EXISTS;
    return Platform::ERR_UNKNOWN;
}

// static
void Platform::GetFilesByRegExp(std::string const & directory, boost::regex const & regexp, FilesList & outFiles)
{
    try
    {
        for (auto const & entry : std::filesystem::directory_iterator(directory))
        {
            if (entry.is_regular_file())
            {
                std::string name = entry.path().filename().string();
                if (boost::regex_search(name, regexp))
                {
                    outFiles.push_back(std::move(name));
                }
            }
        }
    }
    catch (std::exception const & e)
    {
        LOG(LERROR, ("GetFilesByRegExp failed:", e.what()));
    }
}

// static
void Platform::GetAllFiles(std::string const & directory, FilesList & outFiles)
{
    try
    {
        for (auto const & entry : std::filesystem::directory_iterator(directory))
        {
            if (entry.is_regular_file())
            {
                outFiles.push_back(entry.path().filename().string());
            }
        }
    }
    catch (std::exception const & e)
    {
        LOG(LERROR, ("GetAllFiles failed:", e.what()));
    }
}

std::string Platform::Version() const
{
    return "1.0.0";
}

int32_t Platform::IntVersion() const
{
    return 100;
}

std::string Platform::GetMemoryInfo() const
{
    return "";
}

int Platform::PreCachingDepth() const
{
    return 3;
}

int Platform::VideoMemoryLimit() const
{
    return 20 * 1024 * 1024;  // 20 MB
}

#pragma endregion

#pragma region HTTP Stubs

class HttpThread;

namespace downloader {
    class IHttpThreadCallback;
    
    void DeleteNativeHttpThread(::HttpThread*) {}
    
    ::HttpThread * CreateNativeHttpThread(
        std::string const & url, IHttpThreadCallback & callback, int64_t begRange,
        int64_t endRange, int64_t expectedSize, std::string const & postBody)
    {
        // Return nullptr - no HTTP support yet
        return nullptr;
    }
}

#pragma endregion

#pragma region Settings ToString specialization

namespace settings {
    // Required by Platform::SetupMeasurementSystem
    template <>
    std::string ToString<uint8_t>(uint8_t const & v)
    {
        return std::to_string(v);
    }
}

#pragma endregion

#endif // _WIN32
