# Agus Maps Flutter - API Reference

This document details all existing APIs exposed to Flutter and provides a roadmap for future API additions.

> **👋 New to the project?** Before implementing new APIs, please read:
> - **[README.md](../README.md)** - Overview, architecture, and quick start guide
> - **[CONTRIBUTING.md](CONTRIBUTING.md)** - Development setup, build instructions, and commit guidelines
> - **[GUIDE.md](../GUIDE.md)** - Architectural blueprint and design philosophy

## Table of Contents

1. [Implementing New APIs](#implementing-new-apis)
2. [Existing APIs](#existing-apis)
3. [Future API Candidates](#future-api-candidates)
   - [Viewport and Camera Control](#viewport-and-camera-control)
   - [Search and Geocoding](#search-and-geocoding)
   - [Bookmarks and Tracks](#bookmarks-and-tracks)
   - [Routing and Navigation](#routing-and-navigation)
   - [Map Features and Objects](#map-features-and-objects)
   - [Map Style and Display](#map-style-and-display)
   - [Location Services](#location-services)
   - [Storage and Map Management](#storage-and-map-management)
   - [Debug and Development](#debug-and-development)
4. [Implementation Priority Recommendations](#implementation-priority-recommendations)
5. [Notes on Implementation Difficulty](#notes-on-implementation-difficulty)

## Implementing New APIs

When implementing a new API from the candidates list below, follow this workflow:

### 1. Development Setup

First, ensure your development environment is configured:

```bash
# Clone and set up the project (see CONTRIBUTING.md for details)
git clone https://github.com/agus-works/agus-maps-flutter.git
cd agus-maps-flutter

# Build from source (recommended for contributors)
./scripts/build_all.sh  # macOS/Linux
# or
.\scripts\build_all.ps1  # Windows PowerShell 7+

# Targeted native builds (optional)
dart run tool/build.dart --build-binaries --platform <platform>
```

See **[CONTRIBUTING.md](CONTRIBUTING.md#development-setup)** for complete setup instructions and prerequisites.

### 2. FFI API Implementation Pattern

Most APIs follow this pattern:

#### Step 1: Add Native Function to Header

Edit `src/agus_maps_flutter.h` to declare the FFI function:

```c
// Example: Get current viewport center
FFI_PLUGIN_EXPORT void comaps_get_viewport_center(double* lat, double* lon);
```

#### Step 2: Implement in C++ Source

Edit `src/agus_maps_flutter.cpp` (or platform-specific files) to implement:

```cpp
FFI_PLUGIN_EXPORT void comaps_get_viewport_center(double* lat, double* lon) {
    if (!g_framework || !g_drapeEngineCreated) {
        *lat = 0.0;
        *lon = 0.0;
        return;
    }
    
    m2::PointD const center = g_framework->GetViewportCenter();
    m2::PointD const latLon = mercator::ToLatLon(center);
    *lat = latLon.y;
    *lon = latLon.x;
}
```

#### Step 3: Regenerate FFI Bindings

After modifying the header, regenerate Dart bindings:

```bash
dart run ffigen --config ffigen.yaml
```

This updates `lib/agus_maps_flutter_bindings_generated.dart`. See **[CONTRIBUTING.md](CONTRIBUTING.md#ffi-bindings)** for details.

#### Step 4: Add Dart Wrapper

Edit `lib/agus_maps_flutter.dart` to expose a user-friendly Dart API:

```dart
/// Get current viewport center coordinates.
/// Returns (latitude, longitude) in WGS84.
(double lat, double lon) getViewportCenter() {
  final latPtr = malloc<Double>();
  final lonPtr = malloc<Double>();
  
  try {
    _bindings.comaps_get_viewport_center(latPtr, lonPtr);
    return (latPtr.value, lonPtr.value);
  } finally {
    malloc.free(latPtr);
    malloc.free(lonPtr);
  }
}
```

### 3. MethodChannel APIs (Platform-Specific)

For platform-specific functionality (surface creation, asset extraction), use MethodChannel:

1. **Android**: Edit `android/src/main/java/app/agus/maps/agus_maps_flutter/AgusMapsFlutterPlugin.java`
2. **iOS**: Edit `ios/Classes/AgusMapsFlutterPlugin.swift`
3. **macOS**: Edit `macos/Classes/AgusMapsFlutterPlugin.swift`
4. **Windows**: Edit `windows/agus_maps_flutter_plugin.cpp`
5. **Linux**: Edit `linux/agus_maps_flutter_plugin.cc`

See existing implementations of `createMapSurface()` and `extractMap()` for reference.

### 4. Testing Your Implementation

```bash
cd example
flutter run

# Monitor native logs (Android)
adb logcat | grep -E "(CoMaps|AGUS|drape)"

# Check for errors in console output
```

See **[CONTRIBUTING.md](CONTRIBUTING.md#testing)** for testing guidelines.

### 5. Code Review Checklist

Before submitting a PR:

- [ ] FFI function declared in `src/agus_maps_flutter.h`
- [ ] Implementation added to platform-specific source files
- [ ] FFI bindings regenerated (`dart run ffigen`)
- [ ] Dart wrapper function added to `lib/agus_maps_flutter.dart`
- [ ] Memory management correct (malloc/free for pointers)
- [ ] Error handling implemented
- [ ] Platform-specific code tested on target platform(s)
- [ ] Example app updated (if adding new feature)
- [ ] Documentation updated (this file, README if applicable)
- [ ] Commit message follows [Conventional Commits](CONTRIBUTING.md#commit-guidelines)

### 6. Understanding the Architecture

Before implementing complex APIs, understand how the plugin works:

- **[README.md](../README.md#why-its-efficient)** - Memory mapping, zero-copy rendering, battery efficiency
- **[ARCHITECTURE-ANDROID.md](ARCHITECTURE-ANDROID.md)** - Deep dive into Android integration
- **[GUIDE.md](../GUIDE.md)** - Overall plugin architecture
- **[RENDER-LOOP.md](RENDER-LOOP.md)** - How rendering works across platforms

### 7. CoMaps Framework Reference

When implementing APIs that interact with the CoMaps engine:

- Review `thirdparty/comaps/libs/map/framework.hpp` for available Framework methods
- Check `thirdparty/comaps/libs/map/search_api.hpp` for search APIs
- Examine `thirdparty/comaps/libs/map/routing_manager.hpp` for routing APIs
- Look at existing implementations in `src/agus_maps_flutter.cpp` for patterns

The CoMaps source code in `thirdparty/comaps/` is the authoritative reference for what's available in the native engine.

### 8. Common Patterns

#### Async Operations with Callbacks

For async operations (search, routing), use Dart `Future` with completion callbacks:

```dart
Future<List<SearchResult>> searchEverywhere(String query) async {
  final completer = Completer<List<SearchResult>>();
  
  // Register callback in native code
  _searchCallbackId = _registerSearchCallback((results) {
    completer.complete(results);
  });
  
  // Trigger native search
  _bindings.comaps_search_everywhere(query.toNativeUtf8());
  
  return completer.future;
}
```

See `searchEverywhere()` implementation patterns in the CoMaps Qt code for reference.

#### String Handling

Always free native strings:

```dart
String getCountryName(double lat, double lon) {
  final pathPtr = _bindings.comaps_get_country_name(lat, lon);
  if (pathPtr == nullptr) return '';
  
  try {
    return pathPtr.toDartString();
  } finally {
    malloc.free(pathPtr);
  }
}
```

#### Error Handling

Return meaningful error codes or throw Dart exceptions:

```dart
int registerMap(String path) {
  final result = _bindings.comaps_register_map(path.toNativeUtf8());
  if (result < 0) {
    throw AgusMapsException('Failed to register map: $path', result);
  }
  return result;
}
```

## Existing APIs

### Initialization and Setup

#### `init(String apkPath, String storagePath)`
Initialize CoMaps with APK path and storage path (legacy API).
- **Parameters**: 
  - `apkPath`: Path to APK/bundle containing resources
  - `storagePath`: Writable storage directory
- **Implementation**: Fully implemented via FFI
- **Platforms**: Android (legacy)

#### `initWithPaths(String resourcePath, String writablePath)`
Initialize CoMaps with separate resource and writable paths (preferred API).
- **Parameters**:
  - `resourcePath`: Read-only directory containing CoMaps data files
  - `writablePath`: Writable directory for maps and cache
- **Implementation**: Fully implemented via FFI
- **Platforms**: All

#### `extractMap(String assetPath) -> Future<String>`
Extract a single MWM map file from Flutter assets.
- **Parameters**: `assetPath`: Asset path (e.g., `"assets/maps/World.mwm"`)
- **Returns**: Path to extracted file on device
- **Implementation**: MethodChannel-based, fully implemented
- **Platforms**: All

#### `extractDataFiles() -> Future<String>`
Extract all CoMaps data files (classificator, types, categories, etc.) from assets.
- **Returns**: Path to directory containing extracted files
- **Implementation**: MethodChannel-based, fully implemented
- **Platforms**: All

#### `getApkPath() -> Future<String>`
Get the APK/bundle resource path (platform-specific).
- **Returns**: Path to application bundle resources
- **Implementation**: MethodChannel-based, fully implemented
- **Platforms**: All (returns appropriate path for each platform)

### Map File Registration

#### `registerSingleMap(String fullPath) -> int`
Register a single MWM map file by full path.
- **Parameters**: `fullPath`: Complete file system path to `.mwm` file
- **Returns**: `0` on success, negative on error, positive for `MwmSet::RegResult` codes
- **Implementation**: Fully implemented via FFI
- **Note**: Uses default version (0), may fail for World/WorldCoasts

#### `registerSingleMapWithVersion(String fullPath, int version) -> int`
Register a single MWM map file with explicit snapshot version.
- **Parameters**:
  - `fullPath`: Complete file system path to `.mwm` file
  - `version`: Snapshot version (e.g., `251209` for YYMMDD format)
- **Returns**: `0` on success, negative on error, positive for `MwmSet::RegResult` codes
- **Implementation**: Fully implemented via FFI (with fallback to `registerSingleMap`)
- **Note**: Preferred method to avoid `VersionTooOld` errors

#### `debugListMwms()`
List all registered MWMs and their bounds (debug utility).
- **Output**: Logged to platform-specific log (logcat on Android)
- **Implementation**: Fully implemented via FFI

#### `debugCheckPoint(double lat, double lon)`
Check if a lat/lon point is covered by any registered MWM (debug utility).
- **Parameters**: `lat`, `lon`: WGS84 coordinates
- **Output**: Logged to platform-specific log
- **Implementation**: Fully implemented via FFI

### Viewport Control

#### `setView(double lat, double lon, int zoom)`
Set the map viewport center and zoom level.
- **Parameters**:
  - `lat`, `lon`: WGS84 coordinates for center point
  - `zoom`: Zoom level (typically 0-20, higher = more zoomed in)
- **Implementation**: Fully implemented via FFI
- **Note**: Non-animated; for animated movement, use `AgusMapController.animateToLocation()` (currently stub)

#### `invalidateMap()`
Invalidate the current viewport to force tile reload.
- **Implementation**: Fully implemented via FFI
- **Use Case**: Call after registering maps to ensure tiles refresh

#### `forceRedraw()`
Force a complete redraw by updating map style (more aggressive than `invalidateMap`).
- **Implementation**: Fully implemented via FFI
- **Use Case**: Call after registering maps when DrapeEngine was already initialized

### Touch and Gesture Input

#### `sendTouchEvent(TouchType type, int id1, double x1, double y1, {int id2 = -1, double x2 = 0, double y2 = 0})`
Send a touch event to the map engine.
- **Parameters**:
  - `type`: Touch event type (`TouchType.down`, `.move`, `.up`, `.cancel`)
  - `id1`, `x1`, `y1`: First pointer ID and coordinates (physical pixels)
  - `id2`, `x2`, `y2`: Second pointer (for multitouch, use `-1` for `id2` if single touch)
- **Implementation**: Fully implemented via FFI, automatically called by `AgusMap` widget
- **Note**: Coordinates should be in physical pixels, not logical pixels

#### `scaleMap(double factor, double pixelX, double pixelY, {bool animated = false})`
Scale (zoom) the map by a factor, centered on a specific pixel point.
- **Parameters**:
  - `factor`: Zoom factor (>1 zooms in, <1 zooms out). Use `exp(scrollDelta)` for smooth Google Maps-like zoom
  - `pixelX`, `pixelY`: Screen coordinates to zoom towards (physical pixels)
  - `animated`: Whether to animate the zoom transition
- **Implementation**: Fully implemented via FFI
- **Use Case**: Preferred method for scroll wheel zoom on desktop platforms

#### `scrollMap(double distanceX, double distanceY)`
Scroll/pan the map by pixel distance.
- **Parameters**: `distanceX`, `distanceY`: Distances to scroll in physical pixels
- **Implementation**: Fully implemented via FFI

### Surface Management

#### `createMapSurface({int? width, int? height, double? density}) -> Future<int>`
Create a map rendering surface with given dimensions.
- **Parameters** (all optional):
  - `width`, `height`: Physical pixel dimensions (defaults to screen size)
  - `density`: Device pixel ratio / visual scale (e.g., `2.0` for Retina displays). On Windows this enables DPI-aware label scaling without recreating the surface.
- **Returns**: Texture ID for Flutter `Texture` widget
- **Implementation**: MethodChannel-based, platform-specific (Android/iOS/macOS/Linux/Windows)
- **Platforms**: All

#### `resizeMapSurface(int width, int height, {double? density}) -> Future<void>`
Resize the map surface to new dimensions.
- **Parameters**:
  - `width`, `height`: New physical pixel dimensions
  - `density`: Optional visual scale for DPI changes (Windows)
- **Implementation**: MethodChannel-based, fully implemented
- **Platforms**: All

### Widget API

#### `AgusMap` Widget
Main Flutter widget that displays a CoMaps map.

**Properties**:
- `initialLat`, `initialLon`: Initial map center (WGS84)
- `initialZoom`: Initial zoom level (0-20)
- `onMapReady`: Callback when map is ready
- `controller`: `AgusMapController` for programmatic control
- `isVisible`: Whether map is currently visible (for `IndexedStack` optimization)
- `userScale`: Visual scale multiplier for labels (combined with device pixel ratio)

**Implementation**: Fully implemented with gesture handling, surface management, and visibility optimization

#### `AgusMapController` Class
Controller for programmatic map control.

**Methods**:
- `moveToLocation(double lat, double lon, int zoom)`: Move map to location (non-animated)
- `animateToLocation(double lat, double lon, int zoom)`: Move map to location (animated) - **TODO: Not yet implemented**
- `zoomIn()`: Zoom in by one level - **TODO: Not yet implemented**
- `zoomOut()`: Zoom out by one level - **TODO: Not yet implemented**

### Helper Services

#### `MwmStorage` Class (Dart-only)
Storage service for MWM file metadata (not exposed to native).

**Methods**:
- `create() -> Future<MwmStorage>`: Create storage instance
- `getAll() -> List<MwmMetadata>`: Get all stored metadata
- `getByRegion(String regionName) -> MwmMetadata?`: Get metadata for specific region
- `upsert(MwmMetadata metadata) -> Future<void>`: Add or update metadata
- `remove(String regionName) -> Future<void>`: Remove metadata
- `validateFile(String regionName) -> Future<FileValidationResult>`: Validate file exists and size matches
- Many more utility methods for metadata management

#### `MirrorService` Class (Dart-only)
Service for discovering and downloading MWM files from mirror servers.

**Methods**:
- `measureLatencies() -> Future<void>`: Measure latency to all mirrors
- `getFastestMirror() -> Mirror?`: Get fastest available mirror
- `getSnapshots(Mirror mirror) -> Future<List<Snapshot>>`: Get available snapshot versions
- `getRegions(Mirror mirror, Snapshot snapshot) -> Future<List<MwmRegion>>`: Get regions in snapshot
- `downloadToFile(String url, File destination, {onProgress}) -> Future<int>`: Download file with progress
- Many more utility methods for map discovery and download


## Future API Candidates

The following APIs are candidates for future exposure to Flutter. Each is marked with implementation difficulty and a brief description.

### Viewport and Camera Control

#### `getViewportCenter() -> (double lat, double lon)`
Get current viewport center coordinates.
- **Difficulty**: Easy (existing `GetViewportCenter()` in Framework)
- **Returns**: Current center point in WGS84
- **Use Case**: Save/restore viewport state, sync with external components

#### `getCurrentZoom() -> int`
Get current zoom level.
- **Difficulty**: Easy (can derive from `GetDrawScale()` or `GetCurrentViewport()`)
- **Returns**: Current zoom level (0-20)
- **Use Case**: Display zoom level in UI, implement zoom controls

#### `animateToLocation(double lat, double lon, int zoom, {Duration duration})`
Animate camera to location with specified duration.
- **Difficulty**: Medium (Framework has `SetViewportCenter()` with `isAnim` flag, but duration control may need interpolation)
- **Parameters**: Target location, zoom, and optional animation duration
- **Use Case**: Smooth transitions, guided tours

#### `fitBounds(double minLat, double minLon, double maxLat, double maxLon, {Padding padding})`
Fit viewport to bounding box with optional padding.
- **Difficulty**: Medium (Framework has `ShowRect()` which can be adapted)
- **Parameters**: Bounding box coordinates and optional padding
- **Use Case**: Show all search results, fit route bounds

#### `setCameraTilt(double tilt)`
Set 3D camera tilt angle (for 3D buildings mode).
- **Difficulty**: Medium (requires 3D mode to be enabled, Framework has `Allow3dMode()`)
- **Parameters**: Tilt angle in degrees (0 = top-down, 90 = side view)
- **Use Case**: 3D map visualization, architectural views

#### `setCameraBearing(double bearing)`
Set map rotation/bearing.
- **Difficulty**: Easy (Framework has `Rotate()` method)
- **Parameters**: Bearing in degrees (0 = north up, 90 = east up)
- **Use Case**: Compass mode, navigation-oriented maps

#### `getCurrentBearing() -> double`
Get current map rotation/bearing.
- **Difficulty**: Easy (can derive from `ScreenBase` model view)
- **Returns**: Current bearing in degrees
- **Use Case**: Display compass, sync with device orientation

#### `setMinZoom(int minZoom)` / `setMaxZoom(int maxZoom)`
Set zoom level constraints.
- **Difficulty**: Medium (Framework has scale constraints, needs mapping to zoom levels)
- **Parameters**: Minimum/maximum zoom levels
- **Use Case**: Prevent excessive zoom in/out, enforce data coverage limits

#### `getVisibleBounds() -> MapBounds`
Get bounding box of currently visible viewport.
- **Difficulty**: Easy (Framework has `GetCurrentViewport()` which returns `m2::RectD`)
- **Returns**: `{minLat, minLon, maxLat, maxLon}`
- **Use Case**: Query features in viewport, geofencing

### Search and Geocoding

#### `searchEverywhere(String query, {String locale, int maxResults}) -> Future<List<SearchResult>>`
Search for places everywhere (global search).
- **Difficulty**: Medium (Framework has `SearchEverywhere()` with async callback pattern, needs Dart Future wrapper)
- **Parameters**: Query string, optional locale and max results
- **Returns**: List of search results with coordinates, names, types
- **Use Case**: Address search, POI discovery

#### `searchInViewport(String query, {String locale}) -> Future<List<SearchResult>>`
Search for places within current viewport.
- **Difficulty**: Medium (Framework has `SearchInViewport()` with async callback pattern)
- **Parameters**: Query string, optional locale
- **Returns**: List of search results within viewport
- **Use Case**: Local POI search, "what's around me"

#### `reverseGeocode(double lat, double lon) -> Future<Address?>`
Reverse geocode coordinates to address.
- **Difficulty**: Medium (Framework has `GetAddressAtPoint()` which returns `ReverseGeocoder::Address`)
- **Parameters**: WGS84 coordinates
- **Returns**: Address information (street, city, country, etc.)
- **Use Case**: Display address for tapped location, location sharing

#### `geocode(String address) -> Future<List<LocationResult>>`
Geocode address string to coordinates.
- **Difficulty**: Hard (Requires search engine integration, Framework has search but may need address parsing)
- **Parameters**: Address string
- **Returns**: List of matching locations with coordinates
- **Use Case**: Convert addresses to coordinates for routing

#### `getSearchSuggestions(String partialQuery) -> Future<List<String>>`
Get autocomplete suggestions for search query.
- **Difficulty**: Hard (May require extending search engine, Framework has query saving but not suggestions)
- **Parameters**: Partial query string
- **Returns**: List of suggested completions
- **Use Case**: Search autocomplete, type-ahead

#### `searchNearby(double lat, double lon, String category, {double radiusMeters}) -> Future<List<POI>>`
Search for POIs near a location by category.
- **Difficulty**: Medium (Framework has category search, needs distance filtering)
- **Parameters**: Center point, category name/type, optional radius
- **Returns**: List of nearby POIs
- **Use Case**: "Find restaurants near me", category-based discovery

#### `getSearchHistory() -> List<String>`
Get list of recent search queries.
- **Difficulty**: Easy (Framework has `GetLastSearchQueries()`)
- **Returns**: List of recent queries
- **Use Case**: Recent searches UI, quick re-search

#### `clearSearchHistory()`
Clear search query history.
- **Difficulty**: Easy (Framework has `ClearSearchHistory()`)
- **Use Case**: Privacy settings, reset functionality

### Bookmarks and Tracks

#### `addBookmark(String name, double lat, double lon, {String description, String color}) -> String bookmarkId`
Create a bookmark at specified location.
- **Difficulty**: Medium (Framework has `CreateBookmark()` but requires KML data structure creation)
- **Parameters**: Name, location, optional description and color
- **Returns**: Bookmark ID
- **Use Case**: Save favorite locations, user-defined points of interest

#### `getBookmark(String bookmarkId) -> Bookmark?`
Get bookmark by ID.
- **Difficulty**: Easy (Framework has `GetBookmark()`)
- **Parameters**: Bookmark ID
- **Returns**: Bookmark data or null
- **Use Case**: Display bookmark details, edit bookmark

#### `updateBookmark(String bookmarkId, {String? name, String? description, String? color})`
Update bookmark properties.
- **Difficulty**: Easy (Framework has `GetBookmarkForEdit()` and update methods)
- **Parameters**: Bookmark ID and optional new values
- **Use Case**: Edit bookmark metadata

#### `deleteBookmark(String bookmarkId)`
Delete a bookmark.
- **Difficulty**: Easy (Framework has `DeleteBookmark()`)
- **Parameters**: Bookmark ID
- **Use Case**: Remove saved locations

#### `getAllBookmarks() -> List<Bookmark>`
Get all bookmarks.
- **Difficulty**: Medium (Framework has `GetUserMarkIds()` and category iteration)
- **Returns**: List of all bookmarks
- **Use Case**: Bookmark manager UI, export bookmarks

#### `createBookmarkCategory(String name) -> String categoryId`
Create a new bookmark category/folder.
- **Difficulty**: Easy (Framework has `CreateBookmarkCategory()`)
- **Parameters**: Category name
- **Returns**: Category ID
- **Use Case**: Organize bookmarks into folders

#### `addBookmarkToCategory(String bookmarkId, String categoryId)`
Add bookmark to category.
- **Difficulty**: Medium (Framework has category management but may need bookmark move functionality)
- **Parameters**: Bookmark ID and category ID
- **Use Case**: Organize bookmarks

#### `getBookmarksInCategory(String categoryId) -> List<Bookmark>`
Get all bookmarks in a category.
- **Difficulty**: Easy (Framework has `GetUserMarkIds(groupId)`)
- **Parameters**: Category ID
- **Returns**: List of bookmarks in category
- **Use Case**: Display category contents

#### `startTrackRecording()`
Start recording a GPS track.
- **Difficulty**: Easy (Framework has `StartTrackRecording()`)
- **Use Case**: Activity tracking, route recording

#### `stopTrackRecording()`
Stop recording GPS track.
- **Difficulty**: Easy (Framework has `StopTrackRecording()`)
- **Use Case**: End activity recording

#### `saveTrackRecording(String name) -> String trackId`
Save recorded track with name.
- **Difficulty**: Easy (Framework has `SaveTrackRecordingWithName()`)
- **Parameters**: Track name
- **Returns**: Track ID
- **Use Case**: Save activity, create route from track

#### `getTrack(String trackId) -> Track?`
Get track by ID.
- **Difficulty**: Easy (Framework has `GetTrack()`)
- **Parameters**: Track ID
- **Returns**: Track data with points
- **Use Case**: Display track on map, analyze activity

#### `getAllTracks() -> List<Track>`
Get all saved tracks.
- **Difficulty**: Medium (Similar to bookmarks, needs category iteration)
- **Returns**: List of all tracks
- **Use Case**: Track manager UI, export tracks

#### `deleteTrack(String trackId)`
Delete a track.
- **Difficulty**: Easy (Framework has `DeleteTrack()`)
- **Parameters**: Track ID
- **Use Case**: Remove old activities

#### `getTrackStatistics(String trackId) -> TrackStatistics`
Get statistics for a track (distance, duration, elevation gain, etc.).
- **Difficulty**: Medium (Framework has `TrackStatistics` type, needs track ID lookup)
- **Parameters**: Track ID
- **Returns**: Statistics object
- **Use Case**: Display activity metrics, leaderboards

### Routing and Navigation

#### `buildRoute(List<RoutePoint> points, {RouterType type, VehicleType vehicle}) -> Future<RouteResult>`
Build a route through specified points.
- **Difficulty**: Hard (Framework has `BuildRoute()` but requires complex setup with RoutingManager, async callbacks)
- **Parameters**: List of route points (lat/lon), optional router type and vehicle type
- **Returns**: Route result with geometry, distance, duration, turn-by-turn instructions
- **Use Case**: Turn-by-turn navigation, route planning

#### `followRoute(bool follow)`
Enable/disable route following mode (camera follows route).
- **Difficulty**: Medium (Framework has `FollowRoute()` method)
- **Parameters**: Whether to follow route
- **Use Case**: Active navigation mode

#### `getRouteGeometry() -> List<LatLon>`
Get current route geometry as list of coordinates.
- **Difficulty**: Medium (Framework has route access via RoutingManager, needs coordinate extraction)
- **Returns**: List of route waypoints
- **Use Case**: Display route polyline, calculate route bounds

#### `getRouteInstructions() -> List<RouteInstruction>`
Get turn-by-turn instructions for current route.
- **Difficulty**: Hard (Framework has turn-by-turn data but complex structure, needs simplification)
- **Returns**: List of instructions with distance, bearing, description
- **Use Case**: Navigation UI, route preview

#### `getRouteDistance() -> double`
Get total route distance in meters.
- **Difficulty**: Easy (Framework has route distance calculation)
- **Returns**: Distance in meters
- **Use Case**: Display route summary, route comparison

#### `getRouteDuration() -> Duration`
Get estimated route duration.
- **Difficulty**: Easy (Framework has route duration calculation)
- **Returns**: Estimated duration
- **Use Case**: Display ETA, route planning

#### `setRoutePoint(int index, double lat, double lon)`
Update a route waypoint.
- **Difficulty**: Medium (Framework has route point management but may need route rebuilding)
- **Parameters**: Waypoint index and new coordinates
- **Use Case**: Drag-and-drop route editing

#### `addRoutePoint(int index, double lat, double lon)`
Add intermediate waypoint to route.
- **Difficulty**: Hard (Requires route rebuilding with new point)
- **Parameters**: Insertion index and coordinates
- **Use Case**: Add stops to route, waypoint planning

#### `removeRoutePoint(int index)`
Remove waypoint from route.
- **Difficulty**: Hard (Requires route rebuilding)
- **Parameters**: Waypoint index
- **Use Case**: Remove stops, simplify route

#### `clearRoute()`
Clear current route.
- **Difficulty**: Easy (Framework has `ResetRoutingSession()`)
- **Use Case**: Cancel navigation, reset route

#### `isRouteActive() -> bool`
Check if route is currently active.
- **Difficulty**: Easy (Framework has `IsRoutingActive()`)
- **Returns**: Whether route is active
- **Use Case**: Update UI state, navigation status

#### `getCurrentRoutePosition() -> RoutePosition?`
Get current position along route (for navigation).
- **Difficulty**: Hard (Requires position tracking and route matching)
- **Returns**: Current position on route with distance remaining, next instruction
- **Use Case**: Active navigation UI, progress tracking

#### `setVehicleType(VehicleType type)`
Set routing vehicle type (car, pedestrian, bicycle, transit).
- **Difficulty**: Medium (Framework has router type switching)
- **Parameters**: Vehicle type enum
- **Use Case**: Multi-modal routing, route optimization

#### `calculateDistance(List<LatLon> points) -> double`
Calculate total distance along path (for non-routed paths).
- **Difficulty**: Easy (Can use geometry calculations, Framework may have utilities)
- **Parameters**: List of coordinates
- **Returns**: Total distance in meters
- **Use Case**: Track distance, path measurement

### Map Features and Objects

#### `getFeatureAtPoint(double lat, double lon) -> FeatureInfo?`
Get map feature (POI, building, road) at specified point.
- **Difficulty**: Medium (Framework has `GetFeatureAtPoint()` and `GetMapObjectByID()`)
- **Parameters**: WGS84 coordinates
- **Returns**: Feature information (name, type, metadata) or null
- **Use Case**: Show POI details on tap, feature inspection

#### `getFeaturesInBounds(double minLat, double minLon, double maxLat, double maxLon, {String? category}) -> Future<List<FeatureInfo>>`
Get all features within bounding box, optionally filtered by category.
- **Difficulty**: Medium (Framework has `ReadFeatures()` with rect, needs category filtering)
- **Parameters**: Bounding box, optional category filter
- **Returns**: List of features in bounds
- **Use Case**: Area analysis, feature density maps, category-based queries

#### `getFeaturesNearby(double lat, double lon, double radiusMeters, {String? category}) -> Future<List<FeatureInfo>>`
Get features near a point within radius.
- **Difficulty**: Medium (Can use bounding box calculation from point+radius, then filter by distance)
- **Parameters**: Center point, radius in meters, optional category
- **Returns**: List of nearby features
- **Use Case**: "What's around me", proximity search

#### `highlightFeature(String featureId)`
Highlight a specific feature on the map.
- **Difficulty**: Medium (Framework has DrapeApi for custom overlays, may need feature ID to geometry mapping)
- **Parameters**: Feature ID
- **Use Case**: Search result highlighting, feature selection

#### `clearHighlight()`
Clear all feature highlights.
- **Difficulty**: Easy (Clear DrapeApi overlays)
- **Use Case**: Deselect features, reset highlights

#### `getFeatureMetadata(String featureId) -> Map<String, dynamic>`
Get extended metadata for a feature (opening hours, phone, website, etc.).
- **Difficulty**: Hard (Framework has feature metadata access but structure is complex, needs serialization)
- **Parameters**: Feature ID
- **Returns**: Map of metadata keys and values
- **Use Case**: POI detail pages, business information display

#### `addCustomMarker(double lat, double lon, {String? icon, String? label}) -> String markerId`
Add custom marker/pin to map.
- **Difficulty**: Medium (Framework has DrapeApi for custom overlays, needs marker rendering)
- **Parameters**: Location, optional icon and label
- **Returns**: Marker ID for later manipulation
- **Use Case**: Custom annotations, user-defined markers

#### `updateCustomMarker(String markerId, {double? lat, double? lon, String? icon, String? label})`
Update custom marker properties.
- **Difficulty**: Easy (Update DrapeApi overlay)
- **Parameters**: Marker ID and optional new values
- **Use Case**: Move markers, update marker appearance

#### `removeCustomMarker(String markerId)`
Remove custom marker.
- **Difficulty**: Easy (Remove DrapeApi overlay)
- **Parameters**: Marker ID
- **Use Case**: Clear temporary markers, cleanup

#### `addPolyline(List<LatLon> points, {Color color, double width}) -> String polylineId`
Draw polyline on map.
- **Difficulty**: Medium (Framework has DrapeApi for custom geometry)
- **Parameters**: List of coordinates, optional color and width
- **Returns**: Polyline ID
- **Use Case**: Route display, path visualization

#### `addPolygon(List<LatLon> points, {Color fillColor, Color strokeColor}) -> String polygonId`
Draw polygon on map.
- **Difficulty**: Medium (Framework has DrapeApi for custom geometry)
- **Parameters**: List of coordinates forming closed polygon, optional colors
- **Returns**: Polygon ID
- **Use Case**: Area highlighting, region visualization

#### `addCircle(double lat, double lon, double radiusMeters, {Color fillColor, Color strokeColor}) -> String circleId`
Draw circle on map.
- **Difficulty**: Medium (Can convert circle to polygon or use DrapeApi)
- **Parameters**: Center, radius in meters, optional colors
- **Returns**: Circle ID
- **Use Case**: Geofencing visualization, search radius display

#### `removeOverlay(String overlayId)`
Remove custom overlay (polyline, polygon, circle, marker).
- **Difficulty**: Easy (Remove from DrapeApi)
- **Parameters**: Overlay ID
- **Use Case**: Clear temporary overlays

#### `clearAllOverlays()`
Remove all custom overlays.
- **Difficulty**: Easy (Clear all DrapeApi overlays)
- **Use Case**: Reset map, cleanup overlays

### Map Style and Display

#### `setMapStyle(MapStyle style)`
Change map style (default, dark, vehicle, etc.).
- **Difficulty**: Easy (Framework has `SetMapStyle()`)
- **Parameters**: Style enum (Default, Dark, Vehicle, Outdoor, etc.)
- **Use Case**: Theme switching, style preferences

#### `getMapStyle() -> MapStyle`
Get current map style.
- **Difficulty**: Easy (Framework has `GetMapStyle()`)
- **Returns**: Current style enum
- **Use Case**: Sync UI with map style, save preferences

#### `enable3DBuildings(bool enable)`
Enable/disable 3D building rendering.
- **Difficulty**: Easy (Framework has `Allow3dMode()`)
- **Parameters**: Whether to show 3D buildings
- **Use Case**: 3D visualization, performance optimization

#### `setBuildings3D(bool buildings3D)`
Enable/disable 3D buildings specifically (separate from overall 3D mode).
- **Difficulty**: Easy (Framework has `Allow3dMode(bool allow3d, bool allow3dBuildings)`)
- **Parameters**: Whether to show 3D buildings
- **Use Case**: Fine-grained 3D control

#### `enableTraffic(bool enable)`
Show/hide traffic information.
- **Difficulty**: Easy (Framework has TrafficManager with enable/disable methods)
- **Parameters**: Whether to show traffic
- **Use Case**: Traffic-aware routing, traffic visualization

#### `getTrafficEnabled() -> bool`
Check if traffic display is enabled.
- **Difficulty**: Easy (Framework has `LoadTrafficEnabled()`)
- **Returns**: Whether traffic is shown
- **Use Case**: Sync UI state, preferences

#### `enableTransit(bool enable)`
Show/hide transit lines and stations.
- **Difficulty**: Medium (Framework has TransitManager, may need TransitReadManager integration)
- **Parameters**: Whether to show transit
- **Use Case**: Public transit planning, multimodal maps

#### `enableIsolines(bool enable)`
Show/hide isolines (elevation contours, etc.).
- **Difficulty**: Medium (Framework has IsolinesManager)
- **Parameters**: Whether to show isolines
- **Use Case**: Hiking maps, elevation visualization

#### `enableOutdoors(bool enable)`
Enable outdoor/topographic map style.
- **Difficulty**: Easy (Framework has `SaveOutdoorsEnabled()` / `LoadOutdoorsEnabled()`)
- **Parameters**: Whether to use outdoor style
- **Use Case**: Hiking, outdoor activities

#### `setLanguage(String languageCode)`
Set map language for labels and search.
- **Difficulty**: Easy (Framework has `SetMapLanguageCode()`)
- **Parameters**: Language code (e.g., "en", "es", "fr")
- **Use Case**: Localization, multilingual apps

#### `getLanguage() -> String`
Get current map language.
- **Difficulty**: Easy (Framework has `GetMapLanguageCode()`)
- **Returns**: Current language code
- **Use Case**: Display current language, sync with app locale

#### `setUnits(MetricSystem system)`
Set measurement system (metric vs imperial).
- **Difficulty**: Easy (Framework has `SetupMeasurementSystem()`)
- **Parameters**: Measurement system enum
- **Use Case**: Unit preferences, regional settings

#### `setLargeFonts(bool large)`
Enable/disable large fonts for accessibility.
- **Difficulty**: Easy (Framework has `SetLargeFontsSize()`)
- **Parameters**: Whether to use large fonts
- **Use Case**: Accessibility, readability

### Location Services

#### `enableMyLocation(bool enable)`
Enable/disable "my location" marker and tracking.
- **Difficulty**: Medium (Framework has `ConnectToGpsTracker()` / `DisconnectFromGpsTracker()` and position mode)
- **Parameters**: Whether to show user location
- **Use Case**: Location-based apps, "find me" feature

#### `setMyLocationMode(MyLocationMode mode)`
Set location display mode (none, normal, compass, navigation).
- **Difficulty**: Medium (Framework has `SetMyPositionModeListener()` and `GetMyPositionMode()`)
- **Parameters**: Location mode enum
- **Use Case**: Different location tracking modes, navigation UI

#### `getMyLocation() -> Location?`
Get current device location if available.
- **Difficulty**: Medium (Framework has `GetCurrentPosition()` but requires location provider setup)
- **Returns**: Current location (lat, lon, accuracy, timestamp) or null
- **Use Case**: Location-based features, position tracking

#### `onLocationUpdate(LocationCallback callback)`
Set callback for location updates.
- **Difficulty**: Hard (Requires location provider integration, Framework has callbacks but needs Dart bridge)
- **Parameters**: Callback function receiving location updates
- **Returns**: Stream subscription for cleanup
- **Use Case**: Real-time location tracking, background location

#### `followMyLocation(bool follow)`
Enable/disable camera following user location.
- **Difficulty**: Medium (Framework has `StopLocationFollow()` and follow mode in routing)
- **Parameters**: Whether to follow location
- **Use Case**: Navigation mode, activity tracking

#### `setLocationUpdateInterval(Duration interval)`
Set minimum time between location updates.
- **Difficulty**: Hard (Requires location provider configuration, may need platform-specific code)
- **Parameters**: Minimum update interval
- **Use Case**: Battery optimization, reduce update frequency

#### `onCompassUpdate(CompassCallback callback)`
Set callback for compass/bearing updates.
- **Difficulty**: Hard (Framework has `OnCompassUpdate()` but needs Dart bridge and device sensor access)
- **Parameters**: Callback function receiving compass bearing
- **Returns**: Stream subscription
- **Use Case**: Compass mode, orientation-aware maps

### Storage and Map Management

#### `getRegisteredMaps() -> List<MapInfo>`
Get list of all registered/loaded map files.
- **Difficulty**: Medium (Framework has `GetMwmsInfo()` but needs serialization to Dart types)
- **Returns**: List of map info (name, bounds, version, size, etc.)
- **Use Case**: Map management UI, storage display

#### `getRegisteredMapsCount() -> int`
Get count of registered maps (already declared in header but not implemented in Dart).
- **Difficulty**: Easy (Native implementation exists, needs Dart binding)
- **Returns**: Number of registered maps
- **Use Case**: Quick status check, debug info

#### `deregisterMap(String mapPath) -> bool`
Deregister a map file (already declared in header but not implemented in Dart).
- **Difficulty**: Easy (Native implementation exists, needs Dart binding)
- **Parameters**: Full path to map file
- **Returns**: Success status
- **Use Case**: Map cleanup, memory management

#### `isMapLoaded(String countryName) -> bool`
Check if a specific country/region map is loaded.
- **Difficulty**: Easy (Framework has `IsCountryLoadedByName()`)
- **Parameters**: Country/region name
- **Returns**: Whether map is loaded
- **Use Case**: Conditional feature availability, map status checks

#### `getMapBounds(String countryName) -> MapBounds?`
Get bounding box for a country/region map.
- **Difficulty**: Medium (Framework has country info, needs bounds lookup and serialization)
- **Parameters**: Country/region name
- **Returns**: Bounding box or null if map not found
- **Use Case**: Fit map to country, bounds validation

#### `getMapVersion(String countryName) -> int?`
Get version/snapshot date for a loaded map.
- **Difficulty**: Medium (Framework has map version info, needs serialization)
- **Parameters**: Country/region name
- **Returns**: Map version (snapshot date) or null
- **Use Case**: Map update detection, version display

#### `getCountryName(double lat, double lon) -> String?`
Get country/region name at specified coordinates.
- **Difficulty**: Easy (Framework has `GetCountryName()`)
- **Parameters**: WGS84 coordinates
- **Returns**: Country name or null
- **Use Case**: Location-based features, country detection

#### `getCountriesInBounds(double minLat, double minLon, double maxLat, double maxLon) -> List<String>`
Get list of countries/regions intersecting bounding box.
- **Difficulty**: Medium (Framework has `GetRegionsCountryIdByRect()`)
- **Parameters**: Bounding box
- **Returns**: List of country/region names
- **Use Case**: Multi-country queries, region analysis

#### `getStorageSize() -> int`
Get total size of downloaded/registered maps in bytes.
- **Difficulty**: Medium (Needs to iterate registered maps and sum sizes)
- **Returns**: Total size in bytes
- **Use Case**: Storage management UI, disk space warnings

#### `clearMapCache()`
Clear map tile cache (but keep map files).
- **Difficulty**: Medium (Framework has cache management, needs cache directory clearing)
- **Use Case**: Free up disk space, force tile refresh

#### `setCacheSizeLimit(int maxBytes)`
Set maximum cache size.
- **Difficulty**: Hard (Requires cache size monitoring and eviction logic)
- **Parameters**: Maximum cache size in bytes
- **Use Case**: Storage management, cache control

### Debug and Development

#### `enableDebugRendering(bool enable)`
Enable debug rendering (shows tile boundaries, etc.).
- **Difficulty**: Easy (Framework has `EnableDebugRectRendering()`)
- **Parameters**: Whether to enable debug rendering
- **Use Case**: Development, debugging rendering issues

#### `getPerformanceMetrics() -> PerformanceMetrics`
Get rendering performance metrics (FPS, frame time, etc.).
- **Difficulty**: Hard (Requires performance monitoring infrastructure, Framework may have some metrics)
- **Returns**: Performance metrics object
- **Use Case**: Performance optimization, monitoring

#### `setLogLevel(LogLevel level)`
Set native logging verbosity.
- **Difficulty**: Easy (Framework has logging levels, needs Dart binding)
- **Parameters**: Log level (Debug, Info, Warning, Error)
- **Use Case**: Development, production logging control

#### `exportMapState() -> String`
Export current map state (viewport, style, etc.) as JSON.
- **Difficulty**: Medium (Serialize viewport, style, and other state to JSON)
- **Returns**: JSON string representing map state
- **Use Case**: State persistence, debugging, state sharing

#### `importMapState(String json)`
Restore map state from JSON export.
- **Difficulty**: Medium (Parse JSON and restore viewport, style, etc.)
- **Parameters**: JSON string from `exportMapState()`
- **Use Case**: State restoration, saved views

#### `getTileInfo(double lat, double lon, int zoom) -> TileInfo?`
Get information about tile at coordinates and zoom level.
- **Difficulty**: Medium (Calculate tile coordinates and query tile cache/data)
- **Parameters**: Location and zoom level
- **Returns**: Tile information (coordinates, load status, etc.)
- **Use Case**: Debugging tile loading, tile inspection


## Implementation Priority Recommendations

### High Priority (Core Functionality)

1. **Viewport Control**: `getViewportCenter()`, `getCurrentZoom()`, `animateToLocation()`, `fitBounds()`
2. **Search**: `searchEverywhere()`, `searchInViewport()`, `reverseGeocode()`
3. **Bookmarks**: `addBookmark()`, `getAllBookmarks()`, `deleteBookmark()`, `createBookmarkCategory()`
4. **Tracks**: `startTrackRecording()`, `stopTrackRecording()`, `saveTrackRecording()`, `getTrackStatistics()`
5. **Custom Overlays**: `addCustomMarker()`, `addPolyline()`, `removeOverlay()`

### Medium Priority (Enhanced Features)

1. **Map Style**: `setMapStyle()`, `enable3DBuildings()`, `enableTraffic()`, `setLanguage()`
2. **Location Services**: `enableMyLocation()`, `getMyLocation()`, `followMyLocation()`
3. **Map Features**: `getFeatureAtPoint()`, `getFeaturesInBounds()`, `getFeatureMetadata()`
4. **Routing**: `buildRoute()`, `getRouteGeometry()`, `getRouteDistance()`, `clearRoute()`
5. **Storage Management**: `getRegisteredMaps()`, `getStorageSize()`, `clearMapCache()`

### Low Priority (Nice to Have)

1. **Advanced Routing**: `getRouteInstructions()`, `setRoutePoint()`, `getCurrentRoutePosition()`
2. **Advanced Search**: `getSearchSuggestions()`, `searchNearby()`, `geocode()`
3. **Advanced Location**: `onLocationUpdate()`, `onCompassUpdate()`, `setLocationUpdateInterval()`
4. **Debug Tools**: `getPerformanceMetrics()`, `exportMapState()`, `getTileInfo()`
5. **Advanced Overlays**: `addPolygon()`, `addCircle()`, complex overlay styling


## Notes on Implementation Difficulty

- **Easy**: Native API exists and is straightforward to bind, minimal data transformation needed
- **Medium**: Native API exists but requires significant data transformation, async callback patterns, or Dart type mapping
- **Hard**: Requires new native implementation, complex async patterns, platform-specific code, or extensive serialization

Most APIs in the "Medium" category are reasonable to implement and provide good value. "Hard" APIs may require more significant architectural decisions or may be better suited for future plugin versions.

## Related Documentation

This API reference is part of a larger documentation ecosystem. For more information:

### Getting Started

- **[README.md](../README.md)** - Overview, quick start, installation guide, and feature comparison
- **[CONTRIBUTING.md](CONTRIBUTING.md)** - Development setup, build instructions, commit guidelines, and testing

### Architecture & Design

- **[GUIDE.md](../GUIDE.md)** - High-level architectural blueprint and design philosophy
- **[ARCHITECTURE-ANDROID.md](ARCHITECTURE-ANDROID.md)** - Deep dive into Android integration, memory/battery efficiency
- **[RENDER-LOOP.md](RENDER-LOOP.md)** - Render loop implementation across all platforms

### Platform-Specific Implementation

- **[IMPLEMENTATION-ANDROID.md](IMPLEMENTATION-ANDROID.md)** - Android build instructions, debug/release modes
- **[IMPLEMENTATION-IOS.md](IMPLEMENTATION-IOS.md)** - iOS build instructions and Metal integration
- **[IMPLEMENTATION-MACOS.md](IMPLEMENTATION-MACOS.md)** - macOS build instructions, window resize handling
- **[IMPLEMENTATION-WIN.md](IMPLEMENTATION-WIN.md)** - Windows build instructions, x86_64 only
- **[IMPLEMENTATION-LINUX.md](IMPLEMENTATION-LINUX.md)** - Linux build instructions, EGL/GLES3 setup

### Assets & Data Management

- **[COMAPS-ASSETS.md](COMAPS-ASSETS.md)** - CoMaps asset management: data files, localization, MWM maps

### Example Code

- **[example/](../example/)** - Working demo application with downloads manager, full API usage examples

### Additional Resources

- **CoMaps Framework Reference**: `thirdparty/comaps/libs/map/framework.hpp` - Source of truth for available native APIs
- **Existing Implementations**: `src/agus_maps_flutter.cpp` - Reference implementations of FFI functions
- **FFI Bindings**: `lib/agus_maps_flutter_bindings_generated.dart` - Auto-generated bindings (regenerate after header changes)
