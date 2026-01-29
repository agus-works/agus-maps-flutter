// Linux-specific implementation for agus_maps_flutter
// Provides full EGL/OpenGL rendering with Flutter texture sharing

#include "agus_maps_flutter.h"
#include "AgusEglContextFactory.hpp"

#include <chrono>
#include <atomic>
#include <thread>
#include <iostream>
#include <cstdio>
#include <unistd.h>
#include <vector>
#include <sys/stat.h>
#include <dirent.h>
#include <cerrno>
#include <cmath>
#include <mutex>
#include <boost/regex.hpp>

#include "base/file_name_utils.hpp"
#include "base/logging.hpp"
#include "base/exception.hpp"
#include "map/framework.hpp"
#include "map/place_page_info.hpp"
#include "platform/local_country_file.hpp"
#include "platform/platform.hpp"
#include "platform/constants.hpp"
#include "coding/file_reader.hpp"
#include "drape/graphics_context_factory.hpp"
#include "drape_frontend/visual_params.hpp"
#include "drape_frontend/user_event_stream.hpp"
#include "drape_frontend/drape_engine.hpp"
#include "drape_frontend/active_frame_callback.hpp"
#include "geometry/mercator.hpp"
#include "indexer/feature_meta.hpp"
#include "geometry/screenbase.hpp"
#include <sstream>
#include <iomanip>
#include <string_view>

// Custom log handler for Linux - outputs to stderr
static void AgusLogMessage(base::LogLevel level, base::SrcPoint const & src, std::string const & msg) {
    const char* levelStr = "UNKNOWN";
    switch (level) {
    case base::LDEBUG: levelStr = "DEBUG"; break;
    case base::LINFO: levelStr = "INFO"; break;
    case base::LWARNING: levelStr = "WARN"; break;
    case base::LERROR: levelStr = "ERROR"; break;
    case base::LCRITICAL: levelStr = "CRITICAL"; break;
    default: break;
    }
    
    std::string out = DebugPrint(src) + msg;
    std::fprintf(stderr, "[CoMaps/%s] %s\n", levelStr, out.c_str());
    
    if (level >= base::LCRITICAL) {
        std::fprintf(stderr, "[CoMaps/FATAL] CRITICAL ERROR - Aborting\n");
        std::abort();
    }
}

// Globals
static std::unique_ptr<Framework> g_framework;
static drape_ptr<dp::ThreadSafeFactory> g_threadSafeFactory;
static agus::AgusEglContextFactory* g_eglFactory = nullptr;  // Raw pointer - owned by g_threadSafeFactory
static std::string g_resourcePath;
static std::string g_writablePath;
static bool g_platformInitialized = false;
static bool g_drapeEngineCreated = false;
static bool g_loggingInitialized = false;
static std::mutex g_mutex;
static std::mutex g_placePageMutex;

static char* CopyString(std::string const & value) {
    size_t const size = value.size();
    auto* out = static_cast<char*>(malloc(size + 1));
    if (!out) {
        return nullptr;
    }
    if (size > 0) {
        memcpy(out, value.data(), size);
    }
    out[size] = '\0';
    return out;
}

static char* CopyOptionalString(std::string const & value) {
    if (value.empty()) {
        return nullptr;
    }
    return CopyString(value);
}

static int GetObjectType(place_page::Info const & info) {
    if (info.IsMyPosition()) return 3; // MY_POSITION
    if (info.IsBookmark()) return 2; // BOOKMARK
    if (info.IsTrack()) return 5; // TRACK
    if (info.HasApiUrl()) return 1; // API_POINT
    return 0; // POI
}

static AgusPlacePageData* BuildPlacePageData(place_page::Info const & info) {
    auto* data = static_cast<AgusPlacePageData*>(calloc(1, sizeof(AgusPlacePageData)));
    if (!data) {
        return nullptr;
    }

    auto const ll = info.GetLatLon();
    data->feature_id.mwm_name = CopyString(info.GetID().GetMwmName());
    data->feature_id.mwm_version = static_cast<int64_t>(info.GetID().GetMwmVersion());
    data->feature_id.index = static_cast<int64_t>(info.GetID().m_index);

    data->object_type = static_cast<int32_t>(GetObjectType(info));
    data->opening_mode = static_cast<int32_t>(info.GetOpeningMode());
    data->title = CopyString(info.GetTitle());
    data->secondary_title = CopyString(info.GetSecondaryTitle());
    data->subtitle = CopyString(info.GetSubtitle());
    data->address = CopyString(info.GetSecondarySubtitle());
    data->lat = ll.m_lat;
    data->lon = ll.m_lon;
    data->wiki_description_html = CopyString(info.GetWikiDescription());
    data->road_type = static_cast<int32_t>(info.GetRoadType());
    data->is_route_point = info.IsRoutePoint() ? 1 : 0;

    data->coordinates.decimal = CopyOptionalString(
        info.GetFormattedCoordinate(place_page::CoordinatesFormat::LatLonDecimal));
    data->coordinates.dms = CopyOptionalString(
        info.GetFormattedCoordinate(place_page::CoordinatesFormat::LatLonDMS));
    data->coordinates.osm = CopyOptionalString(
        info.GetFormattedCoordinate(place_page::CoordinatesFormat::OSMLink));
    data->coordinates.olc = CopyOptionalString(
        info.GetFormattedCoordinate(place_page::CoordinatesFormat::OLCFull));
    data->coordinates.utm = CopyOptionalString(
        info.GetFormattedCoordinate(place_page::CoordinatesFormat::UTM));
    data->coordinates.mgrs = CopyOptionalString(
        info.GetFormattedCoordinate(place_page::CoordinatesFormat::MGRS));

    auto const & rawTypes = info.GetRawTypes();
    data->raw_types_count = static_cast<int32_t>(rawTypes.size());
    if (data->raw_types_count > 0) {
        data->raw_types = static_cast<const char**>(calloc(data->raw_types_count, sizeof(char*)));
        for (int32_t i = 0; i < data->raw_types_count; ++i) {
            data->raw_types[i] = CopyString(rawTypes[i]);
        }
    }

    std::vector<std::pair<int64_t, std::string>> metadata_entries;
    std::vector<std::pair<std::string, std::string>> metadata_tag_entries;

    info.ForEachMetadataReadable([&](osm::MapObject::MetadataID id, std::string const & value) {
        if (value.empty()) {
            return;
        }
        metadata_entries.emplace_back(static_cast<int64_t>(id), value);
        auto const type = static_cast<feature::Metadata::EType>(id);
        if (type == feature::Metadata::FMD_CHARGE_SOCKETS ||
            type == feature::Metadata::FMD_COUNT) {
            return;
        }
        auto const tag = feature::ToString(type);
        if (tag.empty()) {
            return;
        }
        metadata_tag_entries.emplace_back(tag, value);
    });

    data->metadata_count = static_cast<int32_t>(metadata_entries.size());
    if (data->metadata_count > 0) {
        data->metadata = static_cast<AgusPlacePageIntMetadataEntry*>(
            calloc(data->metadata_count, sizeof(AgusPlacePageIntMetadataEntry)));
        for (int32_t i = 0; i < data->metadata_count; ++i) {
            data->metadata[i].key = metadata_entries[i].first;
            data->metadata[i].value = CopyString(metadata_entries[i].second);
        }
    }

    data->metadata_tags_count = static_cast<int32_t>(metadata_tag_entries.size());
    if (data->metadata_tags_count > 0) {
        data->metadata_tags = static_cast<AgusPlacePageStringMetadataEntry*>(
            calloc(data->metadata_tags_count, sizeof(AgusPlacePageStringMetadataEntry)));
        for (int32_t i = 0; i < data->metadata_tags_count; ++i) {
            data->metadata_tags[i].key = CopyString(metadata_tag_entries[i].first);
            data->metadata_tags[i].value = CopyString(metadata_tag_entries[i].second);
        }
    }

    data->has_bookmark_id = info.IsBookmark() ? 1 : 0;
    if (data->has_bookmark_id) {
        data->bookmark_id = static_cast<int64_t>(info.GetBookmarkId());
        data->has_bookmark_category_id = 1;
        data->bookmark_category_id = static_cast<int64_t>(info.GetBookmarkCategoryId());
    }
    data->has_track_id = info.IsTrack() ? 1 : 0;
    if (data->has_track_id) {
        data->track_id = static_cast<int64_t>(info.GetTrackId());
    }

    return data;
}

// Surface state for Linux rendering
static int32_t g_surfaceWidth = 0;
static int32_t g_surfaceHeight = 0;
static float g_density = 1.0f;
static bool g_renderingEnabled = false;

// Frame ready callback for Flutter texture updates (typedef is in agus_maps_flutter.h)
static FrameReadyCallback g_frameReadyCallback = nullptr;

// Keep-alive counter for initial tile loading
static std::atomic<int> g_keepAliveCounter{0};
static constexpr int kInitialKeepAliveFrames = 120;  // ~2 seconds at 60fps

// ============================================================================
// Platform Implementation
// ============================================================================

// Simple TaskLoop implementation for Linux that runs tasks immediately (usually on main thread)
class LinuxGuiThread : public base::TaskLoop
{
public:
  LinuxGuiThread() = default;
  ~LinuxGuiThread() override = default;

  // Push task to be executed
  PushResult Push(Task && task) override
  {
      task(); 
      return {true, 0};
  }

  PushResult Push(Task const & task) override
  {
      task();
      return {true, 0};
  }
};

Platform & GetPlatform()
{
  static Platform platform;
  return platform;
}

Platform::Platform()
{
  m_guiThread = std::make_unique<LinuxGuiThread>();
  m_isTablet = false;
}

void Platform::GetSystemFontNames(FilesList & res) const
{
    // Stub
}

// Missing platform methods that are typically in platform_linux.cpp

int Platform::VideoMemoryLimit() const { return 1024 * 1024 * 1024; } // 1GB
int Platform::PreCachingDepth() const { return 3; } 
std::string Platform::DeviceName() const { return "Linux Desktop"; }
std::string Platform::DeviceModel() const { return "Unknown"; }
std::string Platform::Version() const { return "1.0.0"; }
int32_t Platform::IntVersion() const { return 10000; }

Platform::EConnectionType Platform::ConnectionStatus() { return EConnectionType::CONNECTION_WIFI; }
Platform::ChargingStatus Platform::GetChargingStatus() { return ChargingStatus::Plugged; }
uint8_t Platform::GetBatteryLevel() { return 100; }
std::string Platform::GetMemoryInfo() const { return ""; }
void Platform::SetupMeasurementSystem() const {}

// Static Platform methods required for file operations
// static
time_t Platform::GetFileCreationTime(std::string const & path)
{
  struct stat st;
  if (0 == stat(path.c_str(), &st))
    return st.st_atim.tv_sec;
  std::fprintf(stderr, "[AgusMapsFlutter] GetFileCreationTime stat failed for %s\n", path.c_str());
  return 0;
}

// static
time_t Platform::GetFileModificationTime(std::string const & path)
{
  struct stat st;
  if (0 == stat(path.c_str(), &st))
    return st.st_mtim.tv_sec;
  std::fprintf(stderr, "[AgusMapsFlutter] GetFileModificationTime stat failed for %s\n", path.c_str());
  return 0;
}

// Implement GetReader since platform_linux.cpp is excluded
std::unique_ptr<ModelReader> Platform::GetReader(std::string const & file, std::string searchScope) const
{
  return std::make_unique<FileReader>(ReadPathForFile(file, searchScope));
}

// File operations
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

void Platform::GetFilesByRegExp(std::string const & directory, boost::regex const & regexp, FilesList & outFiles)
{
  DIR * dir = opendir(directory.c_str());
  if (!dir)
    return;
  
  struct dirent * entry;
  while ((entry = readdir(dir)) != nullptr)
  {
    std::string name(entry->d_name);
    if (name != "." && name != ".." && boost::regex_search(name.begin(), name.end(), regexp))
      outFiles.push_back(std::move(name));
  }
  closedir(dir);
}

void Platform::GetAllFiles(std::string const & directory, FilesList & outFiles)
{
  DIR * dir = opendir(directory.c_str());
  if (!dir)
    return;
  
  struct dirent * entry;
  while ((entry = readdir(dir)) != nullptr)
  {
    std::string name(entry->d_name);
    if (name != "." && name != "..")
      outFiles.push_back(std::move(name));
  }
  closedir(dir);
}

// static
Platform::EError Platform::MkDir(std::string const & dirName)
{
  if (mkdir(dirName.c_str(), 0755) == 0)
    return Platform::ERR_OK;
  if (errno == EEXIST)
    return Platform::ERR_FILE_ALREADY_EXISTS;
  return Platform::ERR_UNKNOWN;
}

// ============================================================================
// Logging
// ============================================================================

static void ensureLoggingConfigured() {
    if (!g_loggingInitialized) {
        base::SetLogMessageFn(&AgusLogMessage);
        base::g_LogAbortLevel = base::LCRITICAL;
        g_loggingInitialized = true;
        std::fprintf(stderr, "[AgusMapsFlutter] Logging initialized for Linux\n");
    }
}

// ============================================================================
// Frame Notification (for Flutter texture updates)
// ============================================================================

static void notifyFlutterFrameReady() {
    // Keep render loop alive during initial tile loading
    if (g_keepAliveCounter.load() > 0) {
        g_keepAliveCounter.fetch_sub(1);
        if (g_framework) {
            g_framework->MakeFrameActive();
        }
    }
    
    // Notify Flutter that a new frame is ready
    if (g_frameReadyCallback) {
        g_frameReadyCallback();
    }
}

// ============================================================================
// DrapeEngine Creation
// ============================================================================

static void createDrapeEngineIfNeeded(int width, int height, float density) {
    if (g_drapeEngineCreated || !g_framework || !g_threadSafeFactory) {
        return;
    }
    
    if (width <= 0 || height <= 0) {
        std::fprintf(stderr, "[AgusMapsFlutter] createDrapeEngine: Invalid dimensions %dx%d\n", width, height);
        return;
    }
    
    // Register active frame callback BEFORE creating DrapeEngine
    df::SetActiveFrameCallback([]() {
        notifyFlutterFrameReady();
    });
    std::fprintf(stderr, "[AgusMapsFlutter] Active frame callback registered\n");
    
    Framework::DrapeCreationParams p;
    p.m_apiVersion = dp::ApiVersion::OpenGLES3;
    p.m_surfaceWidth = width;
    p.m_surfaceHeight = height;
    p.m_visualScale = density;
    
    std::fprintf(stderr, "[AgusMapsFlutter] Creating DrapeEngine: %dx%d, scale=%.2f, API=OpenGLES3\n",
                 width, height, density);
    
    g_framework->CreateDrapeEngine(make_ref(g_threadSafeFactory), std::move(p));
    g_drapeEngineCreated = true;
    
    // Start keep-alive counter for initial tile loading
    g_keepAliveCounter.store(kInitialKeepAliveFrames);
    
    std::fprintf(stderr, "[AgusMapsFlutter] DrapeEngine created successfully\n");
}

// ============================================================================
// FFI Implementations
// ============================================================================

FFI_PLUGIN_EXPORT int sum(int a, int b) { return a + b; }

FFI_PLUGIN_EXPORT int sum_long_running(int a, int b) {
    usleep(5000 * 1000);
    return a + b;
}

FFI_PLUGIN_EXPORT void comaps_init(const char* apkPath, const char* storagePath) {
    std::fprintf(stderr, "[AgusMapsFlutter] comaps_init: apk=%s, storage=%s\n", apkPath, storagePath);
    comaps_init_paths(apkPath, storagePath);
}

FFI_PLUGIN_EXPORT void comaps_init_paths(const char* resourcePath, const char* writablePath) {
    ensureLoggingConfigured();
    
    std::fprintf(stderr, "[AgusMapsFlutter] comaps_init_paths: resource=%s, writable=%s\n", resourcePath, writablePath);
    
    // Store paths
    g_resourcePath = resourcePath ? resourcePath : "";
    g_writablePath = writablePath ? writablePath : "";
    
    // Initialize platform paths
    Platform & pl = GetPlatform();
    pl.SetWritableDirForTests(writablePath);
    pl.SetResourceDir(resourcePath);
    
    g_platformInitialized = true;
    
    // On Linux, create Framework immediately but defer DrapeEngine until surface is ready
    if (!g_framework) {
        std::fprintf(stderr, "[AgusMapsFlutter] Creating Framework during initialization...\n");
        
        FrameworkParams params;
        params.m_enableDiffs = false;
        params.m_numSearchAPIThreads = 1;
        
        g_framework = std::make_unique<Framework>(params, false /* loadMaps */);
        g_framework->RegisterAllMaps();
        
        std::fprintf(stderr, "[AgusMapsFlutter] Framework created and maps registered\n");
    }
    
    std::fprintf(stderr, "[AgusMapsFlutter] Platform and Framework initialized\n");
}

FFI_PLUGIN_EXPORT void comaps_load_map_path(const char* path) {
    std::fprintf(stderr, "[AgusMapsFlutter] comaps_load_map_path: %s\n", path);
    
    if (g_framework) {
        g_framework->RegisterAllMaps();
    }
}

FFI_PLUGIN_EXPORT void comaps_set_view(double lat, double lon, int zoom) {
    std::fprintf(stderr, "[AgusMapsFlutter] comaps_set_view: lat=%f, lon=%f, zoom=%d\n", lat, lon, zoom);
    if (g_framework) {
        // Use isAnim=false for immediate update
        g_framework->SetViewportCenter(m2::PointD(mercator::FromLatLon(lat, lon)), zoom, false /* isAnim */);
        g_framework->InvalidateRendering();
    }
}

FFI_PLUGIN_EXPORT void comaps_invalidate(void) {
    if (g_framework) {
        g_framework->InvalidateRect(g_framework->GetCurrentViewport());
    }
}

FFI_PLUGIN_EXPORT void comaps_force_redraw(void) {
    if (g_framework) {
        // Force complete tile reload
        g_framework->SetMapStyle(g_framework->GetMapStyle());
        g_framework->MakeFrameActive();
        g_framework->InvalidateRendering();
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
    
    df::Touch t1;
    t1.m_id = id1;
    t1.m_location = m2::PointF(x1, y1);
    event.SetFirstTouch(t1);
    event.SetFirstMaskedPointer(0);
    
    if (id2 >= 0) {
        df::Touch t2;
        t2.m_id = id2;
        t2.m_location = m2::PointF(x2, y2);
        event.SetSecondTouch(t2);
        event.SetSecondMaskedPointer(1);
    }
    
    g_framework->TouchEvent(event);
}

FFI_PLUGIN_EXPORT void comaps_scale(double factor, double pixelX, double pixelY, int animated) {
    if (g_framework && g_drapeEngineCreated) {
        g_framework->Scale(factor, m2::PointD(pixelX, pixelY), animated != 0);
    }
}

FFI_PLUGIN_EXPORT void comaps_scroll(double distanceX, double distanceY) {
    if (g_framework && g_drapeEngineCreated) {
        g_framework->Scroll(distanceX, distanceY);
    }
}

FFI_PLUGIN_EXPORT int comaps_place_page_has_data(void) {
    if (!g_framework) {
        return 0;
    }
    return g_framework->HasPlacePageInfo() ? 1 : 0;
}

FFI_PLUGIN_EXPORT AgusPlacePageData* comaps_place_page_copy(void) {
    std::lock_guard<std::mutex> lock(g_placePageMutex);
    if (!g_framework || !g_framework->HasPlacePageInfo()) {
        return nullptr;
    }
    return BuildPlacePageData(g_framework->GetCurrentPlacePageInfo());
}

FFI_PLUGIN_EXPORT void comaps_place_page_free(AgusPlacePageData* data) {
    if (!data) {
        return;
    }
    free(const_cast<char*>(data->feature_id.mwm_name));
    free(const_cast<char*>(data->title));
    free(const_cast<char*>(data->secondary_title));
    free(const_cast<char*>(data->subtitle));
    free(const_cast<char*>(data->address));
    free(const_cast<char*>(data->wiki_description_html));

    free(const_cast<char*>(data->coordinates.decimal));
    free(const_cast<char*>(data->coordinates.dms));
    free(const_cast<char*>(data->coordinates.osm));
    free(const_cast<char*>(data->coordinates.olc));
    free(const_cast<char*>(data->coordinates.utm));
    free(const_cast<char*>(data->coordinates.mgrs));

    if (data->raw_types) {
        for (int32_t i = 0; i < data->raw_types_count; ++i) {
            free(const_cast<char*>(data->raw_types[i]));
        }
        free(data->raw_types);
    }

    if (data->metadata) {
        for (int32_t i = 0; i < data->metadata_count; ++i) {
            free(const_cast<char*>(data->metadata[i].value));
        }
        free(data->metadata);
    }

    if (data->metadata_tags) {
        for (int32_t i = 0; i < data->metadata_tags_count; ++i) {
            free(const_cast<char*>(data->metadata_tags[i].key));
            free(const_cast<char*>(data->metadata_tags[i].value));
        }
        free(data->metadata_tags);
    }

    free(data);
}

FFI_PLUGIN_EXPORT void comaps_place_page_clear_selection(void) {
    if (!g_framework) {
        return;
    }
    g_framework->DeactivateMapSelection();
}

FFI_PLUGIN_EXPORT int comaps_register_single_map(const char* fullPath) {
    return comaps_register_single_map_with_version(fullPath, 0);
}

FFI_PLUGIN_EXPORT int comaps_register_single_map_with_version(const char* fullPath, int64_t version) {
    std::fprintf(stderr, "[AgusMapsFlutter] comaps_register_single_map_with_version: %s (version=%lld)\n",
        fullPath, static_cast<long long>(version));

    if (!g_framework) {
        return -1;
    }

    try {
        std::string path(fullPath ? fullPath : "");
        if (path.empty()) {
            return -2;
        }

        auto name = path;
        base::GetNameFromFullPath(name);
        base::GetNameWithoutExt(name);

        platform::LocalCountryFile file(base::GetDirectory(path), platform::CountryFile(std::move(name)), version);
        file.SyncWithDisk();

        auto result = g_framework->RegisterMap(file);
        if (result.second == MwmSet::RegResult::Success) {
            return 0;
        } else {
            return static_cast<int>(result.second);
        }
    } catch (std::exception const & e) {
        std::fprintf(stderr, "[AgusMapsFlutter] Exception: %s\n", e.what());
        return -2;
    }
}

FFI_PLUGIN_EXPORT void comaps_debug_list_mwms() {
    std::fprintf(stderr, "=== DEBUG: Listing all registered MWMs ===\n");
    
    if (!g_framework) {
        std::fprintf(stderr, "Framework not initialized\n");
        return;
    }
    
    auto const & dataSource = g_framework->GetDataSource();
    std::vector<std::shared_ptr<MwmInfo>> mwms;
    dataSource.GetMwmsInfo(mwms);
    
    std::fprintf(stderr, "Total registered MWMs: %zu\n", mwms.size());
    
    for (auto const & info : mwms) {
        auto const & bounds = info->m_bordersRect;
        const char* typeStr = "UNKNOWN";
        switch (info->GetType()) {
            case MwmInfo::COUNTRY: typeStr = "COUNTRY"; break;
            case MwmInfo::COASTS: typeStr = "COASTS"; break;
            case MwmInfo::WORLD: typeStr = "WORLD"; break;
        }
        
        std::fprintf(stderr, "  MWM: %s [%s] version=%lld scales=[%d-%d] bounds=[%.4f,%.4f - %.4f,%.4f]\n",
            info->GetCountryName().c_str(),
            typeStr,
            static_cast<long long>(info->GetVersion()),
            info->m_minScale,
            info->m_maxScale,
            bounds.minX(), bounds.minY(),
            bounds.maxX(), bounds.maxY());
    }
}

FFI_PLUGIN_EXPORT void comaps_debug_check_point(double lat, double lon) {
    std::fprintf(stderr, "=== DEBUG: Checking point coverage lat=%.6f, lon=%.6f ===\n", lat, lon);
    
    if (!g_framework) {
        std::fprintf(stderr, "Framework not initialized\n");
        return;
    }
    
    m2::PointD const pt = mercator::FromLatLon(lat, lon);
    std::fprintf(stderr, "Mercator coords: x=%.6f, y=%.6f\n", pt.x, pt.y);
    
    auto const & dataSource = g_framework->GetDataSource();
    std::vector<std::shared_ptr<MwmInfo>> mwms;
    dataSource.GetMwmsInfo(mwms);
    
    int coveringCount = 0;
    for (auto const & info : mwms) {
        if (info->m_bordersRect.IsPointInside(pt)) {
            coveringCount++;
            std::fprintf(stderr, "  COVERS: %s [scales %d-%d]\n",
                info->GetCountryName().c_str(),
                info->m_minScale, info->m_maxScale);
        }
    }
    
    if (coveringCount == 0) {
        std::fprintf(stderr, "  NO MWM covers this point!\n");
    } else {
        std::fprintf(stderr, "Point covered by %d MWMs\n", coveringCount);
    }
}

FFI_PLUGIN_EXPORT int comaps_deregister_map(const char* fullPath) {
    std::fprintf(stderr, "[AgusMapsFlutter] comaps_deregister_map: %s (not implemented)\n", fullPath);
    return -1;
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

// ============================================================================
// Linux Surface Management (for Flutter texture sharing)
// These functions need C linkage for the plugin to access them
// ============================================================================

extern "C" {

/// Set the frame ready callback - called by Flutter plugin
FFI_PLUGIN_EXPORT void agus_set_frame_ready_callback(FrameReadyCallback callback) {
    g_frameReadyCallback = callback;
    std::fprintf(stderr, "[AgusMapsFlutter] Frame ready callback set\n");
}

/// Create map surface - called when Flutter widget requests texture
FFI_PLUGIN_EXPORT int64_t agus_native_create_surface(int32_t width, int32_t height, float density) {
    ensureLoggingConfigured();
    
    std::fprintf(stderr, "[AgusMapsFlutter] agus_native_create_surface: %dx%d, density=%.2f\n",
                 width, height, density);
    
    if (!g_platformInitialized) {
        std::fprintf(stderr, "[AgusMapsFlutter] ERROR: Platform not initialized! Call comaps_init_paths first.\n");
        return -1;
    }
    
    std::lock_guard<std::mutex> lock(g_mutex);
    
    g_surfaceWidth = width;
    g_surfaceHeight = height;
    g_density = density;
    
    // Create Framework if not already created
    if (!g_framework) {
        std::fprintf(stderr, "[AgusMapsFlutter] Creating Framework...\n");
        
        FrameworkParams params;
        params.m_enableDiffs = false;
        params.m_numSearchAPIThreads = 1;
        
        g_framework = std::make_unique<Framework>(params, false /* loadMaps */);
        g_framework->RegisterAllMaps();
        std::fprintf(stderr, "[AgusMapsFlutter] Framework created\n");
    }
    
    // Create EGL context factory for offscreen rendering
    g_eglFactory = new agus::AgusEglContextFactory(width, height, density);
    
    if (!g_eglFactory->IsValid()) {
        std::fprintf(stderr, "[AgusMapsFlutter] ERROR: Failed to create EGL context factory\n");
        delete g_eglFactory;
        g_eglFactory = nullptr;
        return -1;
    }
    
    // Set frame callback so factory notifies Flutter after Present()
    g_eglFactory->SetFrameCallback([]() {
        notifyFlutterFrameReady();
    });
    std::fprintf(stderr, "[AgusMapsFlutter] EGL factory frame callback set\n");
    
    // Set keep-alive callback to prevent render loop from suspending during tile loading
    g_eglFactory->SetKeepAliveCallback([]() {
        if (g_framework) {
            g_framework->MakeFrameActive();
        }
    });
    std::fprintf(stderr, "[AgusMapsFlutter] EGL factory keep-alive callback set\n");
    
    // Wrap in ThreadSafeFactory for thread-safe context access
    g_threadSafeFactory = make_unique_dp<dp::ThreadSafeFactory>(g_eglFactory);
    
    // Create DrapeEngine
    createDrapeEngineIfNeeded(width, height, density);
    
    // Enable rendering
    if (g_framework && g_drapeEngineCreated) {
        g_framework->SetRenderingEnabled(make_ref(g_threadSafeFactory));
        g_renderingEnabled = true;
        std::fprintf(stderr, "[AgusMapsFlutter] Rendering enabled\n");
    }
    
    // Return the GL texture ID that Flutter will sample from
    int64_t textureId = static_cast<int64_t>(g_eglFactory->GetTextureId());
    std::fprintf(stderr, "[AgusMapsFlutter] Surface created, texture ID: %lld\n", 
                 static_cast<long long>(textureId));
    return textureId;
}

/// Resize map surface - called when Flutter widget is resized
FFI_PLUGIN_EXPORT void agus_native_on_size_changed(int32_t width, int32_t height) {
    std::fprintf(stderr, "[AgusMapsFlutter] agus_native_on_size_changed: %dx%d\n", width, height);
    
    g_surfaceWidth = width;
    g_surfaceHeight = height;
    
    // Update EGL context factory with new dimensions
    if (g_eglFactory) {
        g_eglFactory->SetSurfaceSize(width, height);
        std::fprintf(stderr, "[AgusMapsFlutter] EGL surface updated to %dx%d\n", width, height);
    }
    
    // Notify DrapeEngine of the new viewport size
    if (g_framework && g_drapeEngineCreated) {
        g_framework->OnSize(width, height);
        g_framework->InvalidateRendering();
        std::fprintf(stderr, "[AgusMapsFlutter] Framework::OnSize called for %dx%d\n", width, height);
    }
}

/// Update visual scale without resizing surface
FFI_PLUGIN_EXPORT void agus_native_set_visual_scale(float density) {
    if (density <= 0) {
        std::fprintf(stderr, "[AgusMapsFlutter] agus_native_set_visual_scale: invalid density %.2f\n", density);
        return;
    }

    if (std::fabs(g_density - density) < 0.0001f) {
        return;
    }

    g_density = density;

    if (g_framework && g_drapeEngineCreated) {
        df::VisualParams::Instance().SetVisualScale(static_cast<double>(density));
        g_framework->InvalidateRendering();
        std::fprintf(stderr, "[AgusMapsFlutter] agus_native_set_visual_scale: Updated visual scale to %.2f\n", density);
    } else {
        std::fprintf(stderr, "[AgusMapsFlutter] agus_native_set_visual_scale: Framework not ready, stored density %.2f\n", density);
    }
}

/// Destroy map surface - called when Flutter widget is disposed
FFI_PLUGIN_EXPORT void agus_native_on_surface_destroyed(void) {
    std::fprintf(stderr, "[AgusMapsFlutter] agus_native_on_surface_destroyed\n");
    
    // Clear active frame callback
    df::SetActiveFrameCallback(nullptr);
    
    if (g_framework) {
        g_framework->SetRenderingDisabled(true /* destroySurface */);
    }
    
    g_threadSafeFactory.reset();
    g_eglFactory = nullptr;  // Deleted by ThreadSafeFactory
    g_drapeEngineCreated = false;
    g_renderingEnabled = false;
}

/// Get the OpenGL texture ID for Flutter texture sharing
FFI_PLUGIN_EXPORT uint32_t agus_get_texture_id(void) {
    if (g_eglFactory) {
        return g_eglFactory->GetTextureId();
    }
    return 0;
}

/// Get the current rendered width
FFI_PLUGIN_EXPORT int32_t agus_get_rendered_width(void) {
    if (g_eglFactory) {
        return g_eglFactory->GetRenderedWidth();
    }
    return g_surfaceWidth;
}

/// Get the current rendered height
FFI_PLUGIN_EXPORT int32_t agus_get_rendered_height(void) {
    if (g_eglFactory) {
        return g_eglFactory->GetRenderedHeight();
    }
    return g_surfaceHeight;
}

/// Copy rendered pixels to a buffer (fallback for non-shared context path)
FFI_PLUGIN_EXPORT int agus_copy_pixels(uint8_t* buffer, int32_t bufferSize) {
    if (g_eglFactory && buffer && bufferSize > 0) {
        return g_eglFactory->CopyToPixelBuffer(buffer, bufferSize) ? 1 : 0;
    }
    return 0;
}

} // extern "C" - end Linux Surface Management functions

/// Shutdown and cleanup all resources
FFI_PLUGIN_EXPORT void comaps_shutdown(void) {
    std::fprintf(stderr, "[AgusMapsFlutter] comaps_shutdown called\n");
    
    std::lock_guard<std::mutex> lock(g_mutex);
    
    // Clear active frame callback first
    df::SetActiveFrameCallback(nullptr);
    
    if (g_framework) {
        g_framework->SetRenderingDisabled(true);
    }
    
    g_threadSafeFactory.reset();
    g_eglFactory = nullptr;
    g_framework.reset();
    
    g_drapeEngineCreated = false;
    g_platformInitialized = false;
    g_renderingEnabled = false;
    
    std::fprintf(stderr, "[AgusMapsFlutter] Shutdown complete\n");
}

// Legacy surface management functions (for compatibility)
extern "C" void linux_native_create_map_surface(int width, int height, double density) {
    agus_native_create_surface(width, height, static_cast<float>(density));
}

extern "C" void linux_native_resize_map_surface(int width, int height) {
    agus_native_on_size_changed(width, height);
}

extern "C" void linux_native_destroy_map_surface(void) {
    agus_native_on_surface_destroyed();
}
