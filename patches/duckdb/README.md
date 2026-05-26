# DuckDB Patch Files

This directory contains patch files (`*.patch`) applied to the DuckDB checkout in `thirdparty/duckdb`.

Patches are applied by `dart run tool/build.dart` in deterministic filename order after the checkout is reset to the configured `DUCKDB_TAG`.

Use this directory only for changes that must live on top of the pinned DuckDB release. Keep patches narrow, documented in their commit message/body, and update `DUCKDB_TAG` deliberately when rebasing them.

## Patch Inventory

### 0001-fmt-secure-scl-value-check.patch

**Purpose:** Fixes DuckDB's bundled `fmt` compatibility with newer MSVC STL headers used by Visual Studio 18 / MSVC 14.51.

The bundled `fmt` header checked `_SECURE_SCL` with `#ifdef`, but current MSVC headers define `_SECURE_SCL` to `0` for non-debug iterator settings. That made `fmt` try to use removed `stdext::checked_array_iterator` symbols even when secure iterator checking is disabled.

**Without this patch:**
- Windows DuckDB builds fail in `third_party/fmt/include/fmt/format.h`.
- Errors include `stdext: is not a class or namespace name` and `checked_array_iterator` syntax failures.
