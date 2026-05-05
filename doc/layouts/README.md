# Layout Documentation

This directory defines the responsive UI contract for the example app. The
goal is to keep one application model and one feature workflow across every
form factor while changing only placement, density, and surface shape.

## Layout targets

| Layout | Typical devices | Primary shell | Key risk |
| --- | --- | --- | --- |
| [Mobile portrait](mobile-portrait/README.md) | Phones held upright | Map-first shell with bottom navigation | Too many stacked bottom surfaces |
| [Mobile landscape](mobile-landscape/README.md) | Phones held sideways | Map-first shell with side navigation and side/compact overlays | Very small height causing sheets and dialogs to collapse |
| [Tablet](tablet/README.md) | iPad, Android tablets, foldables, medium desktop windows | Touch rail with docked or wide sheets | Mixing mobile modal flows with desktop density |
| [Desktop](desktop/README.md) | macOS, Windows, Linux, large external displays | VS Code-style workbench | Dense panes becoming card-heavy mobile layouts |

The current resolver treats a viewport as mobile when the shortest side is
less than 600 logical pixels or width is less than 700 logical pixels. Desktop
is reached on desktop operating systems at widths of at least 1100 logical
pixels, or on any platform at widths of at least 1400 logical pixels. All other
viewports are tablet.

## Shared principles

1. **One workflow per task.** A user should not have to learn separate feature
   creation flows for mobile, tablet, and desktop. The canonical layer editing
   flow is: choose active layer, choose geometry type, draw/edit on the map,
   then commit or cancel.
2. **One live map.** Every layout keeps the native map as the single source of
   spatial interaction. Flutter surfaces may collect metadata and commands, but
   pan, zoom, rotation, tap selection, drawing vertices, and native Drape
   handles remain anchored to the map.
3. **No hidden zero-size surfaces.** Closed panels, offstage desktop panes, and
   inactive overlays must not keep transparent hit-test or layout space above
   the map.
4. **Height-safe overlays.** Any sheet, dialog, or form that can appear on a
   phone must have finite max height, internal scrolling, and a minimum content
   height. It must not depend on bottom-sheet height when the phone is in
   landscape.
5. **Mutually exclusive map overlays.** On mobile, search, layer manager, place
   page, route preview, and feature metadata entry should not stack on top of
   one another unless explicitly designed as parent/child content.
6. **Platform conventions first.** Use Material 3 navigation bars, rails,
   dialogs, sheets, and side sheets in conventional places. Custom chrome is
   acceptable only when it preserves expected mobile and desktop behaviors.
7. **Safe-area ownership is explicit.** Shell elements that consume unsafe
   regions, such as the mobile landscape navigation strip, must prevent body
   pages from applying the same safe-area inset a second time.
8. **Camera gestures stay render-only.** Pan, zoom, and rotation must not run
   synchronous DuckDB queries or full Drape user-mark rebuilds on the gesture
   frame path. Project-layer rendering may refresh immediately after mutations,
   but camera-driven refreshes must be debounced until the viewport is idle.

## Common mobile landscape pattern

Other mature mobile map applications usually avoid tall bottom sheets in phone
landscape. They keep the map full-bleed, move primary navigation to a side edge,
make high-volume content a side panel or full-screen route, and keep only small
transient cards at the bottom. Forms and confirmations either become compact
scrollable dialogs with constrained height or side sheets that use the wider
axis. This app should follow that pattern for landscape phones.

## Shared feature inventory

| Feature | User story | Canonical interaction |
| --- | --- | --- |
| App navigation | As a user, I switch between Map, Favorites, Downloads, Settings, and About. | Portrait uses bottom navigation; landscape phone/tablet/desktop use a side rail or strip. |
| Map browsing | As a user, I pan, pinch, rotate, zoom, reset north, and locate myself. | The map fills the viewport; camera buttons float inside safe readable space. |
| Search | As a user, I find places, coordinates, suggestions, and favorites. | Open one search surface, type, inspect results, tap a result to focus map, optionally route to it. |
| Place page | As a user, I tap a map feature and inspect name, address, coordinates, and metadata. | The map selection opens one details surface; close clears the native selection. |
| Route preview | As a user, I route to a selected place or search result and start guidance. | Route action opens one preview surface with status, refresh, start, and clear actions. |
| Project layers | As a user, I create, show/hide, order, back up, and delete DuckDB-backed project layers. | The Layer Manager is the only entry point for project layer management. |
| Feature creation | As a user, I add a point, segment, line, or polygon to the active layer. | Choose active layer, choose geometry type, draw on map, commit or cancel. No platform gets a second shortcut that skips geometry choice. |
| Feature editing | As a user, I select a stored feature and move/edit its native Drape handles. | Select feature from the layer tree, edit handles on map, commit through the same draw controller. |
| Map presentation | As a user, I toggle 3D buildings, outdoors, contour lines, and subway. | Presentation controls are separate from project layers and use the same state on all layouts. |
| Favorites | As a user, I select a saved example location. | Tap a favorite row to switch/focus the map. |
| Downloads | As a user, I browse map regions, choose mirrors, download/update/delete maps, and monitor progress. | Browse a tree/list, confirm destructive or large actions, show progress and cancellation inline. |
| Settings | As a user, I configure appearance, map language, labels, navigation, routing, and storage. | Use scrollable settings sections; controls keep standard touch sizes. |
| About and licenses | As a user, I inspect attribution, open-source licenses, and component status. | Use scrollable content routes; long legal text must not appear inside short dialogs. |
| Diagnostics | As a developer, I inspect logs, POI properties, and runtime state. | Desktop exposes panes; mobile uses app logs collected through `tee` rather than permanent debug panes. |

## Implementation focus

The first implementation focus is mobile portrait and mobile landscape because
landscape phones are currently the most constrained and are producing zero
height render constraints in debug logs. Tablet and desktop contracts are
documented here to prevent mobile fixes from breaking larger layouts.

Progress is tracked in [PROGRESS.md](PROGRESS.md).
