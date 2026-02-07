# Localization Implementation (Flutter)

## Goal
Provide consistent, cross-platform localization for place page type names and
metadata labels in Flutter so the UI matches macOS behavior on all platforms.

## Problem Summary
Different platforms were returning different subtitle/type strings:
- iOS: `type.aeroway.aerodrome.international`
- Android: `aeroway-aerodrome-international`
- macOS: `International Airport`

The mismatch came from platform-specific native localization. Some platforms
returned raw type keys, while others performed native localization before
sending JSON to Flutter.

## Approach (Single Source of Truth in Flutter)
1. **Always send raw keys from native** and **localize in Dart**.
2. **Normalize** raw type keys (e.g., `aeroway-aerodrome-international`) to
   `type.aeroway.aerodrome.international` before lookup.
3. **Localize type names** using `LocalizableTypes.strings` in Flutter
   (shared across all platforms).
4. **Expose metadata tags as strings** (OSM-style keys) and localize label
   text in Flutter using `Localizable.strings`.

This ensures identical output across iOS/Android/macOS/Linux/Windows.

## Native JSON Payload Changes
### Place page JSON construction
- **Raw subtitle only** is sent from native, no native localization.
- **Metadata tags** are now included as string keys.

**Android/iOS shared core path:**
- [src/agus_maps_flutter.cpp](src/agus_maps_flutter.cpp)
  - Removed `platform::GetLocalizedTypeName` use.
  - Added `metadataTags` (string keys via `feature::ToString`).

**Windows path:**
- [src/agus_maps_flutter_win.cpp](src/agus_maps_flutter_win.cpp)
  - Added `metadataTags` (string keys via `feature::ToString`).

**Linux path:**
- [src/agus_maps_flutter_linux.cpp](src/agus_maps_flutter_linux.cpp)
  - Added `metadataTags` (string keys via `feature::ToString`).

**Metadata ID source of truth:**
- [thirdparty/comaps/libs/indexer/feature_meta.hpp](thirdparty/comaps/libs/indexer/feature_meta.hpp)
- [thirdparty/comaps/libs/indexer/feature_meta.cpp](thirdparty/comaps/libs/indexer/feature_meta.cpp)

## Dart Localization
### Type localization
- `PlacePageLocalization.localizeTypeKey()` normalizes the raw key and
  loads translations from LocalizableTypes.strings.
- Normalization mirrors the native behavior from
  [src/agus_platform.cpp](src/agus_platform.cpp).

**Dart implementation:**
- [lib/agus_maps_flutter.dart](lib/agus_maps_flutter.dart)
  - `PlacePageLocalization._normalizeTypeKey()`
  - `PlacePageLocalization.preload()`

### Metadata label localization
- Native now provides `metadataTags` (string keys like `opening_hours`).
- Dart maps tags to localization keys and uses Localizable.strings.
- Fallback is a humanized label when no localization exists.

**Dart implementation:**
- [lib/agus_maps_flutter.dart](lib/agus_maps_flutter.dart)
  - `PlacePageLocalization.localizeMetadataTag()`
  - `_metadataLabelKeys` (tag → localization key)

**Flutter UI usage:**
- [example/lib/place_page_sheet.dart](example/lib/place_page_sheet.dart)
  - Uses `metadataTags` and Dart localization.

## Assets and Copy Operations
### Source of localized strings
We use CoMaps iOS string resources as the canonical source:
- **Source:**
  - [thirdparty/comaps/iphone/Maps/LocalizedStrings](thirdparty/comaps/iphone/Maps/LocalizedStrings)
- **Destination:**
  - [example/assets/comaps_data/localized_types](example/assets/comaps_data/localized_types)

This folder contains both:
- `LocalizableTypes.strings` (type names)
- `Localizable.strings` (UI strings, including metadata labels)

### Copy step in build tool
A sync step was added to the build tool to keep Flutter assets in sync:
- [tool/src/build_runner.dart](tool/src/build_runner.dart)
  - `_syncLocalizedStringsAssets()`

**What it does:**
1. Deletes `example/assets/comaps_data/localized_types/` if it exists.
2. Copies all locales from
   [thirdparty/comaps/iphone/Maps/LocalizedStrings](thirdparty/comaps/iphone/Maps/LocalizedStrings)
  into [example/assets/comaps_data/localized_types](example/assets/comaps_data/localized_types).

### Additional copy for Android data
When data files are prepared for Android, the localized types folder is copied
directly from the CoMaps iOS localization source into the native data bundle:
- [tool/src/build_runner.dart](tool/src/build_runner.dart)
  - `_copyDataFiles()` copies `thirdparty/comaps/iphone/Maps/LocalizedStrings/`
    into `example/assets/comaps_data/localized_types/` for Android runtime usage.

## Result
All platforms now receive raw type keys and metadata tags from native, and
Flutter performs identical normalization + localization. This matches macOS
behavior for type display (e.g., “International Airport”) and keeps labels
consistent everywhere.
