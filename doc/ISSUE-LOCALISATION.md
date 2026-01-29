# Issue: Native Type Localization Not Working

**Status**: Open  
**Platforms Affected**: Windows, Android (macOS/iOS untested)  
**Discovered**: 2026-01-29  

## Summary

POI type names like `amenity-compressed_air` appear as raw type strings in the place page subtitle instead of being localized to user-friendly names like "Compressed Air".

## Observed Behavior

When tapping on a POI (e.g., a gas station with compressed air amenity):

```
subtitle="Gas Station · amenity-compressed_air · 🚻"
rawType="toilets-yes"
localizedFromRaw="Toilet"
```

- **Main type** (`amenity-fuel` → "Gas Station") is localized ✓
- **Secondary type** (`amenity-compressed_air`) appears **raw** ✗
- **Dart-side fallback** correctly translates `toilets-yes` → "Toilet" ✓

## Root Cause Analysis

### 1. Native Localization Code Path

Both main and secondary types use the same function chain:

```
MapObject::GetLocalizedType()          → platform::GetLocalizedTypeName()
MapObject::GetLocalizedAllTypes()      → platform::GetLocalizedTypeName()
```

**File**: [`thirdparty/comaps/libs/indexer/map_object.cpp`](file:///c:/Users/Bangonkali/Desktop/Projects/agus-maps-flutter/thirdparty/comaps/libs/indexer/map_object.cpp#L106-L156)

### 2. Native Localization Implementation

**File**: [`src/agus_localization.cpp`](file:///c:/Users/Bangonkali/Desktop/Projects/agus-maps-flutter/src/agus_localization.cpp)

```cpp
std::string GetLocalizedTypeName(std::string const & type)
{
    std::lock_guard<std::mutex> lock(g_mutex);
    
    if (!EnsureLocalizationLoaded())  // ← Returns false!
        return type;                   // ← Returns raw type
    
    auto key = NormalizeTypeKey(type);
    auto it = g_typeTranslations.find(key);
    if (it == g_typeTranslations.end())
        return type;
    
    return it->second;
}
```

### 3. Why `EnsureLocalizationLoaded()` Fails

The function calls `TryLoadLocale()` which constructs file paths like:

```cpp
std::string typesPath = baseDir + candidate + ".lproj/LocalizableTypes.strings";
// Results in: "{ResourcesDir}/localized_types/en.lproj/LocalizableTypes.strings"
```

**Potential issues:**
1. `GetPlatform().ResourcesDir()` may not return the correct path
2. The `localized_types/` directory may not exist in the resources path
3. The `.strings` files may not be extracted/accessible at runtime

### 4. Dart-Side Fallback (Partial Workaround)

**File**: [`lib/agus_maps_flutter.dart`](file:///c:/Users/Bangonkali/Desktop/Projects/agus-maps-flutter/lib/agus_maps_flutter.dart#L190-L212)

The Dart layer has a `localizeSubtitle()` function that:
1. Splits subtitle by ` • ` separator
2. **Only localizes the FIRST part** (head)
3. Leaves secondary parts unchanged

```dart
static String localizeSubtitle(String subtitle, List<String> rawTypes) {
  final parts = trimmedSubtitle.split(RegExp(r'\s+•\s+'));
  final head = parts.first.trim();
  final localizedHead = localizeTypeKey(head);  // Only head!
  return [localizedHead, ...parts.skip(1)].join(' • ');  // Rest unchanged
}
```

## Translation File Location

Translations exist and are correctly formatted:

**File**: [`example/assets/comaps_data/localized_types/en.lproj/LocalizableTypes.strings`](file:///c:/Users/Bangonkali/Desktop/Projects/agus-maps-flutter/example/assets/comaps_data/localized_types/en.lproj/LocalizableTypes.strings#L67)

```
"type.amenity.compressed_air" = "Compressed Air";
```

The translation is present in 40+ language files.

## Debugging Steps

### 1. Add Diagnostic Logging

Add logging to `agus_localization.cpp` to trace:
- What `GetPlatform().ResourcesDir()` returns
- What file paths are being attempted
- Whether `std::ifstream` can open the files

### 2. Verify Resource Directory Structure

Check that at runtime, the resources directory contains:
```
{ResourcesDir}/
  localized_types/
    en.lproj/
      LocalizableTypes.strings
      Localizable.strings
```

### 3. Verify Locale Setting

Ensure `AgusPlatform_SetLocale()` is called before any place page is shown.

## Proposed Fixes

### Option A: Fix Native Localization (Recommended)

1. Add logging to diagnose file path issues
2. Ensure `.strings` files are extracted to the correct location
3. Fix `TryLoadLocale()` to find files in the actual resource path

### Option B: Enhance Dart-Side Fallback (Quick Fix)

Modify `localizeSubtitle()` to localize ALL parts:

```dart
static String localizeSubtitle(String subtitle, List<String> rawTypes) {
  final parts = trimmedSubtitle.split(RegExp(r'\s+•\s+'));
  final localizedParts = parts.map((p) {
    final localized = localizeTypeKey(p.trim());
    return localized ?? p;
  }).toList();
  return localizedParts.join(' • ');
}
```

## Related Files

| File | Purpose |
|------|---------|
| [`src/agus_localization.cpp`](file:///c:/Users/Bangonkali/Desktop/Projects/agus-maps-flutter/src/agus_localization.cpp) | Native localization implementation |
| [`src/agus_platform.cpp`](file:///c:/Users/Bangonkali/Desktop/Projects/agus-maps-flutter/src/agus_platform.cpp) | Platform initialization, locale setting |
| [`lib/agus_maps_flutter.dart`](file:///c:/Users/Bangonkali/Desktop/Projects/agus-maps-flutter/lib/agus_maps_flutter.dart) | Dart-side PlacePageLocalization class |
| [`thirdparty/comaps/libs/indexer/map_object.cpp`](file:///c:/Users/Bangonkali/Desktop/Projects/agus-maps-flutter/thirdparty/comaps/libs/indexer/map_object.cpp) | GetLocalizedType/GetLocalizedAllTypes |

## Key Functions

| Function | File | Line | Purpose |
|----------|------|------|---------|
| `GetLocalizedTypeName()` | agus_localization.cpp | 321 | Main entry point for type localization |
| `EnsureLocalizationLoaded()` | agus_localization.cpp | 298 | Lazy-loads .strings files |
| `TryLoadLocale()` | agus_localization.cpp | 271 | Attempts to load locale files |
| `LoadStringsFile()` | agus_localization.cpp | 152 | Parses .strings file format |
| `localizeSubtitle()` | agus_maps_flutter.dart | 190 | Dart fallback localization |
