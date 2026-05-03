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

## Native Drape Rendering

Android now has an initial DuckDB-backed native renderer. The renderer queries visible `agus.layer_features` rows joined to visible `agus.layers`, filters by stored bounding boxes and zoom bounds, converts WGS84 geometry to CoMaps Mercator coordinates in native code, and submits points plus line/polygon outlines to Drape through `df::UserMarksProvider`.

The renderer fetches native rows through paged C ABI calls rather than the JSON query helper, so map refreshes avoid one large materialized JSON payload. The current Android refresh loop reads up to 10,000 matching rows in batches of 1,000 before submitting the visible geometries to Drape.

The public Dart controls are:

- `setDuckDBMapLayerRenderingEnabled(bool enabled)`: enables or disables viewport-driven native refreshes on Android.
- `refreshDuckDBMapLayers()`: manually refreshes visible features and returns the number submitted to Drape, or a negative value if DuckDB/map state is not ready.

The renderer is intentionally Android-only for now. Apple, Windows, and Linux will need platform-specific Drape ownership wiring before these helpers are enabled there.

## Reusable Layer UI

The first reusable DuckDB layer UI is exported from the main plugin library:

- `DuckDBLayerDrawController`: captures pins, two-point segments, multi-vertex lines, and polygons; supports vertex editing; stores user metadata; writes WKT features with bounding boxes to `DuckDBLayerStore`.
- `DuckDBLayerDrawOverlay`: a full-map overlay that captures pointer events while a draw tool is active so map pan/zoom is not forwarded during drawing.
- `DuckDBLayerDrawToolbar`: icon controls for draw tools, undo, commit, and cancel.
- `DuckDBLayerMetadataForm`: title/note capture for the next committed feature.
- `DuckDBLayerPanel`: visibility and z-order controls for DuckDB layers, plus a database backup action.

Android draw overlays can call `screenPointToLatLon()` to convert Flutter overlay positions, after multiplying by the device pixel ratio, into WGS84 coordinates for WKT persistence.

## Manual Testing

Use [doc/schemas/MANUAL-TESTING.md](MANUAL-TESTING.md) for the current step-by-step runtime checklist covering DuckDB startup, Android native rendering, drawing tools, layer controls, backups, and release artifact checks.
