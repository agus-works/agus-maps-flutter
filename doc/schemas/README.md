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

## Migrations

Migrations live in `doc/schemas/migrations/` and are named with date plus sequence: `YYYYMMDD_NNN_description.sql`.

Runtime migration code should treat these files as the source of truth. If migrations are embedded into native source for mobile/offline startup, generation must preserve the SQL text and checksum.
