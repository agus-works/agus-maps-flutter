# Command Bar

The desktop example uses `AgusCommandCenter` in the workbench title bar as a
VS Code-style command bar. Commands are grouped, fuzzy-filtered, keyboard
navigable, and rendered with highlighted label matches.

## Static command dictionary

The current workbench command dictionary is built in `example/lib/main.dart` and
is passed into `VSCodeWorkbench.commandGroups`.

| Group | Commands | Behavior |
| --- | --- | --- |
| Navigation | Show Project Layers, Search Map, Show Downloads, Show Favorites, Open Settings | Opens the matching workbench activity and keeps the primary side bar visible. |
| Workbench | Open Map Editor, Toggle Panel, Toggle Properties Sidebar | Controls editor, bottom panel, and right-side view panes. |
| Drawing | Draw Point Feature, Draw Segment Feature, Draw Line Feature, Draw Polygon Feature | Starts the matching DuckDB drawing tool when the layer store is ready. |
| Map Focus | Focus Gibraltar, Focus Philippines | Moves the active map editor to the favorite location and zoom. |
| MWM Layers | Focus MWM Map: `<region>` | Focuses known map locations directly; otherwise opens the map search activity with the region name. |
| MWM Downloads | Refresh MWM Catalog, Download Map, Update Map, Open Downloaded Map | Uses the downloads mirror cache and `MwmStorage` to download/update maps from the command bar or focus installed maps. |
| Location Search | Search Location: `<query>` | Appears asynchronously as the user types and opens the VS Code-style map search with that query. |

## Filtering and highlighting

`AgusCommandItem.match(query)` supports:

- exact substring matches against command labels,
- fuzzy subsequence matches against command labels,
- keyword substring and fuzzy matches,
- disabled command demotion in result ranking,
- label index highlights for matched characters.

The command dialog resets the highlighted row when the query changes, supports
arrow-key navigation, Enter selection, and Escape dismissal.

## Async feeds

The command bar keeps commands as typed `AgusCommandGroup` /
`AgusCommandItem` data so async services can refresh result groups without
owning UI widgets.

Implemented feed sources:

| Feed | Source | Caching |
| --- | --- | --- |
| MWM maps | `DownloadsCacheService`, `MirrorService`, and local `MwmStorage` metadata | Reuses the downloads mirror cache and can refresh the cache from the command bar. |
| Native locations | `AgusCommandAsyncProvider` in the command dialog plus the existing CoMaps native map search view | Adds query-specific search commands and delegates native result polling/cancellation to the map search controller. |
| Project layers/features | DuckDB layer store | Refreshes when the layer-store revision signal increments after edits. |

MWM command results use the same region metadata as Downloads. Selection
focuses installed maps, downloads missing maps, or updates stale maps when the
cached mirror snapshot is newer.

Native location search results are still rendered in the dedicated Search view,
where stale native generations are cancelled and route actions are available.
The command bar feeds the typed query into that same flow so command input and
search input stay consistent.

## Platform menu entry points

On macOS, the native `Edit > Find` menu item opens the same map search flow as
the Search Map command. The desktop-only native `Tools` menu uses the same
workbench tool registry as the command bar for Point of Interest and Debug
Console, so future tool additions should update the shared registry rather than
adding separate menu-only actions.

## MWM layer actions

The Project Layers activity shows bundled and downloaded MWM files in an
`MWM Maps` view pane. The pane supports:

| Action | Behavior |
| --- | --- |
| Show/Hide | Persists the visibility preference for downloaded maps. Downloaded maps that are shown are registered immediately; hidden downloaded maps are skipped on the next map startup. Bundled maps stay visible because they are loaded before the native surface is created. |
| Focus Map | Moves to known locations such as Gibraltar or starts a map search for the region. |
| Update from Mirror | Runs the command-bar download/update path for the matching cached region. When upgrading, the old version is preserved but marked inactive, and the new version becomes the active map. |
| Delete Download | Deletes non-bundled MWM files via `MwmStorage.deleteMap`. Bundled maps are protected. Can delete specific versions or all versions of a region. |
| Order by Map/Date | Persists the MWM layer ordering preference for the tree. Ordering applies to all versions across all regions consistently. |
| Active Version | Each region can have multiple versions, but only one is active and registered with the native renderer. The active version is marked with an 'ACTIVE' badge in the tree. |

The native CoMaps binding currently exposes map registration but no per-MWM
unregister call, so hiding an already registered downloaded MWM takes full
effect on the next map startup. This limitation is surfaced by the UI message
instead of silently pretending the live native renderer changed.

### Version management

When a map is upgraded:
- The old version metadata is preserved in storage but marked inactive
- The new version becomes the active version
- Only the active version is registered with the native renderer
- All versions appear in the tree, ordered according to the current sort mode
- Users can switch which version is active (future enhancement)
