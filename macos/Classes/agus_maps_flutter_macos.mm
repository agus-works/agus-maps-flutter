/// agus_maps_flutter_macos.mm
/// 
/// macOS FFI implementation for agus_maps_flutter.
/// This provides the C FFI functions that Dart FFI calls on macOS.
/// 
/// This file implements the full CoMaps Framework integration for macOS,
/// using Metal for rendering via CVPixelBuffer/IOSurface zero-copy texture sharing.

#include "../src/agus_maps_flutter.h"

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <CoreVideo/CoreVideo.h>

#include <stdlib.h>
#include <unistd.h>
#include <string>
#include <memory>
#include <atomic>
#include <algorithm>
#include <chrono>
#include <map>
#include <mutex>
#include <set>
#include <iterator>
#include <sstream>
#include <iomanip>
#include <string_view>
#include <cstring>
#include <cmath>

// CoMaps Framework includes
#include <vector>
#include <utility>

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
#include "drape_frontend/visual_params.hpp"
#include "drape_frontend/user_event_stream.hpp"
#include "drape_frontend/active_frame_callback.hpp"
#include "drape_frontend/user_marks_provider.hpp"
#include "drape_frontend/drape_api.hpp"
#include "geometry/mercator.hpp"
#include "geometry/screenbase.hpp"
#include "agus_navigation_bridge.hpp"
#include "agus_search_bridge.hpp"

// Our Metal context factory
#include "AgusMetalContextFactory.h"

#if defined(NDEBUG) || defined(RELEASE)
#define AGUS_DEBUG_LOG(...) do {} while (0)
#else
#define AGUS_DEBUG_LOG(...) NSLog(__VA_ARGS__)
#endif

// Forward declarations for AgusPlatformMacOS (defined in AgusPlatformMacOS.mm)
extern "C" void AgusPlatformMacOS_InitPaths(const char* resourcePath, const char* writablePath);
extern "C" void* AgusPlatformMacOS_GetInstance(void);

#pragma mark - Global State

static std::unique_ptr<Framework> g_framework;
static drape_ptr<dp::ThreadSafeFactory> g_threadSafeFactory;
static agus::AgusMetalContextFactory* g_metalContextFactory = nullptr;  // Raw pointer to access SetPixelBuffer
static std::string g_resourcePath;
static std::string g_writablePath;
static std::string g_explicitLocaleTag;
static bool g_platformInitialized = false;
static bool g_drapeEngineCreated = false;
static std::mutex g_placePageMutex;
static double g_currentBearingDegrees = 0.0;
static bool g_3dBuildingsEnabled = false;
static bool g_outdoorsEnabled = false;
static bool g_isolinesEnabled = false;
static bool g_subwayEnabled = false;
// Render keep-alive to push a few extra frames while tiles/fonts load
static dispatch_source_t g_renderKeepAliveTimer = nil;
static int g_renderKeepAliveCount = 0;
static const int kRenderKeepAliveMaxCount = 20; // ~0.66s at 30Hz

// Forward declarations
static void notifyFlutterFrameReady(void);
static void startRenderKeepAliveTimer(void);
static void stopRenderKeepAliveTimer(void);

namespace
{
double constexpr kDegreesPerRadian = 180.0 / 3.14159265358979323846;
double constexpr kRadiansPerDegree = 3.14159265358979323846 / 180.0;
kml::MarkGroupId constexpr kDuckDBRenderGroupId = 1ULL << 60;
kml::MarkGroupId constexpr kDuckDBEditGroupId = kDuckDBRenderGroupId + 1;
kml::MarkId constexpr kDuckDBPointMarkIdBase = kDuckDBRenderGroupId + 1;
kml::TrackId constexpr kDuckDBLineMarkIdBase = kDuckDBRenderGroupId + (1ULL << 20);
kml::MarkId constexpr kDuckDBEditPointMarkIdBase = kDuckDBEditGroupId + 1;
kml::TrackId constexpr kDuckDBEditLineMarkIdBase = kDuckDBEditGroupId + (1ULL << 20);
int32_t constexpr kDuckDBInteractionInactive = 0;
int32_t constexpr kDuckDBInteractionDrawing = 1;
int32_t constexpr kDuckDBInteractionEditingFeature = 2;
int32_t constexpr kDuckDBRenderFetchBatchSize = 1000;
int32_t constexpr kDuckDBRenderFetchMaxFeatures = 10000;
auto constexpr kDuckDBViewportRefreshInterval = std::chrono::milliseconds(250);

struct DuckDBInteractionLineStyle {
    dp::Color color = dp::Color(37, 99, 235, 235);
    float width = 2.0f;
    bool dashed = false;
    double dashLength = 10.0;
    double gapLength = 6.0;
};

void WakeRenderer();
std::vector<std::vector<m2::PointD>> BuildInteractionLineGeometries(
    std::vector<m2::PointD> const & points,
    DuckDBInteractionLineStyle const & style);

template <typename Set>
void AssignSetDifference(Set const & left, Set const & right, Set & output) {
    output.clear();
    std::set_difference(
        left.begin(), left.end(),
        right.begin(), right.end(),
        std::inserter(output, output.end()),
        left.key_comp());
}

struct DuckDBRenderableGeometry {
    bool isPoint = false;
    int minZoom = 1;
    int zIndex = 0;
    std::vector<m2::PointD> points;
};

struct DuckDBRenderViewport {
    double minLon = 0.0;
    double minLat = 0.0;
    double maxLon = 0.0;
    double maxLat = 0.0;
};

class DuckDBPointMark final : public df::UserPointMark {
public:
    DuckDBPointMark(kml::MarkId id, m2::PointD const & pivot, int minZoom,
                    int zIndex, kml::MarkGroupId groupId = kDuckDBRenderGroupId,
                    dp::Color color = dp::Color(0, 122, 255, 255),
                    float radius = 6.5f)
        : df::UserPointMark(id), m_pivot(pivot), m_minZoom(std::max(1, minZoom)),
          m_zIndex(zIndex), m_groupId(groupId) {
        auto const visualScale = static_cast<float>(df::VisualParams::Instance().GetVisualScale());
        df::ColoredSymbolViewParams params;
        params.m_outlineColor = dp::Color::White();
        params.m_outlineWidth = 2.0f * visualScale;
        params.m_radiusInPixels = radius * visualScale;
        params.m_color = color;
        m_coloredSymbols.m_needOverlay = false;
        m_coloredSymbols.m_zoomInfo.emplace(1, params);
    }

    kml::MarkGroupId GetGroupId() const override { return m_groupId; }
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
    kml::MarkGroupId m_groupId;
    ColoredSymbolZoomInfo m_coloredSymbols;
    mutable bool m_dirty = true;
};

class DuckDBLineMark final : public df::UserLineMark {
public:
    DuckDBLineMark(kml::TrackId id, std::vector<m2::PointD> points, int minZoom,
                   int zIndex, kml::MarkGroupId groupId = kDuckDBRenderGroupId,
                   dp::Color color = dp::Color(0, 122, 255, 220),
                   float width = 4.0f,
                   df::DepthLayer depthLayer = df::DepthLayer::UserLineLayer)
        : df::UserLineMark(id), m_geometries({std::move(points)}),
          m_minZoom(std::max(1, minZoom)), m_zIndex(zIndex),
          m_groupId(groupId), m_color(color), m_depthLayer(depthLayer) {
        m_width = width;
    }

    DuckDBLineMark(kml::TrackId id, std::vector<std::vector<m2::PointD>> geometries,
                   int minZoom, int zIndex, kml::MarkGroupId groupId,
                   DuckDBInteractionLineStyle const & style,
                   df::DepthLayer depthLayer = df::DepthLayer::UserLineLayer)
        : df::UserLineMark(id), m_geometries(std::move(geometries)),
          m_minZoom(std::max(1, minZoom)), m_zIndex(zIndex),
          m_groupId(groupId), m_color(style.color), m_depthLayer(depthLayer) {
        m_width = style.width;
    }

    kml::MarkGroupId GetGroupId() const override { return m_groupId; }
    bool IsDirty() const override { return m_dirty; }
    void ResetChanges() const override { m_dirty = false; }
    int GetMinZoom() const override { return m_minZoom; }
    df::DepthLayer GetDepthLayer() const override { return m_depthLayer; }
    size_t GetLayerCount() const override { return 1; }
    dp::Color GetColor(size_t /* layerIndex */) const override {
        return m_color;
    }
    float GetWidth(size_t /* layerIndex */) const override { return m_width; }
    float GetDepth(size_t layerIndex) const override {
        return static_cast<float>(layerIndex) * 10.0f;
    }
    void ForEachGeometry(GeometryFnT && fn) const override {
        for (auto const & points : m_geometries) {
            if (points.size() > 1) {
                fn(std::vector<m2::PointD>(points));
            }
        }
    }

    size_t GetGeometryCount() const { return m_geometries.size(); }
    size_t GetPointCount() const {
        size_t pointCount = 0;
        for (auto const & points : m_geometries) {
            pointCount += points.size();
        }
        return pointCount;
    }
    float GetBaseWidth() const { return m_width; }
    float GetBaseDepth() const { return GetDepth(0); }
    char const * GetDepthLayerName() const {
        return m_depthLayer == df::DepthLayer::UserLineLayer ? "UserLineLayer" : "Other";
    }

private:
    std::vector<std::vector<m2::PointD>> m_geometries;
    float m_width = 4.0f;
    int m_minZoom;
    int m_zIndex;
    kml::MarkGroupId m_groupId;
    dp::Color m_color;
    df::DepthLayer m_depthLayer;
    mutable bool m_dirty = true;
};

class DuckDBMarksProvider final : public df::UserMarksProvider {
public:
    DuckDBMarksProvider() {
        m_allGroups.insert(kDuckDBRenderGroupId);
        m_allGroups.insert(kDuckDBEditGroupId);
    }

    void SetFeatures(std::vector<DuckDBRenderableGeometry> const & features) {
        auto const previousPointIds = m_pointIds;
        auto const previousLineIds = m_lineIds;
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
        if (m_editVisible) {
            m_updatedGroups.insert(kDuckDBEditGroupId);
        }

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

        AssignSetDifference(m_pointIds, previousPointIds, m_createdPointIds);
        AssignSetDifference(previousPointIds, m_pointIds, m_removedPointIds);
        AssignSetDifference(m_lineIds, previousLineIds, m_createdLineIds);
        AssignSetDifference(previousLineIds, m_lineIds, m_removedLineIds);

        m_updatedPointIds = m_pointIds;
        m_updatedLineIds = m_lineIds;
    }

    void SetEditHandles(
        std::vector<std::vector<m2::PointD>> const & geometries,
        int32_t interactionMode,
        DuckDBInteractionLineStyle const & lineStyle) {
        auto const previousEditPointIds = m_editCombinedPointIds;
        auto const previousEditLineIds = m_editLineIds;
        bool const wasEditVisible = m_editVisible;
        m_editPointMarks.clear();
        m_editLineMarks.clear();
        m_editPointIds.clear();
        m_editCombinedPointIds.clear();
        m_editLineIds.clear();
        m_createdPointIds.clear();
        m_createdLineIds.clear();
        m_updatedPointIds.clear();
        m_updatedLineIds.clear();
        m_removedPointIds.clear();
        m_removedLineIds.clear();
        m_updatedGroups.clear();
        m_becameVisibleGroups.clear();
        m_becameInvisibleGroups.clear();
        m_updatedGroups.insert(kDuckDBEditGroupId);
        m_interactionMode = interactionMode;
        m_editVisible = m_interactionMode != kDuckDBInteractionInactive && !geometries.empty();
        if (!wasEditVisible && m_editVisible) {
            m_becameVisibleGroups.insert(kDuckDBEditGroupId);
        } else if (wasEditVisible && !m_editVisible) {
            m_becameInvisibleGroups.insert(kDuckDBEditGroupId);
        }
        auto const color = m_interactionMode == kDuckDBInteractionDrawing
            ? dp::Color(0, 200, 120, 255)
            : dp::Color(255, 149, 0, 255);

        size_t pointIndex = 0;
        size_t lineIndex = 0;
        for (auto const & points : geometries) {
            for (auto const & point : points) {
                auto const id = kDuckDBEditPointMarkIdBase + pointIndex++;
                m_editPointIds.insert(id);
                m_editPointMarks.emplace(id, std::make_unique<DuckDBPointMark>(
                    id, point, 1, 65535, kDuckDBEditGroupId,
                    color, 8.0f));
            }
            if (points.size() > 1) {
                auto const id = kDuckDBEditLineMarkIdBase + lineIndex++;
                m_editLineIds.insert(id);
                m_editLineMarks.emplace(id, std::make_unique<DuckDBLineMark>(
                    id, BuildInteractionLineGeometries(points, lineStyle),
                    1, 65535, kDuckDBEditGroupId, lineStyle));
            }
        }

        m_editCombinedPointIds.insert(m_editPointIds.begin(), m_editPointIds.end());

        AssignSetDifference(m_editCombinedPointIds, previousEditPointIds, m_createdPointIds);
        AssignSetDifference(previousEditPointIds, m_editCombinedPointIds, m_removedPointIds);
        AssignSetDifference(m_editLineIds, previousEditLineIds, m_createdLineIds);
        AssignSetDifference(previousEditLineIds, m_editLineIds, m_removedLineIds);

        m_updatedPointIds = m_editCombinedPointIds;
        m_updatedLineIds = m_editLineIds;
    }

    size_t GetCommittedPointMarkCount() const { return m_pointIds.size(); }
    size_t GetCommittedLineMarkCount() const { return m_lineIds.size(); }
    size_t GetInteractionPointMarkCount() const { return m_editPointIds.size(); }
    size_t GetInteractionLineMarkCount() const { return m_editLineIds.size(); }
    size_t GetInteractionLineGeometryCount() const {
        size_t geometryCount = 0;
        for (auto const & entry : m_editLineMarks) {
            geometryCount += entry.second->GetGeometryCount();
        }
        return geometryCount;
    }
    size_t GetInteractionLinePointCount() const {
        size_t pointCount = 0;
        for (auto const & entry : m_editLineMarks) {
            pointCount += entry.second->GetPointCount();
        }
        return pointCount;
    }
    float GetInteractionLineBaseWidth() const {
        if (m_editLineMarks.empty()) {
            return 0.0f;
        }
        return m_editLineMarks.begin()->second->GetBaseWidth();
    }
    float GetInteractionLineBaseDepth() const {
        if (m_editLineMarks.empty()) {
            return 0.0f;
        }
        return m_editLineMarks.begin()->second->GetBaseDepth();
    }
    char const * GetInteractionLineDepthLayerName() const {
        if (m_editLineMarks.empty()) {
            return "none";
        }
        return m_editLineMarks.begin()->second->GetDepthLayerName();
    }

    kml::GroupIdSet GetAllGroupIds() const override { return m_allGroups; }
    kml::GroupIdSet const & GetUpdatedGroupIds() const override { return m_updatedGroups; }
    kml::GroupIdSet const & GetRemovedGroupIds() const override { return m_emptyGroups; }
    kml::GroupIdSet const & GetBecameVisibleGroupIds() const override { return m_becameVisibleGroups; }
    kml::GroupIdSet const & GetBecameInvisibleGroupIds() const override { return m_becameInvisibleGroups; }
    kml::MarkIdSet const & GetCreatedMarkIds() const override { return m_createdPointIds; }
    kml::MarkIdSet const & GetRemovedMarkIds() const override { return m_removedPointIds; }
    kml::MarkIdSet const & GetUpdatedMarkIds() const override { return m_updatedPointIds; }
    kml::TrackIdSet const & GetCreatedLineIds() const override { return m_createdLineIds; }
    kml::TrackIdSet const & GetRemovedLineIds() const override { return m_removedLineIds; }
    kml::TrackIdSet const & GetUpdatedLineIds() const override { return m_updatedLineIds; }
    kml::MarkIdSet const & GetGroupPointIds(kml::MarkGroupId groupId) const override {
        if (groupId == kDuckDBRenderGroupId) return m_pointIds;
        if (groupId == kDuckDBEditGroupId) return m_editCombinedPointIds;
        return m_emptyPointIds;
    }
    df::UserPointMark const * GetUserPointMark(kml::MarkId markId) const override {
        auto const found = m_pointMarks.find(markId);
        if (found != m_pointMarks.end()) return found->second.get();
        auto const editFound = m_editPointMarks.find(markId);
        if (editFound != m_editPointMarks.end()) return editFound->second.get();
        return nullptr;
    }
    kml::TrackIdSet const & GetGroupLineIds(kml::MarkGroupId groupId) const override {
        if (groupId == kDuckDBRenderGroupId) return m_lineIds;
        if (groupId == kDuckDBEditGroupId) return m_editLineIds;
        return m_emptyLineIds;
    }
    df::UserLineMark const * GetUserLineMark(kml::TrackId lineId) const override {
        auto const found = m_lineMarks.find(lineId);
        if (found != m_lineMarks.end()) return found->second.get();
        auto const editFound = m_editLineMarks.find(lineId);
        return editFound == m_editLineMarks.end() ? nullptr : editFound->second.get();
    }
    bool IsGroupVisible(kml::MarkGroupId groupId) const override {
        return groupId == kDuckDBRenderGroupId ||
               (groupId == kDuckDBEditGroupId && m_editVisible);
    }

private:
    kml::GroupIdSet m_allGroups;
    kml::GroupIdSet m_updatedGroups;
    kml::GroupIdSet m_emptyGroups;
    kml::GroupIdSet m_becameVisibleGroups;
    kml::GroupIdSet m_becameInvisibleGroups;
    kml::MarkIdSet m_pointIds;
    kml::MarkIdSet m_editPointIds;
    kml::MarkIdSet m_editCombinedPointIds;
    kml::MarkIdSet m_emptyPointIds;
    kml::TrackIdSet m_lineIds;
    kml::TrackIdSet m_editLineIds;
    kml::TrackIdSet m_emptyLineIds;
    kml::MarkIdSet m_createdPointIds;
    kml::MarkIdSet m_removedPointIds;
    kml::MarkIdSet m_updatedPointIds;
    kml::TrackIdSet m_createdLineIds;
    kml::TrackIdSet m_removedLineIds;
    kml::TrackIdSet m_updatedLineIds;
    std::map<kml::MarkId, std::unique_ptr<DuckDBPointMark>> m_pointMarks;
    std::map<kml::MarkId, std::unique_ptr<DuckDBPointMark>> m_editPointMarks;
    std::map<kml::TrackId, std::unique_ptr<DuckDBLineMark>> m_lineMarks;
    std::map<kml::TrackId, std::unique_ptr<DuckDBLineMark>> m_editLineMarks;
    int32_t m_interactionMode = kDuckDBInteractionInactive;
    bool m_editVisible = false;
};

std::mutex g_duckDBRenderMutex;
std::unique_ptr<DuckDBMarksProvider> g_duckDBMarksProvider;
bool g_duckDBRenderingEnabled = false;
std::chrono::steady_clock::time_point g_lastDuckDBRenderRefresh;
std::set<std::string> g_duckDBCommittedDrapeLineIds;
std::set<std::string> g_duckDBInteractionDrapeLineIds;
std::mutex g_viewportMutex;
std::unique_ptr<ScreenBase> g_currentScreen;
std::mutex g_mapPointerMutex;

struct AgusMapPointerState {
    double physicalX = 0.0;
    double physicalY = 0.0;
    double lat = 0.0;
    double lon = 0.0;
    bool insideMap = false;
    bool hasCoordinate = false;
};

AgusMapPointerState g_lastMapPointer;

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
    dp::Color color,
    float width,
    bool dashed,
    double dashLength,
    double gapLength) {
    if (!g_framework || !g_drapeEngineCreated) {
        return;
    }

    std::set<std::string> nextIds;
    size_t lineIndex = 0;
    for (auto const & points : lineGeometries) {
        std::vector<std::vector<m2::PointD>> renderGeometries;
        if (dashed) {
            DuckDBInteractionLineStyle dashStyle;
            dashStyle.dashed = true;
            dashStyle.dashLength = dashLength;
            dashStyle.gapLength = gapLength;
            renderGeometries = BuildInteractionLineGeometries(points, dashStyle);
        } else {
            renderGeometries = points.size() > 1
                ? std::vector<std::vector<m2::PointD>>{points}
                : std::vector<std::vector<m2::PointD>>{};
        }
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
                df::DrapeApiLineData(renderPoints, color).Width(width));
        }
        ++lineIndex;
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

DuckDBRenderViewport GetDuckDBRenderViewport() {
    auto const latLonRect = mercator::ToLatLon(g_framework->GetCurrentViewport());
    return {
        std::min(latLonRect.minY(), latLonRect.maxY()),
        std::min(latLonRect.minX(), latLonRect.maxX()),
        std::max(latLonRect.minY(), latLonRect.maxY()),
        std::max(latLonRect.minX(), latLonRect.maxX()),
    };
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

    auto const viewport = GetDuckDBRenderViewport();
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
                viewport.minLon, viewport.minLat, viewport.maxLon, viewport.maxLat,
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
    std::vector<std::vector<m2::PointD>> committedLineGeometries;
    for (auto const & feature : renderableFeatures) {
        if (!feature.isPoint && feature.points.size() > 1) {
            committedLineGeometries.push_back(feature.points);
        }
    }
    UpdateDuckDBDrapeApiLines(
        g_duckDBCommittedDrapeLineIds,
        committedLineGeometries,
        "duckdb-committed",
        dp::Color(71, 85, 105, 150),
        2.0f,
        false,
        10.0,
        6.0);
    AGUS_DEBUG_LOG(
        @"[AgusMapsFlutter] DuckDB committed render geometry: features=%zu pointMarks=%zu lineMarks=%zu drapeApiLines=%zu renderer=DrapeApiLineData baseWidth=2.00 depthTest=0 style=existing-visible",
        renderableFeatures.size(),
        g_duckDBMarksProvider->GetCommittedPointMarkCount(),
        g_duckDBMarksProvider->GetCommittedLineMarkCount(),
        g_duckDBCommittedDrapeLineIds.size());

    engine->UpdateUserMarks(g_duckDBMarksProvider.get(), true);
    engine->ChangeVisibilityUserMarksGroup(kDuckDBRenderGroupId, true);
    engine->InvalidateUserMarks();
    g_lastDuckDBRenderRefresh = std::chrono::steady_clock::now();
    WakeRenderer();
    return static_cast<int32_t>(renderableFeatures.size());
}

void UpdateDuckDBEditHandlesInternal(
    char const * wkt,
    int32_t interactionMode,
    DuckDBInteractionLineStyle const & lineStyle = DuckDBInteractionLineStyle()) {
    std::lock_guard<std::mutex> lock(g_duckDBRenderMutex);
    if (!g_framework || !g_drapeEngineCreated) {
        return;
    }
    auto engine = g_framework->GetDrapeEngine();
    if (!engine) {
        return;
    }

    if (!g_duckDBMarksProvider) {
        g_duckDBMarksProvider = std::make_unique<DuckDBMarksProvider>();
    }
    auto const geometries = ParseWktMercatorGeometries(wkt);
    size_t pointCount = 0;
    size_t lineCount = 0;
    for (auto const & points : geometries) {
        pointCount += points.size();
        if (points.size() > 1) {
            ++lineCount;
        }
    }
    g_duckDBMarksProvider->SetEditHandles(
        geometries, interactionMode, lineStyle);
    UpdateDuckDBDrapeApiLines(
        g_duckDBInteractionDrapeLineIds,
        geometries,
        "duckdb-interaction",
        lineStyle.color,
        lineStyle.width,
        lineStyle.dashed,
        lineStyle.dashLength,
        lineStyle.gapLength);
    AGUS_DEBUG_LOG(
        @"[AgusMapsFlutter] DuckDB interaction geometry: mode=%d geometries=%zu points=%zu lines=%zu lineMarks=%zu drapeApiLines=%zu renderer=DrapeApiLineData depthTest=0 lineGeometries=%zu linePoints=%zu depth=%s baseWidth=%.2f baseDepth=%.2f lineWidth=%.2f opacity=%u dashed=%d",
        interactionMode,
        geometries.size(),
        pointCount,
        lineCount,
        g_duckDBMarksProvider->GetInteractionLineMarkCount(),
        g_duckDBInteractionDrapeLineIds.size(),
        g_duckDBMarksProvider->GetInteractionLineGeometryCount(),
        g_duckDBMarksProvider->GetInteractionLinePointCount(),
        g_duckDBMarksProvider->GetInteractionLineDepthLayerName(),
        g_duckDBMarksProvider->GetInteractionLineBaseWidth(),
        g_duckDBMarksProvider->GetInteractionLineBaseDepth(),
        lineStyle.width,
        lineStyle.color.GetAlpha(),
        lineStyle.dashed ? 1 : 0);
    engine->UpdateUserMarks(g_duckDBMarksProvider.get(), true);
    engine->ChangeVisibilityUserMarksGroup(
        kDuckDBEditGroupId,
        interactionMode != kDuckDBInteractionInactive && !geometries.empty());
    engine->InvalidateUserMarks();
    WakeRenderer();
}

void ClearDuckDBEditHandlesInternal() {
    ClearDuckDBDrapeApiLines(g_duckDBInteractionDrapeLineIds);
    UpdateDuckDBEditHandlesInternal(nullptr, kDuckDBInteractionInactive);
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

static std::string NormalizeTypeKey(std::string const & type) {
    std::string key = type;
    if (key.rfind("type.", 0) != 0) {
        key = "type." + key;
    }
    std::replace(key.begin(), key.end(), '-', '.');
    std::replace(key.begin(), key.end(), ':', '_');
    return key;
}

static NSString *LookupLocalizedTypeInBundle(NSBundle *bundle, NSString *key, NSString *locale) {
    if (!bundle) {
        return nil;
    }
    NSBundle *localeBundle = [NSBundle bundleWithPath:[bundle pathForResource:locale
                                                                       ofType:@"lproj"
                                                                  inDirectory:@"Resources/LocalizedStrings"]];
    if (localeBundle) {
        NSString *value = NSLocalizedStringFromTableInBundle(key, @"LocalizableTypes", localeBundle, @"");
        if (![value isEqualToString:key]) {
            return value;
        }
    }
    NSBundle *directLocaleBundle = [NSBundle bundleWithPath:[bundle pathForResource:locale
                                                                             ofType:@"lproj"]];
    if (directLocaleBundle) {
        NSString *value = NSLocalizedStringFromTableInBundle(key, @"LocalizableTypes", directLocaleBundle, @"");
        if (![value isEqualToString:key]) {
            return value;
        }
    }
    return nil;
}

static NSString *LookupLocalizedTypeInResourcePath(NSString *key, NSString *locale) {
    if (g_resourcePath.empty()) {
        return nil;
    }

    NSString *resourcePath = [NSString stringWithUTF8String:g_resourcePath.c_str()];
    NSString *localePath = [resourcePath stringByAppendingPathComponent:
        [NSString stringWithFormat:@"localized_types/%@.lproj", locale]];
    NSBundle *localeBundle = [NSBundle bundleWithPath:localePath];
    if (!localeBundle) {
        return nil;
    }

    NSString *value = NSLocalizedStringFromTableInBundle(key, @"LocalizableTypes", localeBundle, @"");
    if (![value isEqualToString:key]) {
        return value;
    }
    return nil;
}

static NSString *LookupLocalizedType(NSString *key, NSString *locale) {
    NSString *resourceValue = LookupLocalizedTypeInResourcePath(key, locale);
    if (resourceValue) return resourceValue;

    NSBundle *mainBundle = NSBundle.mainBundle;
    NSString *value = LookupLocalizedTypeInBundle(mainBundle, key, locale);
    if (value) return value;

    Class pluginClass = NSClassFromString(@"AgusMapsFlutterPlugin");
    if (pluginClass) {
        NSBundle *pluginBundle = [NSBundle bundleForClass:pluginClass];
        value = LookupLocalizedTypeInBundle(pluginBundle, key, locale);
        if (value) return value;
    }

    return nil;
}

static std::string LocalizeTypeName(std::string const & type) {
    std::string key = NormalizeTypeKey(type);
    NSString *nsKey = @(key.c_str());

    NSString *value = NSLocalizedStringFromTableInBundle(nsKey, @"LocalizableTypes", NSBundle.mainBundle, @"");
    if (![value isEqualToString:nsKey]) {
        return [value UTF8String];
    }

    NSMutableArray<NSString *> *candidates = [NSMutableArray array];
    if (!g_explicitLocaleTag.empty()) {
        NSString *explicitLocale = [NSString stringWithUTF8String:g_explicitLocaleTag.c_str()];
        if (![candidates containsObject:explicitLocale]) {
            [candidates addObject:explicitLocale];
        }
        NSRange dash = [explicitLocale rangeOfString:@"-"];
        if (dash.location != NSNotFound) {
            NSString *shortLang = [explicitLocale substringToIndex:dash.location];
            if (![candidates containsObject:shortLang]) {
                [candidates addObject:shortLang];
            }
        }
    }

    NSArray<NSString *> *preferred = [NSLocale preferredLanguages];
    for (NSString *language in preferred) {
        if (![candidates containsObject:language]) {
            [candidates addObject:language];
        }
        NSRange dash = [language rangeOfString:@"-"];
        if (dash.location != NSNotFound) {
            NSString *shortLang = [language substringToIndex:dash.location];
            if (![candidates containsObject:shortLang]) {
                [candidates addObject:shortLang];
            }
        }
    }
    if (![candidates containsObject:@"en"]) {
        [candidates addObject:@"en"];
    }

    for (NSString *locale in candidates) {
        NSString *localized = LookupLocalizedType(nsKey, locale);
        if (localized) {
            return [localized UTF8String];
        }
    }

    return key;
}

static std::string TrimWhitespace(std::string const & value) {
    auto const start = value.find_first_not_of(" \t\n\r");
    if (start == std::string::npos) {
        return std::string();
    }
    auto const end = value.find_last_not_of(" \t\n\r");
    return value.substr(start, end - start + 1);
}

static bool IsTypeToken(std::string const & token) {
    return token.rfind("type.", 0) == 0 || token.find('-') != std::string::npos;
}

static std::string LocalizePlacePageSubtitle(std::string const & subtitle) {
    if (subtitle.empty()) {
        return subtitle;
    }

    static std::string const kSeparator = " • ";
    std::string result;
    size_t start = 0;
    bool first = true;

    while (true) {
        auto const pos = subtitle.find(kSeparator, start);
        auto const token = subtitle.substr(
            start,
            pos == std::string::npos ? std::string::npos : pos - start);
        auto const trimmed = TrimWhitespace(token);
        std::string localized = token;
        if (IsTypeToken(trimmed)) {
            std::string const candidate = LocalizeTypeName(trimmed);
            if (candidate != NormalizeTypeKey(trimmed)) {
                localized = candidate;
            }
        }

        if (!first) {
            result.append(kSeparator);
        }
        result.append(localized);
        if (pos == std::string::npos) {
            break;
        }
        start = pos + kSeparator.size();
        first = false;
    }

    return result;
}

static int GetObjectType(place_page::Info const & info) {
    if (info.IsMyPosition()) return 3; // MY_POSITION
    if (info.IsBookmark()) return 2; // BOOKMARK
    if (info.IsTrack()) return 5; // TRACK
    if (info.HasApiUrl()) return 1; // API_POINT
    return 0; // POI
}

// Surface state
static int32_t g_surfaceWidth = 0;
static int32_t g_surfaceHeight = 0;
static float g_density = 2.0f;
static int64_t g_textureId = -1;

// Frame ready callback
static FrameReadyCallback g_frameReadyCallback = nullptr;

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
    data->subtitle = CopyString(LocalizePlacePageSubtitle(info.GetSubtitle()));
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

#pragma mark - Logging

// Custom log handler that redirects to NSLog
static void AgusLogMessage(base::LogLevel level, base::SrcPoint const & src, std::string const & msg) {
#if defined(NDEBUG) || defined(RELEASE)
    if (level < base::LWARNING) {
        return;
    }
    if (msg.find("Detected using of unknown symbol  transit_") != std::string::npos ||
        msg.find("Bad emoji code: U+2139") != std::string::npos ||
        msg.find("Can't find World map file") != std::string::npos ||
        msg.find("Can't load cities boundaries") != std::string::npos ||
        msg.find("Cannot read power manager config file") != std::string::npos) {
        return;
    }
#endif

    NSString* levelStr;
    switch (level) {
        case base::LDEBUG: levelStr = @"DEBUG"; break;
        case base::LINFO: levelStr = @"INFO"; break;
        case base::LWARNING: levelStr = @"WARN"; break;
        case base::LERROR: levelStr = @"ERROR"; break;
        case base::LCRITICAL: levelStr = @"CRITICAL"; break;
        default: levelStr = @"???"; break;
    }
    
    NSLog(@"[CoMaps %@] %s %s", levelStr, 
          DebugPrint(src).c_str(), msg.c_str());
    
    // Only abort on CRITICAL, not ERROR
    if (level >= base::LCRITICAL) {
        NSLog(@"[CoMaps CRITICAL] Aborting...");
        abort();
    }
}

#pragma mark - FFI Functions

FFI_PLUGIN_EXPORT int sum(int a, int b) { 
    return a + b; 
}

FFI_PLUGIN_EXPORT int sum_long_running(int a, int b) {
    [NSThread sleepForTimeInterval:5.0];
    return a + b;
}

FFI_PLUGIN_EXPORT void comaps_init(const char* apkPath, const char* storagePath) {
    // macOS doesn't use APK paths - redirect to comaps_init_paths
    comaps_init_paths(apkPath, storagePath);
}

FFI_PLUGIN_EXPORT void comaps_init_paths(const char* resourcePath, const char* writablePath) {
    AGUS_DEBUG_LOG(@"[AgusMapsFlutter] comaps_init_paths: resource=%s, writable=%s", resourcePath, writablePath);
    
    // Set up custom log handler before doing anything else
    base::SetLogMessageFn(&AgusLogMessage);
    base::g_LogAbortLevel = base::LCRITICAL;
    
    // Store paths
    g_resourcePath = resourcePath ? resourcePath : "";
    g_writablePath = writablePath ? writablePath : "";
    
    // Initialize platform paths via AgusPlatformMacOS
    AgusPlatformMacOS_InitPaths(resourcePath, writablePath);
    g_platformInitialized = true;
    
    // Register for app termination notification to clean up framework properly
    // This prevents crashes during static destruction order issues
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationWillTerminateNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification * _Nonnull note) {
            NSLog(@"[AgusMapsFlutter] App terminating, cleaning up Framework...");
            stopRenderKeepAliveTimer();
            if (g_framework) {
                g_drapeEngineCreated = false;
                g_framework.reset();
                NSLog(@"[AgusMapsFlutter] Framework destroyed");
            }
            _exit(EXIT_SUCCESS);
        }];
    });
    
    AGUS_DEBUG_LOG(@"[AgusMapsFlutter] Platform initialized, Framework deferred to surface creation");
}

FFI_PLUGIN_EXPORT void comaps_set_locale(const char* localeTag) {
    g_explicitLocaleTag = localeTag ? localeTag : "";
}

/// Explicitly shutdown the CoMaps framework
/// Call this before app termination to ensure clean shutdown
FFI_PLUGIN_EXPORT void comaps_shutdown(void) {
    AGUS_DEBUG_LOG(@"[AgusMapsFlutter] comaps_shutdown called");
    
    stopRenderKeepAliveTimer();
    
    if (g_framework) {
        g_drapeEngineCreated = false;
        g_framework.reset();
        g_platformInitialized = false;
        AGUS_DEBUG_LOG(@"[AgusMapsFlutter] Framework shutdown complete");
    }
}

FFI_PLUGIN_EXPORT void comaps_load_map_path(const char* path) {
    AGUS_DEBUG_LOG(@"[AgusMapsFlutter] comaps_load_map_path: %s", path);
    
    if (g_framework) {
        g_framework->RegisterAllMaps();
        AGUS_DEBUG_LOG(@"[AgusMapsFlutter] Maps registered");
    } else {
        AGUS_DEBUG_LOG(@"[AgusMapsFlutter] Framework not yet initialized, maps will be loaded later");
    }
}

FFI_PLUGIN_EXPORT void comaps_set_view(double lat, double lon, int zoom) {
    AGUS_DEBUG_LOG(@"[AgusMapsFlutter] comaps_set_view: lat=%.6f, lon=%.6f, zoom=%d", lat, lon, zoom);
    
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
    if (inside_map != 0) {
        std::lock_guard<std::mutex> viewportLock(g_viewportMutex);
        if (g_currentScreen) {
            auto const mercatorPoint = g_currentScreen->PtoG(
                m2::PointD(physical_x, physical_y));
            auto const coordinate = mercator::ToLatLon(mercatorPoint);
            projectedLat = coordinate.m_lat;
            projectedLon = coordinate.m_lon;
            hasCoordinate = true;
        }
    }

    {
        std::lock_guard<std::mutex> pointerLock(g_mapPointerMutex);
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
    if (!physical_x || !physical_y) {
        return 0;
    }

    std::lock_guard<std::mutex> lock(g_viewportMutex);
    if (!g_currentScreen) {
        return 0;
    }

    auto const screenPoint = g_currentScreen->GtoP(
        mercator::FromLatLon(lat, lon));
    *physical_x = screenPoint.x;
    *physical_y = screenPoint.y;
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

FFI_PLUGIN_EXPORT void comaps_invalidate(void) {
    AGUS_DEBUG_LOG(@"[AgusMapsFlutter] comaps_invalidate");
    if (g_framework) {
        g_framework->InvalidateRendering();
        if (g_drapeEngineCreated) {
            g_framework->MakeFrameActive();
        }
    }
}

FFI_PLUGIN_EXPORT void comaps_force_redraw(void) {
    AGUS_DEBUG_LOG(@"[AgusMapsFlutter] comaps_force_redraw - triggering full tile reload");
    if (g_framework) {
        // Step 1: Update map style - clears render groups and forces tile re-request
        MapStyle currentStyle = g_framework->GetMapStyle();
        ApplyRuntimeMapStyle(currentStyle);
        
        g_framework->InvalidateRendering();
        if (g_drapeEngineCreated) {
            g_framework->MakeFrameActive();
        }
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
}

FFI_PLUGIN_EXPORT void comaps_scale(double factor, double pixelX, double pixelY, int animated) {
    if (!g_framework || !g_drapeEngineCreated) {
        return;
    }
    
    // Scale the map by the given factor, centered on the pixel point
    // This is the preferred method for scroll wheel zoom on desktop (macOS)
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

FFI_PLUGIN_EXPORT int32_t agus_duckdb_refresh_render_layers(void) {
    return RefreshDuckDBRenderLayersInternal();
}

FFI_PLUGIN_EXPORT void agus_duckdb_set_edit_handles_from_wkt(char const * geometryWkt) {
    UpdateDuckDBEditHandlesInternal(geometryWkt, kDuckDBInteractionEditingFeature);
}

FFI_PLUGIN_EXPORT void agus_duckdb_set_interaction_geometry_from_wkt(
    int32_t interactionMode, char const * geometryWkt) {
    UpdateDuckDBEditHandlesInternal(geometryWkt, interactionMode);
}

FFI_PLUGIN_EXPORT void agus_duckdb_update_interaction_geometry(
    int32_t interactionMode,
    char const * geometryWkt,
    int32_t red,
    int32_t green,
    int32_t blue,
    double opacity,
    double width,
    int32_t dashed,
    double dashLength,
    double gapLength) {
    auto const channel = [](int32_t value) -> uint8_t {
        return static_cast<uint8_t>(std::max(0, std::min(255, value)));
    };
    double const clampedOpacity = std::max(0.0, std::min(1.0, opacity));
    DuckDBInteractionLineStyle style;
    style.color = dp::Color(
        channel(red),
        channel(green),
        channel(blue),
        static_cast<uint8_t>(std::round(clampedOpacity * 255.0)));
    style.width = static_cast<float>(std::max(0.5, std::min(64.0, width)));
    style.dashed = dashed != 0;
    style.dashLength = std::max(1.0, dashLength);
    style.gapLength = std::max(1.0, gapLength);
    UpdateDuckDBEditHandlesInternal(geometryWkt, interactionMode, style);
}

FFI_PLUGIN_EXPORT void agus_duckdb_clear_edit_handles(void) {
    ClearDuckDBEditHandlesInternal();
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
            engine->ClearUserMarksGroup(kDuckDBEditGroupId);
            engine->InvalidateUserMarks();
            WakeRenderer();
        }
    }
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

FFI_PLUGIN_EXPORT int comaps_register_single_map(const char* fullPath) {
    // Delegate to versioned registration with version=0 for backwards compatibility
    return comaps_register_single_map_with_version(fullPath, 0);
}

FFI_PLUGIN_EXPORT int comaps_register_single_map_with_version(const char* fullPath, int64_t version) {
    AGUS_DEBUG_LOG(@"[AgusMapsFlutter] comaps_register_single_map_with_version: %s (version=%lld)", fullPath, (long long)version);
    
    if (!g_framework) {
        NSLog(@"[AgusMapsFlutter] Framework not initialized");
        return -1;
    }
    
    try {
        std::string path(fullPath ? fullPath : "");
        if (path.empty()) {
            NSLog(@"[AgusMapsFlutter] Empty path");
            return -2;
        }
        
        // Derive country name from filename (without extension)
        auto name = path;
        auto lastSlash = name.rfind('/');
        if (lastSlash != std::string::npos) {
            name = name.substr(lastSlash + 1);
        }
        auto dotPos = name.rfind('.');
        if (dotPos != std::string::npos) {
            name = name.substr(0, dotPos);
        }
        
        // Get directory from full path
        std::string directory;
        lastSlash = path.rfind('/');
        if (lastSlash != std::string::npos) {
            directory = path.substr(0, lastSlash);
        }

        if (IsMapAlreadyRegistered(name, version)) {
            AGUS_DEBUG_LOG(@"[AgusMapsFlutter] %s already registered, skipping", name.c_str());
            return 0;
        }
        
        platform::LocalCountryFile file(directory, platform::CountryFile(std::move(name)), version);
        file.SyncWithDisk();
        
        auto result = g_framework->RegisterMap(file);
        if (result.second == MwmSet::RegResult::Success) {
            AGUS_DEBUG_LOG(@"[AgusMapsFlutter] Successfully registered %s", fullPath);
            return 0;
        } else if (result.second == MwmSet::RegResult::VersionAlreadyExists) {
            AGUS_DEBUG_LOG(@"[AgusMapsFlutter] %s already registered, skipping", fullPath);
            return 0;
        } else {
            NSLog(@"[AgusMapsFlutter] Failed to register %s, result=%d", 
                  fullPath, static_cast<int>(result.second));
            return static_cast<int>(result.second);
        }
    } catch (std::exception const & e) {
        NSLog(@"[AgusMapsFlutter] Exception registering map: %s", e.what());
        return -2;
    }
}

FFI_PLUGIN_EXPORT int comaps_deregister_map(const char* fullPath) {
    AGUS_DEBUG_LOG(@"[AgusMapsFlutter] comaps_deregister_map: %s (not implemented)", fullPath);
    
    // TODO: Implement map deregistration when needed
    // Framework only exposes const DataSource, and DeregisterMap requires non-const
    // For MVP, maps are registered at startup and not deregistered at runtime
    
    return -1;  // Not implemented
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
#if !defined(NDEBUG) && !defined(RELEASE)
    NSLog(@"[AgusMapsFlutter] === DEBUG: Listing all registered MWMs ===");
    
    if (!g_framework) {
        NSLog(@"[AgusMapsFlutter] Framework not initialized");
        return;
    }
    
    auto const & dataSource = g_framework->GetDataSource();
    std::vector<std::shared_ptr<MwmInfo>> mwms;
    dataSource.GetMwmsInfo(mwms);
    
    NSLog(@"[AgusMapsFlutter] Total MWMs registered: %lu", mwms.size());
    
    for (auto const & mwmInfo : mwms) {
        if (mwmInfo) {
            auto const & rect = mwmInfo->m_bordersRect;
            NSLog(@"[AgusMapsFlutter]   MWM: %s, bounds: [%.4f, %.4f] - [%.4f, %.4f]",
                  mwmInfo->GetCountryName().c_str(),
                  rect.minX(), rect.minY(), rect.maxX(), rect.maxY());
        }
    }
#endif
}

FFI_PLUGIN_EXPORT void comaps_debug_check_point(double lat, double lon) {
#if !defined(NDEBUG) && !defined(RELEASE)
    NSLog(@"[AgusMapsFlutter] comaps_debug_check_point: lat=%.6f, lon=%.6f", lat, lon);
    
    if (!g_framework) {
        NSLog(@"[AgusMapsFlutter] Framework not initialized");
        return;
    }
    
    m2::PointD const mercatorPt = mercator::FromLatLon(lat, lon);
    NSLog(@"[AgusMapsFlutter] Mercator coords: (%.4f, %.4f)", mercatorPt.x, mercatorPt.y);
    
    auto const & dataSource = g_framework->GetDataSource();
    std::vector<std::shared_ptr<MwmInfo>> mwms;
    dataSource.GetMwmsInfo(mwms);
    
    for (auto const & mwmInfo : mwms) {
        if (mwmInfo && mwmInfo->m_bordersRect.IsPointInside(mercatorPt)) {
            NSLog(@"[AgusMapsFlutter] Point IS covered by MWM: %s", 
                  mwmInfo->GetCountryName().c_str());
            return;
        }
    }
    
    NSLog(@"[AgusMapsFlutter] Point is NOT covered by any registered MWM");
#endif
}

#pragma mark - Render Keep-Alive Timer

/// Stops the render keep-alive timer if running
static void stopRenderKeepAliveTimer() {
    if (g_renderKeepAliveTimer) {
        dispatch_source_cancel(g_renderKeepAliveTimer);
        g_renderKeepAliveTimer = nil;
        AGUS_DEBUG_LOG(@"[AgusMapsFlutter] Render keep-alive timer stopped");
    }
}

/// Starts a timer that periodically invalidates rendering to keep the render loop alive
/// This ensures initial tiles are loaded and rendered before the loop suspends
static void startRenderKeepAliveTimer() {
    stopRenderKeepAliveTimer();
    
    g_renderKeepAliveCount = 0;
    
    // Create a dispatch timer that fires every ~33ms (30 Hz)
    g_renderKeepAliveTimer = dispatch_source_create(
        DISPATCH_SOURCE_TYPE_TIMER,
        0, 0,
        dispatch_get_main_queue()
    );
    
    if (!g_renderKeepAliveTimer) {
        NSLog(@"[AgusMapsFlutter] ERROR: Failed to create render keep-alive timer");
        return;
    }
    
    dispatch_source_set_timer(
        g_renderKeepAliveTimer,
        dispatch_time(DISPATCH_TIME_NOW, 0),
        33 * NSEC_PER_MSEC,  // ~30 Hz
        5 * NSEC_PER_MSEC   // 5ms leeway
    );
    
    dispatch_source_set_event_handler(g_renderKeepAliveTimer, ^{
        g_renderKeepAliveCount++;
        
        if (g_renderKeepAliveCount > kRenderKeepAliveMaxCount) {
            AGUS_DEBUG_LOG(@"[AgusMapsFlutter] Render keep-alive complete after %d invalidations", g_renderKeepAliveCount - 1);
            stopRenderKeepAliveTimer();
            return;
        }
        
        if (g_framework && g_drapeEngineCreated) {
            // MakeFrameActive() posts an ActiveFrameEvent which forces the render loop
            // to render an active frame (isActiveFrame=true), which in turn triggers
            // the ActiveFrameCallback to notify Flutter of new frame content.
            g_framework->MakeFrameActive();
            
            if (g_renderKeepAliveCount <= 5 || g_renderKeepAliveCount % 10 == 0) {
                AGUS_DEBUG_LOG(@"[AgusMapsFlutter] Render keep-alive tick %d/%d (MakeFrameActive)",
                               g_renderKeepAliveCount, kRenderKeepAliveMaxCount);
            }
        }
    });
    
    dispatch_resume(g_renderKeepAliveTimer);
    AGUS_DEBUG_LOG(@"[AgusMapsFlutter] Render keep-alive timer started (max %d ticks)", kRenderKeepAliveMaxCount);
}

#pragma mark - DrapeEngine Creation

static void createDrapeEngineIfNeeded(int width, int height, float density) {
    if (g_drapeEngineCreated || !g_framework || !g_threadSafeFactory) {
        return;
    }
    
    if (width <= 0 || height <= 0) {
        NSLog(@"[AgusMapsFlutter] createDrapeEngine: Invalid dimensions %dx%d", width, height);
        return;
    }
    
    // Register active frame callback BEFORE creating DrapeEngine
    // This callback is invoked only when isActiveFrame is true (Option 3)
    df::SetActiveFrameCallback([]() {
        notifyFlutterFrameReady();
    });
    AGUS_DEBUG_LOG(@"[AgusMapsFlutter] Active frame callback registered");
    
    Framework::DrapeCreationParams p;
    p.m_apiVersion = dp::ApiVersion::Metal;  // Use Metal on macOS
    p.m_surfaceWidth = width;
    p.m_surfaceHeight = height;
    p.m_visualScale = density;
    
    AGUS_DEBUG_LOG(@"[AgusMapsFlutter] createDrapeEngine: Creating with %dx%d, scale=%.2f, API=Metal",
                   width, height, density);
    
    g_framework->CreateDrapeEngine(make_ref(g_threadSafeFactory), std::move(p));
    g_drapeEngineCreated = true;
    
    AGUS_DEBUG_LOG(@"[AgusMapsFlutter] DrapeEngine created successfully");
    
    // Start the render keep-alive timer to ensure initial tiles are rendered
    // The CoMaps render loop suspends after a few inactive frames, but tiles
    // load asynchronously. This timer keeps the loop active until content is ready.
    startRenderKeepAliveTimer();
}

#pragma mark - Native Surface Functions (called from Swift)

/// Called when Swift creates a new map surface
/// @param textureId Flutter texture ID
/// @param pixelBuffer CVPixelBuffer for rendering target
/// @param width Surface width in pixels
/// @param height Surface height in pixels
/// @param density Screen density
extern "C" FFI_PLUGIN_EXPORT void agus_native_set_surface(
    int64_t textureId,
    CVPixelBufferRef pixelBuffer,
    int32_t width,
    int32_t height,
    float density
) {
    AGUS_DEBUG_LOG(@"[AgusMapsFlutter] agus_native_set_surface: texture=%lld, %dx%d, density=%.2f",
                   textureId, width, height, density);
    
    if (!g_platformInitialized) {
        NSLog(@"[AgusMapsFlutter] ERROR: Platform not initialized! Call comaps_init_paths first.");
        return;
    }
    
    g_textureId = textureId;
    g_surfaceWidth = width;
    g_surfaceHeight = height;
    g_density = density;
    
    // Create Framework on this thread if not already created
    if (!g_framework) {
        AGUS_DEBUG_LOG(@"[AgusMapsFlutter] Creating Framework...");
        
        FrameworkParams params;
        params.m_enableDiffs = false;
        params.m_numSearchAPIThreads = 1;
        
        g_framework = std::make_unique<Framework>(params, false /* loadMaps */);
        SetViewportTracking();
        AGUS_DEBUG_LOG(@"[AgusMapsFlutter] Framework created");

        g_framework->RegisterAllMaps();
        AGUS_DEBUG_LOG(@"[AgusMapsFlutter] Maps registered");
        
    }
    
    // Create Metal context factory with the CVPixelBuffer
    m2::PointU screenSize(static_cast<uint32_t>(width), static_cast<uint32_t>(height));
    auto metalFactory = new agus::AgusMetalContextFactory(pixelBuffer, screenSize);
    
    if (!metalFactory->IsDrawContextCreated()) {
        NSLog(@"[AgusMapsFlutter] ERROR: Failed to create Metal context");
        delete metalFactory;
        return;
    }
    
    // Save raw pointer for resize operations (SetPixelBuffer)
    g_metalContextFactory = metalFactory;
    
    // Wrap in ThreadSafeFactory for thread-safe context access
    g_threadSafeFactory = make_unique_dp<dp::ThreadSafeFactory>(metalFactory);
    
    // Create DrapeEngine
    createDrapeEngineIfNeeded(width, height, density);
    
    // Enable rendering
    if (g_framework && g_drapeEngineCreated) {
        g_framework->SetRenderingEnabled(make_ref(g_threadSafeFactory));
        AGUS_DEBUG_LOG(@"[AgusMapsFlutter] Rendering enabled");
    }
}

/// Called when Swift resizes the surface (legacy - does not update pixel buffer)
extern "C" FFI_PLUGIN_EXPORT void agus_native_on_size_changed(int32_t width, int32_t height) {
    AGUS_DEBUG_LOG(@"[AgusMapsFlutter] agus_native_on_size_changed: %dx%d", width, height);
    
    g_surfaceWidth = width;
    g_surfaceHeight = height;
    
    if (g_framework && g_drapeEngineCreated) {
        g_framework->OnSize(width, height);
    }
}

/// Update visual scale without resizing surface
extern "C" FFI_PLUGIN_EXPORT void agus_native_set_visual_scale(float density) {
    if (density <= 0) {
        NSLog(@"[AgusMapsFlutter] agus_native_set_visual_scale: invalid density %.2f", density);
        return;
    }

    g_density = density;

    if (g_framework && g_drapeEngineCreated) {
        df::VisualParams::Instance().SetVisualScale(static_cast<double>(density));
        g_framework->InvalidateRendering();
        AGUS_DEBUG_LOG(@"[AgusMapsFlutter] agus_native_set_visual_scale: Updated visual scale to %.2f", density);
    } else {
        AGUS_DEBUG_LOG(@"[AgusMapsFlutter] agus_native_set_visual_scale: Framework not ready, stored density %.2f", density);
    }
}

/// Called when Swift resizes the surface with new pixel buffer (macOS-specific)
/// This properly updates the Metal texture for resize operations
extern "C" FFI_PLUGIN_EXPORT void agus_native_resize_surface(
    CVPixelBufferRef pixelBuffer,
    int32_t width,
    int32_t height
) {
    AGUS_DEBUG_LOG(@"[AgusMapsFlutter] agus_native_resize_surface: %dx%d", width, height);
    
    if (!pixelBuffer) {
        NSLog(@"[AgusMapsFlutter] ERROR: agus_native_resize_surface called with null pixelBuffer");
        return;
    }
    
    // Skip resize if Framework/DrapeEngine not ready
    if (!g_framework || !g_drapeEngineCreated) {
        NSLog(@"[AgusMapsFlutter] WARNING: resize called but Framework not ready");
        return;
    }
    
    g_surfaceWidth = width;
    g_surfaceHeight = height;
    
    // Update the Metal context factory with the new pixel buffer
    if (g_metalContextFactory) {
        m2::PointU screenSize(static_cast<uint32_t>(width), static_cast<uint32_t>(height));
        g_metalContextFactory->SetPixelBuffer(pixelBuffer, screenSize);
    } else {
        NSLog(@"[AgusMapsFlutter] WARNING: No metal context factory for resize");
    }
    
    // Notify framework of size change and request redraw
    if (g_framework && g_drapeEngineCreated) {
        g_framework->OnSize(width, height);
        
        // Force complete tile reload to fill the new viewport area
        // This ensures expanded areas render properly, not with brown/incomplete tiles
        g_framework->InvalidateRendering();
        g_framework->MakeFrameActive();
    }
}

/// Called when Swift destroys the surface
extern "C" FFI_PLUGIN_EXPORT void agus_native_on_surface_destroyed(void) {
    AGUS_DEBUG_LOG(@"[AgusMapsFlutter] agus_native_on_surface_destroyed");
    
    // Stop the keep-alive timer first
    stopRenderKeepAliveTimer();
    
    if (g_framework) {
        g_framework->SetRenderingDisabled(true /* destroySurface */);
    }
    
    g_metalContextFactory = nullptr;  // Will be deleted by ThreadSafeFactory
    g_threadSafeFactory.reset();
    g_drapeEngineCreated = false;
}

/// Called by native code to notify Swift that a new frame is ready
/// This should trigger textureRegistry.textureFrameAvailable(textureId)
extern "C" FFI_PLUGIN_EXPORT void agus_set_frame_ready_callback(FrameReadyCallback callback) {
    g_frameReadyCallback = callback;
}

// Frame notification timing for 60fps rate limiting (Option 2)
static std::chrono::steady_clock::time_point g_lastFrameNotification;
static constexpr auto kMinFrameInterval = std::chrono::milliseconds(16); // ~60fps

// Throttling flag to prevent queuing too many frame notifications
static std::atomic<bool> g_frameNotificationPending{false};

#if !defined(NDEBUG) && !defined(RELEASE)
static std::atomic<int> g_frameNotificationCount{0};
#endif

/// Internal function to notify Flutter about a new frame
/// Called from the DrapeEngine render thread via df::SetActiveFrameCallback
static void notifyFlutterFrameReady(void) {
#if !defined(NDEBUG) && !defined(RELEASE)
    int count = g_frameNotificationCount.fetch_add(1);
    if (count < 5 || count % 60 == 0) {
        NSLog(@"[AgusMapsFlutter] notifyFlutterFrameReady called (count=%d)", count);
    }
#endif
    
    // Rate limiting (Option 2): Enforce 60fps max
    auto now = std::chrono::steady_clock::now();
    auto elapsed = now - g_lastFrameNotification;
    if (elapsed < kMinFrameInterval) {
        return;  // Too soon, skip this notification
    }
    
    // Throttle: if a notification is already pending, skip this one
    // This prevents memory buildup from queued dispatch_async calls
    bool expected = false;
    if (!g_frameNotificationPending.compare_exchange_strong(expected, true)) {
        return;  // Already a notification pending, skip
    }
    
    g_lastFrameNotification = now;
    
    if (g_frameReadyCallback) {
        dispatch_async(dispatch_get_main_queue(), ^{
            g_frameNotificationPending.store(false);
            g_frameReadyCallback();
        });
    } else {
        // Fallback: call Swift static method directly if no callback is set
        dispatch_async(dispatch_get_main_queue(), ^{
            g_frameNotificationPending.store(false);
            // Use the @objc name we assigned to the Swift class
            // The class is declared as @objc(AgusMapsFlutterPlugin)
            Class pluginClass = NSClassFromString(@"AgusMapsFlutterPlugin");
            if (pluginClass) {
                SEL selector = NSSelectorFromString(@"notifyFrameReadyFromNative");
                if ([pluginClass respondsToSelector:selector]) {
#if !defined(NDEBUG) && !defined(RELEASE)
                    static dispatch_once_t successToken;
                    dispatch_once(&successToken, ^{
                        NSLog(@"[AgusMapsFlutter] Frame notification: class found, calling notifyFrameReadyFromNative");
                    });
#endif
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                    [pluginClass performSelector:selector];
#pragma clang diagnostic pop
                } else {
                    // Debug: selector not found
                    static dispatch_once_t selectorToken;
                    dispatch_once(&selectorToken, ^{
                        NSLog(@"[AgusMapsFlutter] WARNING: AgusMapsFlutterPlugin does not respond to notifyFrameReadyFromNative");
                    });
                }
            } else {
                // Debug: log if class lookup fails
                static dispatch_once_t onceToken;
                dispatch_once(&onceToken, ^{
                    NSLog(@"[AgusMapsFlutter] WARNING: Could not find AgusMapsFlutterPlugin class for frame notification");
                });
            }
        });
    }
}

/// Called by Present() to notify Flutter that a frame was rendered
/// Used for initial frames and as fallback when df::SetActiveFrameCallback doesn't trigger
extern "C" void agus_notify_frame_ready(void) {
    notifyFlutterFrameReady();
}

#pragma mark - Render Frame

/// Called to render a single frame - this is triggered by Flutter's texture system
extern "C" FFI_PLUGIN_EXPORT void agus_render_frame(void) {
    if (!g_framework || !g_drapeEngineCreated) {
        return;
    }
    
    // The DrapeEngine handles rendering internally
    // We just need to ensure the render loop is running
    // Frame completion will trigger agus_notify_frame_ready
}
