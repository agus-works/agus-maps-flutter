// Copyright (c) Agus Maps
//
// iOS localization bridge - provides:
// 1. C API for locale access (used by Flutter plugin)
// 2. Missing platform::* localization functions not in CoMaps iOS localization.mm
//
// The CoMaps XCFramework's localization.mm only implements:
//   - GetLocalizedTypeName, GetLocalizedBrandName, GetLocalizedString
//   - GetCurrencySymbol, GetLocalizedMyPositionBookmarkName
//
// This file provides the missing:
//   - GetLocalizedDistanceUnits, GetLocalizedAltitudeUnits, GetLocalizedSpeedUnits

#import <Foundation/Foundation.h>

#include "platform/localization.hpp"
#include "platform/measurement_utils.hpp"

#include <string>

// ============================================================================
// platform:: localization functions missing from CoMaps iOS localization.mm
// ============================================================================

namespace platform
{

namespace
{
enum class MeasurementType
{
  Distance,
  Speed,
  Altitude
};

LocalizedUnits const & GetLocalizedUnits(measurement_utils::Units units, MeasurementType measurementType)
{
  // Use NSLocalizedString for iOS-native localization
  static LocalizedUnits const lengthImperial = {
    [NSLocalizedString(@"ft", @"feet") UTF8String],
    [NSLocalizedString(@"mi", @"miles") UTF8String]
  };
  static LocalizedUnits const lengthMetric = {
    [NSLocalizedString(@"m", @"meters") UTF8String],
    [NSLocalizedString(@"km", @"kilometers") UTF8String]
  };
  static LocalizedUnits const speedImperial = {
    [NSLocalizedString(@"ft", @"feet") UTF8String],
    [NSLocalizedString(@"miles_per_hour", @"mph") UTF8String]
  };
  static LocalizedUnits const speedMetric = {
    [NSLocalizedString(@"m", @"meters") UTF8String],
    [NSLocalizedString(@"kilometers_per_hour", @"km/h") UTF8String]
  };

  switch (measurementType)
  {
  case MeasurementType::Distance:
  case MeasurementType::Altitude:
    switch (units)
    {
    case measurement_utils::Units::Imperial: return lengthImperial;
    case measurement_utils::Units::Metric: return lengthMetric;
    }
    break;
  case MeasurementType::Speed:
    switch (units)
    {
    case measurement_utils::Units::Imperial: return speedImperial;
    case measurement_utils::Units::Metric: return speedMetric;
    }
  }
  // Should never reach here, but return metric as fallback
  return lengthMetric;
}
}  // namespace

LocalizedUnits const & GetLocalizedDistanceUnits()
{
  return GetLocalizedUnits(measurement_utils::GetMeasurementUnits(), MeasurementType::Distance);
}

LocalizedUnits const & GetLocalizedAltitudeUnits()
{
  return GetLocalizedUnits(measurement_utils::GetMeasurementUnits(), MeasurementType::Altitude);
}

std::string const & GetLocalizedSpeedUnits(measurement_utils::Units units)
{
  return GetLocalizedUnits(units, MeasurementType::Speed).m_high;
}

std::string const & GetLocalizedSpeedUnits()
{
  return GetLocalizedSpeedUnits(measurement_utils::GetMeasurementUnits());
}

}  // namespace platform

// ============================================================================
// C API for setting locale from external code (e.g., Dart FFI)
// ============================================================================

extern "C" {

__attribute__((visibility("default")))
void agus_localization_set_locale(const char* localeTag)
{
	(void)localeTag;
	// No-op on iOS: localization follows the current system locale.
}

__attribute__((visibility("default")))
const char* agus_localization_get_locale()
{
	@autoreleasepool {
		NSString* localeId = [[NSLocale currentLocale] localeIdentifier];
		static thread_local std::string s_locale;
		if (localeId == nil) {
			s_locale.clear();
		} else {
			s_locale = [localeId UTF8String];
		}
		return s_locale.empty() ? nullptr : s_locale.c_str();
	}
}

}  // extern "C"
