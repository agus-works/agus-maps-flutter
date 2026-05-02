# DuckDB extensions required by agus_maps_flutter.
#
# This file is passed to DuckDB through DUCKDB_EXTENSION_CONFIGS. Keep it
# explicit even for extensions that DuckDB loads by default so release builds can
# audit the exact feature surface shipped in the plugin.

duckdb_extension_load(core_functions)
duckdb_extension_load(parquet)
duckdb_extension_load(json)
duckdb_extension_load(icu)
duckdb_extension_load(httpfs
  GIT_URL https://github.com/duckdb/duckdb-httpfs
  GIT_TAG 13e18b3c9f3810334f5972b76a3acc247b28e537
)

if(NOT DEFINED AGUS_DUCKDB_SPATIAL_SOURCE_DIR)
  message(FATAL_ERROR "AGUS_DUCKDB_SPATIAL_SOURCE_DIR must point to thirdparty/duckdb-spatial")
endif()

duckdb_extension_load(spatial
  SOURCE_DIR "${AGUS_DUCKDB_SPATIAL_SOURCE_DIR}"
  INCLUDE_DIR "${AGUS_DUCKDB_SPATIAL_SOURCE_DIR}/src/spatial"
)
