# User Story: Status Telemetry Copy with Notifications

## As a map developer or advanced user
I want to see live map telemetry in the status bar and copy values to clipboard, so that I can debug, report issues, or record coordinates quickly.

## Background
Map development and field work often require precise coordinate tracking, zoom levels, and bearing values. Manually transcribing these values is error-prone and slow. Status bar telemetry provides live feedback, and copy-to-clipboard saves time when recording or sharing location data.

## Acceptance Criteria

### Status Bar Telemetry Display
- ✅ Map telemetry shown only when:
  - Active activity is "Explorer"
  - Active editor tab is "Map"
- ✅ Hidden on other activities (Search, Downloads, Settings, etc.)
- ✅ Hidden on other editor tabs (Properties, Layers, etc.)

### Telemetry Items
- ✅ **Zoom Level**: Displayed as `z14` with zoom icon
  - Derived from `getCurrentZoom()` native API
- ✅ **Bearing**: Displayed as `45.5°` with compass icon
  - Normalized to 0-360° range
  - Derived from `getCurrentBearing()` native API
- ✅ **Center Coordinates**: Displayed as `36.140734°, -5.353456°` with location icon
  - Formatted to 6 decimal places (~0.1m precision)
  - Derived from `getViewportCenter()` native API
- ✅ **Selected Point**: Displayed as `36.500000°, -5.500000°` with pin icon
  - Shown only when a place page is active
  - Extracted from `PlacePageData` when available

### Copy-to-Clipboard Gestures
- ✅ **Double-click** (desktop): Copies item value to clipboard
- ✅ **Long-press** (mobile): Copies item value to clipboard
- ✅ Copied values:
  - Zoom: `14` (integer)
  - Bearing: `45.5` (decimal)
  - Center coordinates: `36.140734, -5.353456` (comma-separated)
  - Selected point: `36.500000, -5.500000` (comma-separated)

### VS Code-Style Notifications
- ✅ Notification toast appears after successful copy
- ✅ Messages:
  - "Zoom level copied"
  - "Bearing copied"
  - "Center coordinates copied"
  - "Selected point copied"
- ✅ Auto-dismisses after 2 seconds
- ✅ Uses existing `AgusNotificationManager` and `AgusNotificationToast`

### Precision and Formatting
- ✅ Coordinates: 6 decimal places (WGS84 lat/lon)
- ✅ Bearing: 1 decimal place, normalized 0-360°
- ✅ Zoom: Integer display, fractional value in backend
- ✅ Icon indicators for each telemetry type

## Implementation References

### Components
- **MapTelemetry** model: Tracks zoom, center, bearing, selected point
  - File: `packages/agus_design/lib/src/components/agus_status_bar_telemetry.dart`
- **MapTelemetryStatusBarBuilder**: Builds status bar items
  - Handles copy gestures (double-click, long-press)
  - Generates clipboard values
  - Triggers notifications

### Status Bar Integration
- **Example App**: `example/lib/main.dart`
  - `_buildWorkbenchStatusBar()`: Enhanced with map telemetry
  - `_buildMapTelemetryItems()`: Queries native APIs and builds items
  - Visibility gating: Explorer activity + Map editor active

### Clipboard Integration
- Uses `flutter/services.dart` → `Clipboard.setData()`
- Implemented in `packages/agus_design/lib/src/components/agus_status_bar.dart`
- `_copyToClipboard(String value, String successMessage)`

### Native API Queries
- `getViewportCenter()`: Returns `LatLng` with current map center
- `getCurrentZoom()`: Returns double zoom level
- `getCurrentBearing()`: Returns double bearing in degrees
- `PlacePageData`: Contains selected point coordinates when place page active

## Testing Approach
- Component tests: `packages/agus_design/test/components/agus_status_bar_telemetry_test.dart`
  - 15 tests for MapTelemetry formatting
  - Tests for zoom, bearing, lat/lon, selected point formatting
  - Tests for clipboard value generation
  - Tests for status bar item construction
- Integration tests: `example/test/features/workbench/workbench_status_bar_test.dart`
  - 11 tests for visibility gating logic
  - Tests for Explorer + Map editor active combination
  - Tests for hiding on non-Explorer activities
  - Tests for hiding on non-Map editor tabs
- Manual: Switch activities/tabs, verify telemetry visibility
- Manual: Double-click/long-press items, verify clipboard and notification

## Documentation
- Implementation summary: `IMPLEMENTATION_STATUS_TELEMETRY.md`
- Status bar component: `packages/agus_design/lib/src/components/agus_status_bar.dart`
- Telemetry component: `packages/agus_design/lib/src/components/agus_status_bar_telemetry.dart`

## Usage Example

When on Explorer activity with Map editor open:
```
[zoom icon] z14  [compass icon] 45.5°  [location icon] 36.140734°, -5.353456°
```

With a place selected:
```
[zoom icon] z14  [compass icon] 45.5°  [location icon] 36.140734°, -5.353456°  [pin icon] 36.500000°, -5.500000°
```

Double-click or long-press any item:
```
✓ Center coordinates copied
```

## Related Features
- Reusable Agus design components and Widgetbook coverage
- Command-driven drawing and interaction state safety
- Layer/feature focus centers and active selection
