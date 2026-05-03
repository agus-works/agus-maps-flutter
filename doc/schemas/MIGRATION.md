# DuckDB Migration Strategy

This document describes how production database migrations should run for the app-instance DuckDB file.

## Goals

- Apply migrations exactly once, in filename order.
- Keep migration SQL reviewable in this repository.
- Support mobile offline startup without fetching migration files from the network.
- Fail safely before rendering layers when schema state is unknown.
- Make file-level backups easy before risky user-driven SQL or schema upgrades.

## Migration Table

The database owns `agus.schema_migrations` with these columns:

- `version`: migration filename stem, for example `20260502_001_initial_duckdb_layers`.
- `description`: human-readable description.
- `checksum`: checksum of the SQL text used by the runtime.
- `applied_at`: timestamp when the migration was applied.

The runtime should verify that already-applied migrations still match their recorded checksum. A checksum mismatch means the database was created with a different migration body and startup should fail with a clear diagnostic.

The current native runner records checksums as `fnv1a64:<16 hex digits>`. The checksum is deterministic and intended to detect accidental drift between a database and the embedded migration text used by the plugin runtime.

## Runtime Algorithm

1. Open the app-instance DuckDB file with `duckdb_open_ext`.
2. Create the `agus` schema and `agus.schema_migrations` table if they do not exist.
3. Load required extensions and verify them through `duckdb_extensions()`.
4. Read embedded migration manifests in sorted order.
5. For each unapplied migration, start a transaction, execute the SQL, insert the migration row, and commit.
6. Roll back on any failure and surface the failing migration name and DuckDB error message to Dart.
7. Only initialize layer rendering after migrations and extension checks succeed.

## Backups

Before production schema upgrades, the UI should offer a quick static backup action:

1. Execute `CHECKPOINT`.
2. Close or quiesce write activity for the copy window.
3. Copy the `.duckdb` file to a timestamped backup path in the app support/documents area.
4. Report the backup path to the user.

The first implementation intentionally does not include sync, merge, or cloud conflict handling. Backups are local files owned by the user/application instance.

## User SQL

Custom SQL is unrestricted by design. The migration runner should not try to guard arbitrary user SQL. Instead, rendering code should require the documented query result contract before treating a user query as a layer source.

## Rollbacks

DuckDB migrations should be forward-only. If a migration must be corrected, add a new migration that transforms the schema/data from the previous state. Do not edit migration files that may already be recorded in `agus.schema_migrations`.
