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
#include <mutex>
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
#include "platform/local_country_file.hpp"
#include "drape/graphics_context_factory.hpp"
#include "drape_frontend/visual_params.hpp"
#include "drape_frontend/user_event_stream.hpp"
#include "drape_frontend/active_frame_callback.hpp"
#include "geometry/mercator.hpp"
#include "geometry/screenbase.hpp"

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

void SetViewportTracking() {
    if (!g_framework) {
        return;
    }
    g_framework->SetViewportListener([](ScreenBase const & screen) {
        g_currentBearingDegrees = NormalizeBearingDegrees(
            screen.GetAngle() * kDegreesPerRadian);
    });
}

void SetOutdoorsEnabledInternal(bool enabled) {
    if (!g_framework) {
        return;
    }

    auto const currentStyle = g_framework->GetMapStyle();
    bool const dark = MapStyleIsDark(currentStyle);
    g_framework->SaveOutdoorsEnabled(enabled);

    if (enabled) {
        g_framework->SetMapStyle(dark ? MapStyleOutdoorsDark : MapStyleOutdoorsLight);
    } else if (IsOutdoorsStyle(currentStyle)) {
        g_framework->SetMapStyle(dark ? MapStyleDefaultDark : MapStyleDefaultLight);
    }
}

void SetIsolinesEnabledInternal(bool enabled) {
    if (!g_framework) {
        return;
    }
    g_framework->GetIsolinesManager().SetEnabled(enabled);
    g_framework->SaveIsolinesEnabled(enabled);
}

void SetSubwayEnabledInternal(bool enabled) {
    if (!g_framework) {
        return;
    }
    if (enabled) {
        SetOutdoorsEnabledInternal(false);
        SetIsolinesEnabledInternal(false);
    }
    g_framework->GetTransitManager().EnableTransitSchemeMode(enabled);
    g_framework->SaveTransitSchemeEnabled(enabled);
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
    g_framework->Save3dMode(g_3dBuildingsEnabled, g_3dBuildingsEnabled);
    g_framework->Allow3dMode(g_3dBuildingsEnabled, g_3dBuildingsEnabled);
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
    g_framework->SetMapStyle(dark != 0
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
        *outdoors = (g_framework && IsOutdoorsStyle(g_framework->GetMapStyle())) ? 1 : 0;
    }
    if (isolines) {
        *isolines = (g_framework && g_framework->LoadIsolinesEnabled()) ? 1 : 0;
    }
    if (subway) {
        *subway = (g_framework && g_framework->LoadTransitSchemeEnabled()) ? 1 : 0;
    }
}

FFI_PLUGIN_EXPORT void comaps_set_map_language(const char* languageCode) {
    if (!g_framework) {
        return;
    }
    if (!languageCode || !*languageCode) {
        g_framework->SetCustomMapLanguageCode();
    } else {
        g_framework->SetCustomMapLanguageCode(
            localisation::LanguageCode(languageCode));
    }
    g_framework->RefreshMapLanguage();
    WakeRenderer();
}

FFI_PLUGIN_EXPORT void comaps_invalidate(void) {
    AGUS_DEBUG_LOG(@"[AgusMapsFlutter] comaps_invalidate");
    if (g_framework) {
        g_framework->InvalidateRect(g_framework->GetCurrentViewport());
    }
}

FFI_PLUGIN_EXPORT void comaps_force_redraw(void) {
    AGUS_DEBUG_LOG(@"[AgusMapsFlutter] comaps_force_redraw - triggering full tile reload");
    if (g_framework) {
        // Step 1: Update map style - clears render groups and forces tile re-request
        MapStyle currentStyle = g_framework->GetMapStyle();
        g_framework->SetMapStyle(currentStyle);
        
        // Step 2: InvalidateRendering posts high-priority message to force re-render
        g_framework->InvalidateRendering();
        
        // Step 3: Invalidate viewport rect
        g_framework->InvalidateRect(g_framework->GetCurrentViewport());
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
        
        platform::LocalCountryFile file(directory, platform::CountryFile(std::move(name)), version);
        file.SyncWithDisk();
        
        auto result = g_framework->RegisterMap(file);
        if (result.second == MwmSet::RegResult::Success) {
            AGUS_DEBUG_LOG(@"[AgusMapsFlutter] Successfully registered %s", fullPath);
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
