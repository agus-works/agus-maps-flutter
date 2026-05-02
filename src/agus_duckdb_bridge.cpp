#include "agus_maps_flutter.h"

#include "duckdb.h"

#include <fstream>
#include <mutex>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

#if defined(__APPLE__)
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

  return true;
}

void EnsureStaticDuckDBExtensionLoaderLinked()
{
#if defined(__APPLE__)
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
  if (duckdb_open(databasePath.c_str(), &g_duckdbDatabase) != DuckDBSuccess)
  {
    SetDuckDBError("Failed to open DuckDB database: " + databasePath);
    return 0;
  }

  if (duckdb_connect(g_duckdbDatabase, &g_duckdbConnection) != DuckDBSuccess)
  {
    SetDuckDBError("Failed to connect to DuckDB database: " + databasePath);
    CloseDuckDBLocked();
    return 0;
  }

  g_duckdbPath = databasePath;
  return LoadRequiredDuckDBExtensionsLocked() ? 1 : 0;
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
