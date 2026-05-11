# User Story: Layer/Feature Focus Centers and Active Selection

## As a map user
I want to quickly focus on layers and features by their calculated center points, so that I can navigate large datasets efficiently.

## Background
Layers and features can span large geographic areas or contain many scattered geometries. Users need a quick way to "jump to" a layer or feature without manually panning and zooming. Calculating centers on-demand for large datasets can be slow, so centers should be cached and invalidated when geometry changes.

## Acceptance Criteria

### Focus Center Persistence
- ✅ Layers store focus centers in nullable columns:
  - `focus_center_lon` (WGS84 longitude)
  - `focus_center_lat` (WGS84 latitude)
  - `focus_center_calculated_at` (timestamp)
- ✅ Features store focus centers in the same schema
- ✅ Null values indicate "not yet calculated"
- ✅ Centers are computed asynchronously on first focus request

### Focus Center API
- ✅ `getLayerFocusCenter(layerId)`: Returns center or null
- ✅ `setLayerFocusCenter(layerId, lon, lat)`: Stores calculated center
- ✅ `clearLayerFocusCenter(layerId)`: Invalidates stored center
- ✅ `getFeatureFocusCenter(featureId)`: Returns center or null
- ✅ `setFeatureFocusCenter(featureId, lon, lat)`: Stores calculated center
- ✅ `clearFeatureFocusCenter(featureId)`: Invalidates stored center

### Focus Workflow
1. User selects "Focus Layer" command or clicks feature in Layer Manager
2. App queries `getLayerFocusCenter(layerId)`
3. If null:
   - App calculates center from layer geometries (e.g., bounding box centroid)
   - App calls `setLayerFocusCenter(layerId, lon, lat)`
4. If non-null:
   - App uses cached center immediately
5. App moves map camera to center point with appropriate zoom

### Invalidation Triggers
- ✅ Adding features to a layer clears layer focus center
- ✅ Editing feature geometry clears feature focus center
- ✅ Deleting features from a layer clears layer focus center
- ✅ Bulk geometry changes trigger batch invalidation

### Active Selection State
- ✅ Layer Manager tracks which layer/feature is currently selected
- ✅ Selected layer highlights in UI with visual indicator
- ✅ Selected feature shows edit handles in Drape (native rendering)
- ✅ Command bar "Focus Layer" commands populate from layer metadata
- ✅ MWM layer focus commands use known region coordinates or trigger search

### Layer Manager Integration
- ✅ Layer rows show visibility toggle and focus action
- ✅ Feature rows show geometry type and focus action
- ✅ Expanding a layer loads features via `listFeatures(layerId)`
- ✅ Focus action calls focus workflow with cached/calculated center

### MWM Focus Centers
- ✅ MWM layer focus commands use known location metadata
- ✅ Known regions (e.g., Gibraltar, Philippines) use hardcoded coordinates
- ✅ Unknown regions trigger map search with region name
- ✅ Focus commands appear in command bar grouped by category

## Implementation References

### Database Schema
- Tables: `agus.layers`, `agus.layer_features`
- Columns: `focus_center_lon`, `focus_center_lat`, `focus_center_calculated_at`
- Schema: `doc/schemas/README.md`

### Dart API
- `DuckDBLayerStore.getLayerFocusCenter()`
- `DuckDBLayerStore.setLayerFocusCenter()`
- `DuckDBLayerStore.clearLayerFocusCenter()`
- `DuckDBLayerStore.getFeatureFocusCenter()`
- `DuckDBLayerStore.setFeatureFocusCenter()`
- `DuckDBLayerStore.clearFeatureFocusCenter()`

### Focus Calculation
- Point: Use point coordinates directly
- LineString: Use bounding box centroid
- Polygon: Use bounding box centroid or geometric center
- MultiGeometry: Use bounding box of union
- Layer: Use bounding box of all features

### Command Bar Integration
- Command group: "Map Focus"
- Commands: "Focus Gibraltar", "Focus Philippines", etc.
- Dynamic: "Focus MWM Map: `<region>`"
- Behavior: Moves camera to known location or starts search

## Testing Approach
- Manual: Focus on a layer with many features, verify center is calculated
- Manual: Focus again, verify cached center is used (faster)
- Manual: Edit a feature, focus parent layer, verify center is recalculated
- Unit: Test center calculation for each geometry type
- Unit: Test invalidation triggers

## Documentation
- Layer runtime: `doc/schemas/LAYERS.md`
- Database schemas: `doc/schemas/README.md`
- Command bar: `doc/COMMAND-BAR.md`
- Layer manager: Layer Manager Explorer section in `LAYERS.md`

## Related Features
- Command-driven drawing and interaction state safety
- Search persistence and result preservation
- MWM ordering/upgrades/active map management
