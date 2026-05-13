# Agus Maps DuckDB Schemas

This directory documents the DuckDB database owned by an `agus_maps_flutter` application instance.

The database stores layer metadata, first-party drawing features, preset query layers, custom query layers, and rendering state. It is not a replacement for CoMaps `.mwm` files; it is a companion persistence and analytics store used to render additional user and data-driven layers through the native map widget.

## Database Scope

The default database is a single app-instance DuckDB file in the app writable/support directory. Mobile builds embed DuckDB and the required extensions statically. Desktop builds bundle private DuckDB artifacts with the plugin or SDK package and must not resolve DuckDB from a user machine installation.

## Required Extensions

The runtime must verify these extensions during startup:

- `core_functions`
- `parquet`
- `json`
- `icu`
- `httpfs`
- `spatial`

`core_functions` and `parquet` are default DuckDB build extensions, but they are still listed in the project extension config so the shipped feature surface is auditable.

## Layer Types

The `agus.layers.kind` column uses these values:

- `native_mwm`: high-level CoMaps style/native layer metadata mirrored for UI ordering and visibility.
- `user_draw`: first-party user-created pins, lines, segments, and polygons.
- `comaps_supported`: project-supported custom layers backed by known data sources or presets.
- `duckdb_query`: user-defined or preset DuckDB query layers.

## Render Contract

First-party drawing layers write into strict tables owned by the plugin. Custom SQL is unrestricted, but a query layer is renderable only when its render SQL returns this contract:

| Column | Type | Required | Meaning |
| --- | --- | --- | --- |
| `feature_id` | `VARCHAR` | Yes | Stable feature identifier within the layer. |
| `geometry` | `GEOMETRY` | Yes | WGS84/EPSG:4326 geometry consumed by the native renderer. |
| `properties` | `JSON` | Yes | Display/query metadata. Use `{}` when empty. |
| `style` | `JSON` | No | Per-feature style override. |
| `min_zoom` | `INTEGER` | No | Feature visibility lower zoom bound. |
| `max_zoom` | `INTEGER` | No | Feature visibility upper zoom bound. |
| `z_index` | `INTEGER` | No | Per-feature ordering override. |

The renderer converts WGS84 geometry to CoMaps Mercator coordinates on the native side. For large result sets, custom queries should include viewport predicates or be wrapped by generated renderer SQL that filters by bounds.

The native bridge now exposes a JSON query-result API for setup, diagnostics, and small UI-facing result sets. The payload shape is:

```json
{
	"columns": [{"name": "feature_id", "type": "VARCHAR"}],
	"rows": [["example-feature"]],
	"row_count": 1
}
```

The same bridge exposes render-query validation that wraps candidate SQL in `SELECT * FROM (...) LIMIT 0` and checks the required render contract without materializing feature rows.

## Migrations

Migrations live in `doc/schemas/migrations/` and are named with date plus sequence: `YYYYMMDD_NNN_description.sql`.

Runtime migration code should treat these files as the source of truth. If migrations are embedded into native source for mobile/offline startup, generation must preserve the SQL text and checksum.

The native manifest is generated from those SQL files into `src/agus_duckdb_migrations.inc`. Run this after adding or editing migrations:

```bash
dart run tool/build.dart --generate-duckdb-migrations
dart run tool/build.dart --check-duckdb-migrations
```

## Dart Layer Store

The public Dart API includes `DuckDBLayerStore`, which uses the native DuckDB bridge for layer persistence. The first API surface supports:

- Layer CRUD through `AgusLayerDraft` and `AgusLayer`.
- Feature CRUD through WKT input in `AgusLayerFeatureDraft` and WKT output in `AgusLayerFeature`.
- Query-layer upsert/read through `AgusQueryLayerDraft` and `AgusQueryLayer`, with optional render-contract validation before saving.
- Layer key/value metadata through `AgusLayerMetadataEntry`.
- Local database backups through `CHECKPOINT` plus file copy to `duckdb_backups/` or a caller-provided directory.
- **Search result caching** through `AgusSearchCacheDraft` and `AgusSearchCacheEntry`, with query/locale-based lookups, map data revision tracking, and invalidation support.
- **Focus center persistence** for layers and features through nullable columns, supporting async on-demand calculation and invalidation. Access via `getLayerFocusCenter`, `setLayerFocusCenter`, `getFeatureFocusCenter`, and `setFeatureFocusCenter`.
- **Keymap settings** through `AgusKeymapSettingDraft` and `AgusKeymapSetting`, storing platform/command/keybinding payloads with validation schema versioning.

### Search Result Cache

The `agus.search_result_cache` table stores normalized search queries with map data revision tracking. Each entry includes:

- **cache_id**: Unique identifier for the cache entry
- **normalized_query**: Normalized search query string
- **locale**: Query locale for localized results
- **map_data_revision** and **map_data_fingerprint**: Optional tracking of map data versions
- **result_payload**: JSON payload containing search results
- **result_count**: Number of results in the payload
- **is_stale**: Boolean flag for invalidation
- **invalidation_reason**: Optional explanation when stale

Cache entries track creation, update, and access timestamps. The API supports:
- `upsertSearchCache`: Insert or update a cache entry
- `getSearchCache`: Retrieve by cache ID (updates accessed_at)
- `searchCache`: Find entries by normalized query and locale
- `invalidateSearchCacheByRevision`: Mark entries stale by map data revision
- `invalidateAllSearchCache`: Global invalidation
- `deleteSearchCache`: Remove an entry

### Focus Center Persistence

Layers and features can store calculated focus centers in nullable columns:

- **focus_center_lon** and **focus_center_lat**: WGS84 coordinates
- **focus_center_calculated_at**: Timestamp of last calculation

Null values indicate "not yet calculated," supporting async computation. The API supports:
- `getLayerFocusCenter` / `getFeatureFocusCenter`: Retrieve center or null
- `setLayerFocusCenter` / `setFeatureFocusCenter`: Store calculated center
- `clearLayerFocusCenter` / `clearFeatureFocusCenter`: Invalidate stored center

Focus centers should be invalidated when layer/feature geometry changes.

### Keymap Settings

The `agus.keymap_settings` table stores platform-specific keybinding configurations:

- **setting_id**: Unique identifier
- **platform**: Platform name (e.g., 'macos', 'windows', 'linux')
- **command**: Command identifier
- **keybinding_payload**: JSON payload with keybinding details
- **is_override**: Whether this is a user override (vs. default)
- **display_name** and **description**: Optional human-readable metadata
- **validation_schema_version**: Schema version for payload validation

The API supports:
- `upsertKeymapSetting`: Insert or update a setting
- `getKeymapSetting`: Retrieve by setting ID
- `listKeymapSettings`: Query by platform and optional command
- `deleteKeymapSetting`: Remove a setting

The `keybinding_payload` JSON follows the schema in `keymap.schema.json` and includes:
- **key**: Primary key (e.g., 'k', 'arrowUp', 'escape')
- **control**: Boolean for Ctrl modifier
- **shift**: Boolean for Shift modifier
- **alt**: Boolean for Alt/Option modifier
- **meta**: Boolean for Cmd/Win modifier

See `doc/KEYMAP-ARCHITECTURE.md` for complete documentation of the keymap system, including default bindings, conflict detection, and platform conventions.

Alternatively, keymap settings can be stored as typed `agus.app_metadata` entries using the key format `keymap:{platform}:{command}`.

## Native Drape Rendering

Android, macOS, iOS, and Windows now have a DuckDB-backed native renderer. The renderer queries visible `agus.layer_features` rows joined to visible `agus.layers`, filters by stored bounding boxes and zoom bounds, converts WGS84 geometry to CoMaps Mercator coordinates in native code, and submits points plus line/polygon outlines to Drape through native Drape APIs.

The renderer fetches native rows through paged C ABI calls rather than the JSON query helper, so map refreshes avoid one large materialized JSON payload. Android and Windows read up to 10,000 matching rows in batches of 1,000 before submitting the visible geometries to Drape.

The public Dart controls are:

- `setDuckDBMapLayerRenderingEnabled(bool enabled)`: enables or disables viewport-driven native refreshes on Android, macOS, iOS, and Windows.
- `refreshDuckDBMapLayers()`: manually refreshes visible features and returns the number submitted to Drape, or a negative value if DuckDB/map state is not ready.

The project layer store starts independently from the renderer so users can
create layers and capture features before the native map surface is ready. See
[LAYERS.md](LAYERS.md) for the runtime startup contract.

## Reusable Layer UI

The first reusable DuckDB layer UI is exported from the main plugin library:

- `DuckDBLayerDrawController`: captures pins, two-point segments, multi-vertex lines, and polygons; supports vertex editing; stores user metadata; writes WKT features with bounding boxes to `DuckDBLayerStore`. Rendering is handled natively via the `nativeEditGeometryRenderer` callback which submits sketch/edit geometry to Drape.
- `DuckDBLayerDrawOverlay`: a compatibility widget that exists for layout/API stability but does not render any Flutter-layer overlays. All drawing/editing visuals (sketch edges, vertex markers, edit handles) are rendered natively by Drape.
- `DuckDBLayerDrawToolbar`: icon controls for draw tools, undo, commit, and cancel.
- `DuckDBLayerMetadataForm`: title/note capture for the next committed feature.
- `DuckDBLayerPanel`: visibility and z-order controls for DuckDB layers, plus a database backup action.

Drawing and editing geometry is submitted to the native side through `setDuckDBInteractionGeometryFromWkt()` which renders sketch/edit edges and vertex handles directly in the Drape scene. The controller ensures native geometry is updated on vertex add/move/undo and cleared on commit/cancel/dispose.

## Manual Testing

Use [doc/schemas/MANUAL-TESTING.md](MANUAL-TESTING.md) for the current step-by-step runtime checklist covering DuckDB startup, Android native rendering, drawing tools, layer controls, backups, and release artifact checks.

## User Stories

See [../user-stories/](../user-stories/) for high-level feature documentation covering:
- Search persistence and result preservation
- Command-driven drawing and interaction state safety
- Layer/feature focus centers and active selection
- Status telemetry copy with notifications
- Editable/platform keymaps
- MWM ordering/upgrades/active map management
- Reusable Agus design components and Widgetbook coverage

Each user story documents implemented behavior from the user's perspective, with acceptance criteria, implementation references, and testing approaches.
