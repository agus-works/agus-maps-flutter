# Tablet Layout

Tablet is the medium-density touch layout for iPad, Android tablets, foldables,
and medium desktop windows. It should preserve mobile discoverability while
using wider space for docked panels.

## Shell contract

| Area | Contract |
| --- | --- |
| Navigation | Side `NavigationRail` with touch-sized destinations. |
| Map canvas | Map remains central and visible while docked panels are open. |
| Primary panels | Search, layers, map presentation, and place details may be docked or wide sheets. |
| Density | Touch targets remain comfortable; rows can be denser than phones but not desktop-compact. |
| Dialogs | Confirmations can use dialogs; forms should use adaptive prompts or panels. |

## Feature stories and interactions

| Feature | User story | Tablet UI |
| --- | --- | --- |
| App navigation | Switch app sections with room for labels when available. | Side rail. Extended labels may appear on larger tablets. |
| Map browsing | Use touch gestures and floating controls without losing context. | Map-first editor with docked or floating tools. Camera controls can be grouped more tightly than on phones. |
| Search | Search places and route to results. | Search can be a left docked panel or wide overlay. Results scroll independently. |
| Place page | Inspect tapped map features. | Bottom or side sheet with wider metadata grid. On landscape tablets, side sheet is preferred. |
| Route preview | Preview and start guidance. | Bottom card with wrapped actions or side panel when place details are already open. |
| Layer manager | Manage project layers and features. | Docked layer tree with large rows, active layer card, feature children, and toolbar actions. |
| Create layer | Add an editable layer. | Use the shared adaptive prompt, anchored to Layer Manager. |
| Add feature | Add point, segment, line, or polygon. | Same canonical flow as phones: active layer -> Add feature -> geometry picker -> map drawing. |
| Draw/edit feature | Place vertices and edit handles. | Drawing toolbar may be horizontal or vertical depending on available width. Native Drape owns visuals. |
| Map presentation | Toggle native basemap overlays. | Can be a separate docked panel or settings section. Do not mix with project layer creation. |
| Favorites | Jump to saved locations. | List with larger touch rows; optional details column can be added later. |
| Downloads | Browse and manage map files. | Header plus region tree. Wider rows can show status and actions without overflowing. |
| Settings | Configure appearance, map labels, routing, and storage. | Scrollable card sections, potentially two-column only when every card remains height-safe. |
| About | Inspect attribution and licenses. | Scrollable content route; long license text stays in a full route. |

## Tablet-specific rules

- Tablet should not inherit mobile landscape's extreme compression.
- Tablet should not use desktop compact rows by default.
- Panels may be docked, but they must remain touch sized.
- Keyboard and text entry still need adaptive prompt constraints.
- The same layer creation and geometry selection flow applies.

## Implementation checklist

| Item | Status | Notes |
| --- | --- | --- |
| Shared form factor resolver | Implemented | Tablet is the middle fallback after mobile and desktop rules. |
| Side rail | Implemented | Non-mobile adaptive scaffold uses `NavigationRail`. |
| Tablet layer panel | Partially implemented | Uses non-mobile `AdaptiveLayerManager`, but should be audited after mobile fixes. |
| Tablet side sheets | Pending | Should reuse the mobile landscape side-sheet components where appropriate. |
| Tablet validation | Pending | Validate both orientations on a tablet or simulator after mobile landscape is fixed. |
