# Mobile Landscape Layout

Mobile landscape is a dedicated phone layout, not a shorter version of mobile
portrait. The available height can be under 400 logical pixels on iPhone-class
devices, so bottom sheets and unconstrained dialogs are the highest-risk
surfaces.

## Observed failure

The debug log at `output.ios-debug.log` shows the app rendering at about
`735x393` logical pixels and later processing a `TextFormField` from
`adaptive_layer_manager.dart` with constraints `BoxConstraints(w=232.0, h=0.0)`.
That means a route/dialog/form surface was squeezed until the input border had
zero height, which then triggered repeated `dart:ui/geometry.dart` assertions.

The fix direction is not to tune a single dialog. Landscape phone needs a
separate layout contract for every transient surface.

## Shell contract

| Area | Contract |
| --- | --- |
| Navigation | Move primary tabs from bottom navigation to a left vertical strip inside safe area. The strip may scroll vertically. |
| Map canvas | Keep native map full-bleed in the remaining viewport. Do not reserve bottom navigation height. |
| Primary actions | Place map action buttons on the right safe edge in a scrollable vertical column. |
| Major panels | Prefer right or left side sheets over bottom sheets. If a bottom card is used, keep it shallow and horizontally compact. |
| Forms | Use full-height side sheets or full-screen routes for text entry. Plain centered dialogs are allowed only when their content is smaller than the safe height. |
| Keyboard | Text input must either resize within a side sheet or use a route where the body scrolls above keyboard insets. |

## Map rendering rules

- Camera gestures must stay smooth even while DuckDB project layers are enabled.
- Pan, zoom, and rotation must not synchronously query DuckDB or rebuild Drape
  user marks from inside the viewport listener.
- DuckDB-backed Drape rendering refreshes immediately after project-layer
  mutations, then debounces camera-driven refreshes until the viewport is idle.
- An idle refresh that returns the same renderable feature set must not call
  Drape user-mark update or invalidation APIs.

## Safe-area ownership

Mobile landscape uses split safe-area ownership:

- The left navigation strip owns the left unsafe region by including the left
  `MediaQuery.padding` in its width and scroll padding.
- Tab page bodies must not add left safe-area padding again, otherwise every
  non-map page appears shifted to the right.
- Tab page bodies keep right safe-area padding because the right edge may hold
  rounded corners, the home indicator region, or system gesture areas.
- Tab page bodies do not add bottom safe-area padding in landscape because there
  is no bottom navigation bar in this orientation and the extra inset reads as
  an unintended gap.
- Map tab content can still opt out of all body safe-area padding; map overlays
  own their own readable safe positions.

## How mature mobile apps usually handle phone landscape

Map-heavy apps normally keep the map usable and move controls to the side:

- bottom tab bars become side rails, strips, or drawers;
- search results and place details become side panels where width is abundant;
- tall bottom sheets are replaced with compact cards or side sheets;
- forms use full-screen or side-sheet routes rather than modal bottom sheets;
- only essential camera controls remain visible while a panel is open;
- overlapping panels are mutually exclusive.

This app should use the same approach: use the wider horizontal axis for
content, preserve vertical map space, and avoid any surface that can collapse to
zero height.

## Feature stories and interactions

| Feature | User story | Landscape UI |
| --- | --- | --- |
| App navigation | Switch between Map, Favorites, Downloads, Settings, and About without losing safe-area affordances. | Left side icon strip, 58 logical pixels plus left safe padding, vertically scrollable. |
| Map browsing | Pan, pinch, rotate, zoom, reset north, and locate while panels are open. | Map fills the rest of the screen. Camera controls use a right safe scroll column. Secondary buttons collapse when panels are open. |
| Search | Search without covering the map height. | Search opens as a side sheet or top-left compact panel with results in a scrollable list. It must not share height with bottom sheets. |
| Place page | Inspect a selected feature. | Prefer a right side sheet with title, actions, and metadata list. If using a bottom card, it must show only summary/actions and offer "More" to a side/full route. |
| Route preview | Review and start navigation. | Use a shallow bottom card or side panel. Actions wrap horizontally and never force the card above a fixed safe height. |
| Layer manager | Manage layers while keeping map space. | Use a side sheet occupying a fixed fraction of width, or a bottom sheet capped to a landscape-specific shallow height. The layer tree scrolls internally. |
| Create layer | Name a layer. | Use a shared adaptive prompt rendered inside the layer side sheet or a full-screen route. Do not use a default centered `AlertDialog` with unconstrained `TextFormField`. |
| Add feature | Choose point, segment, line, or polygon. | One geometry picker appears in the layer side sheet. After selection, close the sheet and show map drawing controls only. |
| Draw/edit feature | Add vertices and commit/cancel without hiding the map. | Use native Drape marks. Floating undo/commit/cancel buttons live in the right control column. Drawing metadata is a compact top banner or side form. |
| Map presentation | Toggle 3D buildings, outdoors, contour lines, and subway. | Use the same side-sheet pattern as project layers or expose in Settings. Never mix presentation toggles into "Add feature". |
| Favorites | Jump to a saved location. | Favorites screen uses the same left navigation strip and a scrollable list in the remaining area. Row heights can be slightly denser than portrait. |
| Downloads | Browse regions and manage downloads. | Downloads screen should use two vertical zones only if height allows; otherwise header controls wrap and the region tree owns the scroll. Empty states must compact and scroll inside the region-list viewport. Confirmation dialogs must be height-safe. |
| Settings | Configure app and map behavior. | Settings screen uses scrollable sections. Segmented controls and dropdown menus wrap or move to one control per line. |
| About | Inspect attribution and licenses. | Use routes and scroll views. URL copy prompts must be scrollable and constrained. |

## Dedicated landscape surface rules

### Side sheet

Use a side sheet for search, layers, place page, and forms when the phone is in
landscape.

- Width: between 320 and 420 logical pixels, capped to leave visible map.
- Height: full safe height.
- Body: always scrollable.
- Header: fixed height with close button.
- Footer/actions: fixed bottom row only when the body has enough scroll inset.

### Compact bottom card

Use a compact bottom card only for transient route status or place summary.

- Height should be content-driven and shallow.
- It must never contain a text field, long metadata list, layer tree, or search
  results.
- It must offer a side/full route for detailed content.

### Dialogs

The shared dialog policy for landscape phones:

- `AlertDialog` is acceptable for two-action confirmations with short text.
- Text input must use a full-screen mobile route or side sheet, not a compact
  centered dialog.
- Long content must be a route or side sheet.
- Dialog content must not use `Column(mainAxisSize: min)` without a scrollable
  wrapper when the content can grow.

## One way to add a feature

The app should expose exactly one feature-creation flow everywhere:

1. Open Layer Manager.
2. Select or create an active editable layer.
3. Tap `Add feature`.
4. Pick `Point`, `Segment`, `Line`, or `Polygon`.
5. The panel closes.
6. Tap the map to add vertices.
7. Use floating drawing controls to undo, commit, or cancel.

No layout should start a default `Point` feature directly from an "add" button.
This removes ambiguity and makes mobile, tablet, and desktop behavior match.

## Implementation checklist

| Item | Status | Notes |
| --- | --- | --- |
| Left navigation strip | Implemented | Existing `AdaptiveAppScaffold` uses a side strip for mobile landscape. |
| Orientation-aware body safe area | Implemented | `AdaptiveBodySafeArea` removes duplicate left and bottom padding from mobile landscape tab bodies while keeping right padding. |
| Scrollable right action column | Implemented | Current map controls use `SingleChildScrollView` in the right column. |
| Android camera rendering stability | Implemented | DuckDB viewport refreshes are debounced until camera idle, unchanged idle refreshes are no-ops, and Drape user-mark updates no longer force first-time rebuilds after initial publication. |
| Downloads empty states | Implemented | No-regions and no-results states use compact scroll-safe content when the region-list viewport is short. |
| Landscape-specific major panels | Partially implemented | Search and layers now use side panels on the map tab; route preview remains a shallow bottom card. |
| Shared adaptive prompt | Partially implemented | Layer creation uses a full-screen mobile prompt in portrait and landscape; Downloads/About dialogs still need migration. |
| Place page side sheet | Implemented | Place page uses a right side panel in mobile landscape and scrolls metadata internally. |
| Layer creation geometry picker | Implemented | Mobile layer-row add actions now ask for point, segment, line, or polygon. |
| Manual landscape validation | Pending | See `../PROGRESS.md` for the command and scenario list. |
