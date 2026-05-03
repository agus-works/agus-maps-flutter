CREATE SCHEMA IF NOT EXISTS agus;

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
