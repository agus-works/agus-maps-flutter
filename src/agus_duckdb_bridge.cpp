#include "agus_maps_flutter.h"

#include "duckdb.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <limits>
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
std::string g_lastDuckdbQueryJson;

struct DuckDBMigration
{
  char const * version;
  char const * description;
  char const * sql;
};

#include "agus_duckdb_migrations.inc"

struct DuckDBColumnInfo
{
  std::string name;
  duckdb_type type;
  duckdb_type logicalType;
  std::string alias;
};

void SetDuckDBError(std::string message)
{
  g_lastDuckdbError = std::move(message);
}

void ClearDuckDBError()
{
  g_lastDuckdbError.clear();
}

std::string ToLowerAscii(std::string value)
{
  std::transform(value.begin(), value.end(), value.begin(),
                 [](unsigned char character) {
                   return static_cast<char>(std::tolower(character));
                 });
  return value;
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

std::string TrimDuckDBSqlForSubquery(std::string value)
{
  auto const isSpace = [](unsigned char character) {
    return std::isspace(character) != 0;
  };

  while (!value.empty() && isSpace(static_cast<unsigned char>(value.back())))
    value.pop_back();
  while (!value.empty() && value.back() == ';')
  {
    value.pop_back();
    while (!value.empty() && isSpace(static_cast<unsigned char>(value.back())))
      value.pop_back();
  }

  auto first = value.begin();
  while (first != value.end() && isSpace(static_cast<unsigned char>(*first)))
    ++first;
  value.erase(value.begin(), first);
  return value;
}

void AppendJsonString(std::string & output, std::string const & value)
{
  output.push_back('"');
  for (unsigned char character : value)
  {
    switch (character)
    {
    case '"':
      output += "\\\"";
      break;
    case '\\':
      output += "\\\\";
      break;
    case '\b':
      output += "\\b";
      break;
    case '\f':
      output += "\\f";
      break;
    case '\n':
      output += "\\n";
      break;
    case '\r':
      output += "\\r";
      break;
    case '\t':
      output += "\\t";
      break;
    default:
      if (character < 0x20)
      {
        std::ostringstream escaped;
        escaped << "\\u" << std::hex << std::setw(4) << std::setfill('0')
                << static_cast<int>(character);
        output += escaped.str();
      }
      else
      {
        output.push_back(static_cast<char>(character));
      }
      break;
    }
  }
  output.push_back('"');
}

char const * DuckDBTypeName(duckdb_type type)
{
  switch (type)
  {
  case DUCKDB_TYPE_BOOLEAN:
    return "BOOLEAN";
  case DUCKDB_TYPE_TINYINT:
    return "TINYINT";
  case DUCKDB_TYPE_SMALLINT:
    return "SMALLINT";
  case DUCKDB_TYPE_INTEGER:
    return "INTEGER";
  case DUCKDB_TYPE_BIGINT:
    return "BIGINT";
  case DUCKDB_TYPE_UTINYINT:
    return "UTINYINT";
  case DUCKDB_TYPE_USMALLINT:
    return "USMALLINT";
  case DUCKDB_TYPE_UINTEGER:
    return "UINTEGER";
  case DUCKDB_TYPE_UBIGINT:
    return "UBIGINT";
  case DUCKDB_TYPE_FLOAT:
    return "FLOAT";
  case DUCKDB_TYPE_DOUBLE:
    return "DOUBLE";
  case DUCKDB_TYPE_TIMESTAMP:
    return "TIMESTAMP";
  case DUCKDB_TYPE_DATE:
    return "DATE";
  case DUCKDB_TYPE_TIME:
    return "TIME";
  case DUCKDB_TYPE_INTERVAL:
    return "INTERVAL";
  case DUCKDB_TYPE_HUGEINT:
    return "HUGEINT";
  case DUCKDB_TYPE_UHUGEINT:
    return "UHUGEINT";
  case DUCKDB_TYPE_VARCHAR:
    return "VARCHAR";
  case DUCKDB_TYPE_BLOB:
    return "BLOB";
  case DUCKDB_TYPE_DECIMAL:
    return "DECIMAL";
  case DUCKDB_TYPE_TIMESTAMP_S:
    return "TIMESTAMP_S";
  case DUCKDB_TYPE_TIMESTAMP_MS:
    return "TIMESTAMP_MS";
  case DUCKDB_TYPE_TIMESTAMP_NS:
    return "TIMESTAMP_NS";
  case DUCKDB_TYPE_ENUM:
    return "ENUM";
  case DUCKDB_TYPE_LIST:
    return "LIST";
  case DUCKDB_TYPE_STRUCT:
    return "STRUCT";
  case DUCKDB_TYPE_MAP:
    return "MAP";
  case DUCKDB_TYPE_ARRAY:
    return "ARRAY";
  case DUCKDB_TYPE_UUID:
    return "UUID";
  case DUCKDB_TYPE_UNION:
    return "UNION";
  case DUCKDB_TYPE_BIT:
    return "BIT";
  case DUCKDB_TYPE_TIME_TZ:
    return "TIME_TZ";
  case DUCKDB_TYPE_TIMESTAMP_TZ:
    return "TIMESTAMP_TZ";
  case DUCKDB_TYPE_GEOMETRY:
    return "GEOMETRY";
  case DUCKDB_TYPE_SQLNULL:
    return "SQLNULL";
  case DUCKDB_TYPE_STRING_LITERAL:
    return "STRING_LITERAL";
  case DUCKDB_TYPE_INTEGER_LITERAL:
    return "INTEGER_LITERAL";
  case DUCKDB_TYPE_TIME_NS:
    return "TIME_NS";
  case DUCKDB_TYPE_BIGNUM:
    return "BIGNUM";
  default:
    return "INVALID";
  }
}

std::string DuckDBValueVarchar(duckdb_result * result, idx_t columnIndex,
                               idx_t rowIndex)
{
  char * rawValue = duckdb_value_varchar(result, columnIndex, rowIndex);
  if (rawValue == nullptr)
    return {};

  std::string value(rawValue);
  duckdb_free(rawValue);
  return value;
}

char * CopyDuckDBCString(std::string const & value)
{
  auto * output = static_cast<char *>(std::malloc(value.size() + 1));
  if (output == nullptr)
    return nullptr;
  if (!value.empty())
    std::memcpy(output, value.data(), value.size());
  output[value.size()] = '\0';
  return output;
}

std::vector<DuckDBColumnInfo> ReadDuckDBColumnInfo(duckdb_result * result)
{
  std::vector<DuckDBColumnInfo> columns;
  idx_t const columnCount = duckdb_column_count(result);
  columns.reserve(static_cast<size_t>(columnCount));

  for (idx_t columnIndex = 0; columnIndex < columnCount; ++columnIndex)
  {
    char const * rawName = duckdb_column_name(result, columnIndex);
    duckdb_type const physicalType = duckdb_column_type(result, columnIndex);
    duckdb_type logicalTypeId = physicalType;
    std::string alias;

    duckdb_logical_type logicalType = duckdb_column_logical_type(result, columnIndex);
    if (logicalType != nullptr)
    {
      logicalTypeId = duckdb_get_type_id(logicalType);
      char * rawAlias = duckdb_logical_type_get_alias(logicalType);
      if (rawAlias != nullptr)
      {
        alias = rawAlias;
        duckdb_free(rawAlias);
      }
      duckdb_destroy_logical_type(&logicalType);
    }

    columns.push_back({
        rawName != nullptr ? rawName : "",
        physicalType,
        logicalTypeId,
        alias,
    });
  }

  return columns;
}

std::string DuckDBColumnDisplayType(DuckDBColumnInfo const & column)
{
  return column.alias.empty() ? DuckDBTypeName(column.logicalType) : column.alias;
}

bool IsDuckDBJsonColumn(DuckDBColumnInfo const & column)
{
  return ToLowerAscii(column.alias) == "json";
}

bool IsDuckDBGeometryColumn(DuckDBColumnInfo const & column)
{
  return column.type == DUCKDB_TYPE_GEOMETRY ||
         column.logicalType == DUCKDB_TYPE_GEOMETRY ||
         ToLowerAscii(column.alias) == "geometry";
}

bool IsDuckDBStringColumn(DuckDBColumnInfo const & column)
{
  return column.logicalType == DUCKDB_TYPE_VARCHAR ||
         column.logicalType == DUCKDB_TYPE_STRING_LITERAL;
}

bool IsDuckDBIntegerColumn(DuckDBColumnInfo const & column)
{
  switch (column.logicalType)
  {
  case DUCKDB_TYPE_TINYINT:
  case DUCKDB_TYPE_SMALLINT:
  case DUCKDB_TYPE_INTEGER:
  case DUCKDB_TYPE_BIGINT:
  case DUCKDB_TYPE_UTINYINT:
  case DUCKDB_TYPE_USMALLINT:
  case DUCKDB_TYPE_UINTEGER:
  case DUCKDB_TYPE_UBIGINT:
  case DUCKDB_TYPE_INTEGER_LITERAL:
    return true;
  default:
    return false;
  }
}

int FindDuckDBColumn(std::vector<DuckDBColumnInfo> const & columns,
                     char const * name)
{
  std::string const expectedName = ToLowerAscii(name);
  for (size_t columnIndex = 0; columnIndex < columns.size(); ++columnIndex)
  {
    if (ToLowerAscii(columns[columnIndex].name) == expectedName)
      return static_cast<int>(columnIndex);
  }
  return -1;
}

void AppendDuckDBJsonValue(duckdb_result * result, idx_t columnIndex,
                           idx_t rowIndex, DuckDBColumnInfo const & column,
                           std::string & output)
{
  if (duckdb_value_is_null(result, columnIndex, rowIndex))
  {
    output += "null";
    return;
  }

  switch (column.logicalType)
  {
  case DUCKDB_TYPE_BOOLEAN:
    output += duckdb_value_boolean(result, columnIndex, rowIndex) ? "true" : "false";
    return;
  case DUCKDB_TYPE_TINYINT:
  case DUCKDB_TYPE_SMALLINT:
  case DUCKDB_TYPE_INTEGER:
  case DUCKDB_TYPE_BIGINT:
  case DUCKDB_TYPE_INTEGER_LITERAL:
    output += std::to_string(duckdb_value_int64(result, columnIndex, rowIndex));
    return;
  case DUCKDB_TYPE_UTINYINT:
  case DUCKDB_TYPE_USMALLINT:
  case DUCKDB_TYPE_UINTEGER:
  case DUCKDB_TYPE_UBIGINT:
    output += std::to_string(duckdb_value_uint64(result, columnIndex, rowIndex));
    return;
  case DUCKDB_TYPE_FLOAT:
  case DUCKDB_TYPE_DOUBLE:
  {
    double const value = duckdb_value_double(result, columnIndex, rowIndex);
    if (!std::isfinite(value))
    {
      output += "null";
      return;
    }

    std::ostringstream number;
    number << std::setprecision(17) << value;
    output += number.str();
    return;
  }
  default:
    break;
  }

  std::string const value = DuckDBValueVarchar(result, columnIndex, rowIndex);
  if (IsDuckDBJsonColumn(column))
    output += value.empty() ? "null" : value;
  else
    AppendJsonString(output, value);
}

bool QueryDuckDBJsonLocked(std::string const & sql)
{
  if (g_duckdbConnection == nullptr)
  {
    SetDuckDBError("DuckDB connection is not open");
    g_lastDuckdbQueryJson.clear();
    return false;
  }

  duckdb_result result;
  if (duckdb_query(g_duckdbConnection, sql.c_str(), &result) != DuckDBSuccess)
  {
    char const * error = duckdb_result_error(&result);
    SetDuckDBError(error != nullptr ? error : "DuckDB query failed");
    duckdb_destroy_result(&result);
    g_lastDuckdbQueryJson.clear();
    return false;
  }

  auto const columns = ReadDuckDBColumnInfo(&result);
  idx_t const rowCount = duckdb_row_count(&result);

  std::string output;
  output.reserve(256 + static_cast<size_t>(rowCount) * columns.size() * 16);
  output += "{\"columns\":[";
  for (size_t columnIndex = 0; columnIndex < columns.size(); ++columnIndex)
  {
    if (columnIndex > 0)
      output.push_back(',');
    output += "{\"name\":";
    AppendJsonString(output, columns[columnIndex].name);
    output += ",\"type\":";
    AppendJsonString(output, DuckDBColumnDisplayType(columns[columnIndex]));
    output.push_back('}');
  }
  output += "],\"rows\":[";
  for (idx_t rowIndex = 0; rowIndex < rowCount; ++rowIndex)
  {
    if (rowIndex > 0)
      output.push_back(',');
    output.push_back('[');
    for (idx_t columnIndex = 0; columnIndex < columns.size(); ++columnIndex)
    {
      if (columnIndex > 0)
        output.push_back(',');
      AppendDuckDBJsonValue(&result, columnIndex, rowIndex,
                            columns[static_cast<size_t>(columnIndex)], output);
    }
    output.push_back(']');
  }
  output += "],\"row_count\":";
  output += std::to_string(rowCount);
  output.push_back('}');

  g_lastDuckdbQueryJson = std::move(output);
  duckdb_destroy_result(&result);
  ClearDuckDBError();
  return true;
}

bool ValidateRequiredDuckDBColumn(std::vector<DuckDBColumnInfo> const & columns,
                                  char const * name,
                                  bool (*predicate)(DuckDBColumnInfo const &),
                                  char const * expectedType)
{
  int const columnIndex = FindDuckDBColumn(columns, name);
  if (columnIndex < 0)
  {
    SetDuckDBError(std::string("Renderable query is missing required column: ") +
                   name);
    return false;
  }

  DuckDBColumnInfo const & column = columns[static_cast<size_t>(columnIndex)];
  if (!predicate(column))
  {
    SetDuckDBError(std::string("Renderable query column '") + name +
                   "' must be " + expectedType + ", found " +
                   DuckDBColumnDisplayType(column));
    return false;
  }

  return true;
}

bool ValidateOptionalDuckDBColumn(std::vector<DuckDBColumnInfo> const & columns,
                                  char const * name,
                                  bool (*predicate)(DuckDBColumnInfo const &),
                                  char const * expectedType)
{
  int const columnIndex = FindDuckDBColumn(columns, name);
  if (columnIndex < 0)
    return true;

  DuckDBColumnInfo const & column = columns[static_cast<size_t>(columnIndex)];
  if (!predicate(column))
  {
    SetDuckDBError(std::string("Renderable query column '") + name +
                   "' must be " + expectedType + ", found " +
                   DuckDBColumnDisplayType(column));
    return false;
  }

  return true;
}

bool ValidateRenderableDuckDBQueryLocked(std::string const & sql)
{
  if (g_duckdbConnection == nullptr)
  {
    SetDuckDBError("DuckDB connection is not open");
    return false;
  }

  std::string const trimmedSql = TrimDuckDBSqlForSubquery(sql);
  if (trimmedSql.empty())
  {
    SetDuckDBError("Renderable query SQL is empty");
    return false;
  }

  std::string validationSql = "SELECT * FROM (";
  validationSql += trimmedSql;
  validationSql += ") AS agus_render_query_validation LIMIT 0;";

  duckdb_result result;
  if (duckdb_query(g_duckdbConnection, validationSql.c_str(), &result) !=
      DuckDBSuccess)
  {
    char const * error = duckdb_result_error(&result);
    SetDuckDBError(error != nullptr ? error : "DuckDB render query validation failed");
    duckdb_destroy_result(&result);
    return false;
  }

  auto const columns = ReadDuckDBColumnInfo(&result);
  bool const valid =
      ValidateRequiredDuckDBColumn(columns, "feature_id", IsDuckDBStringColumn,
                                   "VARCHAR") &&
      ValidateRequiredDuckDBColumn(columns, "geometry", IsDuckDBGeometryColumn,
                                   "GEOMETRY") &&
      ValidateRequiredDuckDBColumn(columns, "properties", IsDuckDBJsonColumn,
                                   "JSON") &&
      ValidateOptionalDuckDBColumn(columns, "style", IsDuckDBJsonColumn,
                                   "JSON") &&
      ValidateOptionalDuckDBColumn(columns, "min_zoom", IsDuckDBIntegerColumn,
                                   "INTEGER") &&
      ValidateOptionalDuckDBColumn(columns, "max_zoom", IsDuckDBIntegerColumn,
                                   "INTEGER") &&
      ValidateOptionalDuckDBColumn(columns, "z_index", IsDuckDBIntegerColumn,
                                   "INTEGER");

  duckdb_destroy_result(&result);
  if (valid)
    ClearDuckDBError();
  return valid;
}

int32_t CopyRenderableDuckDBFeaturesLocked(double minLon, double minLat,
                                           double maxLon, double maxLat,
                                           int32_t zoom, int32_t limit,
                                           int32_t offset,
                                           AgusDuckDBRenderFeature ** outFeatures,
                                           int32_t * outCount)
{
  if (g_duckdbConnection == nullptr)
  {
    SetDuckDBError("DuckDB connection is not open");
    return 0;
  }

  if (limit <= 0)
  {
    SetDuckDBError("DuckDB render feature limit must be positive");
    return 0;
  }

  if (offset < 0)
  {
    SetDuckDBError("DuckDB render feature offset must be non-negative");
    return 0;
  }

  std::ostringstream query;
  query << "SELECT f.layer_id, f.feature_id, f.geometry_kind, "
        << "ST_AsText(f.geometry) AS geometry_wkt, "
        << "COALESCE(f.min_zoom, l.min_zoom, -1) AS min_zoom, "
        << "COALESCE(f.max_zoom, l.max_zoom, -1) AS max_zoom, "
        << "COALESCE(f.z_index, l.z_index, 0) AS z_index "
        << "FROM agus.layer_features f "
        << "JOIN agus.layers l ON l.layer_id = f.layer_id "
        << "WHERE l.visible = true "
        << "AND l.deleted_at IS NULL "
        << "AND f.deleted_at IS NULL "
        << "AND (COALESCE(f.min_zoom, l.min_zoom) IS NULL OR "
        << "COALESCE(f.min_zoom, l.min_zoom) <= " << zoom << ") "
        << "AND (COALESCE(f.max_zoom, l.max_zoom) IS NULL OR "
        << "COALESCE(f.max_zoom, l.max_zoom) >= " << zoom << ") "
        << "AND (f.bbox_min_lon IS NULL OR ("
        << "f.bbox_max_lon >= " << minLon << " AND "
        << "f.bbox_min_lon <= " << maxLon << " AND "
        << "f.bbox_max_lat >= " << minLat << " AND "
        << "f.bbox_min_lat <= " << maxLat << ")) "
        << "ORDER BY l.z_index ASC, f.z_index ASC NULLS LAST, f.feature_id ASC "
        << "LIMIT " << limit << " OFFSET " << offset << ";";

  duckdb_result result;
  if (duckdb_query(g_duckdbConnection, query.str().c_str(), &result) !=
      DuckDBSuccess)
  {
    char const * error = duckdb_result_error(&result);
    SetDuckDBError(error != nullptr ? error : "DuckDB render feature query failed");
    duckdb_destroy_result(&result);
    return 0;
  }

  idx_t const rowCount = duckdb_row_count(&result);
  if (rowCount > static_cast<idx_t>(std::numeric_limits<int32_t>::max()))
  {
    duckdb_destroy_result(&result);
    SetDuckDBError("DuckDB render feature query returned too many rows");
    return 0;
  }

  auto * features = static_cast<AgusDuckDBRenderFeature *>(
      std::calloc(static_cast<size_t>(rowCount), sizeof(AgusDuckDBRenderFeature)));
  if (rowCount > 0 && features == nullptr)
  {
    duckdb_destroy_result(&result);
    SetDuckDBError("Failed to allocate DuckDB render feature buffer");
    return 0;
  }

  for (idx_t rowIndex = 0; rowIndex < rowCount; ++rowIndex)
  {
    auto & feature = features[rowIndex];
    feature.layer_id = CopyDuckDBCString(DuckDBValueVarchar(&result, 0, rowIndex));
    feature.feature_id = CopyDuckDBCString(DuckDBValueVarchar(&result, 1, rowIndex));
    feature.geometry_kind = CopyDuckDBCString(DuckDBValueVarchar(&result, 2, rowIndex));
    feature.geometry_wkt = CopyDuckDBCString(DuckDBValueVarchar(&result, 3, rowIndex));
    feature.min_zoom = duckdb_value_int32(&result, 4, rowIndex);
    feature.max_zoom = duckdb_value_int32(&result, 5, rowIndex);
    feature.z_index = duckdb_value_int32(&result, 6, rowIndex);

    if (feature.layer_id == nullptr || feature.feature_id == nullptr ||
        feature.geometry_kind == nullptr || feature.geometry_wkt == nullptr)
    {
      duckdb_destroy_result(&result);
      agus_duckdb_free_render_features(features, static_cast<int32_t>(rowIndex + 1));
      SetDuckDBError("Failed to allocate DuckDB render feature strings");
      return 0;
    }
  }

  duckdb_destroy_result(&result);
  *outFeatures = features;
  *outCount = static_cast<int32_t>(rowCount);
  ClearDuckDBError();
  return 1;
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

FFI_PLUGIN_EXPORT const char * agus_duckdb_query_json(char const * sql)
{
  if (sql == nullptr || sql[0] == '\0')
  {
    std::lock_guard<std::mutex> lock(g_duckdbMutex);
    SetDuckDBError("SQL is empty");
    g_lastDuckdbQueryJson.clear();
    return nullptr;
  }

  std::lock_guard<std::mutex> lock(g_duckdbMutex);
  return QueryDuckDBJsonLocked(sql) ? g_lastDuckdbQueryJson.c_str() : nullptr;
}

FFI_PLUGIN_EXPORT int32_t agus_duckdb_validate_render_query(char const * sql)
{
  if (sql == nullptr || sql[0] == '\0')
  {
    std::lock_guard<std::mutex> lock(g_duckdbMutex);
    SetDuckDBError("Renderable query SQL is empty");
    return 0;
  }

  std::lock_guard<std::mutex> lock(g_duckdbMutex);
  return ValidateRenderableDuckDBQueryLocked(sql) ? 1 : 0;
}

FFI_PLUGIN_EXPORT int32_t agus_duckdb_copy_render_features(
    double min_lon, double min_lat, double max_lon, double max_lat, int32_t zoom,
    AgusDuckDBRenderFeature ** out_features, int32_t * out_count)
{
  return agus_duckdb_copy_render_features_page(
      min_lon, min_lat, max_lon, max_lat, zoom, 5000, 0, out_features,
      out_count);
}

FFI_PLUGIN_EXPORT int32_t agus_duckdb_copy_render_features_page(
    double min_lon, double min_lat, double max_lon, double max_lat, int32_t zoom,
    int32_t limit, int32_t offset, AgusDuckDBRenderFeature ** out_features,
    int32_t * out_count)
{
  if (out_features == nullptr || out_count == nullptr)
  {
    std::lock_guard<std::mutex> lock(g_duckdbMutex);
    SetDuckDBError("DuckDB render feature output pointer is null");
    return 0;
  }

  *out_features = nullptr;
  *out_count = 0;

  std::lock_guard<std::mutex> lock(g_duckdbMutex);
  return CopyRenderableDuckDBFeaturesLocked(min_lon, min_lat, max_lon, max_lat,
                                            zoom, limit, offset, out_features,
                                            out_count);
}

FFI_PLUGIN_EXPORT void agus_duckdb_free_render_features(
    AgusDuckDBRenderFeature * features, int32_t count)
{
  if (features == nullptr || count <= 0)
  {
    std::free(features);
    return;
  }

  for (int32_t index = 0; index < count; ++index)
  {
    std::free(features[index].layer_id);
    std::free(features[index].feature_id);
    std::free(features[index].geometry_kind);
    std::free(features[index].geometry_wkt);
  }
  std::free(features);
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
