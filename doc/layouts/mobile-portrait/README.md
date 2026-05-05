# Mobile Portrait Layout

Mobile portrait is the default phone experience. It is map-first, touch-first,
and optimized for one-handed vertical use. The native map owns the full map tab,
including safe-area regions, while Flutter overlays remain inside readable safe
positions.

## Shell contract

| Area | Contract |
| --- | --- |
| Navigation | Icon-only Material `NavigationBar` at the bottom for Map, Favorites, Downloads, Settings, and About. |
| Map canvas | Full-bleed native `AgusMap` on the Map tab. The map should remain hit-testable wherever no visible control is present. |
| Primary actions | Floating circular buttons on the right side: Search, Layers, zoom in/out, reset north, current position. |
| Overlays | Only one major map overlay at a time: search, layers, place page, route preview, or drawing metadata. |
| Sheets | Bottom-aligned, max-width constrained, max-height constrained, internally scrollable when content exceeds available height. |
| Dialogs | Allowed for short confirmations only; content must be scrollable and constrained. Complex forms should use a sheet or route. |

## Safe-area ownership

Mobile portrait keeps the conventional Material shell ownership:

- The bottom navigation bar owns bottom navigation placement and remains outside
  the body.
- Non-map tab bodies keep requested top, left, right, and bottom safe-area
  padding.
- The map tab opts out of body safe-area padding so the native map can render
  edge-to-edge; visible overlays then apply their own safe positioning.
- The same `AdaptiveBodySafeArea` wrapper is used by the shell, but portrait
  does not suppress left or bottom padding the way landscape does.

## Feature stories and interactions

| Feature | User story | Portrait UI |
| --- | --- | --- |
| App navigation | Switch between primary app sections. | Bottom navigation stays visible outside the edge-to-edge map tab; Map tab removes body safe-area padding so the native map reaches screen edges. |
| Map browsing | Pan, pinch, rotate, zoom, reset north, and locate. | Touch gestures go to native map. Floating controls sit above any bottom sheet and collapse secondary camera controls when a sheet is open. |
| Search | Search places, coordinates, and favorites. | Search FAB opens a top search bar. Search results appear below the field with capped height. Opening search closes layers. |
| Place page | Inspect a tapped map feature. | A bottom details sheet shows title, subtitle, address, coordinates, route action, metadata, and close. Metadata scrolls inside the sheet instead of expanding past the viewport. |
| Route preview | Route to a selected place or result. | A bottom route preview card shows destination, route status, refresh, start, and clear. It uses `Wrap` for actions on narrow widths. |
| Layer manager | Manage DuckDB project layers. | Layers FAB opens a lower overlay capped to roughly half the screen. The map remains visible behind it. Opening layers closes search. |
| Create layer | Add a new editable layer. | `New layer` appears once at the top of the Layer Manager. The layer-name prompt should be a height-safe dialog or compact sheet. |
| Add feature | Add point, segment, line, or polygon. | The active layer card offers one `Add feature` path that always asks for geometry type before drawing starts. After selection, the layer sheet closes and map drawing begins. |
| Draw/edit feature | Place vertices and commit/cancel geometry. | Native Drape shows sketch/edit marks. Floating drawing buttons show undo, commit, and cancel. The geometry type is locked until commit or cancel. |
| Map presentation | Toggle basemap overlays. | Presentation controls live in Settings or a dedicated map presentation panel, not mixed into project layer creation. |
| Favorites | Jump to a saved location. | Favorites tab is a scrollable list with large rows. Tapping a row switches to Map and moves the camera. |
| Downloads | Browse and manage map files. | Downloads tab has a header, search, mirror/snapshot controls, status chips, and a region tree. Empty states are scroll-safe inside the list viewport. Row actions stay at the trailing edge and destructive actions confirm first. |
| Settings | Configure appearance, map labels, navigation, routing, and storage. | Settings tab is a single scrollable column of cards. Controls keep 48 logical pixel touch targets. |
| About | Inspect attribution and licenses. | About tab uses scrollable cards; long license text opens a full route, not a cramped dialog. |

## Standard surface rules

### Bottom sheets

- Use bottom sheets for browse/inspect surfaces that benefit from keeping the
  map visible: place page, layers, route preview, and short metadata entry.
- Cap height to leave a usable map area.
- Use `SafeArea` plus internal `ListView` or `SingleChildScrollView`.
- Do not put unbounded `Column(mainAxisSize: min)` content directly in a sheet
  when metadata, search results, or layer rows can grow.

### Floating action buttons

- Buttons are independent circular controls, not a shared vertical card.
- The Search and Layers buttons stay available when sheets are open.
- Zoom and reset-north may collapse when a lower sheet is open.
- Current position remains available unless the layout cannot fit it without
  covering important sheet controls.

### Dialogs

- Confirmations may use `AlertDialog`.
- Text input should use a full-screen route on phones because keyboard insets
  can reduce compact dialogs below their intrinsic form height.
- Long content, legal text, region lists, layer trees, and feature forms must
  not use plain `AlertDialog` on phones.

## Implementation checklist

| Item | Status | Notes |
| --- | --- | --- |
| Edge-to-edge map tab | Implemented | Existing map tab removes safe-area padding for the map tab. |
| Orientation-aware body safe area | Implemented | Portrait keeps caller-requested safe-area sides; landscape has a different contract. |
| Search/layers mutual exclusion | Implemented | Opening either surface closes the other. |
| Layer overlay capped height | Implemented | Current height is based on viewport height, but the minimum must be revisited for very small landscape heights. |
| Place page scroll safety | Implemented | Place page content is height-capped and metadata scrolls internally. |
| One feature creation path | Partially implemented | Mobile layer-row add actions now ask for geometry type. Remaining future work is to converge every non-layer shortcut through the same command service if new shortcuts are added. |
| Height-safe dialogs | Partially implemented | Layer creation uses a full-screen mobile prompt. Downloads/About confirmations still need the shared prompt treatment. |
| Manual portrait validation | Pending | Run the example on a phone, open every overlay, rotate back to portrait, and collect logs with `tee`. |
