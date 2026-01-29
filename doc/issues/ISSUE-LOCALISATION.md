# Issue: Native Type Localization Not Working

**Status**: Resolved  
**Platforms Affected**: Windows, Android, Linux (macOS/iOS untested)  
**Discovered**: 2026-01-29  
**Resolved**: 2026-01-29

## Summary

POI type names like `amenity-compressed_air` appeared as raw type strings in the place page subtitle instead of being localized to user-friendly names like "Compressed Air".

## Resolution

The issue was resolved by:

1. **Removing Dart-side localization entirely** — The `PlacePageLocalization` class and all related functions have been removed from [lib/agus_maps_flutter.dart](lib/agus_maps_flutter.dart). All localization is now handled by native code.

2. **Adding `setLocale()` API** — A new `setLocale(String localeTag)` function was added for consumers to explicitly set the locale for native localization. This should be called after `initWithPaths()` but before displaying place pages. The function gracefully handles missing symbols on older binaries.

3. **Multi-platform `comaps_set_locale()`** — Added the FFI export to all platform implementations:
   - Android: [src/agus_maps_flutter.cpp](../src/agus_maps_flutter.cpp)
   - Windows: [src/agus_maps_flutter_win.cpp](../src/agus_maps_flutter_win.cpp)
   - Linux: [src/agus_maps_flutter_linux.cpp](../src/agus_maps_flutter_linux.cpp)

4. **Adding diagnostic logging** — Native `TryLoadLocale()` in [src/agus_localization.cpp](src/agus_localization.cpp) now logs:
   - The `ResourcesDir` path being used
   - Each file path attempted
   - Success/failure status with translation count

5. **Auto-generating asset declarations** — The build runner in [tool/src/assets_updater.dart](tool/src/assets_updater.dart) now auto-generates `localized_types` asset declarations for [example/pubspec.yaml](example/pubspec.yaml) after copying localization files.

## New API: `setLocale()`

```dart
/// Set the locale for native POI type localization.
///
/// This controls how POI type names are translated in place page data
/// (e.g., "amenity-fuel" → "Gas Station").
///
/// **When to call:**
/// - After initWithPaths() so the resource directory is known
/// - Before creating the map surface for best results
/// - Can be called at any time to change locale (affects subsequent requests)
///
/// **Example:**
/// ```dart
/// final dataPath = await extractDataFiles();
/// initWithPaths(dataPath, dataPath);
/// setLocale(ui.PlatformDispatcher.instance.locale.toLanguageTag()); // e.g., "en-US"
/// ```
void setLocale(String localeTag);
```

**Behavior:**
- If not called, native code auto-detects the system locale (may not work reliably on all platforms)
- If the symbol is not found (older binaries), falls back to auto-detection with a debug message
- Explicitly calling `setLocale()` is recommended for consistent cross-platform behavior

## Migration Guide

### For Plugin Consumers

**Before (Dart localization):**
```dart
// OLD: Preload Dart-side localization
await preloadPlacePageLocalization();
initWithPaths(dataPath, dataPath);
```

**After (Native localization):**
```dart
// NEW: Set locale for native localization
initWithPaths(dataPath, dataPath);
setLocale(ui.PlatformDispatcher.instance.locale.toLanguageTag());
```

### What Changed

| Component | Before | After |
|-----------|--------|-------|
| `PlacePageLocalization` class | Existed in Dart | **Removed** |
| `preloadPlacePageLocalization()` | Required before use | **Removed** |
| `localizeSubtitle()` | Dart-side, partial | **Removed** - native handles all |
| `setLocale()` | Did not exist | **New** - explicit locale setting |
| Place page subtitle | Partially localized | Fully pre-localized by native |

## Original Problem

### Observed Behavior

When tapping on a POI (e.g., a gas station with compressed air amenity):

```
subtitle="Gas Station · amenity-compressed_air · 🚻"
```

- **Main type** (`amenity-fuel` → "Gas Station") was localized ✓
- **Secondary type** (`amenity-compressed_air`) appeared **raw** ✗

### Root Cause

The Dart-side `localizeSubtitle()` function only localized the **first** bullet point in the subtitle, leaving secondary types unchanged:

```dart
// OLD CODE (removed)
final parts = trimmedSubtitle.split(RegExp(r'\s+•\s+'));
final head = parts.first.trim();
final localizedHead = localizeTypeKey(head);  // Only head!
return [localizedHead, ...parts.skip(1)].join(' • ');  // Rest unchanged!
```

Additionally, native localization was not loading translation files because:
1. The locale wasn't being set explicitly on all platforms
2. Asset declarations for `localized_types` were missing from the example app's pubspec

## Technical Details

| File | Purpose |
|------|---------|
| [`src/agus_localization.cpp`](file:///c:/Users/Bangonkali/Desktop/Projects/agus-maps-flutter/src/agus_localization.cpp) | Native localization implementation |
| [`src/agus_platform.cpp`](file:///c:/Users/Bangonkali/Desktop/Projects/agus-maps-flutter/src/agus_platform.cpp) | Platform initialization, locale setting |
| [`lib/agus_maps_flutter.dart`](file:///c:/Users/Bangonkali/Desktop/Projects/agus-maps-flutter/lib/agus_maps_flutter.dart) | Dart-side PlacePageLocalization class |
| [`thirdparty/comaps/libs/indexer/map_object.cpp`](file:///c:/Users/Bangonkali/Desktop/Projects/agus-maps-flutter/thirdparty/comaps/libs/indexer/map_object.cpp) | GetLocalizedType/GetLocalizedAllTypes |

## Key Functions
## Technical Details

### Native Localization Flow

```
setLocale("en-US")                      // Dart calls FFI
    ↓
comaps_set_locale("en-US")              // C++ FFI export
    ↓
AgusPlatform_SetLocale("en-US")         // Sets g_explicitLocaleTag
    ↓
GetLocalizedTypeName("amenity-fuel")    // Called from place page
    ↓
EnsureLocalizationLoaded()              // Checks/loads translations
    ↓
TryLoadLocale("en-US")                  // Loads .strings files
    ↓
LoadStringsFile("{ResourcesDir}/localized_types/en.lproj/LocalizableTypes.strings")
    ↓
Returns "Gas Station"                   // Localized name
```

### Diagnostic Log Output

When localization succeeds, you'll see in logcat/debug console:

```
[LINFO] TryLoadLocale: localeTag = en-US ResourcesDir = /data/data/.../files/
[LINFO] TryLoadLocale: Trying path = /data/data/.../files/localized_types/en-US.lproj/LocalizableTypes.strings
[LINFO] TryLoadLocale: File not found or empty: ...
[LINFO] TryLoadLocale: Trying path = /data/data/.../files/localized_types/en.lproj/LocalizableTypes.strings
[LINFO] TryLoadLocale: SUCCESS! Loaded 1247 type translations and 892 string translations for locale = en
```

## Related Files

| File | Purpose |
|------|---------|
| [src/agus_maps_flutter.h](../src/agus_maps_flutter.h) | FFI header with `comaps_set_locale()` declaration |
| [src/agus_maps_flutter.cpp](../src/agus_maps_flutter.cpp) | FFI implementation calling `AgusPlatform_SetLocale()` |
| [src/agus_localization.cpp](../src/agus_localization.cpp) | Native localization with diagnostic logging |
| [lib/agus_maps_flutter.dart](../lib/agus_maps_flutter.dart) | Dart `setLocale()` wrapper |
| [tool/src/assets_updater.dart](../tool/src/assets_updater.dart) | Auto-generates localized_types asset declarations |
| [example/lib/main.dart](../example/lib/main.dart) | Example showing `setLocale()` usage |

## Key Functions

| Function | File | Purpose |
|----------|------|---------|
| `setLocale()` | agus_maps_flutter.dart | **NEW** Dart API for setting locale |
| `comaps_set_locale()` | agus_maps_flutter.cpp | **NEW** FFI export for locale setting |
| `GetLocalizedTypeName()` | agus_localization.cpp | Main entry point for type localization |
| `TryLoadLocale()` | agus_localization.cpp | Loads .strings files with diagnostic logging |
| `updateExampleLocalizedTypesAssets()` | assets_updater.dart | **NEW** Auto-generates pubspec assets |
