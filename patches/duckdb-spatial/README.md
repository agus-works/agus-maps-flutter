# duckdb-spatial Patch Files

This directory contains patch files (`*.patch`) applied to the duckdb-spatial checkout in `thirdparty/duckdb-spatial`.

The default `DUCKDB_SPATIAL_TAG` is pinned to the spatial commit referenced by DuckDB `v1.5.2` so the extension and DuckDB core move together. Patches here should only cover mobile/static-linking or build-system fixes that cannot be carried in project CMake.
