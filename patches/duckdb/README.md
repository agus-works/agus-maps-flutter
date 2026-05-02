# DuckDB Patch Files

This directory contains patch files (`*.patch`) applied to the DuckDB checkout in `thirdparty/duckdb`.

Patches are applied by `dart run tool/build.dart` in deterministic filename order after the checkout is reset to the configured `DUCKDB_TAG`.

Use this directory only for changes that must live on top of the pinned DuckDB release. Keep patches narrow, documented in their commit message/body, and update `DUCKDB_TAG` deliberately when rebasing them.
