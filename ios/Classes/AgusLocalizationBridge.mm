// Copyright (c) Agus Maps
//
// iOS localization bridge - provides platform::GetLocalizedXxx implementations
// for the CoMaps engine. These functions are called by libcomaps.a.
//
// This file bridges the CoMaps localization API with the cross-platform
// implementation in agus_localization.cpp.

#import <Foundation/Foundation.h>

#include <string>
#include <mutex>
#include <unordered_map>
#include <vector>

#include "platform/localization.hpp"
#include "platform/measurement_utils.hpp"
#include "platform/settings.hpp"

// ============================================================================
// Namespace-scope state (same as agus_localization.cpp)
// ============================================================================
namespace {
std::mutex g_mutex;
std::unordered_map<std::string, std::string> g_typeTranslations;
std::unordered_map<std::string, std::string> g_stringTranslations;
std::string g_loadedLocaleTag;
std::string g_explicitLocaleTag;

/// Parse a .strings file into the translation map.
void ParseStringsFile(
	std::string const & path,
	std::unordered_map<std::string, std::string> & translations)
{
	@autoreleasepool {
		NSString * nsPath = [NSString stringWithUTF8String:path.c_str()];
		NSDictionary * dict = [NSDictionary dictionaryWithContentsOfFile:nsPath];
		if (!dict) {
			return;
		}
		for (NSString * key in dict) {
			NSString * value = dict[key];
			if ([key isKindOfClass:[NSString class]] &&
				[value isKindOfClass:[NSString class]]) {
				translations[[key UTF8String]] = [value UTF8String];
			}
		}
	}
}

/// Get the current locale tag.
std::string GetCurrentLocaleTag()
{
	if (!g_explicitLocaleTag.empty()) {
		return g_explicitLocaleTag;
	}

	@autoreleasepool {
		NSString * langCode = [[NSLocale preferredLanguages] firstObject];
		if (langCode) {
			NSRange dashRange = [langCode rangeOfString:@"-"];
			if (dashRange.location != NSNotFound) {
				langCode = [langCode substringToIndex:dashRange.location];
			}
			return std::string([langCode UTF8String]);
		}
	}
	return "en";
}

/// Try to load translations for a given locale.
bool TryLoadTranslations(std::string const & localeTag)
{
	@autoreleasepool {
		NSBundle * mainBundle = [NSBundle mainBundle];
		NSString * nsLocale = [NSString stringWithUTF8String:localeTag.c_str()];

		NSString * typesPath = [mainBundle
			pathForResource:@"LocalizableTypes"
					 ofType:@"strings"
				inDirectory:[NSString stringWithFormat:
					@"LocalizedStrings/%@", nsLocale]];

		if (!typesPath) {
			NSBundle * pluginBundle =
				[NSBundle bundleForClass:NSClassFromString(@"AgusLocalizationBridge")
								   ?: [NSBundle mainBundle].class];
			typesPath = [pluginBundle
				pathForResource:@"LocalizableTypes"
						 ofType:@"strings"
					inDirectory:[NSString stringWithFormat:
						@"LocalizedStrings/%@", nsLocale]];
		}

		if (typesPath) {
			ParseStringsFile([typesPath UTF8String], g_typeTranslations);
		}

		NSString * stringsPath = [mainBundle
			pathForResource:@"Localizable"
					 ofType:@"strings"
				inDirectory:[NSString stringWithFormat:
					@"LocalizedStrings/%@", nsLocale]];
		if (!stringsPath) {
			NSBundle * pluginBundle =
				[NSBundle bundleForClass:NSClassFromString(@"AgusLocalizationBridge")
								   ?: [NSBundle mainBundle].class];
			stringsPath = [pluginBundle
				pathForResource:@"Localizable"
						 ofType:@"strings"
					inDirectory:[NSString stringWithFormat:
						@"LocalizedStrings/%@", nsLocale]];
		}

		if (stringsPath) {
			ParseStringsFile([stringsPath UTF8String], g_stringTranslations);
		}

		return !g_typeTranslations.empty() || !g_stringTranslations.empty();
	}
}

/// Ensure translations are loaded for the current locale.
void EnsureTranslationsLoaded()
{
	std::string currentLocale = GetCurrentLocaleTag();
	if (currentLocale == g_loadedLocaleTag && !g_typeTranslations.empty()) {
		return;
	}

	g_typeTranslations.clear();
	g_stringTranslations.clear();

	if (TryLoadTranslations(currentLocale)) {
		g_loadedLocaleTag = currentLocale;
	} else if (currentLocale != "en" && TryLoadTranslations("en")) {
		g_loadedLocaleTag = "en";
	} else {
		g_loadedLocaleTag = currentLocale;
	}
}

}  // namespace

// ============================================================================
// Static storage for functions returning const references
// ============================================================================
namespace {
platform::LocalizedUnits g_distanceUnitsMetric{"m", "km"};
platform::LocalizedUnits g_distanceUnitsImperial{"ft", "mi"};
platform::LocalizedUnits g_altitudeUnitsMetric{"m", "m"};
platform::LocalizedUnits g_altitudeUnitsImperial{"ft", "ft"};
std::string g_speedUnitsMetric = "km/h";
std::string g_speedUnitsImperial = "mph";
}  // namespace

// ============================================================================
// platform:: namespace implementations required by CoMaps
// ============================================================================
namespace platform
{

std::string GetLocalizedTypeName(std::string const & type)
{
	std::lock_guard<std::mutex> lock(g_mutex);
	EnsureTranslationsLoaded();

	auto it = g_typeTranslations.find(type);
	if (it != g_typeTranslations.end()) {
		return it->second;
	}

	if (type.rfind("type.", 0) == 0) {
		return type.substr(5);
	}
	return type;
}

std::string GetLocalizedBrandName(std::string const & brand)
{
	return brand;
}

std::string GetLocalizedString(std::string const & key)
{
	std::lock_guard<std::mutex> lock(g_mutex);
	EnsureTranslationsLoaded();

	auto it = g_stringTranslations.find(key);
	if (it != g_stringTranslations.end()) {
		return it->second;
	}

	it = g_typeTranslations.find(key);
	if (it != g_typeTranslations.end()) {
		return it->second;
	}

	return key;
}

std::string GetCurrencySymbol(std::string const & currencyCode)
{
	@autoreleasepool {
		NSLocale * locale = [NSLocale currentLocale];
		NSString * code = [NSString stringWithUTF8String:currencyCode.c_str()];
		NSString * symbol =
			[locale displayNameForKey:NSLocaleCurrencySymbol value:code];
		if (symbol) {
			return std::string([symbol UTF8String]);
		}
	}
	return currencyCode;
}

std::string GetLocalizedMyPositionBookmarkName()
{
	std::lock_guard<std::mutex> lock(g_mutex);
	EnsureTranslationsLoaded();

	auto it = g_stringTranslations.find("my_position");
	if (it != g_stringTranslations.end()) {
		return it->second;
	}

	return "My Position";
}

LocalizedUnits const & GetLocalizedDistanceUnits()
{
	auto units = measurement_utils::Units::Metric;
	settings::TryGet(settings::kMeasurementUnits, units);
	return (units == measurement_utils::Units::Metric)
		? g_distanceUnitsMetric
		: g_distanceUnitsImperial;
}

LocalizedUnits const & GetLocalizedAltitudeUnits()
{
	auto units = measurement_utils::Units::Metric;
	settings::TryGet(settings::kMeasurementUnits, units);
	return (units == measurement_utils::Units::Metric)
		? g_altitudeUnitsMetric
		: g_altitudeUnitsImperial;
}

std::string const & GetLocalizedSpeedUnits(measurement_utils::Units units)
{
	return (units == measurement_utils::Units::Metric)
		? g_speedUnitsMetric
		: g_speedUnitsImperial;
}

std::string const & GetLocalizedSpeedUnits()
{
	auto units = measurement_utils::Units::Metric;
	settings::TryGet(settings::kMeasurementUnits, units);
	return GetLocalizedSpeedUnits(units);
}

}  // namespace platform

// ============================================================================
// C API for setting locale from Dart FFI
// ============================================================================
extern "C" {

__attribute__((visibility("default")))
void agus_localization_set_locale(const char * localeTag)
{
	std::lock_guard<std::mutex> lock(g_mutex);
	g_explicitLocaleTag = localeTag ? localeTag : "";
	g_typeTranslations.clear();
	g_stringTranslations.clear();
	g_loadedLocaleTag.clear();
}

__attribute__((visibility("default")))
const char * agus_localization_get_locale()
{
	std::lock_guard<std::mutex> lock(g_mutex);
	EnsureTranslationsLoaded();

	if (g_loadedLocaleTag.empty()) {
		return nullptr;
	}

	static thread_local std::string s_buffer;
	s_buffer = g_loadedLocaleTag;
	return s_buffer.c_str();
}

}  // extern "C"
