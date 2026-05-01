# Map Widget Parts

This cheat sheet names the visible controls layered over the example map so
they can be referenced consistently in issues, implementation notes, and API
work.

## Map Shell

| Name | Widget or component | Source | Notes |
| --- | --- | --- | --- |
| `MapTab` | `_buildMapTab()` | `example/lib/main.dart` | Owns the full map `Stack` and places the overlays. |
| `MapCanvas` | `agus_maps_flutter.AgusMap` | `example/lib/main.dart` | Native CoMaps texture surface plus pointer, scroll, and pan-zoom gesture forwarding. |
| `SearchOverlay` | `_buildSearchOverlay()` | `example/lib/main.dart` | Top overlay containing the map search field and result list. |
| `MapControlsOverlay` | `_buildMapControls()` | `example/lib/main.dart` | Right-bottom vertical button cluster. It moves upward while the place page is open. |
| `PlacePageOverlay` | `PlacePageSheet` | `example/lib/place_page_sheet.dart` | Bottom sheet shown after selecting a map feature. |

## Search Overlay Buttons

| Name | Visible control | Widget | Callback | Behavior |
| --- | --- | --- | --- | --- |
| `SearchToggleButton` | Search icon / close icon | `IconButton` in the search field `prefixIcon` | `_toggleSearch()` | Opens the search panel and focuses the field, or closes search and clears state. |
| `SearchClearButton` | Clear icon | `IconButton` in the search field `suffixIcon` | Inline clear handler | Clears the search text and cancels active search state. |
| `SearchResultTile` | Search result row | `ListTile` | `_focusSearchResult(result)` | Opens a native result, coordinates result, favorite, or suggestion. |

## Map Control Buttons

| Name | Tooltip | Icon | Widget | Callback | Behavior |
| --- | --- | --- | --- | --- | --- |
| `ZoomInButton` | `Zoom in` | `Icons.add` | `IconButton` | `_zoomIn()` | Calls `AgusMapController.zoomIn()`. |
| `ZoomOutButton` | `Zoom out` | `Icons.remove` | `IconButton` | `_zoomOut()` | Calls `AgusMapController.zoomOut()`. |
| `ResetNorthButton` | `Reset north` | Rotating `Icons.navigation` | `IconButton` with `ValueListenableBuilder<double>` | `_resetNorth()` | Calls `AgusMapController.resetBearing()` and rotates the icon from native bearing updates. |
| `CurrentPositionButton` | `Current position` | `Icons.my_location` or progress spinner | `IconButton` | `_centerOnCurrentPosition()` | Centers on device or estimated location. On macOS it uses network estimation to avoid unreliable CoreLocation updates in release builds. |

## Place Page Overlay Buttons

| Name | Visible control | Widget | Callback | Behavior |
| --- | --- | --- | --- | --- |
| `PlacePageCloseButton` | Close icon | `IconButton` | `_closePlacePage()` through `PlacePageSheet.onClose` | Closes the native place page and removes the bottom sheet. |

## Bottom Navigation

| Name | Destination label | Widget | Selected tab index | Behavior |
| --- | --- | --- | --- | --- |
| `MapNavigationDestination` | `Map` | `NavigationDestination` | `0` | Shows `MapTab`. |
| `FavoritesNavigationDestination` | `Favorites` | `NavigationDestination` | `1` | Shows saved example locations. |
| `DownloadsNavigationDestination` | `Downloads` | `NavigationDestination` | `2` | Shows map download and mirror controls. |
| `SettingsNavigationDestination` | `Settings` | `NavigationDestination` | `3` | Shows map scale, theme, language, 3D, and layer settings. |
| `AboutNavigationDestination` | `About` | `NavigationDestination` | `4` | Shows package and license information. |

## Gesture Names

| Name | Source | Native call | Notes |
| --- | --- | --- | --- |
| `MapPointerTouchGesture` | `Listener.onPointerDown/Move/Up/Cancel` | `sendTouchEvent()` / `comaps_touch()` | Raw pointer path used for mouse and direct touch-style gestures. |
| `MapScrollZoomGesture` | `Listener.onPointerSignal` with `PointerScrollEvent` | `scaleMap()` / `comaps_scale()` | Desktop wheel or trackpad scroll zoom. |
| `MapPanZoomRotationGesture` | `Listener.onPointerPanZoomStart/Update/End` | `setMapBearing()` / `comaps_set_bearing()` | Desktop trackpad rotation path for macOS, Windows, and Linux. |