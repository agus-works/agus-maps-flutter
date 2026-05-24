# Desktop Layout

Desktop is the compact pointer-first layout for macOS, Windows, Linux, and very
wide external displays. It uses a VS Code-style workbench with shared app state
visible through panes and tabs.

## Shell contract

| Area | Contract |
| --- | --- |
| Activity Bar | Fixed left icon strip for Explorer/Layers, Map Presentation, Search, Favorites, Downloads, Settings, and About. |
| Primary Side Bar | Resizable left pane controlled by the Activity Bar. |
| Editor Area | Tabbed central viewport. Initial tabs are Map and Blank. |
| Panel | Resizable bottom pane for Point of Interest and Debug Console. |
| Secondary Side Bar | Resizable right pane for Properties and future inspectors. |
| Density | Compact rows, one-pixel separators, property grids, and clipped text. |

## Feature stories and interactions

| Feature | User story | Desktop UI |
| --- | --- | --- |
| App navigation | Switch between workbench activities and editor tabs. | Activity Bar controls the Primary Side Bar; Editor Area owns map and future document tabs. |
| Map browsing | Use mouse, trackpad, and keyboard-adjacent controls. | Map lives in an editor tab. Pointer, scroll zoom, and pan-zoom rotation go to native map. |
| Search | Search places, coordinates, and favorites while map remains visible. | Compact Search activity in the Primary Side Bar with 34 px input and 36 px result rows. |
| Place page | Inspect selected map features. | Point of Interest bottom panel and Properties side bar show details; no mobile bottom sheet in workbench mode. |
| Route preview | Preview and start routes. | Route card appears over the map editor or later in a dedicated workbench panel. Actions stay compact and wrapped. |
| Layer manager | Manage project layers and feature rows. | Explorer activity uses compact tree/grid rows with New Layer, refresh, backup, active edit layer, z-order, visibility, delete, and feature rows. |
| Create layer | Add an editable layer. | `New Layer` in the Layer Manager toolbar opens the shared adaptive prompt. |
| Add feature | Add point, segment, line, or polygon. | Same canonical flow: active layer -> Add feature -> geometry picker -> map drawing. Desktop may expose keyboard shortcuts later, but they must call the same command. |
| Draw/edit feature | Create or modify geometry. | Compact toolbar and native Drape handles. Feature commits write DuckDB state and refresh native rendering. |
| Map presentation | Toggle basemap/runtime overlays. | Separate Map Presentation activity with compact property grid. |
| Favorites | Jump to saved locations. | Favorites activity uses dense rows in the Primary Side Bar. |
| Downloads | Browse map regions and manage files. | Downloads activity uses compact explorer rows, status columns, static progress, and right-aligned actions. |
| Settings | Configure appearance, map labels, navigation, and storage. | Settings activity may reuse card sections but should move toward compact desktop forms over time. |
| About | Inspect attribution, licenses, and DuckDB smoke status. | About activity can reuse scrollable route/card content inside Primary Side Bar until a desktop-specific pane is built. |
| Diagnostics | Inspect logs and properties. | Debug Console bottom panel and Properties side bar expose runtime state without mobile debug overlays. |

## Platform menu contract

On macOS, desktop layout adds a `Tools` native platform menu for workbench-only
panel tools. It does not own the whole platform menu by itself; the app-level
menu host remains mounted above the responsive shell so resizing between
desktop, tablet, and mobile widths never clears the default macOS menus.

Expected desktop menu bar:

```text
Agus Suite | Edit | View | Window | Help | Tools
```

The `Tools` entries use the same `_workbenchToolRegistry` as command-bar and
pane actions.

## Desktop-specific rules

- Do not use mobile rounded cards inside dense workbench panes unless the pane
  is intentionally a content route.
- Pane boundaries should be one visible line with no invisible layout gaps.
- Resize hit targets may be overlaid but must not reserve extra space.
- Desktop layout should never create a second native map surface during
  responsive transitions.
- All project layer operations must surface errors in pane status areas or the
  scaffold message area, not as unhandled red screens.

## Implementation checklist

| Item | Status | Notes |
| --- | --- | --- |
| VS Code-style workbench | Implemented | Activity Bar, Primary Side Bar, Editor Area, Panel, and Secondary Side Bar exist. |
| Compact Layer Manager | Implemented | Desktop branch uses compact toolbar and layer grid. |
| Desktop search/favorites | Implemented | Primary Side Bar activities use compact rows. |
| Shared adaptive prompt | Needs implementation | Desktop should use the same prompt service as mobile/tablet to avoid divergent creation flows. |
| One feature creation path | Needs implementation | Desktop draw controls must converge with the shared geometry picker command model. |
| Regression validation | Pending | Re-run desktop window resize and workbench workflows after mobile layout changes. |
