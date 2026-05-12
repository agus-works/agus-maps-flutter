# Workbench Explorer Tree Grid and Selection Feedback

## Story

As a desktop map editor user, I want Explorer, Downloads, Favorites, and Map Presentation to use the same compact tree-grid language so I can scan map content, visibility, state, and actions consistently.

## Acceptance criteria

- Selecting a project feature or layer shows green vertices and edges on the map, using a transient native overlay instead of changing persisted feature styles.
- Map Presentation appears in Explorer as tree-grid rows with eye icons for visibility booleans.
- Enabling Subway disables Outdoors and Contour Lines, preserving the existing incompatible-layer boundary.
- Project Layers actions are on the Project Layers row as icon-only buttons with tooltips.
- Downloads and Favorites use the same compact row density and tree/grid visual styling as Explorer surfaces.
- Resizing between mobile, tablet, and desktop shells keeps the map editor selected when the user was on the map.

## Notes

- Layer-level selection highlights visible non-deleted features up to a bounded overlay size to avoid blocking large layer interactions.
- Downloads keeps its existing storage, progress, delete, update, cancel, and concurrency behavior; only the presentation shell changes.
