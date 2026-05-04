#include "agus_maps_flutter.h"

// A very short-lived native function.
//
// For very short-lived functions, it is fine to call them on the main isolate.
// They will block the Dart execution while running the native function, so
// only do this for native functions which are guaranteed to be short-lived.
FFI_PLUGIN_EXPORT int sum(int a, int b) { return a + b; }

// A longer-lived native function, which occupies the thread calling it.
//
// Do not call these kind of native functions in the main isolate. They will
// block Dart execution. This will cause dropped frames in Flutter applications.
// Instead, call these native functions on a separate isolate.
FFI_PLUGIN_EXPORT int sum_long_running(int a, int b) {
  // Simulate work.
#if _WIN32
  Sleep(5000);
#else
  usleep(5000 * 1000);
#endif
  return a + b;
}

#include <android/log.h>
#include <jni.h>
#include <android/native_window_jni.h>
#include <algorithm>
#include <chrono>
#include <atomic>
#include <cstdlib>
#include <cstring>
#include <map>
#include <memory>
#include <mutex>
#include <set>
#include <thread>
#include <vector>
#include <cmath>

#include "base/file_name_utils.hpp"
#include "base/logging.hpp"
#include "base/localisation.hpp"
#include "map/framework.hpp"
#include "map/place_page_info.hpp"
#include "indexer/feature_meta.hpp"
#include "indexer/map_style.hpp"
#include "indexer/map_style_reader.hpp"
#include "indexer/scales.hpp"
#include "platform/local_country_file.hpp"
#include "drape/color.hpp"
#include "drape/graphics_context_factory.hpp"
#include "drape_frontend/drape_engine.hpp"
#include "drape_frontend/visual_params.hpp"
#include "drape_frontend/user_event_stream.hpp"
#include "drape_frontend/active_frame_callback.hpp"
#include "drape_frontend/user_marks_provider.hpp"
#include "geometry/mercator.hpp"
#include "geometry/screenbase.hpp"
#include "platform/localization.hpp"
#include "agus_navigation_bridge.hpp"
#include "agus_search_bridge.hpp"
#include "agus_ogl.hpp"
#include <sstream>
#include <iomanip>
#include <string_view>

extern "C" void AgusPlatform_Init(const char* apkPath, const char* storagePath);
extern "C" void AgusPlatform_InitPaths(const char* resourcePath, const char* writablePath);
extern "C" void AgusPlatform_SetLocale(const char* locale);

// Custom log handler that redirects to Android logcat without aborting on ERROR
static void AgusLogMessage(base::LogLevel level, base::SrcPoint const & src, std::string const & msg) {
    android_LogPriority pr = ANDROID_LOG_SILENT;
    
    switch (level) {
    case base::LDEBUG: pr = ANDROID_LOG_DEBUG; break;
    case base::LINFO: pr = ANDROID_LOG_INFO; break;
    case base::LWARNING: pr = ANDROID_LOG_WARN; break;
    case base::LERROR: pr = ANDROID_LOG_ERROR; break;
    case base::LCRITICAL: pr = ANDROID_LOG_FATAL; break;
    default: break;
    }
    
    std::string out = DebugPrint(src) + msg;
    __android_log_print(pr, "CoMaps", "%s", out.c_str());
    
    // Only abort on CRITICAL, not ERROR
    if (level >= base::LCRITICAL) {
        __android_log_print(ANDROID_LOG_FATAL, "CoMaps", "CRITICAL ERROR - Aborting");
        abort();
    }
}

// Globals
static std::unique_ptr<Framework> g_framework;
static drape_ptr<dp::ThreadSafeFactory> g_factory;
static agus::AgusOGLContextFactory* g_oglFactory = nullptr;
static std::string g_resourcePath;
static std::string g_writablePath;
static bool g_platformInitialized = false;
static std::mutex g_placePageMutex;
static bool g_drapeEngineCreated = false;
static double g_currentBearingDegrees = 0.0;
static bool g_3dBuildingsEnabled = false;
static bool g_outdoorsEnabled = false;
static bool g_isolinesEnabled = false;
static bool g_subwayEnabled = false;

namespace
{
double constexpr kDegreesPerRadian = 180.0 / 3.14159265358979323846;
double constexpr kRadiansPerDegree = 3.14159265358979323846 / 180.0;
kml::MarkGroupId constexpr kDuckDBRenderGroupId = 1ULL << 60;
kml::MarkId constexpr kDuckDBPointMarkIdBase = kDuckDBRenderGroupId + 1;
kml::TrackId constexpr kDuckDBLineMarkIdBase = kDuckDBRenderGroupId + (1ULL << 20);
int32_t constexpr kDuckDBRenderFetchBatchSize = 1000;
int32_t constexpr kDuckDBRenderFetchMaxFeatures = 10000;
auto constexpr kDuckDBViewportRefreshInterval = std::chrono::milliseconds(250);

void WakeRenderer();

struct DuckDBRenderableGeometry {
    bool isPoint = false;
    int minZoom = 1;
    int zIndex = 0;
    std::vector<m2::PointD> points;
};

class DuckDBPointMark final : public df::UserPointMark {
public:
    DuckDBPointMark(kml::MarkId id, m2::PointD const & pivot, int minZoom,
                    int zIndex)
        : df::UserPointMark(id), m_pivot(pivot), m_minZoom(std::max(1, minZoom)),
          m_zIndex(zIndex) {
        auto const visualScale = static_cast<float>(df::VisualParams::Instance().GetVisualScale());
        df::ColoredSymbolViewParams params;
        params.m_outlineColor = dp::Color::White();
        params.m_outlineWidth = 1.5f * visualScale;
        params.m_radiusInPixels = 6.5f * visualScale;
        params.m_color = dp::Color(0, 122, 255, 255);
        m_coloredSymbols.m_needOverlay = false;
        m_coloredSymbols.m_zoomInfo.emplace(1, params);
    }

    kml::MarkGroupId GetGroupId() const override { return kDuckDBRenderGroupId; }
    bool IsDirty() const override { return m_dirty; }
    void ResetChanges() const override { m_dirty = false; }
    bool IsVisible() const override { return true; }
    m2::PointD const & GetPivot() const override { return m_pivot; }
    m2::PointD GetPixelOffset() const override { return {0.0, 0.0}; }
    dp::Anchor GetAnchor() const override { return dp::Center; }
    bool GetDepthTestEnabled() const override { return true; }
    float GetDepth() const override { return kInvalidDepth; }
    df::DepthLayer GetDepthLayer() const override { return df::DepthLayer::UserMarkLayer; }
    drape_ptr<TitlesInfo> GetTitleDecl() const override { return nullptr; }
    drape_ptr<SymbolNameZoomInfo> GetSymbolNames() const override { return nullptr; }
    drape_ptr<ColoredSymbolZoomInfo> GetColoredSymbols() const override {
        return make_unique_dp<ColoredSymbolZoomInfo>(m_coloredSymbols);
    }
    drape_ptr<SymbolSizes> GetSymbolSizes() const override { return nullptr; }
    drape_ptr<SymbolOffsets> GetSymbolOffsets() const override { return nullptr; }
    uint16_t GetPriority() const override {
        return static_cast<uint16_t>(std::clamp(m_zIndex, 0, 65535));
    }
    df::SpecialDisplacement GetDisplacement() const override { return df::SpecialDisplacement::UserMark; }
    uint32_t GetIndex() const override { return 0; }
    bool SymbolIsPOI() const override { return true; }
    bool HasTitlePriority() const override { return false; }
    int GetMinZoom() const override { return m_minZoom; }
    int GetMinTitleZoom() const override { return m_minZoom; }
    FeatureID GetFeatureID() const override { return FeatureID(); }
    bool HasCreationAnimation() const override { return false; }
    df::ColorConstant GetColorConstant() const override { return {}; }
    bool IsMarkAboveText() const override { return false; }
    float GetSymbolOpacity() const override { return 1.0f; }
    bool IsSymbolSelectable() const override { return false; }
    bool IsNonDisplaceable() const override { return false; }

private:
    m2::PointD m_pivot;
    int m_minZoom;
    int m_zIndex;
    ColoredSymbolZoomInfo m_coloredSymbols;
    mutable bool m_dirty = true;
};

class DuckDBLineMark final : public df::UserLineMark {
public:
    DuckDBLineMark(kml::TrackId id, std::vector<m2::PointD> points, int minZoom,
                   int zIndex)
        : df::UserLineMark(id), m_points(std::move(points)),
          m_minZoom(std::max(1, minZoom)), m_zIndex(zIndex) {
        auto const visualScale = static_cast<float>(df::VisualParams::Instance().GetVisualScale());
        m_width = 4.0f * visualScale;
    }

    kml::MarkGroupId GetGroupId() const override { return kDuckDBRenderGroupId; }
    bool IsDirty() const override { return m_dirty; }
    void ResetChanges() const override { m_dirty = false; }
    int GetMinZoom() const override { return m_minZoom; }
    df::DepthLayer GetDepthLayer() const override { return df::DepthLayer::UserLineLayer; }
    size_t GetLayerCount() const override { return 1; }
    dp::Color GetColor(size_t /* layerIndex */) const override {
        return dp::Color(0, 122, 255, 220);
    }
    float GetWidth(size_t /* layerIndex */) const override { return m_width; }
    float GetDepth(size_t /* layerIndex */) const override {
        return static_cast<float>(m_zIndex) * 0.001f;
    }
    void ForEachGeometry(GeometryFnT && fn) const override {
        if (m_points.size() > 1) {
            fn(std::vector<m2::PointD>(m_points));
        }
    }

private:
    std::vector<m2::PointD> m_points;
    float m_width = 4.0f;
    int m_minZoom;
    int m_zIndex;
    mutable bool m_dirty = true;
};

class DuckDBMarksProvider final : public df::UserMarksProvider {
public:
    DuckDBMarksProvider() { m_allGroups.insert(kDuckDBRenderGroupId); }

    void SetFeatures(std::vector<DuckDBRenderableGeometry> const & features) {
        m_pointMarks.clear();
        m_lineMarks.clear();
        m_pointIds.clear();
        m_lineIds.clear();
        m_createdPointIds.clear();
        m_createdLineIds.clear();
        m_updatedPointIds.clear();
        m_updatedLineIds.clear();
        m_updatedGroups.clear();
        m_updatedGroups.insert(kDuckDBRenderGroupId);

        size_t pointIndex = 0;
        size_t lineIndex = 0;
        for (auto const & feature : features) {
            if (feature.isPoint && !feature.points.empty()) {
                auto const id = kDuckDBPointMarkIdBase + pointIndex++;
                m_pointIds.insert(id);
                m_createdPointIds.insert(id);
                m_pointMarks.emplace(id, std::make_unique<DuckDBPointMark>(
                    id, feature.points.front(), feature.minZoom, feature.zIndex));
            } else if (feature.points.size() > 1) {
                auto const id = kDuckDBLineMarkIdBase + lineIndex++;
                m_lineIds.insert(id);
                m_createdLineIds.insert(id);
                m_lineMarks.emplace(id, std::make_unique<DuckDBLineMark>(
                    id, feature.points, feature.minZoom, feature.zIndex));
            }
        }
    }

    kml::GroupIdSet GetAllGroupIds() const override { return m_allGroups; }
    kml::GroupIdSet const & GetUpdatedGroupIds() const override { return m_updatedGroups; }
    kml::GroupIdSet const & GetRemovedGroupIds() const override { return m_emptyGroups; }
    kml::GroupIdSet const & GetBecameVisibleGroupIds() const override { return m_emptyGroups; }
    kml::GroupIdSet const & GetBecameInvisibleGroupIds() const override { return m_emptyGroups; }
    kml::MarkIdSet const & GetCreatedMarkIds() const override { return m_createdPointIds; }
    kml::MarkIdSet const & GetRemovedMarkIds() const override { return m_removedPointIds; }
    kml::MarkIdSet const & GetUpdatedMarkIds() const override { return m_updatedPointIds; }
    kml::TrackIdSet const & GetCreatedLineIds() const override { return m_createdLineIds; }
    kml::TrackIdSet const & GetRemovedLineIds() const override { return m_removedLineIds; }
    kml::TrackIdSet const & GetUpdatedLineIds() const override { return m_updatedLineIds; }
    kml::MarkIdSet const & GetGroupPointIds(kml::MarkGroupId groupId) const override {
        return groupId == kDuckDBRenderGroupId ? m_pointIds : m_emptyPointIds;
    }
    df::UserPointMark const * GetUserPointMark(kml::MarkId markId) const override {
        auto const found = m_pointMarks.find(markId);
        return found == m_pointMarks.end() ? nullptr : found->second.get();
    }
    kml::TrackIdSet const & GetGroupLineIds(kml::MarkGroupId groupId) const override {
        return groupId == kDuckDBRenderGroupId ? m_lineIds : m_emptyLineIds;
    }
    df::UserLineMark const * GetUserLineMark(kml::TrackId lineId) const override {
        auto const found = m_lineMarks.find(lineId);
        return found == m_lineMarks.end() ? nullptr : found->second.get();
    }
    bool IsGroupVisible(kml::MarkGroupId groupId) const override {
        return groupId == kDuckDBRenderGroupId;
    }

private:
    kml::GroupIdSet m_allGroups;
    kml::GroupIdSet m_updatedGroups;
    kml::GroupIdSet m_emptyGroups;
    kml::MarkIdSet m_pointIds;
    kml::MarkIdSet m_emptyPointIds;
    kml::TrackIdSet m_lineIds;
    kml::TrackIdSet m_emptyLineIds;
    kml::MarkIdSet m_createdPointIds;
    kml::MarkIdSet m_removedPointIds;
    kml::MarkIdSet m_updatedPointIds;
    kml::TrackIdSet m_createdLineIds;
    kml::TrackIdSet m_removedLineIds;
    kml::TrackIdSet m_updatedLineIds;
    std::map<kml::MarkId, std::unique_ptr<DuckDBPointMark>> m_pointMarks;
    std::map<kml::TrackId, std::unique_ptr<DuckDBLineMark>> m_lineMarks;
};

std::mutex g_duckDBRenderMutex;
std::unique_ptr<DuckDBMarksProvider> g_duckDBMarksProvider;
bool g_duckDBRenderingEnabled = false;
std::chrono::steady_clock::time_point g_lastDuckDBRenderRefresh;
std::mutex g_viewportMutex;
std::unique_ptr<ScreenBase> g_currentScreen;

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

bool IsPointFeature(char const * geometryKind, char const * wkt) {
    std::string_view const kind = geometryKind == nullptr ? std::string_view() : std::string_view(geometryKind);
    if (kind == "point") {
        return true;
    }
    std::string_view const text = wkt == nullptr ? std::string_view() : std::string_view(wkt);
    return text.rfind("POINT", 0) == 0;
}

int ClampZoom(int zoom) {
    if (zoom < 1) {
        return 1;
    }
    if (zoom > scales::UPPER_STYLE_SCALE) {
        return scales::UPPER_STYLE_SCALE;
    }
    return zoom;
}

int32_t RefreshDuckDBRenderLayersInternal() {
    std::lock_guard<std::mutex> lock(g_duckDBRenderMutex);
    if (!g_framework || !g_drapeEngineCreated || agus_duckdb_is_open() == 0) {
        return -1;
    }

    auto engine = g_framework->GetDrapeEngine();
    if (!engine) {
        return -1;
    }

    auto const viewport = mercator::ToLatLon(g_framework->GetCurrentViewport());
    auto const zoom = ClampZoom(g_framework->GetDrawScale());
    std::vector<DuckDBRenderableGeometry> renderableFeatures;
    renderableFeatures.reserve(kDuckDBRenderFetchBatchSize);

    int32_t queryOffset = 0;
    while (queryOffset < kDuckDBRenderFetchMaxFeatures) {
        int32_t const batchLimit =
            std::min(kDuckDBRenderFetchBatchSize,
                     kDuckDBRenderFetchMaxFeatures - queryOffset);
        AgusDuckDBRenderFeature * features = nullptr;
        int32_t featureCount = 0;
        if (agus_duckdb_copy_render_features_page(
                viewport.minX(), viewport.minY(), viewport.maxX(), viewport.maxY(),
                zoom, batchLimit, queryOffset, &features, &featureCount) == 0) {
            return -2;
        }

        for (int32_t index = 0; index < featureCount; ++index) {
            auto const & feature = features[index];
            DuckDBRenderableGeometry renderable;
            renderable.isPoint = IsPointFeature(feature.geometry_kind, feature.geometry_wkt);
            renderable.minZoom = feature.min_zoom <= 0 ? 1 : feature.min_zoom;
            renderable.zIndex = feature.z_index;
            renderable.points = ParseWktMercatorPoints(feature.geometry_wkt);
            if ((renderable.isPoint && !renderable.points.empty()) ||
                (!renderable.isPoint && renderable.points.size() > 1)) {
                renderableFeatures.push_back(std::move(renderable));
            }
        }

        agus_duckdb_free_render_features(features, featureCount);
        queryOffset += featureCount;
        if (featureCount < batchLimit) {
            break;
        }
    }

    if (!g_duckDBMarksProvider) {
        g_duckDBMarksProvider = std::make_unique<DuckDBMarksProvider>();
    }
    g_duckDBMarksProvider->SetFeatures(renderableFeatures);

    engine->ClearUserMarksGroup(kDuckDBRenderGroupId);
    engine->UpdateUserMarks(g_duckDBMarksProvider.get(), true);
    engine->InvalidateUserMarks();
    g_lastDuckDBRenderRefresh = std::chrono::steady_clock::now();
    WakeRenderer();
    return static_cast<int32_t>(renderableFeatures.size());
}

bool ShouldRefreshDuckDBRenderOnViewportChange() {
    std::lock_guard<std::mutex> lock(g_duckDBRenderMutex);
    if (!g_duckDBRenderingEnabled) {
        return false;
    }
    auto const now = std::chrono::steady_clock::now();
    return now - g_lastDuckDBRenderRefresh >= kDuckDBViewportRefreshInterval;
}

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

void KeepCameraFrameActive() {
    if (!g_framework || !g_drapeEngineCreated) {
        return;
    }
    g_framework->MakeFrameActive();
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
        if (ShouldRefreshDuckDBRenderOnViewportChange()) {
            RefreshDuckDBRenderLayersInternal();
        }
    });
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
}  // namespace

static bool IsMapAlreadyRegistered(std::string const & countryName, int64_t requestedVersion) {
    if (!g_framework) {
        return false;
    }

    auto const & dataSource = g_framework->GetDataSource();
    std::vector<std::shared_ptr<MwmInfo>> mwms;
    dataSource.GetMwmsInfo(mwms);

    for (auto const & info : mwms) {
        if (!info || info->GetCountryName() != countryName) {
            continue;
        }

        int64_t const registeredVersion =
            static_cast<int64_t>(info->GetVersion());
        if (requestedVersion == 0 || requestedVersion == registeredVersion ||
            countryName == "World" || countryName == "WorldCoasts") {
            return true;
        }
    }

    return false;
}

static char* CopyString(std::string const & value) {
    const size_t size = value.size();
    char* out = static_cast<char*>(malloc(size + 1));
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

static jobject NewJavaLong(JNIEnv* env, int64_t value) {
    jclass cls = env->FindClass("java/lang/Long");
    jmethodID valueOf = env->GetStaticMethodID(cls, "valueOf", "(J)Ljava/lang/Long;");
    jobject obj = env->CallStaticObjectMethod(cls, valueOf, static_cast<jlong>(value));
    env->DeleteLocalRef(cls);
    return obj;
}

static jobject NewJavaDouble(JNIEnv* env, double value) {
    jclass cls = env->FindClass("java/lang/Double");
    jmethodID valueOf = env->GetStaticMethodID(cls, "valueOf", "(D)Ljava/lang/Double;");
    jobject obj = env->CallStaticObjectMethod(cls, valueOf, static_cast<jdouble>(value));
    env->DeleteLocalRef(cls);
    return obj;
}

static jobject NewJavaBoolean(JNIEnv* env, bool value) {
    jclass cls = env->FindClass("java/lang/Boolean");
    jmethodID valueOf = env->GetStaticMethodID(cls, "valueOf", "(Z)Ljava/lang/Boolean;");
    jobject obj = env->CallStaticObjectMethod(cls, valueOf, static_cast<jboolean>(value));
    env->DeleteLocalRef(cls);
    return obj;
}

static jobject NewArrayList(JNIEnv* env, jint capacity) {
    jclass cls = env->FindClass("java/util/ArrayList");
    jmethodID ctor = env->GetMethodID(cls, "<init>", "(I)V");
    jobject list = env->NewObject(cls, ctor, capacity);
    env->DeleteLocalRef(cls);
    return list;
}

static void ArrayListAdd(JNIEnv* env, jobject list, jobject item) {
    jclass cls = env->GetObjectClass(list);
    jmethodID add = env->GetMethodID(cls, "add", "(Ljava/lang/Object;)Z");
    env->CallBooleanMethod(list, add, item);
    env->DeleteLocalRef(cls);
}

static jobject BuildPlacePageFeatureId(JNIEnv* env, AgusPlacePageFeatureId const & fid) {
    jclass builderCls = env->FindClass(
        "app/agus/maps/agus_maps_flutter/AgusMapsApi$PlacePageFeatureId$Builder");
    jmethodID ctor = env->GetMethodID(builderCls, "<init>", "()V");
    jobject builder = env->NewObject(builderCls, ctor);

    jmethodID setMwmName = env->GetMethodID(
        builderCls, "setMwmName",
        "(Ljava/lang/String;)Lapp/agus/maps/agus_maps_flutter/AgusMapsApi$PlacePageFeatureId$Builder;");
    jmethodID setMwmVersion = env->GetMethodID(
        builderCls, "setMwmVersion",
        "(Ljava/lang/Long;)Lapp/agus/maps/agus_maps_flutter/AgusMapsApi$PlacePageFeatureId$Builder;");
    jmethodID setIndex = env->GetMethodID(
        builderCls, "setIndex",
        "(Ljava/lang/Long;)Lapp/agus/maps/agus_maps_flutter/AgusMapsApi$PlacePageFeatureId$Builder;");
    jmethodID build = env->GetMethodID(
        builderCls, "build",
        "()Lapp/agus/maps/agus_maps_flutter/AgusMapsApi$PlacePageFeatureId;");

    jstring mwmName = env->NewStringUTF(fid.mwm_name ? fid.mwm_name : "");
    jobject mwmVersion = NewJavaLong(env, fid.mwm_version);
    jobject index = NewJavaLong(env, fid.index);

    env->CallObjectMethod(builder, setMwmName, mwmName);
    env->CallObjectMethod(builder, setMwmVersion, mwmVersion);
    env->CallObjectMethod(builder, setIndex, index);

    jobject featureId = env->CallObjectMethod(builder, build);

    env->DeleteLocalRef(mwmName);
    env->DeleteLocalRef(mwmVersion);
    env->DeleteLocalRef(index);
    env->DeleteLocalRef(builder);
    env->DeleteLocalRef(builderCls);
    return featureId;
}

static jobject BuildPlacePageCoordinates(JNIEnv* env, AgusPlacePageCoordinates const & coords) {
    jclass builderCls = env->FindClass(
        "app/agus/maps/agus_maps_flutter/AgusMapsApi$PlacePageCoordinates$Builder");
    jmethodID ctor = env->GetMethodID(builderCls, "<init>", "()V");
    jobject builder = env->NewObject(builderCls, ctor);

    jmethodID setDecimal = env->GetMethodID(
        builderCls, "setDecimal",
        "(Ljava/lang/String;)Lapp/agus/maps/agus_maps_flutter/AgusMapsApi$PlacePageCoordinates$Builder;");
    jmethodID setDms = env->GetMethodID(
        builderCls, "setDms",
        "(Ljava/lang/String;)Lapp/agus/maps/agus_maps_flutter/AgusMapsApi$PlacePageCoordinates$Builder;");
    jmethodID setOsm = env->GetMethodID(
        builderCls, "setOsm",
        "(Ljava/lang/String;)Lapp/agus/maps/agus_maps_flutter/AgusMapsApi$PlacePageCoordinates$Builder;");
    jmethodID setOlc = env->GetMethodID(
        builderCls, "setOlc",
        "(Ljava/lang/String;)Lapp/agus/maps/agus_maps_flutter/AgusMapsApi$PlacePageCoordinates$Builder;");
    jmethodID setUtm = env->GetMethodID(
        builderCls, "setUtm",
        "(Ljava/lang/String;)Lapp/agus/maps/agus_maps_flutter/AgusMapsApi$PlacePageCoordinates$Builder;");
    jmethodID setMgrs = env->GetMethodID(
        builderCls, "setMgrs",
        "(Ljava/lang/String;)Lapp/agus/maps/agus_maps_flutter/AgusMapsApi$PlacePageCoordinates$Builder;");
    jmethodID build = env->GetMethodID(
        builderCls, "build",
        "()Lapp/agus/maps/agus_maps_flutter/AgusMapsApi$PlacePageCoordinates;");

    if (coords.decimal) {
        jstring value = env->NewStringUTF(coords.decimal);
        env->CallObjectMethod(builder, setDecimal, value);
        env->DeleteLocalRef(value);
    } else {
        env->CallObjectMethod(builder, setDecimal, nullptr);
    }

    if (coords.dms) {
        jstring value = env->NewStringUTF(coords.dms);
        env->CallObjectMethod(builder, setDms, value);
        env->DeleteLocalRef(value);
    } else {
        env->CallObjectMethod(builder, setDms, nullptr);
    }

    if (coords.osm) {
        jstring value = env->NewStringUTF(coords.osm);
        env->CallObjectMethod(builder, setOsm, value);
        env->DeleteLocalRef(value);
    } else {
        env->CallObjectMethod(builder, setOsm, nullptr);
    }

    if (coords.olc) {
        jstring value = env->NewStringUTF(coords.olc);
        env->CallObjectMethod(builder, setOlc, value);
        env->DeleteLocalRef(value);
    } else {
        env->CallObjectMethod(builder, setOlc, nullptr);
    }

    if (coords.utm) {
        jstring value = env->NewStringUTF(coords.utm);
        env->CallObjectMethod(builder, setUtm, value);
        env->DeleteLocalRef(value);
    } else {
        env->CallObjectMethod(builder, setUtm, nullptr);
    }

    if (coords.mgrs) {
        jstring value = env->NewStringUTF(coords.mgrs);
        env->CallObjectMethod(builder, setMgrs, value);
        env->DeleteLocalRef(value);
    } else {
        env->CallObjectMethod(builder, setMgrs, nullptr);
    }

    jobject coordinates = env->CallObjectMethod(builder, build);

    env->DeleteLocalRef(builder);
    env->DeleteLocalRef(builderCls);
    return coordinates;
}

static jobject BuildPlacePageIntMetadataEntry(
    JNIEnv* env, AgusPlacePageIntMetadataEntry const & entry) {
    jclass builderCls = env->FindClass(
        "app/agus/maps/agus_maps_flutter/AgusMapsApi$PlacePageIntMetadataEntry$Builder");
    jmethodID ctor = env->GetMethodID(builderCls, "<init>", "()V");
    jobject builder = env->NewObject(builderCls, ctor);

    jmethodID setKey = env->GetMethodID(
        builderCls, "setKey",
        "(Ljava/lang/Long;)Lapp/agus/maps/agus_maps_flutter/AgusMapsApi$PlacePageIntMetadataEntry$Builder;");
    jmethodID setValue = env->GetMethodID(
        builderCls, "setValue",
        "(Ljava/lang/String;)Lapp/agus/maps/agus_maps_flutter/AgusMapsApi$PlacePageIntMetadataEntry$Builder;");
    jmethodID build = env->GetMethodID(
        builderCls, "build",
        "()Lapp/agus/maps/agus_maps_flutter/AgusMapsApi$PlacePageIntMetadataEntry;");

    jobject key = NewJavaLong(env, entry.key);
    jstring value = env->NewStringUTF(entry.value ? entry.value : "");

    env->CallObjectMethod(builder, setKey, key);
    env->CallObjectMethod(builder, setValue, value);

    jobject metadataEntry = env->CallObjectMethod(builder, build);

    env->DeleteLocalRef(key);
    env->DeleteLocalRef(value);
    env->DeleteLocalRef(builder);
    env->DeleteLocalRef(builderCls);
    return metadataEntry;
}

static jobject BuildPlacePageStringMetadataEntry(
    JNIEnv* env, AgusPlacePageStringMetadataEntry const & entry) {
    jclass builderCls = env->FindClass(
        "app/agus/maps/agus_maps_flutter/AgusMapsApi$PlacePageStringMetadataEntry$Builder");
    jmethodID ctor = env->GetMethodID(builderCls, "<init>", "()V");
    jobject builder = env->NewObject(builderCls, ctor);

    jmethodID setKey = env->GetMethodID(
        builderCls, "setKey",
        "(Ljava/lang/String;)Lapp/agus/maps/agus_maps_flutter/AgusMapsApi$PlacePageStringMetadataEntry$Builder;");
    jmethodID setValue = env->GetMethodID(
        builderCls, "setValue",
        "(Ljava/lang/String;)Lapp/agus/maps/agus_maps_flutter/AgusMapsApi$PlacePageStringMetadataEntry$Builder;");
    jmethodID build = env->GetMethodID(
        builderCls, "build",
        "()Lapp/agus/maps/agus_maps_flutter/AgusMapsApi$PlacePageStringMetadataEntry;");

    jstring key = env->NewStringUTF(entry.key ? entry.key : "");
    jstring value = env->NewStringUTF(entry.value ? entry.value : "");

    env->CallObjectMethod(builder, setKey, key);
    env->CallObjectMethod(builder, setValue, value);

    jobject metadataEntry = env->CallObjectMethod(builder, build);

    env->DeleteLocalRef(key);
    env->DeleteLocalRef(value);
    env->DeleteLocalRef(builder);
    env->DeleteLocalRef(builderCls);
    return metadataEntry;
}

static jobject BuildPlacePageData(JNIEnv* env, AgusPlacePageData const & data) {
    jclass builderCls = env->FindClass(
        "app/agus/maps/agus_maps_flutter/AgusMapsApi$PlacePageData$Builder");
    jmethodID ctor = env->GetMethodID(builderCls, "<init>", "()V");
    jobject builder = env->NewObject(builderCls, ctor);

    jmethodID setFeatureId = env->GetMethodID(
        builderCls, "setFeatureId",
        "(Lapp/agus/maps/agus_maps_flutter/AgusMapsApi$PlacePageFeatureId;)Lapp/agus/maps/agus_maps_flutter/AgusMapsApi$PlacePageData$Builder;");
    jmethodID setObjectType = env->GetMethodID(
        builderCls, "setObjectType",
        "(Ljava/lang/Long;)Lapp/agus/maps/agus_maps_flutter/AgusMapsApi$PlacePageData$Builder;");
    jmethodID setOpeningMode = env->GetMethodID(
        builderCls, "setOpeningMode",
        "(Ljava/lang/Long;)Lapp/agus/maps/agus_maps_flutter/AgusMapsApi$PlacePageData$Builder;");
    jmethodID setTitle = env->GetMethodID(
        builderCls, "setTitle",
        "(Ljava/lang/String;)Lapp/agus/maps/agus_maps_flutter/AgusMapsApi$PlacePageData$Builder;");
    jmethodID setSecondaryTitle = env->GetMethodID(
        builderCls, "setSecondaryTitle",
        "(Ljava/lang/String;)Lapp/agus/maps/agus_maps_flutter/AgusMapsApi$PlacePageData$Builder;");
    jmethodID setSubtitle = env->GetMethodID(
        builderCls, "setSubtitle",
        "(Ljava/lang/String;)Lapp/agus/maps/agus_maps_flutter/AgusMapsApi$PlacePageData$Builder;");
    jmethodID setAddress = env->GetMethodID(
        builderCls, "setAddress",
        "(Ljava/lang/String;)Lapp/agus/maps/agus_maps_flutter/AgusMapsApi$PlacePageData$Builder;");
    jmethodID setLat = env->GetMethodID(
        builderCls, "setLat",
        "(Ljava/lang/Double;)Lapp/agus/maps/agus_maps_flutter/AgusMapsApi$PlacePageData$Builder;");
    jmethodID setLon = env->GetMethodID(
        builderCls, "setLon",
        "(Ljava/lang/Double;)Lapp/agus/maps/agus_maps_flutter/AgusMapsApi$PlacePageData$Builder;");
    jmethodID setWikiDescriptionHtml = env->GetMethodID(
        builderCls, "setWikiDescriptionHtml",
        "(Ljava/lang/String;)Lapp/agus/maps/agus_maps_flutter/AgusMapsApi$PlacePageData$Builder;");
    jmethodID setRoadType = env->GetMethodID(
        builderCls, "setRoadType",
        "(Ljava/lang/Long;)Lapp/agus/maps/agus_maps_flutter/AgusMapsApi$PlacePageData$Builder;");
    jmethodID setIsRoutePoint = env->GetMethodID(
        builderCls, "setIsRoutePoint",
        "(Ljava/lang/Boolean;)Lapp/agus/maps/agus_maps_flutter/AgusMapsApi$PlacePageData$Builder;");
    jmethodID setCoordinates = env->GetMethodID(
        builderCls, "setCoordinates",
        "(Lapp/agus/maps/agus_maps_flutter/AgusMapsApi$PlacePageCoordinates;)Lapp/agus/maps/agus_maps_flutter/AgusMapsApi$PlacePageData$Builder;");
    jmethodID setRawTypes = env->GetMethodID(
        builderCls, "setRawTypes",
        "(Ljava/util/List;)Lapp/agus/maps/agus_maps_flutter/AgusMapsApi$PlacePageData$Builder;");
    jmethodID setMetadata = env->GetMethodID(
        builderCls, "setMetadata",
        "(Ljava/util/List;)Lapp/agus/maps/agus_maps_flutter/AgusMapsApi$PlacePageData$Builder;");
    jmethodID setMetadataTags = env->GetMethodID(
        builderCls, "setMetadataTags",
        "(Ljava/util/List;)Lapp/agus/maps/agus_maps_flutter/AgusMapsApi$PlacePageData$Builder;");
    jmethodID setBookmarkId = env->GetMethodID(
        builderCls, "setBookmarkId",
        "(Ljava/lang/Long;)Lapp/agus/maps/agus_maps_flutter/AgusMapsApi$PlacePageData$Builder;");
    jmethodID setBookmarkCategoryId = env->GetMethodID(
        builderCls, "setBookmarkCategoryId",
        "(Ljava/lang/Long;)Lapp/agus/maps/agus_maps_flutter/AgusMapsApi$PlacePageData$Builder;");
    jmethodID setTrackId = env->GetMethodID(
        builderCls, "setTrackId",
        "(Ljava/lang/Long;)Lapp/agus/maps/agus_maps_flutter/AgusMapsApi$PlacePageData$Builder;");
    jmethodID build = env->GetMethodID(
        builderCls, "build",
        "()Lapp/agus/maps/agus_maps_flutter/AgusMapsApi$PlacePageData;");

    jobject featureId = BuildPlacePageFeatureId(env, data.feature_id);
    jobject coordinates = BuildPlacePageCoordinates(env, data.coordinates);
    jobject rawTypes = NewArrayList(env, data.raw_types_count);
    for (int32_t i = 0; i < data.raw_types_count; ++i) {
        jstring value = env->NewStringUTF(data.raw_types[i] ? data.raw_types[i] : "");
        ArrayListAdd(env, rawTypes, value);
        env->DeleteLocalRef(value);
    }

    jobject metadata = NewArrayList(env, data.metadata_count);
    for (int32_t i = 0; i < data.metadata_count; ++i) {
        jobject entry = BuildPlacePageIntMetadataEntry(env, data.metadata[i]);
        ArrayListAdd(env, metadata, entry);
        env->DeleteLocalRef(entry);
    }

    jobject metadataTags = NewArrayList(env, data.metadata_tags_count);
    for (int32_t i = 0; i < data.metadata_tags_count; ++i) {
        jobject entry = BuildPlacePageStringMetadataEntry(env, data.metadata_tags[i]);
        ArrayListAdd(env, metadataTags, entry);
        env->DeleteLocalRef(entry);
    }

    jobject objectType = NewJavaLong(env, data.object_type);
    jobject openingMode = NewJavaLong(env, data.opening_mode);
    jobject roadType = NewJavaLong(env, data.road_type);
    jobject lat = NewJavaDouble(env, data.lat);
    jobject lon = NewJavaDouble(env, data.lon);
    jobject isRoutePoint = NewJavaBoolean(env, data.is_route_point != 0);

    jstring title = env->NewStringUTF(data.title ? data.title : "");
    jstring secondaryTitle = env->NewStringUTF(data.secondary_title ? data.secondary_title : "");
    jstring subtitle = env->NewStringUTF(data.subtitle ? data.subtitle : "");
    jstring address = env->NewStringUTF(data.address ? data.address : "");
    jstring wiki = env->NewStringUTF(data.wiki_description_html ? data.wiki_description_html : "");

    env->CallObjectMethod(builder, setFeatureId, featureId);
    env->CallObjectMethod(builder, setObjectType, objectType);
    env->CallObjectMethod(builder, setOpeningMode, openingMode);
    env->CallObjectMethod(builder, setTitle, title);
    env->CallObjectMethod(builder, setSecondaryTitle, secondaryTitle);
    env->CallObjectMethod(builder, setSubtitle, subtitle);
    env->CallObjectMethod(builder, setAddress, address);
    env->CallObjectMethod(builder, setLat, lat);
    env->CallObjectMethod(builder, setLon, lon);
    env->CallObjectMethod(builder, setWikiDescriptionHtml, wiki);
    env->CallObjectMethod(builder, setRoadType, roadType);
    env->CallObjectMethod(builder, setIsRoutePoint, isRoutePoint);
    env->CallObjectMethod(builder, setCoordinates, coordinates);
    env->CallObjectMethod(builder, setRawTypes, rawTypes);
    env->CallObjectMethod(builder, setMetadata, metadata);
    env->CallObjectMethod(builder, setMetadataTags, metadataTags);

    if (data.has_bookmark_id) {
        jobject bookmarkId = NewJavaLong(env, data.bookmark_id);
        env->CallObjectMethod(builder, setBookmarkId, bookmarkId);
        env->DeleteLocalRef(bookmarkId);
    } else {
        env->CallObjectMethod(builder, setBookmarkId, nullptr);
    }

    if (data.has_bookmark_category_id) {
        jobject bookmarkCategoryId = NewJavaLong(env, data.bookmark_category_id);
        env->CallObjectMethod(builder, setBookmarkCategoryId, bookmarkCategoryId);
        env->DeleteLocalRef(bookmarkCategoryId);
    } else {
        env->CallObjectMethod(builder, setBookmarkCategoryId, nullptr);
    }

    if (data.has_track_id) {
        jobject trackId = NewJavaLong(env, data.track_id);
        env->CallObjectMethod(builder, setTrackId, trackId);
        env->DeleteLocalRef(trackId);
    } else {
        env->CallObjectMethod(builder, setTrackId, nullptr);
    }

    jobject placePage = env->CallObjectMethod(builder, build);

    env->DeleteLocalRef(featureId);
    env->DeleteLocalRef(coordinates);
    env->DeleteLocalRef(rawTypes);
    env->DeleteLocalRef(metadata);
    env->DeleteLocalRef(metadataTags);
    env->DeleteLocalRef(objectType);
    env->DeleteLocalRef(openingMode);
    env->DeleteLocalRef(roadType);
    env->DeleteLocalRef(lat);
    env->DeleteLocalRef(lon);
    env->DeleteLocalRef(isRoutePoint);
    env->DeleteLocalRef(title);
    env->DeleteLocalRef(secondaryTitle);
    env->DeleteLocalRef(subtitle);
    env->DeleteLocalRef(address);
    env->DeleteLocalRef(wiki);
    env->DeleteLocalRef(builder);
    env->DeleteLocalRef(builderCls);

    return placePage;
}

// Old init function for backwards compatibility (uses APK path)
FFI_PLUGIN_EXPORT void comaps_init(const char* apkPath, const char* storagePath) {
    __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", "comaps_init: apk=%s, storage=%s", apkPath, storagePath);
    AgusPlatform_Init(apkPath, storagePath);
    
    // Note: Framework initialization requires many data files (categories.txt, etc.)
    // For now we just initialize the platform; full Framework will be created when surface is ready
    __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", "comaps_init: Platform initialized, Framework deferred");
}

// New init function with explicit resource and writable paths
// NOTE: This just stores paths. Framework creation is deferred to nativeSetSurface
// to ensure Framework and CreateDrapeEngine happen on the same thread.
FFI_PLUGIN_EXPORT void comaps_init_paths(const char* resourcePath, const char* writablePath) {
    __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", "comaps_init_paths: resource=%s, writable=%s", resourcePath, writablePath);
    
    // Set up our custom log handler before doing anything else
    base::SetLogMessageFn(&AgusLogMessage);
    // Set abort level to LCRITICAL so ERROR logs don't crash
    base::g_LogAbortLevel = base::LCRITICAL;
    __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", "comaps_init_paths: Custom logging initialized");
    
    // Store paths for later use
    g_resourcePath = resourcePath;
    g_writablePath = writablePath;
    
    // Initialize platform now (sets up directories, thread infrastructure)
    AgusPlatform_InitPaths(resourcePath, writablePath);
    g_platformInitialized = true;
    
    __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", "comaps_init_paths: Platform initialized, Framework deferred to render thread");
}

FFI_PLUGIN_EXPORT void comaps_load_map_path(const char* path) {
    __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", "comaps_load_map_path: %s", path);
    
    if (g_framework) {
        // Register maps from the writable directory
        // The framework will scan the writable path for .mwm files
        g_framework->RegisterAllMaps();
        __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", "comaps_load_map_path: Maps registered");
    } else {
        __android_log_print(ANDROID_LOG_WARN, "AgusMapsFlutterNative", "comaps_load_map_path: Framework not yet initialized, maps will be loaded later");
    }
}

extern "C" void agus_localization_set_locale(const char* locale);

FFI_PLUGIN_EXPORT void comaps_set_locale(const char* localeTag) {
    __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", 
                        "comaps_set_locale: %s", localeTag ? localeTag : "(null)");
    if (localeTag && *localeTag) {
        agus_localization_set_locale(localeTag);
        __android_log_print(ANDROID_LOG_INFO, "AgusMapsFlutterNative", 
                            "comaps_set_locale: Locale set to '%s'", localeTag);
    } else {
        __android_log_print(ANDROID_LOG_WARN, "AgusMapsFlutterNative", 
                            "comaps_set_locale: Empty locale tag, using auto-detect");
    }
}

// Store current surface dimensions
static int g_surfaceWidth = 0;
static int g_surfaceHeight = 0;
static float g_density = 2.0f;

// Frame notification timing for 60fps rate limiting (Option 2)
static std::chrono::steady_clock::time_point g_lastFrameNotification;
static constexpr auto kMinFrameInterval = std::chrono::milliseconds(16); // ~60fps
static std::atomic<bool> g_frameNotificationPending{false};

// JNI global refs for frame notification callback
// g_javaVM is defined in agus_gui_thread.cpp and shared
extern JavaVM* g_javaVM;
static jobject g_pluginInstance = nullptr;
static jmethodID g_notifyFrameReadyMethod = nullptr;

/// Internal function to notify Android/Flutter about a new frame
static void notifyFlutterFrameReady() {
    // Rate limiting (Option 2): Enforce 60fps max
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
    
    // Call back to Java/Flutter on the main thread
    if (g_javaVM && g_pluginInstance && g_notifyFrameReadyMethod) {
        JNIEnv* env = nullptr;
        bool attached = false;
        
        int status = g_javaVM->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6);
        if (status == JNI_EDETACHED) {
            if (g_javaVM->AttachCurrentThread(&env, nullptr) == JNI_OK) {
                attached = true;
            } else {
                g_frameNotificationPending.store(false);
                return;
            }
        }
        
        if (env) {
            env->CallVoidMethod(g_pluginInstance, g_notifyFrameReadyMethod);
            if (env->ExceptionCheck()) {
                env->ExceptionClear();
            }
        }
        
        if (attached) {
            g_javaVM->DetachCurrentThread();
        }
    }
    
    g_frameNotificationPending.store(false);
}

static void createDrapeEngineIfNeeded(int width, int height, float density) {
    if (g_drapeEngineCreated || !g_framework) {
        return;
    }
    
    if (width <= 0 || height <= 0) {
        __android_log_print(ANDROID_LOG_WARN, "AgusMapsFlutterNative", "createDrapeEngine: Invalid dimensions %dx%d", width, height);
        return;
    }
    
    if (!g_factory) {
        __android_log_print(ANDROID_LOG_WARN, "AgusMapsFlutterNative", "createDrapeEngine: Factory not valid");
        return;
    }
    
    // Register active frame callback BEFORE creating DrapeEngine
    // This callback is invoked only when isActiveFrame is true (Option 3)
    df::SetActiveFrameCallback([]() {
        notifyFlutterFrameReady();
    });
    __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", "createDrapeEngine: Active frame callback registered");
    
    Framework::DrapeCreationParams p;
    p.m_apiVersion = dp::ApiVersion::OpenGLES3;
    p.m_surfaceWidth = width;
    p.m_surfaceHeight = height;
    p.m_visualScale = density;
    
    // Disable all widgets for now (require symbols.sdf which needs Qt6 to generate)
    // TODO: Generate symbols.sdf and enable widgets
    
    __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", "createDrapeEngine: Creating with %dx%d, scale=%.2f", width, height, density);
    g_framework->CreateDrapeEngine(make_ref(g_factory), std::move(p));
    g_drapeEngineCreated = true;
    __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", "createDrapeEngine: Drape engine created successfully");
    
    // CRITICAL: Enable rendering after DrapeEngine creation!
    // Without this, the DrapeEngine is in a disabled state and won't render.
    g_framework->SetRenderingEnabled(make_ref(g_factory));
    __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", "createDrapeEngine: Rendering enabled");
    
    // Force initial render cycle like iOS does
    g_framework->InvalidateRendering();
    g_framework->InvalidateRect(g_framework->GetCurrentViewport());
    g_framework->MakeFrameActive();
    __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", "createDrapeEngine: Initial render invalidation posted");
    
    // Kick-start the render loop by posting initial MakeFrameActive calls.
    // Without this, the DrapeEngine may not start rendering until user interaction.
    // We post a few delayed calls to ensure initial tiles are requested and rendered.
    for (int i = 0; i < 5; ++i) {
        std::thread([delay = i * 100]() {
            usleep(delay * 1000);  // delay in milliseconds
            if (g_framework && g_drapeEngineCreated) {
                g_framework->MakeFrameActive();
            }
        }).detach();
    }
    __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", "createDrapeEngine: Posted initial MakeFrameActive calls");
}

extern "C" JNIEXPORT void JNICALL
Java_app_agus_maps_agus_1maps_1flutter_AgusMapsFlutterPlugin_nativeSetSurface(
    JNIEnv* env, jobject thiz, jlong textureId, jobject surface, jint width, jint height, jfloat density) {
    
    ANativeWindow* window = ANativeWindow_fromSurface(env, surface);
    __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", 
        "nativeSetSurface: textureId=%ld, window=%p, size=%dx%d, density=%.2f", 
        textureId, window, width, height, density);
    
    if (!g_platformInitialized) {
       __android_log_print(ANDROID_LOG_ERROR, "AgusMapsFlutterNative", "Platform not initialized! Call comaps_init_paths first.");
       if (window) ANativeWindow_release(window);
       return;
    }
    
    g_surfaceWidth = width;
    g_surfaceHeight = height;
    g_density = density;

    // Create Framework on this thread if not already created
    // This ensures Framework and CreateDrapeEngine are on the same thread,
    // avoiding ThreadChecker assertion failures in BookmarkManager etc.
    if (!g_framework) {
        __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", "nativeSetSurface: Creating Framework...");
        
        FrameworkParams params;
        params.m_enableDiffs = false;
        params.m_numSearchAPIThreads = 1;
        
        // Create framework, defer map loading
        g_framework = std::make_unique<Framework>(params, false /* loadMaps */);
        SetViewportTracking();
        
        __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", "nativeSetSurface: Framework created");
        
        // Now register maps
        g_framework->RegisterAllMaps();
        __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", "nativeSetSurface: Maps registered");
    }

    // Create the OGL context factory with the native window
    auto oglFactory = new agus::AgusOGLContextFactory(window);
    if (!oglFactory->IsValid()) {
        __android_log_print(ANDROID_LOG_ERROR, "AgusMapsFlutterNative", "nativeSetSurface: Invalid OGL context");
        delete oglFactory;
        return;
    }
    
    // Update surface size from what we received (ANativeWindow might report different size)
    oglFactory->UpdateSurfaceSize(width, height);
    
    // Wrap our context factory in ThreadSafeFactory for thread-safe context creation
    g_oglFactory = oglFactory;
    g_factory = make_unique_dp<dp::ThreadSafeFactory>(oglFactory);
    
    // Create DrapeEngine with proper dimensions
    createDrapeEngineIfNeeded(width, height, density);
}

extern "C" JNIEXPORT void JNICALL
Java_app_agus_maps_agus_1maps_1flutter_AgusMapsFlutterPlugin_nativeOnSurfaceChanged(
    JNIEnv* env, jobject thiz, jlong textureId, jobject surface, jint width, jint height, jfloat density) {
    
    __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", 
        "nativeOnSurfaceChanged: size=%dx%d", width, height);
    
    ANativeWindow* window = ANativeWindow_fromSurface(env, surface);
    
    g_surfaceWidth = width;
    g_surfaceHeight = height;
    g_density = density;
    
    if (g_oglFactory) {
        g_oglFactory->ResetSurface();
        g_oglFactory->SetSurface(window);
        g_oglFactory->ResizeSurface(width, height);
    } else if (window) {
        ANativeWindow_release(window);
    }

    if (g_factory && g_framework) {
        g_framework->SetRenderingEnabled(make_ref(g_factory));
        g_framework->OnSize(width, height);
        g_framework->InvalidateRendering();
        g_framework->InvalidateRect(g_framework->GetCurrentViewport());
        g_framework->MakeFrameActive();
    }
}

extern "C" JNIEXPORT void JNICALL
Java_app_agus_maps_agus_1maps_1flutter_AgusMapsFlutterPlugin_nativeOnSurfaceDestroyed(JNIEnv* env, jobject thiz) {
    __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", "nativeOnSurfaceDestroyed");
    
    if (g_framework) {
        g_framework->SetRenderingDisabled(true /* destroySurface */);
    }

    if (g_oglFactory) {
        g_oglFactory->ResetSurface();
    }
}

extern "C" JNIEXPORT void JNICALL
Java_app_agus_maps_agus_1maps_1flutter_AgusMapsFlutterPlugin_nativeOnSizeChanged(
    JNIEnv* env, jobject thiz, jint width, jint height) {
    
    __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", 
        "nativeOnSizeChanged: %dx%d", width, height);
    
    g_surfaceWidth = width;
    g_surfaceHeight = height;
    
    if (g_oglFactory) {
        g_oglFactory->ResizeSurface(width, height);
    }

    if (g_framework && g_drapeEngineCreated) {
        g_framework->OnSize(width, height);
        g_framework->InvalidateRendering();
        g_framework->InvalidateRect(g_framework->GetCurrentViewport());
        g_framework->MakeFrameActive();
    }
}

extern "C" JNIEXPORT void JNICALL
Java_app_agus_maps_agus_1maps_1flutter_AgusMapsFlutterPlugin_nativeSetVisualScale(
    JNIEnv* env, jobject thiz, jfloat density) {
    if (density <= 0) {
        __android_log_print(ANDROID_LOG_WARN, "AgusMapsFlutterNative",
            "nativeSetVisualScale: invalid density %.2f", density);
        return;
    }

    g_density = density;

    if (g_framework && g_drapeEngineCreated) {
        df::VisualParams::Instance().SetVisualScale(static_cast<double>(density));
        g_framework->InvalidateRendering();
        __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative",
            "nativeSetVisualScale: Updated visual scale to %.2f", density);
    } else {
        __android_log_print(ANDROID_LOG_WARN, "AgusMapsFlutterNative",
            "nativeSetVisualScale: Framework not ready, stored density %.2f", density);
    }
}

extern "C" JNIEXPORT void JNICALL
Java_app_agus_maps_agus_1maps_1flutter_AgusMapsFlutterPlugin_nativeSetLocale(
    JNIEnv* env, jobject thiz, jstring localeTag) {
    if (!localeTag) return;
    const char* chars = env->GetStringUTFChars(localeTag, nullptr);
    if (chars) {
        AgusPlatform_SetLocale(chars);
        env->ReleaseStringUTFChars(localeTag, chars);
    }
}

extern "C" JNIEXPORT jobject JNICALL
Java_app_agus_maps_agus_1maps_1flutter_AgusMapsFlutterPlugin_nativeGetCurrentPlacePage(
    JNIEnv* env, jobject thiz) {
    std::lock_guard<std::mutex> lock(g_placePageMutex);
    if (!g_framework || !g_framework->HasPlacePageInfo()) {
        return nullptr;
    }

    AgusPlacePageData* snapshot = BuildPlacePageData(g_framework->GetCurrentPlacePageInfo());
    if (!snapshot) {
        return nullptr;
    }

    jobject placePage = BuildPlacePageData(env, *snapshot);
    comaps_place_page_free(snapshot);
    return placePage;
}

extern "C" JNIEXPORT void JNICALL
Java_app_agus_maps_agus_1maps_1flutter_AgusMapsFlutterPlugin_nativeClearPlacePageSelection(
    JNIEnv* env, jobject thiz) {
    (void)env;
    (void)thiz;
    comaps_place_page_clear_selection();
}

FFI_PLUGIN_EXPORT void comaps_set_view(double lat, double lon, int zoom) {
     __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", "comaps_set_view: lat=%f, lon=%f, zoom=%d", lat, lon, zoom);
     if (g_framework) {
         g_framework->SetViewportCenter(m2::PointD(mercator::FromLatLon(lat, lon)), zoom);
         // Force invalidate to ensure tiles reload
         g_framework->InvalidateRect(g_framework->GetCurrentViewport());
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
    if (!lat || !lon) {
        return 0;
    }

    std::lock_guard<std::mutex> lock(g_viewportMutex);
    if (!g_currentScreen) {
        return 0;
    }

    auto const mercatorPoint = g_currentScreen->PtoG(
        m2::PointD(physical_x, physical_y));
    auto const coordinate = mercator::ToLatLon(mercatorPoint);
    *lat = coordinate.m_lat;
    *lon = coordinate.m_lon;
    return 1;
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
    KeepCameraFrameActive();
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

FFI_PLUGIN_EXPORT int32_t agus_duckdb_refresh_render_layers(void) {
    return RefreshDuckDBRenderLayersInternal();
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
    g_duckDBMarksProvider.reset();
    if (g_framework && g_drapeEngineCreated) {
        auto engine = g_framework->GetDrapeEngine();
        if (engine) {
            engine->ClearUserMarksGroup(kDuckDBRenderGroupId);
            engine->InvalidateUserMarks();
            WakeRenderer();
        }
    }
}

FFI_PLUGIN_EXPORT void comaps_invalidate(void) {
    __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", "comaps_invalidate");
    if (g_framework) {
        g_framework->InvalidateRect(g_framework->GetCurrentViewport());
    }
}

FFI_PLUGIN_EXPORT void comaps_force_redraw(void) {
    __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", "comaps_force_redraw - triggering full tile reload");
    if (g_framework) {
        // Step 1: Update map style - clears render groups and forces tile re-request
        MapStyle currentStyle = g_framework->GetMapStyle();
        ApplyRuntimeMapStyle(currentStyle);
        
        // Step 2: InvalidateRendering posts high-priority message to force re-render
        g_framework->InvalidateRendering();
        
        // Step 3: Invalidate viewport rect
        g_framework->InvalidateRect(g_framework->GetCurrentViewport());
    }
}

// Touch event types matching df::TouchEvent::ETouchType
// 0 = TOUCH_NONE, 1 = TOUCH_DOWN, 2 = TOUCH_MOVE, 3 = TOUCH_UP, 4 = TOUCH_CANCEL
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
}

FFI_PLUGIN_EXPORT void comaps_scale(double factor, double pixelX, double pixelY, int animated) {
    if (!g_framework || !g_drapeEngineCreated) {
        return;
    }
    
    // Scale the map by the given factor, centered on the pixel point
    // This is the preferred method for scroll wheel zoom on desktop platforms
    g_framework->Scale(factor, m2::PointD(pixelX, pixelY), animated != 0);
}

FFI_PLUGIN_EXPORT void comaps_scroll(double distanceX, double distanceY) {
    if (!g_framework || !g_drapeEngineCreated) {
        return;
    }
    
    // Scroll the map by the given distance
    g_framework->Scroll(distanceX, distanceY);
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

// Register a single MWM map file directly by full path.
// This bypasses the version folder scanning and registers the map file
// directly with the rendering engine using LocalCountryFile::MakeTemporary.
FFI_PLUGIN_EXPORT int comaps_register_single_map(const char* fullPath) {
    return comaps_register_single_map_with_version(fullPath, 0 /* version */);
}

FFI_PLUGIN_EXPORT int comaps_register_single_map_with_version(const char* fullPath, int64_t version) {
    __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative",
        "comaps_register_single_map_with_version: %s (version=%lld)",
        fullPath, static_cast<long long>(version));

    if (!g_framework) {
        __android_log_print(ANDROID_LOG_ERROR, "AgusMapsFlutterNative",
            "comaps_register_single_map_with_version: Framework not initialized");
        return -1;  // Error: Framework not ready
    }

    try {
        std::string path(fullPath ? fullPath : "");
        if (path.empty()) {
            __android_log_print(ANDROID_LOG_ERROR, "AgusMapsFlutterNative",
                "comaps_register_single_map_with_version: Empty path");
            return -2;
        }

        // Derive country name from filename (without extension), matching MakeTemporary().
        auto name = path;
        base::GetNameFromFullPath(name);
        base::GetNameWithoutExt(name);

        if (IsMapAlreadyRegistered(name, version)) {
            __android_log_print(ANDROID_LOG_INFO, "AgusMapsFlutterNative",
                "comaps_register_single_map_with_version: %s already registered, skipping",
                name.c_str());
            return 0;
        }

        platform::LocalCountryFile file(base::GetDirectory(path), platform::CountryFile(std::move(name)), version);
        file.SyncWithDisk();

        auto result = g_framework->RegisterMap(file);
        if (result.second == MwmSet::RegResult::Success) {
            __android_log_print(ANDROID_LOG_INFO, "AgusMapsFlutterNative",
                "comaps_register_single_map_with_version: Successfully registered %s", fullPath);
            return 0;  // Success
        } else {
            __android_log_print(ANDROID_LOG_WARN, "AgusMapsFlutterNative",
                "comaps_register_single_map_with_version: Failed to register %s, result=%d",
                fullPath, static_cast<int>(result.second));
            return static_cast<int>(result.second);
        }
    } catch (std::exception const & e) {
        __android_log_print(ANDROID_LOG_ERROR, "AgusMapsFlutterNative",
            "comaps_register_single_map_with_version: Exception: %s", e.what());
        return -2;  // Error: Exception
    }
}

// Debug function to list all registered MWMs and their bounds
FFI_PLUGIN_EXPORT void comaps_debug_list_mwms() {
    __android_log_print(ANDROID_LOG_INFO, "AgusMapsFlutterNative", 
        "=== DEBUG: Listing all registered MWMs ===");
    
    if (!g_framework) {
        __android_log_print(ANDROID_LOG_ERROR, "AgusMapsFlutterNative", 
            "comaps_debug_list_mwms: Framework not initialized");
        return;
    }
    
    auto const & dataSource = g_framework->GetDataSource();
    std::vector<std::shared_ptr<MwmInfo>> mwms;
    dataSource.GetMwmsInfo(mwms);
    
    __android_log_print(ANDROID_LOG_INFO, "AgusMapsFlutterNative", 
        "Total registered MWMs: %zu", mwms.size());
    
    for (auto const & info : mwms) {
        auto const & bounds = info->m_bordersRect;
        const char* typeStr = "UNKNOWN";
        switch (info->GetType()) {
            case MwmInfo::COUNTRY: typeStr = "COUNTRY"; break;
            case MwmInfo::COASTS: typeStr = "COASTS"; break;
            case MwmInfo::WORLD: typeStr = "WORLD"; break;
        }
        
        __android_log_print(ANDROID_LOG_INFO, "AgusMapsFlutterNative", 
            "  MWM: %s [%s] version=%lld scales=[%d-%d] bounds=[%.4f,%.4f - %.4f,%.4f] status=%d",
            info->GetCountryName().c_str(),
            typeStr,
            static_cast<long long>(info->GetVersion()),
            info->m_minScale,
            info->m_maxScale,
            bounds.minX(), bounds.minY(),
            bounds.maxX(), bounds.maxY(),
            static_cast<int>(info->GetStatus()));
    }
    
    __android_log_print(ANDROID_LOG_INFO, "AgusMapsFlutterNative", 
        "=== END MWM list ===");
}

// Debug function to check if a point is covered by any MWM
FFI_PLUGIN_EXPORT void comaps_debug_check_point(double lat, double lon) {
    __android_log_print(ANDROID_LOG_INFO, "AgusMapsFlutterNative", 
        "=== DEBUG: Checking point coverage lat=%.6f, lon=%.6f ===", lat, lon);
    
    if (!g_framework) {
        __android_log_print(ANDROID_LOG_ERROR, "AgusMapsFlutterNative", 
            "comaps_debug_check_point: Framework not initialized");
        return;
    }
    
    // Convert to Mercator coordinates (what the engine uses internally)
    m2::PointD const pt = mercator::FromLatLon(lat, lon);
    __android_log_print(ANDROID_LOG_INFO, "AgusMapsFlutterNative", 
        "Mercator coords: x=%.6f, y=%.6f", pt.x, pt.y);
    
    auto const & dataSource = g_framework->GetDataSource();
    std::vector<std::shared_ptr<MwmInfo>> mwms;
    dataSource.GetMwmsInfo(mwms);
    
    int coveringCount = 0;
    for (auto const & info : mwms) {
        if (info->m_bordersRect.IsPointInside(pt)) {
            coveringCount++;
            __android_log_print(ANDROID_LOG_INFO, "AgusMapsFlutterNative", 
                "  COVERS: %s [scales %d-%d]",
                info->GetCountryName().c_str(),
                info->m_minScale, info->m_maxScale);
        }
    }
    
    if (coveringCount == 0) {
        __android_log_print(ANDROID_LOG_WARN, "AgusMapsFlutterNative", 
            "  NO MWM covers this point!");
    } else {
        __android_log_print(ANDROID_LOG_INFO, "AgusMapsFlutterNative", 
            "Point covered by %d MWMs", coveringCount);
    }
    
    __android_log_print(ANDROID_LOG_INFO, "AgusMapsFlutterNative", 
        "=== END point check ===");
}

// Initialize frame notification callback - called from Kotlin/Java plugin
extern "C" JNIEXPORT void JNICALL
Java_app_agus_maps_agus_1maps_1flutter_AgusMapsFlutterPlugin_nativeInitFrameCallback(
    JNIEnv* env, jobject thiz) {
    
    // Create global reference to plugin instance
    if (g_pluginInstance) {
        env->DeleteGlobalRef(g_pluginInstance);
    }
    g_pluginInstance = env->NewGlobalRef(thiz);
    
    // Get the method ID for onFrameReady callback
    jclass cls = env->GetObjectClass(thiz);
    g_notifyFrameReadyMethod = env->GetMethodID(cls, "onFrameReady", "()V");
    
    if (g_notifyFrameReadyMethod) {
        __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", 
            "nativeInitFrameCallback: Frame notification callback initialized");
    } else {
        __android_log_print(ANDROID_LOG_ERROR, "AgusMapsFlutterNative", 
            "nativeInitFrameCallback: Failed to find onFrameReady method");
    }
}

// Cleanup frame notification callback
extern "C" JNIEXPORT void JNICALL
Java_app_agus_maps_agus_1maps_1flutter_AgusMapsFlutterPlugin_nativeCleanupFrameCallback(
    JNIEnv* env, jobject thiz) {
    
    if (g_pluginInstance) {
        env->DeleteGlobalRef(g_pluginInstance);
        g_pluginInstance = nullptr;
    }
    g_notifyFrameReadyMethod = nullptr;
    
    // Clear the active frame callback
    df::SetActiveFrameCallback(nullptr);
    
    __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", 
        "nativeCleanupFrameCallback: Frame notification callback cleaned up");
}
