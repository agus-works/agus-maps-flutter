# Layout Implementation Progress

This file records the responsive layout investigation and the implementation
direction for fixing mobile portrait and mobile landscape first.

## Current status

| Area | Status | Notes |
| --- | --- | --- |
| Feature inventory | Documented | See `README.md` and per-layout documents. |
| Mobile portrait contract | Documented | See `mobile-portrait/README.md`. |
| Mobile landscape contract | Documented | See `mobile-landscape/README.md`. |
| Tablet contract | Documented | See `tablet/README.md`. |
| Desktop contract | Documented | See `desktop/README.md`. |
| iOS landscape failure analysis | Documented | The log shows a zero-height `TextFormField` constraint in the layer creation dialog. |
| Code implementation | Partially implemented | Mobile landscape now uses side panels for search, layers, and place page; the layer-name prompt is height-safe; mobile layer-row add actions now ask for geometry type; mobile landscape tab bodies no longer add duplicate left/bottom safe-area padding. |

## Observed iOS debug failure

Input log:

```text
/Users/gilmichael/Desktop/Projects/agus-maps-flutter/output.ios-debug.log
```

Relevant symptoms:

```text
AgusMap resizing near 735x393 logical pixels.
TextFormField from adaptive_layer_manager.dart receives BoxConstraints(w=232.0, h=0.0).
InputDecorator / OutlineInputBorder then hits a dart:ui geometry assertion.
Repeated geometry assertions follow until the application finishes.
```

Conclusion: the immediate failing widget is the layer-name `TextFormField`, but
the root problem is that phone landscape gives dialogs and bottom-style panels
too little height. The solution should introduce dedicated mobile landscape
surface rules and shared adaptive prompt/sheet components.

## Implementation direction

1. Create shared adaptive surface primitives:
   - `AdaptivePrompt` for short text input and confirmations.
   - `AdaptiveMapPanel` for search, layers, place page, route preview, and
     drawing metadata.
   - `AdaptiveGeometryPicker` for point, segment, line, and polygon selection.
2. Route surfaces by layout:
   - Mobile portrait: bottom sheet or top overlay with max height and internal
     scrolling.
   - Mobile landscape: side sheet or full route for forms; compact bottom card
     only for shallow status.
   - Tablet: docked side/wide sheet.
   - Desktop: workbench pane or compact dialog, still using the same command
     model.
3. Standardize layer feature creation:
   - Layer Manager is the only feature creation entry point.
   - User must choose geometry type before drawing starts.
   - Drawing mode closes panels and uses native Drape marks plus floating
     commit/cancel controls.
4. Convert risky current surfaces:
   - Layer creation dialog. Implemented for layer manager.
   - Place page sheet. Implemented for mobile map place page.
   - Search results overlay in landscape. Implemented for mobile map search.
   - Mobile Layer Manager overlay in landscape. Implemented as side panel.
   - Downloads and delete/download confirmation dialogs.
   - About URL dialog.

## Implemented mobile landscape fixes

The first code pass implements the highest-risk map-tab surfaces:

1. `example/lib/features/map/widgets/adaptive_layer_manager.dart`
   - Replaced the layer-name `AlertDialog` text field with an adaptive prompt.
   - Mobile portrait and landscape use a full-screen prompt route with
     scrollable body and fixed actions, avoiding zero-height and very short
     text-field constraints when the keyboard appears.
   - The create-layer async flow now checks that the layer manager is still
     mounted after the prompt returns before calling `setState`.
   - Mobile layer-row `Add feature` no longer starts a default point directly;
     it opens a geometry picker for point, segment, line, or polygon.
   - Desktop `Add feature` also uses a geometry picker menu instead of
     defaulting to point.
2. `example/lib/main.dart`
   - Mobile landscape search opens as a left side panel with internally
     scrollable results.
   - Mobile landscape Layer Manager opens as a right side panel using full safe
     height instead of a shallow bottom sheet.
   - Floating map controls shift left when a right side panel is open so they do
     not sit under the panel.
3. `example/lib/place_page_sheet.dart`
   - Place page content is now bounded and internally scrollable.
   - Mobile landscape place pages use a right side panel instead of a bottom
     sheet.
   - Portrait place pages keep the bottom-sheet placement but now cap height
     and scroll metadata internally.
4. `example/lib/shared/layout/adaptive_body_safe_area.dart`
   - Centralizes body safe-area decisions for the adaptive shell.
   - Mobile landscape keeps right safe-area padding but suppresses duplicate
     left and bottom body padding because the left navigation strip owns the
     left unsafe region and no bottom navigation bar is present.
5. `example/lib/shared/layout/adaptive_app_scaffold.dart`
   - Uses `AdaptiveBodySafeArea` for tab body content instead of directly
     applying `SafeArea` in every orientation.
6. `example/lib/downloads_tab.dart`
   - Fixed the logged `A RenderFlex overflowed by 72 pixels on the bottom`
     failure in the no-regions empty state.
   - Downloads no-regions and no-results states now compact at short heights and
     scroll within the region-list viewport instead of using a fixed centered
     `Column`.
7. `src/agus_maps_flutter.cpp`
   - Android DuckDB layer refreshes from viewport changes are now debounced until
     the camera is idle instead of running synchronous DuckDB queries and Drape
     user-mark rebuilds during pan, zoom, or rotation frames.
   - The delayed idle refresh now compares the renderable DuckDB feature set and
     skips Drape user-mark updates when nothing changed, avoiding the remaining
     single post-gesture flicker.
   - DuckDB-backed Drape user marks now use first-time publication only once and
     report created, updated, and removed ids on later refreshes.
   - Explicit project-layer mutations still refresh native rendering immediately.
8. `example/lib/main.dart`
   - `DownloadsTab` now uses a stable app-owned key so mobile portrait/landscape
     shell swaps do not reset loaded mirrors, catalog regions, search text,
     expanded rows, errors, or active download progress.

## Manual validation command

The agent should not run the app directly. To collect the next iOS landscape
log, run from the repository root:

```shell
cd example
flutter run -d 00008130-0009390A00698D3A --debug 2>&1 | tee ../output.ios-debug.log
```

If you use another device id, replace only the `-d` value. Keep the `tee`
target at `../output.ios-debug.log` so the root-level analysis commands can
find the log.

## Manual validation scenario list

Run these on an iPhone-class device in portrait and landscape after each layout
implementation milestone:

1. Start app, open Map, pan, pinch, rotate, zoom in/out, reset north, and locate.
2. Open Search, type text, inspect results, tap a result, clear search, close.
3. Open Layers, create a layer, choose each geometry type, draw, undo, commit,
   and cancel.
4. Select an existing feature from the layer tree and enter edit mode.
5. Tap map POIs to open place page, inspect metadata, route to the place, close.
6. Preview route, refresh status, start when available, and clear route.
7. Switch to Favorites, tap a favorite, confirm map camera movement.
8. Switch to Downloads, search regions, expand groups, start/cancel download,
   update, delete, and inspect warnings.
9. Switch to Settings, exercise segmented controls, dropdowns, switches,
   checkboxes, slider, and clear cache action.
10. Switch to About, open URL dialog, copy URL, open license route, scroll long
    license text.

## Acceptance criteria

- No Flutter red-screen exceptions in portrait or landscape.
- No zero-height constraints for text fields, input decorators, sheets, or
  dialogs.
- Map remains gesture-responsive outside visible controls.
- Every major surface is scrollable within its own bounded viewport.
- Mobile landscape uses side or route surfaces for tall content.
- There is exactly one layer feature creation workflow across layouts.
- Tablet and desktop still use their documented shells after mobile fixes.

## Non-app validation

The app was not launched by the agent. Non-app checks run for this pass:

```shell
dart format example/lib/main.dart example/lib/place_page_sheet.dart example/lib/features/map/widgets/adaptive_layer_manager.dart
dart format example/lib/shared/layout/adaptive_app_scaffold.dart example/lib/shared/layout/adaptive_body_safe_area.dart
dart format example/lib/downloads_tab.dart
flutter analyze
flutter test
```

`flutter analyze` reported repository-wide existing warnings and info-level
lint output, with no diagnostics in the changed layout files. `flutter test`
found no `test/` directory.
