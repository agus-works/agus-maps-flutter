/// agus_maps_flutter_win.cpp
/// 
/// Windows FFI implementation for agus_maps_flutter.
/// This provides the C FFI functions that Dart FFI calls on Windows.
/// 
/// This file implements the full CoMaps Framework integration for Windows,
/// using OpenGL (via WGL) for rendering with D3D11 texture sharing for Flutter integration.

#ifdef _WIN32

#include "agus_maps_flutter.h"
#include "AgusWglContextFactory.hpp"

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <shlobj.h>   // For SHGetFolderPathW
#include <dbghelp.h>  // For MiniDumpWriteDump

#pragma comment(lib, "dbghelp.lib")

#include <string>
#include <memory>
#include <atomic>
#include <algorithm>
#include <chrono>
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <mutex>
#include <set>
#include <vector>
#include <utility>
#include <sstream>
#include <iomanip>
#include <cmath>
#include <string_view>
#include <thread>

// CoMaps Framework includes
#include "base/file_name_utils.hpp"
#include "base/logging.hpp"
#include "base/localisation.hpp"
#include "map/framework.hpp"
#include "map/place_page_info.hpp"
#include "indexer/map_style.hpp"
#include "indexer/map_style_reader.hpp"
#include "platform/local_country_file.hpp"
#include "drape/color.hpp"
#include "drape/graphics_context_factory.hpp"
#include "drape_frontend/visual_params.hpp"
#include "drape_frontend/user_event_stream.hpp"
#include "drape_frontend/active_frame_callback.hpp"
#include "drape_frontend/drape_api.hpp"
#include "geometry/mercator.hpp"
#include "geometry/screenbase.hpp"
#include "indexer/feature_meta.hpp"
#include "agus_navigation_bridge.hpp"
#include "agus_search_bridge.hpp"

// Forward declarations for Windows platform (defined in agus_platform_win.cpp)
extern "C" void AgusPlatformWin_InitPaths(const char* resourcePath, const char* writablePath);

#if defined(NDEBUG) || defined(RELEASE)
#define AGUS_RELEASE_BUILD 1
#else
#define AGUS_RELEASE_BUILD 0
#endif

static void AgusWriteLog(char const * message) {
    OutputDebugStringA(message);
    std::fprintf(stderr, "%s", message);
    std::fflush(stderr);
}

static void AgusLogPrintf(char const * format, ...) {
    char buffer[1024];
    va_list args;
    va_start(args, format);
    std::vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);
    AgusWriteLog(buffer);
}

#if AGUS_RELEASE_BUILD
#define AGUS_DEBUG_LOG(...) do {} while (0)
#else
#define AGUS_DEBUG_LOG(...) AgusLogPrintf(__VA_ARGS__)
#endif

#pragma region Crash Dump Handler

/// Crash dump handler for Windows.
/// When enabled, this captures minidumps on unhandled exceptions for debugging.
static bool g_crashHandlerInstalled = false;
static wchar_t g_dumpPath[MAX_PATH] = {0};

/// Generate minidump file on crash
static LONG WINAPI AgusCrashHandler(EXCEPTION_POINTERS* pExceptionInfo)
{
    // Build dump filename with timestamp
    SYSTEMTIME st;
    GetLocalTime(&st);
    
    wchar_t dumpFile[MAX_PATH];
    swprintf_s(dumpFile, MAX_PATH, 
               L"%s\\agus_maps_crash_%04d%02d%02d_%02d%02d%02d.dmp",
               g_dumpPath, st.wYear, st.wMonth, st.wDay, 
               st.wHour, st.wMinute, st.wSecond);
    
    OutputDebugStringW(L"[AgusMapsFlutter] CRASH DETECTED - Writing minidump to: ");
    OutputDebugStringW(dumpFile);
    OutputDebugStringW(L"\n");
    
    HANDLE hFile = CreateFileW(dumpFile, GENERIC_WRITE, 0, NULL, 
                               CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    
    if (hFile != INVALID_HANDLE_VALUE)
    {
        MINIDUMP_EXCEPTION_INFORMATION mdei;
        mdei.ThreadId = GetCurrentThreadId();
        mdei.ExceptionPointers = pExceptionInfo;
        mdei.ClientPointers = FALSE;
        
        // Write minidump with full memory info for debugging
        MINIDUMP_TYPE dumpType = static_cast<MINIDUMP_TYPE>(
            MiniDumpWithDataSegs | 
            MiniDumpWithHandleData |
            MiniDumpWithThreadInfo |
            MiniDumpWithUnloadedModules);
        
        if (MiniDumpWriteDump(GetCurrentProcess(), GetCurrentProcessId(),
                              hFile, dumpType, &mdei, NULL, NULL))
        {
            OutputDebugStringW(L"[AgusMapsFlutter] Minidump written successfully\n");
        }
        else
        {
            OutputDebugStringW(L"[AgusMapsFlutter] Failed to write minidump\n");
        }
        
        CloseHandle(hFile);
    }
    else
    {
        OutputDebugStringW(L"[AgusMapsFlutter] Failed to create dump file\n");
    }
    
    // Log exception details
    char msg[512];
    snprintf(msg, sizeof(msg), 
             "[AgusMapsFlutter] Exception code: 0x%08lX at address: %p\n",
             pExceptionInfo->ExceptionRecord->ExceptionCode,
             pExceptionInfo->ExceptionRecord->ExceptionAddress);
    OutputDebugStringA(msg);
    fprintf(stderr, "%s", msg);
    
    // Let Windows handle the exception (will show crash dialog or terminate)
    return EXCEPTION_CONTINUE_SEARCH;
}

/// Install crash handler. Call early in initialization.
static void installCrashHandler()
{
    if (g_crashHandlerInstalled)
        return;
    
    // Get Documents folder for crash dumps
    wchar_t documentsPath[MAX_PATH];
    if (SUCCEEDED(SHGetFolderPathW(NULL, CSIDL_PERSONAL, NULL, 0, documentsPath)))
    {
        swprintf_s(g_dumpPath, MAX_PATH, L"%s\\agus_maps_flutter", documentsPath);
        CreateDirectoryW(g_dumpPath, NULL);  // Ensure directory exists
    }
    else
    {
        wcscpy_s(g_dumpPath, MAX_PATH, L".");
    }
    
    SetUnhandledExceptionFilter(AgusCrashHandler);
    g_crashHandlerInstalled = true;
    
    OutputDebugStringW(L"[AgusMapsFlutter] Crash handler installed. Dumps will be saved to: ");
    OutputDebugStringW(g_dumpPath);
    OutputDebugStringW(L"\n");
}

#pragma endregion

#pragma region Global State

static std::unique_ptr<Framework> g_framework;
static drape_ptr<dp::ThreadSafeFactory> g_threadSafeFactory;
static agus::AgusWglContextFactory* g_wglFactory = nullptr;  // Raw pointer - owned by g_threadSafeFactory
static std::string g_resourcePath;
static std::string g_writablePath;
static bool g_platformInitialized = false;
static bool g_drapeEngineCreated = false;
static bool g_loggingInitialized = false;

// Surface state
static int32_t g_surfaceWidth = 0;
static int32_t g_surfaceHeight = 0;
static float g_density = 1.0f;
static int64_t g_textureId = -1;

// Frame ready callback
typedef void (*FrameReadyCallback)(void);
static FrameReadyCallback g_frameReadyCallback = nullptr;

// Frame notification timing for 60fps rate limiting
static std::chrono::steady_clock::time_point g_lastFrameNotification;
static constexpr auto kMinFrameInterval = std::chrono::milliseconds(16); // ~60fps
static std::atomic<bool> g_frameNotificationPending{false};

// Mutex for thread safety
static std::mutex g_mutex;

static std::mutex g_placePageMutex;
static std::mutex g_mapPointerMutex;
static std::mutex g_viewportMutex;
static double g_currentBearingDegrees = 0.0;
static std::unique_ptr<ScreenBase> g_currentScreen;
static bool g_3dBuildingsEnabled = false;
static bool g_outdoorsEnabled = false;
static bool g_isolinesEnabled = false;
static bool g_subwayEnabled = false;

struct AgusMapPointerState {
    double physicalX = 0.0;
    double physicalY = 0.0;
    double lat = 0.0;
    double lon = 0.0;
    bool insideMap = false;
    bool hasCoordinate = false;
};

static AgusMapPointerState g_lastMapPointer;

namespace
{
double constexpr kDegreesPerRadian = 180.0 / 3.14159265358979323846;
double constexpr kRadiansPerDegree = 3.14159265358979323846 / 180.0;
std::set<std::string> g_duckDBInteractionDrapeLineIds;
std::set<std::string> g_duckDBInteractionPointIds;
std::set<std::string> g_duckDBCommittedDrapeLineIds;
std::set<std::string> g_duckDBCommittedPointIds;
std::mutex g_duckDBRenderMutex;
bool g_duckDBRenderingEnabled = false;
bool g_duckDBRenderPublished = false;
std::vector<std::string> g_lastDuckDBRenderableFeatureKeys;
std::chrono::steady_clock::time_point g_lastDuckDBRenderRefresh;
std::atomic<uint64_t> g_duckDBViewportGeneration{0};
std::atomic<bool> g_duckDBViewportRefreshScheduled{false};
int32_t constexpr kDuckDBRenderFetchBatchSize = 1000;
int32_t constexpr kDuckDBRenderFetchMaxFeatures = 10000;
auto constexpr kDuckDBViewportRefreshInterval = std::chrono::milliseconds(250);
auto constexpr kDuckDBViewportIdleRefreshDelay = std::chrono::milliseconds(450);

struct DuckDBRenderViewport {
    double minLon = 0.0;
    double minLat = 0.0;
    double maxLon = 0.0;
    double maxLat = 0.0;
};

int32_t RefreshDuckDBRenderLayersInternal();
void ScheduleDuckDBRenderRefreshAfterViewportIdle();

struct DuckDBInteractionLineStyle {
    dp::Color color = dp::Color(37, 99, 235, 235);
    float width = 3.0f;
    bool dashed = false;
    double dashLength = 12.0;
    double gapLength = 7.0;
};

double NormalizeBearingDegrees(double degrees) {
    double normalized = std::fmod(degrees, 360.0);
    if (normalized < 0.0) {
        normalized += 360.0;
    }
    return normalized >= 359.999 ? 0.0 : normalized;
}

bool IsOutdoorsStyle(MapStyle style) {
    return style == MapStyleOutdoorsLight || style == MapStyleOutdoorsDark;
}

void ApplyRuntimeMapStyle(MapStyle mapStyle) {
    if (!g_framework || mapStyle == MapStyleMerged) {
        return;
    }
    GetStyleReader().SetCurrentStyle(mapStyle);
    if (auto engine = g_framework->GetDrapeEngine()) {
        engine->UpdateMapStyle();
    }
}

void WakeRenderer() {
    if (!g_framework) {
        return;
    }
    g_framework->InvalidateRendering();
    g_framework->InvalidateRect(g_framework->GetCurrentViewport());
    if (g_drapeEngineCreated) {
        g_framework->MakeFrameActive();
    }
}

void RequestActiveRenderFrame() {
    if (g_framework && g_drapeEngineCreated) {
        g_framework->MakeFrameActive();
    }
}

void SetViewportTracking() {
    if (!g_framework) {
        return;
    }
    g_framework->SetViewportListener([](ScreenBase const & screen) {
        g_currentBearingDegrees = NormalizeBearingDegrees(
            screen.GetAngle() * kDegreesPerRadian);
        {
            std::lock_guard<std::mutex> lock(g_viewportMutex);
            g_currentScreen = std::make_unique<ScreenBase>(screen);
        }
        ScheduleDuckDBRenderRefreshAfterViewportIdle();
    });
}

std::vector<m2::PointD> ParseWktMercatorPoints(char const * wkt) {
    std::vector<m2::PointD> points;
    if (wkt == nullptr) {
        return points;
    }

    char const * cursor = wkt;
    while (*cursor != '\0') {
        char * numberEnd = nullptr;
        double const lon = std::strtod(cursor, &numberEnd);
        if (numberEnd == cursor) {
            ++cursor;
            continue;
        }
        cursor = numberEnd;

        double const lat = std::strtod(cursor, &numberEnd);
        if (numberEnd == cursor) {
            break;
        }
        cursor = numberEnd;
        points.push_back(mercator::FromLatLon(lat, lon));
    }
    return points;
}

std::vector<std::vector<m2::PointD>> ParseWktMercatorGeometries(char const * wkt) {
    std::vector<std::vector<m2::PointD>> geometries;
    if (wkt == nullptr) {
        return geometries;
    }

    std::string_view const text(wkt);
    size_t start = 0;
    while (start < text.size()) {
        size_t end = text.find('\n', start);
        if (end == std::string_view::npos) {
            end = text.size();
        }
        auto const chunk = text.substr(start, end - start);
        if (!chunk.empty()) {
            std::string geometry(chunk);
            auto points = ParseWktMercatorPoints(geometry.c_str());
            if (!points.empty()) {
                geometries.push_back(std::move(points));
            }
        }
        start = end + 1;
    }
    return geometries;
}

std::vector<m2::PointD> FlattenGeometryPoints(
    std::vector<std::vector<m2::PointD>> const & geometries) {
    std::vector<m2::PointD> points;
    for (auto const & geometry : geometries) {
        points.insert(points.end(), geometry.begin(), geometry.end());
    }
    return points;
}

std::vector<std::vector<m2::PointD>> BuildInteractionLineGeometries(
    std::vector<m2::PointD> const & points,
    DuckDBInteractionLineStyle const & style) {
    if (points.size() < 2) {
        return {};
    }
    if (!style.dashed) {
        return {points};
    }

    ScreenBase screen;
    {
        std::lock_guard<std::mutex> lock(g_viewportMutex);
        if (!g_currentScreen) {
            return {points};
        }
        screen = *g_currentScreen;
    }

    double const dashLength = std::max(1.0, style.dashLength);
    double const gapLength = std::max(1.0, style.gapLength);
    double const cycleLength = dashLength + gapLength;
    std::vector<std::vector<m2::PointD>> dashes;
    for (size_t segmentIndex = 1; segmentIndex < points.size(); ++segmentIndex) {
        auto const & start = points[segmentIndex - 1];
        auto const & end = points[segmentIndex];
        auto const startPx = screen.GtoP(start);
        auto const endPx = screen.GtoP(end);
        double const lengthPx = std::hypot(endPx.x - startPx.x, endPx.y - startPx.y);
        if (lengthPx <= 0.0) {
            continue;
        }
        for (double offsetPx = 0.0; offsetPx < lengthPx; offsetPx += cycleLength) {
            double const dashEndPx = std::min(lengthPx, offsetPx + dashLength);
            if (dashEndPx <= offsetPx) {
                continue;
            }
            double const startT = offsetPx / lengthPx;
            double const endT = dashEndPx / lengthPx;
            dashes.push_back({
                m2::PointD(
                    start.x + ((end.x - start.x) * startT),
                    start.y + ((end.y - start.y) * startT)),
                m2::PointD(
                    start.x + ((end.x - start.x) * endT),
                    start.y + ((end.y - start.y) * endT)),
            });
        }
    }
    return dashes.empty() ? std::vector<std::vector<m2::PointD>>{points} : dashes;
}

void UpdateDuckDBDrapeApiLines(
    std::set<std::string> & activeIds,
    std::vector<std::vector<m2::PointD>> const & lineGeometries,
    std::string const & idPrefix,
    DuckDBInteractionLineStyle const & style) {
    if (!g_framework || !g_drapeEngineCreated) {
        return;
    }

    std::set<std::string> nextIds;
    size_t lineIndex = 0;
    for (auto const & points : lineGeometries) {
        auto const renderGeometries = BuildInteractionLineGeometries(points, style);
        size_t segmentIndex = 0;
        for (auto const & renderPoints : renderGeometries) {
            if (renderPoints.size() < 2) {
                continue;
            }
            auto const id = idPrefix + "-" + std::to_string(lineIndex) +
                "-" + std::to_string(segmentIndex++);
            nextIds.insert(id);
            g_framework->GetDrapeApi().AddLine(
                id,
                df::DrapeApiLineData(renderPoints, style.color)
                    .Width(style.width));
        }
        ++lineIndex;
    }

    if (!lineGeometries.empty() && nextIds.empty() && !activeIds.empty()) {
        return;
    }

    for (auto const & oldId : activeIds) {
        if (nextIds.count(oldId) == 0) {
            g_framework->GetDrapeApi().RemoveLine(oldId);
        }
    }
    activeIds = std::move(nextIds);
}

void ClearDuckDBDrapeApiLines(std::set<std::string> & activeIds) {
    if (!g_framework || !g_drapeEngineCreated) {
        activeIds.clear();
        return;
    }
    for (auto const & id : activeIds) {
        g_framework->GetDrapeApi().RemoveLine(id);
    }
    activeIds.clear();
}

void UpdateDuckDBDrapeApiPoints(
    std::set<std::string> & activeIds,
    std::vector<m2::PointD> const & points,
    std::string const & idPrefix,
    dp::Color color,
    float width) {
    if (!g_framework || !g_drapeEngineCreated) {
        activeIds.clear();
        return;
    }

    std::set<std::string> nextIds;
    for (size_t index = 0; index < points.size(); ++index) {
        auto const id = idPrefix + "-" + std::to_string(index);
        nextIds.insert(id);
        g_framework->GetDrapeApi().AddLine(
            id,
            df::DrapeApiLineData(std::vector<m2::PointD>{points[index]}, color)
                .Width(width)
                .ShowPoints(true));
    }

    for (auto const & oldId : activeIds) {
        if (nextIds.count(oldId) == 0) {
            g_framework->GetDrapeApi().RemoveLine(oldId);
        }
    }
    activeIds = std::move(nextIds);
}

void SetOutdoorsEnabledInternal(bool enabled) {
    if (!g_framework) {
        return;
    }

    g_outdoorsEnabled = enabled;
    auto const currentStyle = g_framework->GetMapStyle();
    bool const dark = MapStyleIsDark(currentStyle);

    if (enabled) {
        ApplyRuntimeMapStyle(dark ? MapStyleOutdoorsDark : MapStyleOutdoorsLight);
    } else if (IsOutdoorsStyle(currentStyle)) {
        ApplyRuntimeMapStyle(dark ? MapStyleDefaultDark : MapStyleDefaultLight);
    }
}

void SetIsolinesEnabledInternal(bool enabled) {
    if (!g_framework) {
        return;
    }
    g_isolinesEnabled = enabled;
    g_framework->GetIsolinesManager().SetEnabled(enabled);
}

void SetSubwayEnabledInternal(bool enabled) {
    if (!g_framework) {
        return;
    }
    if (enabled) {
        SetOutdoorsEnabledInternal(false);
        SetIsolinesEnabledInternal(false);
    }
    g_subwayEnabled = enabled;
    g_framework->GetTransitManager().EnableTransitSchemeMode(enabled);
}

bool IsPointFeature(char const * geometryKind, char const * wkt) {
    std::string_view const kind =
        geometryKind == nullptr ? std::string_view() : std::string_view(geometryKind);
    if (kind == "point") {
        return true;
    }
    std::string_view const text =
        wkt == nullptr ? std::string_view() : std::string_view(wkt);
    return text.rfind("POINT", 0) == 0;
}

int ClampZoom(int zoom) {
    if (zoom < 1) {
        return 1;
    }
    return std::min(zoom, 20);
}

DuckDBRenderViewport GetDuckDBRenderViewport() {
    auto const latLonRect = mercator::ToLatLon(g_framework->GetCurrentViewport());
    return {
        std::min(latLonRect.minY(), latLonRect.maxY()),
        std::min(latLonRect.minX(), latLonRect.maxX()),
        std::max(latLonRect.minY(), latLonRect.maxY()),
        std::max(latLonRect.minX(), latLonRect.maxX()),
    };
}

bool ShouldRefreshDuckDBRenderOnViewportChange() {
    std::lock_guard<std::mutex> lock(g_duckDBRenderMutex);
    if (!g_duckDBRenderingEnabled) {
        return false;
    }
    auto const now = std::chrono::steady_clock::now();
    return now - g_lastDuckDBRenderRefresh >= kDuckDBViewportRefreshInterval;
}

void ScheduleDuckDBRenderRefreshAfterViewportIdle() {
    {
        std::lock_guard<std::mutex> lock(g_duckDBRenderMutex);
        if (!g_duckDBRenderingEnabled) {
            return;
        }
    }

    g_duckDBViewportGeneration.fetch_add(1, std::memory_order_relaxed);
    bool expected = false;
    if (!g_duckDBViewportRefreshScheduled.compare_exchange_strong(
            expected, true, std::memory_order_acq_rel)) {
        return;
    }

    std::thread([]() {
        while (true) {
            auto const observedGeneration =
                g_duckDBViewportGeneration.load(std::memory_order_relaxed);
            std::this_thread::sleep_for(kDuckDBViewportIdleRefreshDelay);
            if (observedGeneration ==
                g_duckDBViewportGeneration.load(std::memory_order_relaxed)) {
                break;
            }
        }

        g_duckDBViewportRefreshScheduled.store(false, std::memory_order_release);
        if (ShouldRefreshDuckDBRenderOnViewportChange()) {
            RefreshDuckDBRenderLayersInternal();
        }
    }).detach();
}
}  // namespace

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

#pragma endregion

#pragma region Logging

/// Custom log handler that redirects to OutputDebugString and stderr
static void AgusLogMessage(base::LogLevel level, base::SrcPoint const & src, std::string const & msg) {
#if AGUS_RELEASE_BUILD
    if (level < base::LWARNING) {
        return;
    }
    if (msg.find("Detected using of unknown symbol") != std::string::npos ||
        msg.find("Style error. Symbol name must be valid") != std::string::npos ||
        msg.find("Bad emoji code: U+2139") != std::string::npos ||
        msg.find("Can't find World map file") != std::string::npos ||
        msg.find("Can't load cities boundaries") != std::string::npos ||
        msg.find("Can't open en-US localization file: sound-strings") != std::string::npos ||
        msg.find("Inconsistent MWM and version for LocalCountryFile") != std::string::npos ||
        msg.find("Cannot read power manager config file") != std::string::npos) {
        return;
    }
#endif

    const char* levelStr;
    switch (level) {
        case base::LDEBUG: levelStr = "DEBUG"; break;
        case base::LINFO: levelStr = "INFO"; break;
        case base::LWARNING: levelStr = "WARN"; break;
        case base::LERROR: levelStr = "ERROR"; break;
        case base::LCRITICAL: levelStr = "CRITICAL"; break;
        default: levelStr = "???"; break;
    }
    
    std::string out = "[CoMaps " + std::string(levelStr) + "] " + DebugPrint(src) + msg + "\n";
    AgusWriteLog(out.c_str());
    
    // Only abort on CRITICAL, not ERROR
    if (level >= base::LCRITICAL) {
        AgusWriteLog("[CoMaps CRITICAL] Aborting...\n");
        std::abort();
    }
}

static void ensureLoggingConfigured() {
    if (!g_loggingInitialized) {
        base::SetLogMessageFn(&AgusLogMessage);
        base::g_LogAbortLevel = base::LCRITICAL;
        g_loggingInitialized = true;
        
        // Install crash handler for better diagnostics
        installCrashHandler();
        
        AGUS_DEBUG_LOG("[AgusMapsFlutter] Logging initialized\n");
    }
}

#pragma endregion

#pragma region Frame Notification

/// Internal function to notify Flutter about a new frame
/// Called from DrapeEngine render thread via df::SetActiveFrameCallback
static void notifyFlutterFrameReady() {
    // Rate limiting: Enforce 60fps max
    auto now = std::chrono::steady_clock::now();
    auto elapsed = now - g_lastFrameNotification;
    if (elapsed < kMinFrameInterval) {
        return;  // Too soon, skip this notification
    }
    
    // Throttle: if a notification is already pending, skip this one
    bool expected = false;
    if (!g_frameNotificationPending.compare_exchange_strong(expected, true)) {
        return;  // Already a notification pending, skip
    }
    
    g_lastFrameNotification = now;
    
    // Call the registered callback
    if (g_frameReadyCallback) {
        g_frameReadyCallback();
    }
    
    g_frameNotificationPending.store(false);
}

/// Called by Present() to notify Flutter that a frame was rendered
/// Exported for AgusWglContextFactory to call
extern "C" void agus_notify_frame_ready(void) {
    notifyFlutterFrameReady();
}

#pragma endregion

#pragma region DrapeEngine

static void createDrapeEngineIfNeeded(int width, int height, float density) {
    if (g_drapeEngineCreated || !g_framework || !g_threadSafeFactory) {
        return;
    }
    
    if (width <= 0 || height <= 0) {
        AgusWriteLog("[AgusMapsFlutter] createDrapeEngine: Invalid dimensions\n");
        return;
    }
    
    // Present() performs the D3D copy and only then notifies Flutter. Avoid the
    // generic active-frame callback here because it fires before Present(), which
    // can make Flutter sample an old or blank shared texture.
    df::SetActiveFrameCallback({});
    AGUS_DEBUG_LOG("[AgusMapsFlutter] Active frame callback disabled; Present handles frame delivery\n");
    
    Framework::DrapeCreationParams p;
    p.m_apiVersion = dp::ApiVersion::OpenGLES3;  // Use OpenGL on Windows
    p.m_surfaceWidth = width;
    p.m_surfaceHeight = height;
    p.m_visualScale = density;
    
    AGUS_DEBUG_LOG("[AgusMapsFlutter] Creating DrapeEngine: %dx%d, scale=%.2f, API=OpenGL\n",
                   width, height, density);
    
    g_framework->CreateDrapeEngine(make_ref(g_threadSafeFactory), std::move(p));
    g_drapeEngineCreated = true;
    
    AGUS_DEBUG_LOG("[AgusMapsFlutter] DrapeEngine created successfully\n");
}

#pragma endregion

#pragma region FFI Functions

FFI_PLUGIN_EXPORT int sum(int a, int b) { 
    return a + b; 
}

FFI_PLUGIN_EXPORT int sum_long_running(int a, int b) {
    Sleep(5000);
    return a + b;
}

FFI_PLUGIN_EXPORT void comaps_init(const char* apkPath, const char* storagePath) {
    // Windows doesn't use APK paths - redirect to comaps_init_paths
    comaps_init_paths(apkPath, storagePath);
}

FFI_PLUGIN_EXPORT void comaps_init_paths(const char* resourcePath, const char* writablePath) {
    ensureLoggingConfigured();

    AGUS_DEBUG_LOG("[AgusMapsFlutter] comaps_init_paths: resource=%s, writable=%s\n",
                   resourcePath, writablePath);
    
    // Store paths
    g_resourcePath = resourcePath ? resourcePath : "";
    g_writablePath = writablePath ? writablePath : "";
    
    // Initialize platform paths via AgusPlatformWin
    AgusPlatformWin_InitPaths(resourcePath, writablePath);
    g_platformInitialized = true;
    
    AGUS_DEBUG_LOG("[AgusMapsFlutter] Platform initialized, Framework deferred to surface creation\n");
}

FFI_PLUGIN_EXPORT void comaps_load_map_path(const char* path) {
    AGUS_DEBUG_LOG("[AgusMapsFlutter] comaps_load_map_path: %s\n", path);
    
    if (g_framework) {
        g_framework->RegisterAllMaps();
        AGUS_DEBUG_LOG("[AgusMapsFlutter] Maps registered\n");
    } else {
        AGUS_DEBUG_LOG("[AgusMapsFlutter] Framework not yet initialized, maps will be loaded later\n");
    }
}

// Forward declaration for locale setting from agus_localization.cpp
extern "C" void agus_localization_set_locale(const char* localeTag);

FFI_PLUGIN_EXPORT void comaps_set_locale(const char* localeTag) {
    AGUS_DEBUG_LOG("[AgusMapsFlutter] comaps_set_locale: %s\n", localeTag ? localeTag : "(null)");
    
    if (localeTag && *localeTag) {
        agus_localization_set_locale(localeTag);
        AGUS_DEBUG_LOG("[AgusMapsFlutter] Locale set to '%s'\n", localeTag);
    } else {
        AGUS_DEBUG_LOG("[AgusMapsFlutter] Empty locale tag, using auto-detect\n");
    }
}

FFI_PLUGIN_EXPORT void comaps_set_view(double lat, double lon, int zoom) {
    LOG(LINFO, ("comaps_set_view: lat=", lat, " lon=", lon, " zoom=", zoom));
    
    if (g_framework) {
        // Use isAnim=false to set the view synchronously.
        // This ensures the screen is updated immediately so that subsequent
        // tile requests use the correct viewport coordinates.
        // With isAnim=true (default), the view change is animated which delays
        // the actual screen update, causing tile requests to use stale coordinates.
        g_framework->SetViewportCenter(m2::PointD(mercator::FromLatLon(lat, lon)), zoom, false /* isAnim */);
        
        // Wake up the render loop to process the view change event
        g_framework->InvalidateRendering();
        LOG(LINFO, ("comaps_set_view: Viewport set (no animation)"));
    } else {
        LOG(LWARNING, ("comaps_set_view: Framework not ready"));
    }
}

FFI_PLUGIN_EXPORT int comaps_get_viewport_center(double* lat, double* lon) {
    if (!g_framework || !lat || !lon) {
        return 0;
    }
    auto const ll = mercator::ToLatLon(g_framework->GetViewportCenter());
    *lat = ll.m_lat;
    *lon = ll.m_lon;
    return 1;
}

FFI_PLUGIN_EXPORT int comaps_get_current_zoom(void) {
    if (!g_framework) {
        return -1;
    }
    return g_framework->GetDrawScale();
}

FFI_PLUGIN_EXPORT int comaps_screen_to_latlon(
    double physical_x,
    double physical_y,
    double* lat,
    double* lon) {
    if (!g_framework || !lat || !lon) {
        return 0;
    }

    auto const mercatorPoint = g_framework->PtoG(
        m2::PointD(physical_x, physical_y));
    auto const coordinate = mercator::ToLatLon(mercatorPoint);
    *lat = coordinate.m_lat;
    *lon = coordinate.m_lon;
    return 1;
}

FFI_PLUGIN_EXPORT int comaps_update_map_pointer(
    double physical_x,
    double physical_y,
    int inside_map,
    double* lat,
    double* lon) {
    if (!lat || !lon) {
        return 0;
    }

    bool hasCoordinate = false;
    double projectedLat = 0.0;
    double projectedLon = 0.0;
    if (g_framework && inside_map != 0) {
        auto const mercatorPoint = g_framework->PtoG(
            m2::PointD(physical_x, physical_y));
        auto const coordinate = mercator::ToLatLon(mercatorPoint);
        projectedLat = coordinate.m_lat;
        projectedLon = coordinate.m_lon;
        hasCoordinate = true;
    }

    {
        std::lock_guard<std::mutex> lock(g_mapPointerMutex);
        g_lastMapPointer.physicalX = physical_x;
        g_lastMapPointer.physicalY = physical_y;
        g_lastMapPointer.lat = projectedLat;
        g_lastMapPointer.lon = projectedLon;
        g_lastMapPointer.insideMap = inside_map != 0;
        g_lastMapPointer.hasCoordinate = hasCoordinate;
    }

    if (!hasCoordinate) {
        return 0;
    }
    *lat = projectedLat;
    *lon = projectedLon;
    return 1;
}

FFI_PLUGIN_EXPORT int comaps_latlon_to_screen(
    double lat,
    double lon,
    double* physical_x,
    double* physical_y) {
    if (!g_framework || !physical_x || !physical_y) {
        return 0;
    }

    auto const screenPoint = g_framework->GtoP(mercator::FromLatLon(lat, lon));
    *physical_x = screenPoint.x;
    *physical_y = screenPoint.y;
    return 1;
}

namespace {
int32_t RefreshDuckDBRenderLayersInternal() {
    std::lock_guard<std::mutex> lock(g_duckDBRenderMutex);
    if (!g_framework || !g_drapeEngineCreated || agus_duckdb_is_open() == 0) {
        return -1;
    }

    auto const viewport = GetDuckDBRenderViewport();
    auto const zoom = ClampZoom(g_framework->GetDrawScale());
    std::vector<std::vector<m2::PointD>> lineGeometries;
    std::vector<m2::PointD> pointGeometries;
    std::vector<std::string> featureKeys;
    lineGeometries.reserve(kDuckDBRenderFetchBatchSize);
    pointGeometries.reserve(64);
    featureKeys.reserve(kDuckDBRenderFetchBatchSize);

    int32_t queryOffset = 0;
    while (queryOffset < kDuckDBRenderFetchMaxFeatures) {
        int32_t const batchLimit =
            std::min(kDuckDBRenderFetchBatchSize,
                     kDuckDBRenderFetchMaxFeatures - queryOffset);
        AgusDuckDBRenderFeature * features = nullptr;
        int32_t featureCount = 0;
        if (agus_duckdb_copy_render_features_page(
                viewport.minLon, viewport.minLat, viewport.maxLon, viewport.maxLat,
                zoom, batchLimit, queryOffset, &features, &featureCount) == 0) {
            return -2;
        }

        for (int32_t index = 0; index < featureCount; ++index) {
            auto const & feature = features[index];
            auto points = ParseWktMercatorPoints(feature.geometry_wkt);
            if (points.empty()) {
                continue;
            }
            std::string key = feature.layer_id ? feature.layer_id : "";
            key += "/";
            key += feature.feature_id ? feature.feature_id : "";
            key += ":";
            key += feature.geometry_wkt ? feature.geometry_wkt : "";
            featureKeys.push_back(std::move(key));
            if (IsPointFeature(feature.geometry_kind, feature.geometry_wkt)) {
                pointGeometries.push_back(points.front());
            } else if (points.size() > 1) {
                lineGeometries.push_back(std::move(points));
            }
        }

        agus_duckdb_free_render_features(features, featureCount);
        queryOffset += featureCount;
        if (featureCount < batchLimit) {
            break;
        }
    }

    if (g_duckDBRenderPublished && featureKeys == g_lastDuckDBRenderableFeatureKeys) {
        g_lastDuckDBRenderRefresh = std::chrono::steady_clock::now();
        return static_cast<int32_t>(featureKeys.size());
    }

    DuckDBInteractionLineStyle style;
    style.color = dp::Color(37, 99, 235, 235);
    style.width = 3.0f;
    style.dashed = false;
    UpdateDuckDBDrapeApiLines(
        g_duckDBCommittedDrapeLineIds,
        lineGeometries,
        "duckdb-committed",
        style);
    UpdateDuckDBDrapeApiPoints(
        g_duckDBCommittedPointIds,
        pointGeometries,
        "duckdb-committed-point",
        dp::Color(219, 39, 119, 240),
        10.0f);
    g_framework->GetDrapeApi().Invalidate();

    g_duckDBRenderPublished = true;
    g_lastDuckDBRenderableFeatureKeys = std::move(featureKeys);
    g_lastDuckDBRenderRefresh = std::chrono::steady_clock::now();
    WakeRenderer();
    return static_cast<int32_t>(lineGeometries.size() + pointGeometries.size());
}
}  // namespace

FFI_PLUGIN_EXPORT int32_t agus_duckdb_refresh_render_layers(void) {
    return RefreshDuckDBRenderLayersInternal();
}

FFI_PLUGIN_EXPORT void agus_duckdb_set_edit_handles_from_wkt(const char* geometryWkt) {
    auto geometries = ParseWktMercatorGeometries(geometryWkt);
    DuckDBInteractionLineStyle style;
    style.color = dp::Color(219, 39, 119, 245);
    style.dashed = false;
    UpdateDuckDBDrapeApiLines(g_duckDBInteractionDrapeLineIds, geometries, "duckdb-interaction", style);
    UpdateDuckDBDrapeApiPoints(
        g_duckDBInteractionPointIds,
        FlattenGeometryPoints(geometries),
        "duckdb-interaction-point",
        dp::Color(219, 39, 119, 245),
        9.0f);
    AGUS_DEBUG_LOG(
        "[AgusMapsFlutter] DuckDB interaction geometry: mode=2 geometries=%zu renderer=DrapeApiLineData depthTest=0 lineWidth=%.2f dashed=0 platform=windows\n",
        geometries.size(),
        style.width);
    WakeRenderer();
}

FFI_PLUGIN_EXPORT void agus_duckdb_set_interaction_geometry_from_wkt(
    int32_t interactionMode,
    const char* geometryWkt) {
    if (interactionMode == 0 || geometryWkt == nullptr || *geometryWkt == '\0') {
        ClearDuckDBDrapeApiLines(g_duckDBInteractionDrapeLineIds);
        ClearDuckDBDrapeApiLines(g_duckDBInteractionPointIds);
        WakeRenderer();
        return;
    }
    DuckDBInteractionLineStyle style;
    style.dashed = false;
    if (interactionMode == 2) {
        style.color = dp::Color(219, 39, 119, 245);
        style.dashed = false;
    }
    auto geometries = ParseWktMercatorGeometries(geometryWkt);
    UpdateDuckDBDrapeApiLines(g_duckDBInteractionDrapeLineIds, geometries, "duckdb-interaction", style);
    if (interactionMode == 2) {
        UpdateDuckDBDrapeApiPoints(
            g_duckDBInteractionPointIds,
            FlattenGeometryPoints(geometries),
            "duckdb-interaction-point",
            dp::Color(219, 39, 119, 245),
            9.0f);
    } else {
        ClearDuckDBDrapeApiLines(g_duckDBInteractionPointIds);
    }
    AGUS_DEBUG_LOG(
        "[AgusMapsFlutter] DuckDB interaction geometry: mode=%d geometries=%zu renderer=DrapeApiLineData depthTest=0 lineWidth=%.2f dashed=%d platform=windows\n",
        interactionMode,
        geometries.size(),
        style.width,
        style.dashed ? 1 : 0);
    WakeRenderer();
}

FFI_PLUGIN_EXPORT void agus_duckdb_update_interaction_geometry(
    int32_t interactionMode,
    const char* geometryWkt,
    int32_t red,
    int32_t green,
    int32_t blue,
    double opacity,
    double width,
    int32_t dashed,
    double dashLength,
    double gapLength) {
    if (interactionMode == 0 || geometryWkt == nullptr || *geometryWkt == '\0') {
        ClearDuckDBDrapeApiLines(g_duckDBInteractionDrapeLineIds);
        ClearDuckDBDrapeApiLines(g_duckDBInteractionPointIds);
        WakeRenderer();
        return;
    }
    DuckDBInteractionLineStyle style;
    int const clampedRed = std::max(0, std::min(red, 255));
    int const clampedGreen = std::max(0, std::min(green, 255));
    int const clampedBlue = std::max(0, std::min(blue, 255));
    int const alpha = std::max(0, std::min(static_cast<int>(opacity * 255.0), 255));
    style.color = dp::Color(clampedRed, clampedGreen, clampedBlue, alpha);
    style.width = static_cast<float>(std::max(0.5, std::min(width, 8.0)));
    style.dashed = dashed != 0;
    style.dashLength = std::max(1.0, dashLength);
    style.gapLength = std::max(1.0, gapLength);
    auto geometries = ParseWktMercatorGeometries(geometryWkt);
    UpdateDuckDBDrapeApiLines(g_duckDBInteractionDrapeLineIds, geometries, "duckdb-interaction", style);
    if (interactionMode == 2) {
        UpdateDuckDBDrapeApiPoints(
            g_duckDBInteractionPointIds,
            FlattenGeometryPoints(geometries),
            "duckdb-interaction-point",
            style.color,
            std::max(7.0f, style.width * 2.5f));
    } else {
        ClearDuckDBDrapeApiLines(g_duckDBInteractionPointIds);
    }
    AGUS_DEBUG_LOG(
        "[AgusMapsFlutter] DuckDB interaction geometry: mode=%d geometries=%zu renderer=DrapeApiLineData depthTest=0 lineWidth=%.2f opacity=%d dashed=%d platform=windows\n",
        interactionMode,
        geometries.size(),
        style.width,
        alpha,
        style.dashed ? 1 : 0);
    WakeRenderer();
}

FFI_PLUGIN_EXPORT void agus_duckdb_clear_edit_handles(void) {
    ClearDuckDBDrapeApiLines(g_duckDBInteractionDrapeLineIds);
    ClearDuckDBDrapeApiLines(g_duckDBInteractionPointIds);
    WakeRenderer();
}

FFI_PLUGIN_EXPORT void agus_duckdb_set_rendering_enabled(int32_t enabled) {
    if (enabled != 0) {
        {
            std::lock_guard<std::mutex> lock(g_duckDBRenderMutex);
            g_duckDBRenderingEnabled = true;
        }
        RefreshDuckDBRenderLayersInternal();
        return;
    }

    std::lock_guard<std::mutex> lock(g_duckDBRenderMutex);
    g_duckDBRenderingEnabled = false;
    g_duckDBRenderPublished = false;
    g_lastDuckDBRenderableFeatureKeys.clear();
    ClearDuckDBDrapeApiLines(g_duckDBCommittedDrapeLineIds);
    ClearDuckDBDrapeApiLines(g_duckDBCommittedPointIds);
    WakeRenderer();
}

FFI_PLUGIN_EXPORT void comaps_zoom_in(int animated) {
    if (!g_framework || !g_drapeEngineCreated) {
        return;
    }
    g_framework->Scale(Framework::SCALE_MAG_LIGHT, animated != 0);
    WakeRenderer();
}

FFI_PLUGIN_EXPORT void comaps_zoom_out(int animated) {
    if (!g_framework || !g_drapeEngineCreated) {
        return;
    }
    g_framework->Scale(Framework::SCALE_MIN_LIGHT, animated != 0);
    WakeRenderer();
}

FFI_PLUGIN_EXPORT double comaps_get_current_bearing(void) {
    return g_currentBearingDegrees;
}

FFI_PLUGIN_EXPORT void comaps_set_bearing(double degrees, int animated) {
    if (!g_framework || !g_drapeEngineCreated) {
        return;
    }
    g_currentBearingDegrees = NormalizeBearingDegrees(degrees);
    g_framework->Rotate(g_currentBearingDegrees * kRadiansPerDegree, animated != 0);
    WakeRenderer();
}

FFI_PLUGIN_EXPORT void comaps_reset_bearing(int animated) {
    comaps_set_bearing(0.0, animated);
}

FFI_PLUGIN_EXPORT void comaps_set_3d_buildings_enabled(int enabled) {
    g_3dBuildingsEnabled = enabled != 0;
    if (!g_framework) {
        return;
    }
    g_framework->Allow3dMode(false, g_3dBuildingsEnabled);
    WakeRenderer();
}

FFI_PLUGIN_EXPORT int comaps_get_3d_buildings_enabled(void) {
    return g_3dBuildingsEnabled ? 1 : 0;
}

FFI_PLUGIN_EXPORT void comaps_set_map_theme(int dark) {
    if (!g_framework) {
        return;
    }
    auto const currentStyle = g_framework->GetMapStyle();
    ApplyRuntimeMapStyle(dark != 0
        ? GetDarkMapStyleVariant(currentStyle)
        : GetLightMapStyleVariant(currentStyle));
    WakeRenderer();
}

FFI_PLUGIN_EXPORT int comaps_get_map_theme_is_dark(void) {
    if (!g_framework) {
        return 0;
    }
    return MapStyleIsDark(g_framework->GetMapStyle()) ? 1 : 0;
}

FFI_PLUGIN_EXPORT void comaps_set_outdoors_enabled(int enabled) {
    if (!g_framework) {
        return;
    }
    if (enabled) {
        SetSubwayEnabledInternal(false);
    }
    SetOutdoorsEnabledInternal(enabled != 0);
    WakeRenderer();
}

FFI_PLUGIN_EXPORT void comaps_set_isolines_enabled(int enabled) {
    if (!g_framework) {
        return;
    }
    if (enabled) {
        SetSubwayEnabledInternal(false);
    }
    SetIsolinesEnabledInternal(enabled != 0);
    WakeRenderer();
}

FFI_PLUGIN_EXPORT void comaps_set_subway_enabled(int enabled) {
    SetSubwayEnabledInternal(enabled != 0);
    WakeRenderer();
}

FFI_PLUGIN_EXPORT void comaps_get_map_layer_state(int* outdoors, int* isolines, int* subway) {
    if (outdoors) {
        *outdoors = g_outdoorsEnabled ? 1 : 0;
    }
    if (isolines) {
        *isolines = g_isolinesEnabled ? 1 : 0;
    }
    if (subway) {
        *subway = g_subwayEnabled ? 1 : 0;
    }
}

FFI_PLUGIN_EXPORT void comaps_set_map_language(const char* languageCode) {
    if (!g_framework) {
        return;
    }
    auto engine = g_framework->GetDrapeEngine();
    if (!engine) {
        return;
    }
    auto languageIndex = localisation::GetMapLanguageIndex();
    if (languageCode && *languageCode) {
        auto const requestedIndex =
            localisation::ConvertLanguageCodeToLanguageIndex(languageCode);
        if (requestedIndex != localisation::kUnsupportedLanguageIndex) {
            languageIndex = requestedIndex;
        }
    }
    engine->SetMapLangIndex(languageIndex);
    WakeRenderer();
}

FFI_PLUGIN_EXPORT int32_t comaps_navigation_set_router(int32_t routerType) {
    auto const result = agus::navigation::SetRouter(g_framework.get(), routerType);
    if (result > 0) WakeRenderer();
    return result;
}

FFI_PLUGIN_EXPORT int32_t comaps_navigation_get_router(void) {
    return agus::navigation::GetRouter(g_framework.get());
}

FFI_PLUGIN_EXPORT int32_t comaps_navigation_add_route_point(
    int32_t markType, const char* title, const char* subtitle, double lat,
    double lon, int32_t intermediateIndex, int32_t isMyPosition,
    int32_t reorderIntermediatePoints) {
    auto const result = agus::navigation::AddRoutePoint(
        g_framework.get(), markType, title, subtitle, lat, lon,
        intermediateIndex, isMyPosition, reorderIntermediatePoints);
    if (result > 0) WakeRenderer();
    return result;
}

FFI_PLUGIN_EXPORT void comaps_navigation_remove_route_point(
    int32_t markType, int32_t intermediateIndex) {
    agus::navigation::RemoveRoutePoint(g_framework.get(), markType, intermediateIndex);
    WakeRenderer();
}

FFI_PLUGIN_EXPORT void comaps_navigation_clear_route_points(void) {
    agus::navigation::ClearRoutePoints(g_framework.get());
    WakeRenderer();
}

FFI_PLUGIN_EXPORT int32_t comaps_navigation_build_route(void) {
    auto const result = agus::navigation::BuildRoute(g_framework.get());
    if (result > 0) WakeRenderer();
    return result;
}

FFI_PLUGIN_EXPORT int32_t comaps_navigation_follow_route(void) {
    auto const result = agus::navigation::FollowRoute(g_framework.get());
    if (result > 0) WakeRenderer();
    return result;
}

FFI_PLUGIN_EXPORT void comaps_navigation_close_route(int32_t removeRoutePoints) {
    agus::navigation::CloseRoute(g_framework.get(), removeRoutePoints);
    WakeRenderer();
}

FFI_PLUGIN_EXPORT int32_t comaps_navigation_is_active(void) {
    return agus::navigation::IsActive(g_framework.get());
}

FFI_PLUGIN_EXPORT int32_t comaps_navigation_is_built(void) {
    return agus::navigation::IsBuilt(g_framework.get());
}

FFI_PLUGIN_EXPORT int32_t comaps_navigation_is_building(void) {
    return agus::navigation::IsBuilding(g_framework.get());
}

FFI_PLUGIN_EXPORT int32_t comaps_navigation_is_following(void) {
    return agus::navigation::IsFollowing(g_framework.get());
}

FFI_PLUGIN_EXPORT AgusNavigationStatus* comaps_navigation_copy_status(void) {
    return agus::navigation::CopyStatus(g_framework.get());
}

FFI_PLUGIN_EXPORT void comaps_navigation_status_free(AgusNavigationStatus* status) {
    agus::navigation::FreeStatus(status);
}

FFI_PLUGIN_EXPORT void comaps_navigation_set_measurement_units(int32_t units) {
    agus::navigation::SetMeasurementUnits(g_framework.get(), units);
    WakeRenderer();
}

FFI_PLUGIN_EXPORT int32_t comaps_navigation_get_measurement_units(void) {
    return agus::navigation::GetMeasurementUnits();
}

FFI_PLUGIN_EXPORT void comaps_navigation_set_turn_notifications_enabled(int32_t enabled) {
    agus::navigation::SetTurnNotificationsEnabled(g_framework.get(), enabled);
}

FFI_PLUGIN_EXPORT int32_t comaps_navigation_get_turn_notifications_enabled(void) {
    return agus::navigation::GetTurnNotificationsEnabled(g_framework.get());
}

FFI_PLUGIN_EXPORT void comaps_navigation_set_turn_notifications_locale(const char* locale) {
    agus::navigation::SetTurnNotificationsLocale(g_framework.get(), locale);
}

FFI_PLUGIN_EXPORT void comaps_navigation_set_speed_camera_mode(int32_t mode) {
    agus::navigation::SetSpeedCameraMode(g_framework.get(), mode);
}

FFI_PLUGIN_EXPORT int32_t comaps_navigation_get_speed_camera_mode(void) {
    return agus::navigation::GetSpeedCameraMode(g_framework.get());
}

FFI_PLUGIN_EXPORT void comaps_navigation_set_avoid_routing_options(int32_t mask) {
    agus::navigation::SetAvoidRoutingOptions(mask);
}

FFI_PLUGIN_EXPORT int32_t comaps_navigation_get_avoid_routing_options(void) {
    return agus::navigation::GetAvoidRoutingOptions();
}

FFI_PLUGIN_EXPORT void comaps_invalidate(void) {
    LOG(LINFO, ("comaps_invalidate called"));
    
    if (g_framework) {
        g_framework->InvalidateRect(g_framework->GetCurrentViewport());
        LOG(LINFO, ("comaps_invalidate: Viewport invalidated"));
    } else {
        LOG(LWARNING, ("comaps_invalidate: Framework not ready"));
    }
}

FFI_PLUGIN_EXPORT void comaps_force_redraw(void) {
    LOG(LINFO, ("comaps_force_redraw called"));
    
    if (g_framework) {
        // UpdateMapStyle clears all render groups and invalidates the read manager,
        // which forces a complete tile reload when the render loop processes it.
        // This is the cleanest way to force a full redraw.
        ApplyRuntimeMapStyle(g_framework->GetMapStyle());
        
        // MakeFrameActive ensures the render loop stays active (isActiveFrame=true)
        // long enough to process the style update and request new tiles.
        g_framework->MakeFrameActive();
        
        LOG(LINFO, ("comaps_force_redraw: SetMapStyle + MakeFrameActive triggered"));
    } else {
        LOG(LWARNING, ("comaps_force_redraw: Framework not ready"));
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
    RequestActiveRenderFrame();
}

FFI_PLUGIN_EXPORT void comaps_scale(double factor, double pixelX, double pixelY, int animated) {
    if (!g_framework || !g_drapeEngineCreated) {
        return;
    }
    
    // Scale the map by the given factor, centered on the pixel point
    // This is the preferred method for scroll wheel zoom on desktop
    g_framework->Scale(factor, m2::PointD(pixelX, pixelY), animated != 0);
    RequestActiveRenderFrame();
}

FFI_PLUGIN_EXPORT void comaps_scroll(double distanceX, double distanceY) {
    if (!g_framework || !g_drapeEngineCreated) {
        return;
    }
    
    // Scroll the map by the given distance
    g_framework->Scroll(distanceX, distanceY);
    RequestActiveRenderFrame();
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

FFI_PLUGIN_EXPORT int32_t comaps_search_start(const char* query, const char* locale,
                                              int32_t interactive, int32_t isCategory) {
    return agus_search_bridge::StartSearch(g_framework.get(), query, locale, interactive, isCategory);
}

FFI_PLUGIN_EXPORT AgusSearchResults* comaps_search_copy_results(void) {
    return agus_search_bridge::CopyResults();
}

FFI_PLUGIN_EXPORT void comaps_search_results_free(AgusSearchResults* data) {
    agus_search_bridge::FreeResults(data);
}

FFI_PLUGIN_EXPORT int32_t comaps_search_show_result(int32_t index) {
    int32_t const status = agus_search_bridge::ShowResult(g_framework.get(), index);
    if (status > 0) {
        WakeRenderer();
    }
    return status;
}

FFI_PLUGIN_EXPORT void comaps_search_cancel(void) {
    agus_search_bridge::Cancel(g_framework.get());
}

// Helper function to normalize path separators (convert / to \ on Windows)
static std::string NormalizePath(const char* path) {
    std::string normalized(path);
    for (auto& c : normalized) {
        if (c == '/') {
            c = '\\';
        }
    }
    return normalized;
}

FFI_PLUGIN_EXPORT int comaps_register_single_map(const char* fullPath) {
    char msg[512];
    
    // Normalize path separators (convert / to \ for Windows)
    std::string normalizedPath = NormalizePath(fullPath);
    
    snprintf(msg, sizeof(msg), "[AgusMapsFlutter] comaps_register_single_map: %s (normalized: %s)\n", 
             fullPath, normalizedPath.c_str());
    AGUS_DEBUG_LOG("%s", msg);
    
    if (!g_framework) {
        AgusWriteLog("[AgusMapsFlutter] Framework not initialized\n");
        return -1;
    }
    
    return comaps_register_single_map_with_version(fullPath, 0 /* version */);
}

FFI_PLUGIN_EXPORT int comaps_register_single_map_with_version(const char* fullPath, int64_t version) {
    char msg[512];
    
    // Normalize path on Windows
    char normalizedPath[MAX_PATH];
    snprintf(normalizedPath, sizeof(normalizedPath), "%s", fullPath);
    for (char* p = normalizedPath; *p; ++p) {
        if (*p == '/') *p = '\\';
    }

    snprintf(msg, sizeof(msg), "[AgusMapsFlutter] comaps_register_single_map_with_version: %s (normalized: %s, version=%lld)\n",
        fullPath, normalizedPath, static_cast<long long>(version));
    AGUS_DEBUG_LOG("%s", msg);

    if (!g_framework) {
        AgusWriteLog("[AgusMapsFlutter] comaps_register_single_map_with_version: Framework not initialized\n");
        return -1;
    }

    std::string path(normalizedPath);
    if (path.empty()) {
        AgusWriteLog("[AgusMapsFlutter] comaps_register_single_map_with_version: Empty path\n");
        return -2;
    }

    // Derive country name from filename (without extension), matching MakeTemporary().
    auto name = path;
    base::GetNameFromFullPath(name);
    base::GetNameWithoutExt(name);

    platform::LocalCountryFile file(base::GetDirectory(path), platform::CountryFile(std::move(name)), version);
    file.SyncWithDisk();

    auto result = g_framework->RegisterMap(file);
    if (result.second == MwmSet::RegResult::Success) {
        snprintf(msg, sizeof(msg), "[AgusMapsFlutter] comaps_register_single_map_with_version: Successfully registered %s\n", fullPath);
        AGUS_DEBUG_LOG("%s", msg);
        return 0;
    } else {
        snprintf(msg, sizeof(msg), "[AgusMapsFlutter] comaps_register_single_map_with_version: Failed to register %s, result=%d\n",
            fullPath, static_cast<int>(result.second));
        AgusWriteLog(msg);
        return static_cast<int>(result.second);
    }
}

FFI_PLUGIN_EXPORT void comaps_shutdown(void) {
    AGUS_DEBUG_LOG("[AgusMapsFlutter] comaps_shutdown called\n");
    
    std::lock_guard<std::mutex> lock(g_mutex);
    
    // Clear active frame callback first
    df::SetActiveFrameCallback(nullptr);
    
    if (g_framework) {
        g_framework->SetRenderingDisabled(true);
    }
    
    g_threadSafeFactory.reset();
    g_wglFactory = nullptr;
    g_framework.reset();
    
    g_drapeEngineCreated = false;
    g_platformInitialized = false;
    
    AGUS_DEBUG_LOG("[AgusMapsFlutter] Shutdown complete\n");
}

FFI_PLUGIN_EXPORT int comaps_deregister_map(const char* fullPath) {
    AGUS_DEBUG_LOG("[AgusMapsFlutter] comaps_deregister_map: not implemented\n");
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

FFI_PLUGIN_EXPORT void comaps_debug_list_mwms(void) {
#if !AGUS_RELEASE_BUILD
    AgusWriteLog("[AgusMapsFlutter] === DEBUG: Listing all registered MWMs ===\n");
    
    if (!g_framework) {
        AgusWriteLog("[AgusMapsFlutter] Framework not initialized\n");
        return;
    }
    
    auto const & dataSource = g_framework->GetDataSource();
    std::vector<std::shared_ptr<MwmInfo>> mwms;
    dataSource.GetMwmsInfo(mwms);
    
    char msg[256];
    snprintf(msg, sizeof(msg), "[AgusMapsFlutter] Total MWMs registered: %zu\n", mwms.size());
    AgusWriteLog(msg);
    
    for (auto const & mwmInfo : mwms) {
        if (mwmInfo) {
            auto const & rect = mwmInfo->m_bordersRect;
            snprintf(msg, sizeof(msg), "[AgusMapsFlutter]   MWM: %s, bounds: [%.4f, %.4f] - [%.4f, %.4f]\n",
                     mwmInfo->GetCountryName().c_str(),
                     rect.minX(), rect.minY(), rect.maxX(), rect.maxY());
            AgusWriteLog(msg);
        }
    }
#endif
}

FFI_PLUGIN_EXPORT void comaps_debug_check_point(double lat, double lon) {
#if !AGUS_RELEASE_BUILD
    char msg[256];
    snprintf(msg, sizeof(msg), "[AgusMapsFlutter] comaps_debug_check_point: lat=%.6f, lon=%.6f\n", lat, lon);
    AgusWriteLog(msg);
    
    if (!g_framework) {
        AgusWriteLog("[AgusMapsFlutter] Framework not initialized\n");
        return;
    }
    
    m2::PointD const mercatorPt = mercator::FromLatLon(lat, lon);
    snprintf(msg, sizeof(msg), "[AgusMapsFlutter] Mercator coords: (%.4f, %.4f)\n", mercatorPt.x, mercatorPt.y);
    AgusWriteLog(msg);
    
    auto const & dataSource = g_framework->GetDataSource();
    std::vector<std::shared_ptr<MwmInfo>> mwms;
    dataSource.GetMwmsInfo(mwms);
    
    for (auto const & mwmInfo : mwms) {
        if (mwmInfo && mwmInfo->m_bordersRect.IsPointInside(mercatorPt)) {
            snprintf(msg, sizeof(msg), "[AgusMapsFlutter] Point IS covered by MWM: %s\n",
                     mwmInfo->GetCountryName().c_str());
            AgusWriteLog(msg);
            return;
        }
    }
    
    AgusWriteLog("[AgusMapsFlutter] Point is NOT covered by any registered MWM\n");
#endif
}

#pragma endregion

#pragma region Native Surface Functions

/// Set the frame ready callback
FFI_PLUGIN_EXPORT void agus_set_frame_ready_callback(FrameReadyCallback callback) {
    g_frameReadyCallback = callback;
    AGUS_DEBUG_LOG("[AgusMapsFlutter] Frame ready callback set\n");
}

/// Called when the native surface is created
/// @param width Surface width in pixels
/// @param height Surface height in pixels
/// @param density Screen density / DPI scale
FFI_PLUGIN_EXPORT void agus_native_create_surface(int32_t width, int32_t height, float density) {
    ensureLoggingConfigured();

    AGUS_DEBUG_LOG("[AgusMapsFlutter] agus_native_create_surface: %dx%d, density=%.2f\n",
                   width, height, density);
    
    if (!g_platformInitialized) {
        AgusWriteLog("[AgusMapsFlutter] ERROR: Platform not initialized! Call comaps_init_paths first.\n");
        return;
    }
    
    std::lock_guard<std::mutex> lock(g_mutex);
    
    g_surfaceWidth = width;
    g_surfaceHeight = height;
    g_density = density;
    
    // Create Framework on this thread if not already created
    if (!g_framework) {
        AGUS_DEBUG_LOG("[AgusMapsFlutter] Creating Framework...\n");
        
        FrameworkParams params;
        params.m_enableDiffs = false;
        params.m_numSearchAPIThreads = 1;
        
        g_framework = std::make_unique<Framework>(params, false /* loadMaps */);
        SetViewportTracking();
        AGUS_DEBUG_LOG("[AgusMapsFlutter] Framework created\n");
        
        // Register maps
        g_framework->RegisterAllMaps();
        AGUS_DEBUG_LOG("[AgusMapsFlutter] Maps registered\n");
    }
    
    // Create WGL context factory for OpenGL rendering
    g_wglFactory = new agus::AgusWglContextFactory(width, height);
    
    if (!g_wglFactory->GetDrawContext()) {
        AgusWriteLog("[AgusMapsFlutter] ERROR: Failed to create WGL context factory\n");
        delete g_wglFactory;
        g_wglFactory = nullptr;
        return;
    }
    
    // Set frame callback on factory so it notifies Flutter after CopyToSharedTexture()
    g_wglFactory->SetFrameCallback([]() {
        notifyFlutterFrameReady();
    });
    AGUS_DEBUG_LOG("[AgusMapsFlutter] WGL factory frame callback set\n");
    
    // Set keep-alive callback to prevent render loop from suspending during tile loading.
    // This calls Framework::MakeFrameActive() which sends an ActiveFrameEvent to keep
    // the FrontendRenderer's render loop running. Without this, the render loop would
    // suspend after kMaxInactiveFrames (2) inactive frames, before tiles have arrived.
    g_wglFactory->SetKeepAliveCallback([]() {
        if (g_framework) {
            g_framework->MakeFrameActive();
        }
    });
    AGUS_DEBUG_LOG("[AgusMapsFlutter] WGL factory keep-alive callback set\n");
    
    // Wrap in ThreadSafeFactory for thread-safe context access
    g_threadSafeFactory = make_unique_dp<dp::ThreadSafeFactory>(g_wglFactory);
    
    // Create DrapeEngine
    createDrapeEngineIfNeeded(width, height, density);
    
    // Enable rendering
    if (g_framework && g_drapeEngineCreated) {
        g_framework->SetRenderingEnabled(make_ref(g_threadSafeFactory));
        AGUS_DEBUG_LOG("[AgusMapsFlutter] Rendering enabled\n");
    }
}

/// Called when the surface size changes
FFI_PLUGIN_EXPORT void agus_native_on_size_changed(int32_t width, int32_t height) {
    LOG(LINFO, ("agus_native_on_size_changed:", width, "x", height));
    
    g_surfaceWidth = width;
    g_surfaceHeight = height;
    
    // IMPORTANT: Avoid calling SetSurfaceSize() from this thread because the
    // WGL draw context is owned by the render thread. wglMakeCurrent will fail
    // if the context is current on another thread.
    // Instead, rely on Framework::OnSize() which triggers FrontendRenderer::OnResize()
    // on the render thread, and that path calls AgusWglContext::Resize() safely.
    if (g_framework && g_drapeEngineCreated) {
        g_framework->OnSize(width, height);
        LOG(LINFO, ("agus_native_on_size_changed: Framework::OnSize called for", width, "x", height));
    } else if (g_wglFactory) {
        // Fallback for early calls before the framework is ready.
        g_wglFactory->SetSurfaceSize(width, height);
        LOG(LINFO, ("agus_native_on_size_changed: WGL surface updated to", width, "x", height));
    } else {
        LOG(LWARNING, ("agus_native_on_size_changed: Cannot resize - framework:",
                       (g_framework != nullptr), "drapeEngineCreated:", g_drapeEngineCreated,
                       "wglFactory:", (g_wglFactory != nullptr)));
    }
}

/// Called when the display scale (density/DPI) changes at runtime
FFI_PLUGIN_EXPORT void agus_native_set_visual_scale(float density) {
    if (std::fabs(density - g_density) < 0.001f) {
        return;
    }
    g_density = density;

    if (g_framework && g_drapeEngineCreated) {
        // Update visual scale without forcing render context teardown.
        df::VisualParams::Instance().SetVisualScale(static_cast<double>(density));
        g_framework->InvalidateRendering();
        LOG(LINFO, ("agus_native_set_visual_scale: Updated visual scale to", density));
    } else {
        LOG(LWARNING, ("agus_native_set_visual_scale: Framework not ready - stored density:", density));
    }
}

/// Called when the surface is destroyed
FFI_PLUGIN_EXPORT void agus_native_on_surface_destroyed(void) {
    AGUS_DEBUG_LOG("[AgusMapsFlutter] agus_native_on_surface_destroyed\n");
    
    if (g_framework) {
        g_framework->SetRenderingDisabled(true /* destroySurface */);
    }
    
    g_threadSafeFactory.reset();
    g_wglFactory = nullptr;
    g_drapeEngineCreated = false;
}

/// Get the D3D11 shared texture handle for Flutter
/// @return HANDLE that Flutter can use to open the shared texture
FFI_PLUGIN_EXPORT void* agus_get_shared_texture_handle(void) {
    if (g_wglFactory) {
        return g_wglFactory->GetSharedTextureHandle();
    }
    return nullptr;
}

FFI_PLUGIN_EXPORT int agus_get_shared_texture_descriptor_info(void** handle, int32_t* width, int32_t* height) {
    if (!g_wglFactory || !handle || !width || !height) {
        return 0;
    }

    HANDLE sharedHandle = nullptr;
    int textureWidth = 0;
    int textureHeight = 0;
    if (!g_wglFactory->GetSharedTextureInfo(&sharedHandle, &textureWidth, &textureHeight)) {
        return 0;
    }

    *handle = sharedHandle;
    *width = static_cast<int32_t>(textureWidth);
    *height = static_cast<int32_t>(textureHeight);
    return 1;
}

/// Get the D3D11 device pointer for Flutter
/// @return ID3D11Device pointer
FFI_PLUGIN_EXPORT void* agus_get_d3d11_device(void) {
    if (g_wglFactory) {
        return g_wglFactory->GetD3D11Device();
    }
    return nullptr;
}

/// Get the D3D11 texture pointer for Flutter
/// @return ID3D11Texture2D pointer
FFI_PLUGIN_EXPORT void* agus_get_d3d11_texture(void) {
    if (g_wglFactory) {
        return g_wglFactory->GetD3D11Texture();
    }
    return nullptr;
}

FFI_PLUGIN_EXPORT int agus_get_d3d11_texture_info(void** texture, int32_t* width, int32_t* height) {
    if (!g_wglFactory || !texture || !width || !height) {
        return 0;
    }

    ID3D11Texture2D* d3dTexture = nullptr;
    int textureWidth = 0;
    int textureHeight = 0;
    if (!g_wglFactory->AddRefSharedTextureInfo(&d3dTexture, &textureWidth, &textureHeight)) {
        return 0;
    }

    *texture = d3dTexture;
    *width = static_cast<int32_t>(textureWidth);
    *height = static_cast<int32_t>(textureHeight);
    return 1;
}

/// Render a single frame (called by Flutter's texture system)
FFI_PLUGIN_EXPORT void agus_render_frame(void) {
    if (!g_framework || !g_drapeEngineCreated) {
        return;
    }
    
    // The DrapeEngine handles rendering internally
    // Frame completion will trigger agus_notify_frame_ready
}

#pragma endregion

#endif // _WIN32
