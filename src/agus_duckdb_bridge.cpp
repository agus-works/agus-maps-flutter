#include "agus_maps_flutter.h"

#include "duckdb.h"

#include <cstdint>
#include <fstream>
#include <iomanip>
#include <mutex>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

#if defined(__APPLE__) || defined(__ANDROID__)
namespace duckdb
{
std::vector<std::string> LinkedExtensions();
}
#endif

namespace
{
std::mutex g_duckdbMutex;
duckdb_database g_duckdbDatabase = nullptr;
duckdb_connection g_duckdbConnection = nullptr;
std::string g_duckdbPath;
std::string g_lastDuckdbError;

struct DuckDBMigration
{
  char const * version;
  char const * description;
  char const * sql;
};

char const kInitialDuckDBLayerMigrationSql[] = R"AGUS_SQL(CREATE SCHEMA IF NOT EXISTS agus;

CREATE TABLE IF NOT EXISTS agus.schema_migrations (
  version VARCHAR PRIMARY KEY,
  description VARCHAR NOT NULL,
  checksum VARCHAR NOT NULL,
  applied_at TIMESTAMP NOT NULL DEFAULT current_timestamp
);

CREATE TABLE IF NOT EXISTS agus.app_metadata (
  key VARCHAR PRIMARY KEY,
  value JSON NOT NULL,
  updated_at TIMESTAMP NOT NULL DEFAULT current_timestamp
);

CREATE TABLE IF NOT EXISTS agus.layers (
  layer_id VARCHAR PRIMARY KEY,
  name VARCHAR NOT NULL,
  kind VARCHAR NOT NULL CHECK (
    kind IN ('native_mwm', 'user_draw', 'comaps_supported', 'duckdb_query')
  ),
  visible BOOLEAN NOT NULL DEFAULT true,
  locked BOOLEAN NOT NULL DEFAULT false,
  z_index INTEGER NOT NULL DEFAULT 0,
  min_zoom INTEGER,
  max_zoom INTEGER,
  style JSON,
  metadata JSON,
  created_at TIMESTAMP NOT NULL DEFAULT current_timestamp,
  updated_at TIMESTAMP NOT NULL DEFAULT current_timestamp,
  deleted_at TIMESTAMP
);

CREATE TABLE IF NOT EXISTS agus.layer_features (
  layer_id VARCHAR NOT NULL REFERENCES agus.layers(layer_id),
  feature_id VARCHAR NOT NULL,
  geometry GEOMETRY NOT NULL,
  geometry_kind VARCHAR NOT NULL CHECK (
    geometry_kind IN ('point', 'line', 'segment', 'polygon', 'multipoint', 'multiline', 'multipolygon', 'collection')
  ),
  properties JSON NOT NULL,
  style JSON,
  bbox_min_lon DOUBLE,
  bbox_min_lat DOUBLE,
  bbox_max_lon DOUBLE,
  bbox_max_lat DOUBLE,
  z_index INTEGER,
  min_zoom INTEGER,
  max_zoom INTEGER,
  created_at TIMESTAMP NOT NULL DEFAULT current_timestamp,
  updated_at TIMESTAMP NOT NULL DEFAULT current_timestamp,
  deleted_at TIMESTAMP,
  PRIMARY KEY (layer_id, feature_id)
);

CREATE TABLE IF NOT EXISTS agus.query_layers (
  layer_id VARCHAR PRIMARY KEY REFERENCES agus.layers(layer_id),
  sql_text VARCHAR NOT NULL,
  is_preset BOOLEAN NOT NULL DEFAULT false,
  required_extensions JSON NOT NULL,
  result_contract_version INTEGER NOT NULL DEFAULT 1,
  last_validated_at TIMESTAMP,
  last_error VARCHAR
);

CREATE TABLE IF NOT EXISTS agus.layer_metadata (
  layer_id VARCHAR NOT NULL REFERENCES agus.layers(layer_id),
  key VARCHAR NOT NULL,
  value VARCHAR NOT NULL,
  value_type VARCHAR NOT NULL DEFAULT 'string',
  updated_at TIMESTAMP NOT NULL DEFAULT current_timestamp,
  PRIMARY KEY (layer_id, key)
);

CREATE TABLE IF NOT EXISTS agus.layer_render_cache (
  layer_id VARCHAR NOT NULL REFERENCES agus.layers(layer_id),
  cache_key VARCHAR NOT NULL,
  viewport_min_lon DOUBLE NOT NULL,
  viewport_min_lat DOUBLE NOT NULL,
  viewport_max_lon DOUBLE NOT NULL,
  viewport_max_lat DOUBLE NOT NULL,
  zoom INTEGER NOT NULL,
  feature_count INTEGER NOT NULL DEFAULT 0,
  generated_at TIMESTAMP NOT NULL DEFAULT current_timestamp,
  PRIMARY KEY (layer_id, cache_key)
);

CREATE INDEX IF NOT EXISTS idx_agus_layers_visible_z
  ON agus.layers(visible, z_index);

CREATE INDEX IF NOT EXISTS idx_agus_features_layer
  ON agus.layer_features(layer_id);

CREATE INDEX IF NOT EXISTS idx_agus_features_bbox
  ON agus.layer_features(bbox_min_lon, bbox_min_lat, bbox_max_lon, bbox_max_lat);

CREATE INDEX IF NOT EXISTS idx_agus_features_deleted
  ON agus.layer_features(deleted_at);
)AGUS_SQL";

DuckDBMigration const kDuckDBMigrations[] = {
    {
        "20260502_001_initial_duckdb_layers",
        "Initial DuckDB layer schema",
        kInitialDuckDBLayerMigrationSql,
    },
};

void SetDuckDBError(std::string message)
{
  g_lastDuckdbError = std::move(message);
}

void ClearDuckDBError()
{
  g_lastDuckdbError.clear();
}

std::string BuildAppDatabasePath(char const * writablePath)
{
  if (writablePath == nullptr || writablePath[0] == '\0')
    return {};

  std::string base(writablePath);
  if (!base.empty() && base.back() != '/')
    base.push_back('/');
  base += "agus_layers.duckdb";
  return base;
}

void CloseDuckDBLocked()
{
  if (g_duckdbConnection != nullptr)
  {
    duckdb_disconnect(&g_duckdbConnection);
    g_duckdbConnection = nullptr;
  }
  if (g_duckdbDatabase != nullptr)
  {
    duckdb_close(&g_duckdbDatabase);
    g_duckdbDatabase = nullptr;
  }
  g_duckdbPath.clear();
}

bool ExecuteDuckDBLocked(std::string const & sql)
{
  if (g_duckdbConnection == nullptr)
  {
    SetDuckDBError("DuckDB connection is not open");
    return false;
  }

  duckdb_result result;
  if (duckdb_query(g_duckdbConnection, sql.c_str(), &result) != DuckDBSuccess)
  {
    char const * error = duckdb_result_error(&result);
    SetDuckDBError(error != nullptr ? error : "DuckDB query failed");
    duckdb_destroy_result(&result);
    return false;
  }

  duckdb_destroy_result(&result);
  ClearDuckDBError();
  return true;
}

std::string DuckDBStringLiteral(std::string const & value)
{
  std::string escaped;
  escaped.reserve(value.size() + 2);
  escaped.push_back('\'');
  for (char c : value)
  {
    if (c == '\'')
      escaped.push_back('\'');
    escaped.push_back(c);
  }
  escaped.push_back('\'');
  return escaped;
}

std::string DuckDBMigrationChecksum(std::string const & sql)
{
  uint64_t hash = 14695981039346656037ULL;
  for (unsigned char c : sql)
  {
    hash ^= static_cast<uint64_t>(c);
    hash *= 1099511628211ULL;
  }

  std::ostringstream stream;
  stream << "fnv1a64:" << std::hex << std::setw(16) << std::setfill('0')
         << hash;
  return stream.str();
}

bool QuerySingleDuckDBStringLocked(std::string const & sql, bool & hasRow,
                                   std::string & value)
{
  hasRow = false;
  value.clear();

  if (g_duckdbConnection == nullptr)
  {
    SetDuckDBError("DuckDB connection is not open");
    return false;
  }

  duckdb_result result;
  if (duckdb_query(g_duckdbConnection, sql.c_str(), &result) != DuckDBSuccess)
  {
    char const * error = duckdb_result_error(&result);
    SetDuckDBError(error != nullptr ? error : "DuckDB query failed");
    duckdb_destroy_result(&result);
    return false;
  }

  if (duckdb_column_count(&result) == 0)
  {
    duckdb_destroy_result(&result);
    SetDuckDBError("DuckDB scalar query returned no columns");
    return false;
  }

  if (duckdb_row_count(&result) > 0)
  {
    hasRow = true;
    char * rawValue = duckdb_value_varchar(&result, 0, 0);
    if (rawValue != nullptr)
    {
      value = rawValue;
      duckdb_free(rawValue);
    }
  }

  duckdb_destroy_result(&result);
  ClearDuckDBError();
  return true;
}

bool VerifyRequiredDuckDBExtensionLocked(char const * extension)
{
  std::string sql =
      "SELECT CASE WHEN loaded THEN '1' ELSE '0' END "
      "FROM duckdb_extensions() WHERE extension_name = ";
  sql += DuckDBStringLiteral(extension);
  sql += ";";

  bool hasRow = false;
  std::string loaded;
  if (!QuerySingleDuckDBStringLocked(sql, hasRow, loaded))
    return false;

  if (!hasRow)
  {
    SetDuckDBError(std::string("Required DuckDB extension is unavailable: ") +
                   extension);
    return false;
  }

  if (loaded != "1")
  {
    SetDuckDBError(std::string("Required DuckDB extension is not loaded: ") +
                   extension);
    return false;
  }

  return true;
}

bool LoadRequiredDuckDBExtensionsLocked()
{
  char const * extensions[] = {
      "core_functions",
      "parquet",
      "json",
      "icu",
      "httpfs",
      "spatial",
  };

  for (char const * extension : extensions)
  {
    std::string sql = "LOAD ";
    sql += extension;
    sql += ";";
    if (!ExecuteDuckDBLocked(sql))
      return false;
  }

  for (char const * extension : extensions)
  {
    if (!VerifyRequiredDuckDBExtensionLocked(extension))
      return false;
  }

  return true;
}

bool EnsureDuckDBMigrationTableLocked()
{
  return ExecuteDuckDBLocked(R"AGUS_SQL(CREATE SCHEMA IF NOT EXISTS agus;

CREATE TABLE IF NOT EXISTS agus.schema_migrations (
  version VARCHAR PRIMARY KEY,
  description VARCHAR NOT NULL,
  checksum VARCHAR NOT NULL,
  applied_at TIMESTAMP NOT NULL DEFAULT current_timestamp
);
)AGUS_SQL");
}

bool GetAppliedDuckDBMigrationChecksumLocked(std::string const & version,
                                             bool & hasMigration,
                                             std::string & checksum)
{
  std::string sql = "SELECT checksum FROM agus.schema_migrations WHERE version = ";
  sql += DuckDBStringLiteral(version);
  sql += ";";
  return QuerySingleDuckDBStringLocked(sql, hasMigration, checksum);
}

bool RollbackDuckDBMigrationLocked(std::string const & version,
                                   std::string const & message)
{
  ExecuteDuckDBLocked("ROLLBACK;");
  SetDuckDBError("DuckDB migration " + version + " failed: " + message);
  return false;
}

bool RunDuckDBMigrationLocked(DuckDBMigration const & migration)
{
  std::string const expectedChecksum = DuckDBMigrationChecksum(migration.sql);

  bool hasMigration = false;
  std::string existingChecksum;
  if (!GetAppliedDuckDBMigrationChecksumLocked(migration.version, hasMigration,
                                               existingChecksum))
    return false;

  if (hasMigration)
  {
    if (existingChecksum == expectedChecksum)
      return true;

    SetDuckDBError("DuckDB migration checksum mismatch for " +
                   std::string(migration.version) + ": expected " +
                   expectedChecksum + ", found " + existingChecksum);
    return false;
  }

  if (!ExecuteDuckDBLocked("BEGIN TRANSACTION;"))
    return false;

  if (!ExecuteDuckDBLocked(migration.sql))
    return RollbackDuckDBMigrationLocked(migration.version, g_lastDuckdbError);

  std::string insertSql =
      "INSERT INTO agus.schema_migrations(version, description, checksum) "
      "VALUES (";
  insertSql += DuckDBStringLiteral(migration.version);
  insertSql += ", ";
  insertSql += DuckDBStringLiteral(migration.description);
  insertSql += ", ";
  insertSql += DuckDBStringLiteral(expectedChecksum);
  insertSql += ");";
  if (!ExecuteDuckDBLocked(insertSql))
    return RollbackDuckDBMigrationLocked(migration.version, g_lastDuckdbError);

  if (!ExecuteDuckDBLocked("COMMIT;"))
  {
    std::string const commitError = g_lastDuckdbError;
    ExecuteDuckDBLocked("ROLLBACK;");
    SetDuckDBError("DuckDB migration " + std::string(migration.version) +
                   " commit failed: " + commitError);
    return false;
  }

  return true;
}

bool RunEmbeddedDuckDBMigrationsLocked()
{
  if (g_duckdbConnection == nullptr)
  {
    SetDuckDBError("DuckDB connection is not open");
    return false;
  }

  if (!EnsureDuckDBMigrationTableLocked())
    return false;

  for (auto const & migration : kDuckDBMigrations)
  {
    if (!RunDuckDBMigrationLocked(migration))
      return false;
  }

  ClearDuckDBError();
  return true;
}

void EnsureStaticDuckDBExtensionLoaderLinked()
{
#if defined(__APPLE__) || defined(__ANDROID__)
  static auto const linkedExtensions = duckdb::LinkedExtensions();
  (void)linkedExtensions;
#endif
}
} // namespace

FFI_PLUGIN_EXPORT const char * agus_duckdb_library_version(void)
{
  char const * version = duckdb_library_version();
  return version != nullptr ? version : "";
}

FFI_PLUGIN_EXPORT const char * agus_duckdb_last_error(void)
{
  std::lock_guard<std::mutex> lock(g_duckdbMutex);
  return g_lastDuckdbError.c_str();
}

FFI_PLUGIN_EXPORT int32_t agus_duckdb_open_app_database(char const * writablePath)
{
  std::lock_guard<std::mutex> lock(g_duckdbMutex);
  ClearDuckDBError();

  auto const databasePath = BuildAppDatabasePath(writablePath);
  if (databasePath.empty())
  {
    SetDuckDBError("Writable path is empty");
    return 0;
  }

  EnsureStaticDuckDBExtensionLoaderLinked();
  CloseDuckDBLocked();
  char * openError = nullptr;
  if (duckdb_open_ext(databasePath.c_str(), &g_duckdbDatabase, nullptr,
                      &openError) != DuckDBSuccess)
  {
    std::string message = "Failed to open DuckDB database: " + databasePath;
    if (openError != nullptr)
    {
      message += ": ";
      message += openError;
      duckdb_free(openError);
    }
    SetDuckDBError(message);
    return 0;
  }

  if (duckdb_connect(g_duckdbDatabase, &g_duckdbConnection) != DuckDBSuccess)
  {
    SetDuckDBError("Failed to connect to DuckDB database: " + databasePath);
    CloseDuckDBLocked();
    return 0;
  }

  g_duckdbPath = databasePath;
  if (!LoadRequiredDuckDBExtensionsLocked() ||
      !RunEmbeddedDuckDBMigrationsLocked())
  {
    CloseDuckDBLocked();
    return 0;
  }

  ClearDuckDBError();
  return 1;
}

FFI_PLUGIN_EXPORT void agus_duckdb_close(void)
{
  std::lock_guard<std::mutex> lock(g_duckdbMutex);
  CloseDuckDBLocked();
  ClearDuckDBError();
}

FFI_PLUGIN_EXPORT int32_t agus_duckdb_is_open(void)
{
  std::lock_guard<std::mutex> lock(g_duckdbMutex);
  return g_duckdbConnection != nullptr ? 1 : 0;
}

FFI_PLUGIN_EXPORT int32_t agus_duckdb_load_required_extensions(void)
{
  std::lock_guard<std::mutex> lock(g_duckdbMutex);
  return LoadRequiredDuckDBExtensionsLocked() ? 1 : 0;
}

FFI_PLUGIN_EXPORT int32_t agus_duckdb_execute(char const * sql)
{
  if (sql == nullptr || sql[0] == '\0')
  {
    std::lock_guard<std::mutex> lock(g_duckdbMutex);
    SetDuckDBError("SQL is empty");
    return 0;
  }

  std::lock_guard<std::mutex> lock(g_duckdbMutex);
  return ExecuteDuckDBLocked(sql) ? 1 : 0;
}

FFI_PLUGIN_EXPORT int32_t agus_duckdb_apply_migration_file(char const * path)
{
  if (path == nullptr || path[0] == '\0')
  {
    std::lock_guard<std::mutex> lock(g_duckdbMutex);
    SetDuckDBError("Migration path is empty");
    return 0;
  }

  std::ifstream file(path);
  if (!file)
  {
    std::lock_guard<std::mutex> lock(g_duckdbMutex);
    SetDuckDBError(std::string("Failed to open migration file: ") + path);
    return 0;
  }

  std::ostringstream buffer;
  buffer << file.rdbuf();

  std::lock_guard<std::mutex> lock(g_duckdbMutex);
  return ExecuteDuckDBLocked(buffer.str()) ? 1 : 0;
}

FFI_PLUGIN_EXPORT int32_t agus_duckdb_run_migrations(void)
{
  std::lock_guard<std::mutex> lock(g_duckdbMutex);
  return RunEmbeddedDuckDBMigrationsLocked() ? 1 : 0;
}
