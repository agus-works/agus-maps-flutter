# User Story: MWM Ordering, Upgrades, and Active Map Management

## As a map user
I want to download, update, order, and manage MWM map versions, so that I can control which maps are active and keep them up to date.

## Background
CoMaps uses MWM (Mobile World Maps) files for offline map data. Users can download multiple regions, and regions can have multiple versions (e.g., after upgrades). Only one version of each region should be active (registered with the native renderer) at a time. Users need visibility, ordering, and upgrade controls in the UI.

## Acceptance Criteria

### MWM Layer Visibility in Project Layers
- ✅ MWM maps appear in Layer Manager "MWM Maps" view pane
- ✅ Bundled maps (shipped with app) always shown and loaded before native surface ready
- ✅ Downloaded maps support Show/Hide toggle with persistent preference
- ✅ Shown downloaded maps are registered immediately
- ✅ Hidden downloaded maps skipped on next map startup
- ✅ Current limitation: Native CoMaps does not expose per-MWM unregister, so hiding takes effect on next startup

### Version Management
- ✅ Each region can have multiple versions
- ✅ Only one version per region is "active"
- ✅ Active version marked with 'ACTIVE' badge in tree
- ✅ Active version registered with native renderer
- ✅ Old versions preserved but marked inactive after upgrade
- ✅ All versions appear in tree, ordered by current sort mode
- ✅ Future: Users can switch which version is active

### MWM Layer Actions
- ✅ **Show/Hide**: Persists visibility preference
- ✅ **Focus Map**: Moves to known location or starts map search for region
- ✅ **Update from Mirror**: Downloads/updates map from cached mirror
  - Old version preserved but marked inactive
  - New version becomes active
  - Upgrading reuses command-bar download/update path
- ✅ **Delete Download**: Deletes non-bundled MWM files via `MwmStorage.deleteMap`
  - Bundled maps protected from deletion
  - Can delete specific versions or all versions of a region
- ✅ **Order by Map/Date**: Persists ordering preference for tree
  - Applies to all versions across all regions consistently

### Command Bar Integration
- ✅ **MWM Layers** command group:
  - "Focus MWM Map: `<region>`" commands
  - Focuses known map locations directly
  - Opens map search activity for unknown regions
- ✅ **MWM Downloads** command group:
  - "Refresh MWM Catalog": Refreshes mirror cache
  - "Download Map": Downloads missing map
  - "Update Map": Updates stale map
  - "Open Downloaded Map": Focuses installed map
- ✅ MWM command results use same region metadata as Downloads activity
- ✅ Selection behavior:
  - Installed maps: Focuses map
  - Missing maps: Downloads from mirror
  - Stale maps: Updates to newer cached version

### Download and Mirror Cache
- ✅ `DownloadsCacheService`: Caches mirror metadata
- ✅ `MirrorService`: Manages download mirror endpoints
- ✅ `MwmStorage`: Native API for map registration, deletion, metadata
- ✅ Command bar can refresh cache and trigger downloads/updates
- ✅ Cache reused across command bar and Downloads activity

### MWM Metadata Tracking
- ✅ Region name and version stored in metadata
- ✅ Map data fingerprint computed from visible MWM metadata:
  - Region name + snapshot version
- ✅ Fingerprint used for search cache invalidation
- ✅ Adding/removing/hiding/showing/upgrading MWM changes fingerprint
- ✅ Search cache entries invalidated on fingerprint change

### Native Registration Contract
- ✅ Bundled maps registered before native surface ready
- ✅ Downloaded maps registered when shown
- ✅ Active version of each region registered
- ✅ Inactive versions not registered
- ✅ Native CoMaps tracks registration, not individual unregister
- ✅ UI shows messages when hide takes effect on restart

## Implementation References

### Dart Services
- **DownloadsCacheService**: Mirror metadata caching
- **MirrorService**: Download mirror management
- **MwmStorage**: Native FFI for MWM operations

### Native APIs
- `MwmStorage.listMaps()`: Returns all MWM files with metadata
- `MwmStorage.registerMap()`: Registers MWM with native renderer
- `MwmStorage.deleteMap()`: Deletes MWM file
- `MwmStorage.getMapMetadata()`: Returns region name, version, size, etc.

### Command Bar Actions
- Command groups: "MWM Layers", "MWM Downloads"
- Async feeds: MWM command results from `DownloadsCacheService` + `MwmStorage`
- Selection delegates to focus, download, or update flow

### Layer Manager UI
- View pane: "MWM Maps"
- Tree structure: Region → Versions
- Actions: Show/Hide, Focus, Update, Delete, Order
- Badges: 'ACTIVE' for active version, 'BUNDLED' for shipped maps
- Ordering: By map name or by date (persistent preference)

### Map Data Fingerprint
- Computed from: Visible MWM metadata (region name + version)
- Used by: Search cache invalidation
- Triggers: Add/remove/hide/show/upgrade MWM
- Effect: Invalidates stale search cache entries

## Testing Approach
- Manual: Download map from command bar, verify registration
- Manual: Upgrade map, verify old version marked inactive, new version active
- Manual: Hide map, restart app, verify not registered
- Manual: Show map, verify registered on next startup
- Manual: Delete specific version, verify tree updates
- Manual: Order by map/date, verify tree reorders
- Manual: Focus MWM map, verify camera moves to known location
- Manual: Search cache invalidation after MWM change
- Unit: Test metadata parsing, fingerprint generation, version comparison

## Documentation
- Command bar: `doc/COMMAND-BAR.md`
- Layer runtime: `doc/schemas/LAYERS.md`
- MWM ordering summary: `mwm-ordering-summary.md` (root)
- Search implementation: `doc/IMPLEMENTATION-SEARCH.md`

## Limitations and Future Work
- Current: No per-MWM unregister API in native CoMaps
  - Hide takes effect on next startup
- Future: Real-time unregister without restart
- Future: User can switch active version without upgrade
- Future: Automatic update notifications when mirror has newer version
- Future: Download queue and progress tracking in UI

## Related Features
- Search persistence and result preservation (cache invalidation)
- Command-driven drawing and interaction state safety
- Layer/feature focus centers and active selection
