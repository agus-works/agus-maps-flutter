# IMPL-05: Place Page (POI) Drawer for Flutter

## Goal
Expose CoMaps place page (POI) information to Flutter and implement a cross-platform, pure-Dart UI drawer in the example app that mirrors CoMaps behavior on Android/macOS.

## Scope
- **Platforms**: Android, iOS, macOS, Linux, Windows
- **UI**: Flutter/Dart only (no platform UI)
- **Data Source**: CoMaps core `place_page::Info` built by tap events

## Data Model (Cross-Platform)
We will expose a minimal, stable JSON payload from native and parse it in Dart.

### `PlacePageData`
- **Identity**
  - `featureId`: `{mwmName, mwmVersion, index}`
  - `objectType`: int (aligns with Android `MapObject`)
  - `openingMode`: int (aligns with `place_page::OpeningMode`)
- **Display**
  - `title`, `secondaryTitle`, `subtitle`, `address`
  - `lat`, `lon`
  - `coordinates`: `{decimal, dms, osm, olc, utm, mgrs}`
  - `wikiDescriptionHtml`
  - `rawTypes`: array of raw types
- **Metadata**
  - `metadata`: map of `metadataId -> value` (IDs match `indexer/feature_meta.hpp` and Android `Metadata.MetadataType`)
- **Status**
  - `isRoutePoint`
  - `roadType`
  - `bookmarkId`, `bookmarkCategoryId`, `trackId` (when available)

## Native API (FFI)
Add lightweight FFI functions to fetch current place page info:
- `comaps_place_page_has_data() -> int`
- `comaps_place_page_get_json() -> const char*`
- `comaps_place_page_clear_selection()`

These functions are implemented in all platform-native C++ entry points and rely on the existing framework selection lifecycle (`Framework::SetTapEventInfoListener` → `OnTapEvent` → `BuildPlacePageInfo`).

## Flutter API
Expose in Dart:
- `PlacePageData? getCurrentPlacePage()`
- `void closePlacePage()`
- `AgusMap(onPlacePage: ValueChanged<PlacePageData?>?)`

`AgusMap` will detect a short tap (no drag, no multitouch) and then query native for place page data after a short delay. The callback receives `null` when there is no selection.

## Example App UI
- Implement a bottom sheet overlay in Flutter (`Stack` + `Material`) to show:
  - Title, subtitle, address
  - Coordinates (decimal)
  - Selected metadata entries
- Include a close button that calls `closePlacePage()` and hides the sheet.

## Phases
1. **Native FFI additions** (C++): place page JSON fetch + close selection.
2. **Dart model + API**: parse JSON into `PlacePageData`.
3. **AgusMap tap detection**: trigger `onPlacePage` callback.
4. **Example UI**: pure Flutter drawer overlay.

## Validation
- Tap on map shows drawer with title/coords and metadata.
- Tap empty map area hides drawer.
- Works on Android, iOS, macOS, Linux, Windows.

## Notes
- The JSON payload is intentionally minimal and stable; new fields can be added without breaking Dart parsing.
- This plan avoids platform UI and keeps Flutter in control of rendering.
