-- agus_migration_description: Add search cache, focus centers, and keymap persistence tables

-- Search result cache table
-- Stores normalized search query results with map data revision tracking
CREATE TABLE IF NOT EXISTS agus.search_result_cache (
  cache_id VARCHAR PRIMARY KEY,
  normalized_query VARCHAR NOT NULL,
  locale VARCHAR NOT NULL,
  map_data_revision VARCHAR,
  map_data_fingerprint VARCHAR,
  result_payload JSON NOT NULL,
  result_count INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMP NOT NULL DEFAULT current_timestamp,
  updated_at TIMESTAMP NOT NULL DEFAULT current_timestamp,
  accessed_at TIMESTAMP NOT NULL DEFAULT current_timestamp,
  is_stale BOOLEAN NOT NULL DEFAULT false,
  invalidation_reason VARCHAR
);

CREATE INDEX IF NOT EXISTS idx_search_cache_query_locale
  ON agus.search_result_cache(normalized_query, locale);

CREATE INDEX IF NOT EXISTS idx_search_cache_stale
  ON agus.search_result_cache(is_stale);

CREATE INDEX IF NOT EXISTS idx_search_cache_accessed
  ON agus.search_result_cache(accessed_at);

-- Layer focus/center persistence using nullable columns
-- Supports async calculation with null indicating "not yet calculated"
ALTER TABLE agus.layers
ADD COLUMN IF NOT EXISTS focus_center_lon DOUBLE;

ALTER TABLE agus.layers
ADD COLUMN IF NOT EXISTS focus_center_lat DOUBLE;

ALTER TABLE agus.layers
ADD COLUMN IF NOT EXISTS focus_center_calculated_at TIMESTAMP;

-- Feature focus/center persistence using nullable columns
ALTER TABLE agus.layer_features
ADD COLUMN IF NOT EXISTS focus_center_lon DOUBLE;

ALTER TABLE agus.layer_features
ADD COLUMN IF NOT EXISTS focus_center_lat DOUBLE;

ALTER TABLE agus.layer_features
ADD COLUMN IF NOT EXISTS focus_center_calculated_at TIMESTAMP;

-- Keymap settings persistence table
-- Stores platform/command/keybinding payloads with validation metadata
CREATE TABLE IF NOT EXISTS agus.keymap_settings (
  setting_id VARCHAR PRIMARY KEY,
  platform VARCHAR NOT NULL,
  command VARCHAR NOT NULL,
  keybinding_payload JSON NOT NULL,
  is_override BOOLEAN NOT NULL DEFAULT false,
  display_name VARCHAR,
  description VARCHAR,
  validation_schema_version INTEGER NOT NULL DEFAULT 1,
  created_at TIMESTAMP NOT NULL DEFAULT current_timestamp,
  updated_at TIMESTAMP NOT NULL DEFAULT current_timestamp
);

CREATE INDEX IF NOT EXISTS idx_keymap_platform_command
  ON agus.keymap_settings(platform, command);

CREATE INDEX IF NOT EXISTS idx_keymap_is_override
  ON agus.keymap_settings(is_override);

-- Alternative: Typed app_metadata entries for keymap settings
-- This approach uses the existing app_metadata table with a convention
-- Key format: "keymap:{platform}:{command}"
-- Value is JSON with keybinding_payload, is_override, and metadata
-- No new table needed, but we document the schema convention here
