DROP TABLE IF EXISTS agus.layer_features_without_fk;
CREATE TABLE agus.layer_features_without_fk (
  layer_id VARCHAR NOT NULL,
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
INSERT INTO agus.layer_features_without_fk
SELECT * FROM agus.layer_features;
DROP TABLE agus.layer_features;
ALTER TABLE agus.layer_features_without_fk RENAME TO layer_features;

DROP TABLE IF EXISTS agus.query_layers_without_fk;
CREATE TABLE agus.query_layers_without_fk (
  layer_id VARCHAR PRIMARY KEY,
  sql_text VARCHAR NOT NULL,
  is_preset BOOLEAN NOT NULL DEFAULT false,
  required_extensions JSON NOT NULL,
  result_contract_version INTEGER NOT NULL DEFAULT 1,
  last_validated_at TIMESTAMP,
  last_error VARCHAR
);
INSERT INTO agus.query_layers_without_fk
SELECT * FROM agus.query_layers;
DROP TABLE agus.query_layers;
ALTER TABLE agus.query_layers_without_fk RENAME TO query_layers;

DROP TABLE IF EXISTS agus.layer_metadata_without_fk;
CREATE TABLE agus.layer_metadata_without_fk (
  layer_id VARCHAR NOT NULL,
  key VARCHAR NOT NULL,
  value VARCHAR NOT NULL,
  value_type VARCHAR NOT NULL DEFAULT 'string',
  updated_at TIMESTAMP NOT NULL DEFAULT current_timestamp,
  PRIMARY KEY (layer_id, key)
);
INSERT INTO agus.layer_metadata_without_fk
SELECT * FROM agus.layer_metadata;
DROP TABLE agus.layer_metadata;
ALTER TABLE agus.layer_metadata_without_fk RENAME TO layer_metadata;

DROP TABLE IF EXISTS agus.layer_render_cache_without_fk;
CREATE TABLE agus.layer_render_cache_without_fk (
  layer_id VARCHAR NOT NULL,
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
INSERT INTO agus.layer_render_cache_without_fk
SELECT * FROM agus.layer_render_cache;
DROP TABLE agus.layer_render_cache;
ALTER TABLE agus.layer_render_cache_without_fk RENAME TO layer_render_cache;

CREATE INDEX IF NOT EXISTS idx_agus_features_layer
  ON agus.layer_features(layer_id);
CREATE INDEX IF NOT EXISTS idx_agus_features_bbox
  ON agus.layer_features(bbox_min_lon, bbox_min_lat, bbox_max_lon, bbox_max_lat);
CREATE INDEX IF NOT EXISTS idx_agus_features_deleted
  ON agus.layer_features(deleted_at);
