/// agus_localization.cpp
///
/// Cross-platform localization implementation for agus_maps_flutter.
/// Provides runtime localization by loading .strings files from the
/// assets/comaps_data/localized_types/ directory, matching iOS's localization
/// format.
///
/// This file implements all functions from platform/localization.hpp:
/// - GetLocalizedTypeName() - POI type name localization
/// - GetLocalizedBrandName() - Brand name localization (stub)
/// - GetLocalizedString() - General string localization (stub)
/// - GetCurrencySymbol() - Currency symbol lookup (stub)
/// - GetLocalizedMyPositionBookmarkName() - "My Position" bookmark name
/// - GetLocalizedDistanceUnits() - Distance unit strings (m/km or ft/mi)
/// - GetLocalizedAltitudeUnits() - Altitude unit strings
/// - GetLocalizedSpeedUnits() - Speed unit strings (km/h or mph)
///
/// Locale detection:
/// - Windows: GetUserDefaultLocaleName()
/// - macOS/Linux: setlocale() / LC_ALL environment
/// - Android: Set via agus_localization_set_locale() from JNI
///
/// Thread safety: All public functions are thread-safe via mutex protection.

#include "platform/localization.hpp"
#include "platform/platform.hpp"
#include "platform/settings.hpp"
#include "platform/measurement_utils.hpp"
#include "base/logging.hpp"

#include <algorithm>
#include <fstream>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>
#include <clocale>
#include <cstring>

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#define AGUS_EXPORT __declspec(dllexport)
#else
#define AGUS_EXPORT __attribute__((visibility("default")))
#endif

namespace platform
{
namespace
{
/// Mutex protecting all localization state
std::mutex g_mutex;

/// Cached type translations loaded from LocalizableTypes.strings
std::unordered_map<std::string, std::string> g_typeTranslations;

/// Cached general string translations loaded from Localizable.strings
std::unordered_map<std::string, std::string> g_stringTranslations;

/// Currently loaded locale tag (e.g., "en", "de", "zh-Hans")
std::string g_loadedLocaleTag;

/// Explicitly set locale tag (e.g., from Android JNI)
std::string g_explicitLocaleTag;

/// Static unit strings for metric system
LocalizedUnits const g_distanceUnitsMetric = {"m", "km"};
LocalizedUnits const g_altitudeUnitsMetric = {"m", "km"};
std::string const g_speedUnitsMetric = "km/h";

/// Static unit strings for imperial system
LocalizedUnits const g_distanceUnitsImperial = {"ft", "mi"};
LocalizedUnits const g_altitudeUnitsImperial = {"ft", "mi"};
std::string const g_speedUnitsImperial = "mph";

/// Normalize a type key to match the format in LocalizableTypes.strings
/// e.g., "aeroway-aerodrome-international" -> "type.aeroway.aerodrome.international"
std::string NormalizeTypeKey(std::string const & type)
{
    std::string key = type;
    if (key.rfind("type.", 0) != 0)
        key = "type." + key;
    std::replace(key.begin(), key.end(), '-', '.');
    std::replace(key.begin(), key.end(), ':', '_');
    return key;
}

// Unescape a string from .strings file format.
// Handles backslash sequences: n, r, t, quote, backslash.
std::string UnescapeStringsValue(std::string const & str)
{
    std::string out;
    out.reserve(str.size());
    for (size_t i = 0; i < str.size(); ++i)
    {
        char c = str[i];
        if (c == '\\' && i + 1 < str.size())
        {
            char n = str[i + 1];
            switch (n)
            {
                case 'n': out.push_back('\n'); break;
                case 'r': out.push_back('\r'); break;
                case 't': out.push_back('\t'); break;
                case '"': out.push_back('"'); break;
                case '\\': out.push_back('\\'); break;
                default: out.push_back(n); break;
            }
            ++i;
        }
        else
        {
            out.push_back(c);
        }
    }
    return out;
}

/// Read a quoted string from a line, handling escapes
/// Returns true if successful, advances pos past the closing quote
bool ReadQuoted(std::string const & line, size_t & pos, std::string & out)
{
    auto start = line.find('"', pos);
    if (start == std::string::npos)
        return false;
    
    std::string result;
    for (size_t i = start + 1; i < line.size(); ++i)
    {
        char c = line[i];
        if (c == '\\' && i + 1 < line.size())
        {
            result.push_back(c);
            result.push_back(line[i + 1]);
            ++i;
            continue;
        }
        if (c == '"')
        {
            pos = i + 1;
            out = UnescapeStringsValue(result);
            return true;
        }
        result.push_back(c);
    }
    return false;
}

/// Load translations from a .strings file
/// Format: "key" = "value";
bool LoadStringsFile(std::string const & path, std::unordered_map<std::string, std::string> & outMap)
{
    std::ifstream file(path);
    if (!file.is_open())
        return false;
    
    std::unordered_map<std::string, std::string> map;
    std::string line;
    while (std::getline(file, line))
    {
        // Trim leading whitespace
        auto trimmed = line;
        trimmed.erase(0, trimmed.find_first_not_of(" \t\r\n"));
        
        // Skip empty lines and comments
        if (trimmed.empty() || trimmed.rfind("/*", 0) == 0 || trimmed.rfind("//", 0) == 0)
            continue;
        
        // Parse "key" = "value";
        size_t pos = 0;
        std::string key;
        if (!ReadQuoted(trimmed, pos, key))
            continue;
        
        auto eq = trimmed.find('=', pos);
        if (eq == std::string::npos)
            continue;
        
        pos = eq + 1;
        std::string value;
        if (!ReadQuoted(trimmed, pos, value))
            continue;
        
        if (!key.empty() && !value.empty())
            map.emplace(std::move(key), std::move(value));
    }
    
    outMap = std::move(map);
    return !outMap.empty();
}

/// Get the system locale tag
/// Returns a locale like "en", "en-US", "zh-Hans", etc.
std::string GetSystemLocaleTag()
{
    // If explicitly set (e.g., from Android JNI), use that
    if (!g_explicitLocaleTag.empty())
        return g_explicitLocaleTag;
    
#ifdef _WIN32
    // Windows: Use GetUserDefaultLocaleName
    wchar_t localeName[LOCALE_NAME_MAX_LENGTH] = {0};
    if (GetUserDefaultLocaleName(localeName, LOCALE_NAME_MAX_LENGTH) > 0)
    {
        // Convert wide string to narrow string
        char narrowName[LOCALE_NAME_MAX_LENGTH] = {0};
        WideCharToMultiByte(CP_UTF8, 0, localeName, -1, narrowName, LOCALE_NAME_MAX_LENGTH, nullptr, nullptr);
        return narrowName;
    }
    return "en";
#else
    // macOS/Linux: Use setlocale or environment
    char const * locale = std::setlocale(LC_ALL, "");
    if (!locale || std::strlen(locale) == 0)
        locale = std::getenv("LANG");
    if (!locale || std::strlen(locale) == 0)
        locale = std::getenv("LC_ALL");
    if (!locale || std::strlen(locale) == 0)
        return "en";
    
    std::string tag(locale);
    
    // Strip encoding suffix (e.g., "en_US.UTF-8" -> "en_US")
    auto dot = tag.find('.');
    if (dot != std::string::npos)
        tag = tag.substr(0, dot);
    
    // Convert underscore to hyphen (e.g., "en_US" -> "en-US")
    std::replace(tag.begin(), tag.end(), '_', '-');
    
    return tag;
#endif
}

/// Build a list of locale candidates to try, from most specific to least
/// e.g., ["en-US", "en"] or ["zh-Hans-CN", "zh-Hans", "zh"]
std::vector<std::string> BuildLocaleCandidates(std::string const & localeTag)
{
    std::vector<std::string> candidates;
    
    std::string tag = localeTag;
    std::replace(tag.begin(), tag.end(), '_', '-');
    
    // Add the full tag first
    if (!tag.empty())
        candidates.push_back(tag);
    
    // Try removing suffixes progressively
    // e.g., "zh-Hans-CN" -> "zh-Hans" -> "zh"
    while (true)
    {
        auto lastSep = tag.rfind('-');
        if (lastSep == std::string::npos)
            break;
        tag = tag.substr(0, lastSep);
        if (!tag.empty())
            candidates.push_back(tag);
    }
    
    // Always try English as fallback
    bool hasEn = std::find(candidates.begin(), candidates.end(), "en") != candidates.end();
    if (!hasEn)
        candidates.push_back("en");
    
    return candidates;
}

/// Try to load localization files for the given locale
/// Returns true if successful
bool TryLoadLocale(std::string const & localeTag)
{
    auto const & resDir = GetPlatform().ResourcesDir();
    auto const baseDir = resDir + "localized_types/";
    
    LOG(LINFO, ("TryLoadLocale: localeTag =", localeTag, "ResourcesDir =", resDir));
    
    auto candidates = BuildLocaleCandidates(localeTag);
    
    for (auto const & candidate : candidates)
    {
        std::string typesPath = baseDir + candidate + ".lproj/LocalizableTypes.strings";
        LOG(LINFO, ("TryLoadLocale: Trying path =", typesPath));
        
        if (LoadStringsFile(typesPath, g_typeTranslations))
        {
            g_loadedLocaleTag = candidate;
            
            // Also try to load general strings
            std::string stringsPath = baseDir + candidate + ".lproj/Localizable.strings";
            LoadStringsFile(stringsPath, g_stringTranslations);
            
            LOG(LINFO, ("TryLoadLocale: SUCCESS! Loaded", g_typeTranslations.size(), 
                        "type translations and", g_stringTranslations.size(), 
                        "string translations for locale =", candidate));
            
            return true;
        }
        else
        {
            LOG(LINFO, ("TryLoadLocale: File not found or empty:", typesPath));
        }
    }
    
    LOG(LWARNING, ("TryLoadLocale: FAILED to load any locale files for", localeTag));
    return false;
}

/// Ensure localization files are loaded for current locale
/// Must be called with g_mutex held
bool EnsureLocalizationLoaded()
{
    std::string currentLocale = GetSystemLocaleTag();
    std::replace(currentLocale.begin(), currentLocale.end(), '_', '-');
    
    // Check if already loaded for this locale
    if (!g_loadedLocaleTag.empty() && g_loadedLocaleTag == currentLocale && !g_typeTranslations.empty())
        return true;
    
    // Clear and reload
    g_typeTranslations.clear();
    g_stringTranslations.clear();
    g_loadedLocaleTag.clear();
    
    return TryLoadLocale(currentLocale);
}

}  // namespace

// ============================================================================
// Public API - implements platform/localization.hpp
// ============================================================================

std::string GetLocalizedTypeName(std::string const & type)
{
    std::lock_guard<std::mutex> lock(g_mutex);
    
    if (!EnsureLocalizationLoaded())
        return type;
    
    auto key = NormalizeTypeKey(type);
    auto it = g_typeTranslations.find(key);
    if (it == g_typeTranslations.end())
        return type;
    
    return it->second;
}

std::string GetLocalizedBrandName(std::string const & brand)
{
    // Brand localization not implemented - return unchanged
    // Could be extended to load from brand localization files
    return brand;
}

std::string GetLocalizedString(std::string const & key)
{
    std::lock_guard<std::mutex> lock(g_mutex);
    
    if (!EnsureLocalizationLoaded())
        return key;
    
    auto it = g_stringTranslations.find(key);
    if (it == g_stringTranslations.end())
        return key;
    
    return it->second;
}

std::string GetCurrencySymbol(std::string const & currencyCode)
{
    // Currency symbol lookup not implemented - return code unchanged
    // Could be extended to use ICU or platform APIs
    return currencyCode;
}

std::string GetLocalizedMyPositionBookmarkName()
{
    // Return a simple name - could be localized via GetLocalizedString()
    // if we had a key for it in Localizable.strings
    return "My Position";
}

LocalizedUnits const & GetLocalizedDistanceUnits()
{
    auto units = measurement_utils::GetMeasurementUnits();
    return units == measurement_utils::Units::Metric ? g_distanceUnitsMetric : g_distanceUnitsImperial;
}

LocalizedUnits const & GetLocalizedAltitudeUnits()
{
    auto units = measurement_utils::GetMeasurementUnits();
    return units == measurement_utils::Units::Metric ? g_altitudeUnitsMetric : g_altitudeUnitsImperial;
}

std::string const & GetLocalizedSpeedUnits(measurement_utils::Units units)
{
    return units == measurement_utils::Units::Metric ? g_speedUnitsMetric : g_speedUnitsImperial;
}

std::string const & GetLocalizedSpeedUnits()
{
    return GetLocalizedSpeedUnits(measurement_utils::GetMeasurementUnits());
}

}  // namespace platform

// ============================================================================
// C API for setting locale from external code (e.g., Android JNI, Dart FFI)
// ============================================================================

extern "C" {

/// Set the locale tag explicitly
/// Call this from Android JNI or Dart FFI to set the locale
/// before any localization calls are made
AGUS_EXPORT
void agus_localization_set_locale(const char* localeTag)
{
    std::lock_guard<std::mutex> lock(platform::g_mutex);
    platform::g_explicitLocaleTag = localeTag ? localeTag : "";
    // Clear cached translations to force reload with new locale
    platform::g_typeTranslations.clear();
    platform::g_stringTranslations.clear();
    platform::g_loadedLocaleTag.clear();
}

/// Get the currently loaded locale tag
/// Returns nullptr if no locale is loaded
AGUS_EXPORT
const char* agus_localization_get_locale()
{
    std::lock_guard<std::mutex> lock(platform::g_mutex);
    if (platform::g_loadedLocaleTag.empty())
        return nullptr;
    // Return static buffer - not thread-safe for the returned pointer
    // but the string content is protected by the lock during copy
    static thread_local std::string s_buffer;
    s_buffer = platform::g_loadedLocaleTag;
    return s_buffer.c_str();
}

}  // extern "C"
