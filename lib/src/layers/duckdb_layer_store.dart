part of '../../agus_maps_flutter.dart';

/// Layer kinds stored in `agus.layers.kind`.
enum AgusLayerKind {
  /// Metadata for a native CoMaps MWM layer.
  nativeMwm('native_mwm'),

  /// First-party user drawing layer.
  userDraw('user_draw'),

  /// Project-supported preset or known data-source layer.
  comapsSupported('comaps_supported'),

  /// Custom or preset SQL query layer.
  duckdbQuery('duckdb_query');

  const AgusLayerKind(this.databaseValue);

  /// Value stored in DuckDB.
  final String databaseValue;

  /// Parses a DuckDB layer kind value.
  static AgusLayerKind fromDatabaseValue(String value) {
    return AgusLayerKind.values.firstWhere(
      (kind) => kind.databaseValue == value,
      orElse: () => throw ArgumentError.value(value, 'value'),
    );
  }
}

/// Geometry kinds stored in `agus.layer_features.geometry_kind`.
enum AgusGeometryKind {
  /// Point geometry.
  point('point'),

  /// Line geometry.
  line('line'),

  /// Two-point segment geometry.
  segment('segment'),

  /// Polygon geometry.
  polygon('polygon'),

  /// Multi-point geometry.
  multipoint('multipoint'),

  /// Multi-line geometry.
  multiline('multiline'),

  /// Multi-polygon geometry.
  multipolygon('multipolygon'),

  /// Heterogeneous geometry collection.
  collection('collection');

  const AgusGeometryKind(this.databaseValue);

  /// Value stored in DuckDB.
  final String databaseValue;

  /// Parses a DuckDB geometry kind value.
  static AgusGeometryKind fromDatabaseValue(String value) {
    return AgusGeometryKind.values.firstWhere(
      (kind) => kind.databaseValue == value,
      orElse: () => throw ArgumentError.value(value, 'value'),
    );
  }
}

/// WGS84 bounding box stored with a feature for viewport filtering.
class AgusBoundingBox {
  /// Creates a WGS84 bounding box.
  const AgusBoundingBox({
    required this.minLon,
    required this.minLat,
    required this.maxLon,
    required this.maxLat,
  });

  /// Western longitude.
  final double minLon;

  /// Southern latitude.
  final double minLat;

  /// Eastern longitude.
  final double maxLon;

  /// Northern latitude.
  final double maxLat;
}

/// Layer row stored in `agus.layers`.
class AgusLayer {
  /// Creates a layer snapshot.
  const AgusLayer({
    required this.layerId,
    required this.name,
    required this.kind,
    required this.visible,
    required this.locked,
    required this.zIndex,
    required this.minZoom,
    required this.maxZoom,
    required this.style,
    required this.metadata,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
  });

  /// Stable layer identifier.
  final String layerId;

  /// Human-readable layer name.
  final String name;

  /// Layer category.
  final AgusLayerKind kind;

  /// Whether the layer should render.
  final bool visible;

  /// Whether editing is disabled.
  final bool locked;

  /// Global layer draw order.
  final int zIndex;

  /// Optional lower zoom bound.
  final int? minZoom;

  /// Optional upper zoom bound.
  final int? maxZoom;

  /// Layer style JSON.
  final Map<String, Object?>? style;

  /// Layer metadata JSON.
  final Map<String, Object?>? metadata;

  /// Creation timestamp reported by DuckDB.
  final DateTime? createdAt;

  /// Last update timestamp reported by DuckDB.
  final DateTime? updatedAt;

  /// Soft-delete timestamp when present.
  final DateTime? deletedAt;
}

/// Mutable inputs for creating or updating a layer.
class AgusLayerDraft {
  /// Creates layer upsert input.
  const AgusLayerDraft({
    required this.layerId,
    required this.name,
    required this.kind,
    this.visible = true,
    this.locked = false,
    this.zIndex = 0,
    this.minZoom,
    this.maxZoom,
    this.style,
    this.metadata,
  });

  /// Stable layer identifier.
  final String layerId;

  /// Human-readable layer name.
  final String name;

  /// Layer category.
  final AgusLayerKind kind;

  /// Whether the layer should render.
  final bool visible;

  /// Whether editing is disabled.
  final bool locked;

  /// Global layer draw order.
  final int zIndex;

  /// Optional lower zoom bound.
  final int? minZoom;

  /// Optional upper zoom bound.
  final int? maxZoom;

  /// Layer style JSON.
  final Map<String, Object?>? style;

  /// Layer metadata JSON.
  final Map<String, Object?>? metadata;
}

/// Feature row stored in `agus.layer_features`.
class AgusLayerFeature {
  /// Creates a feature snapshot.
  const AgusLayerFeature({
    required this.layerId,
    required this.featureId,
    required this.geometryWkt,
    required this.geometryKind,
    required this.properties,
    required this.style,
    required this.boundingBox,
    required this.zIndex,
    required this.minZoom,
    required this.maxZoom,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
  });

  /// Owning layer identifier.
  final String layerId;

  /// Stable feature identifier within the layer.
  final String featureId;

  /// WKT geometry representation in WGS84 coordinates.
  final String geometryWkt;

  /// Feature geometry category.
  final AgusGeometryKind geometryKind;

  /// Feature display/query properties.
  final Map<String, Object?> properties;

  /// Optional per-feature style override.
  final Map<String, Object?>? style;

  /// Optional WGS84 bounding box.
  final AgusBoundingBox? boundingBox;

  /// Optional per-feature draw order.
  final int? zIndex;

  /// Optional lower zoom bound.
  final int? minZoom;

  /// Optional upper zoom bound.
  final int? maxZoom;

  /// Creation timestamp reported by DuckDB.
  final DateTime? createdAt;

  /// Last update timestamp reported by DuckDB.
  final DateTime? updatedAt;

  /// Soft-delete timestamp when present.
  final DateTime? deletedAt;
}

/// Mutable inputs for creating or updating a feature.
class AgusLayerFeatureDraft {
  /// Creates feature upsert input.
  const AgusLayerFeatureDraft({
    required this.layerId,
    required this.featureId,
    required this.geometryWkt,
    required this.geometryKind,
    this.properties = const <String, Object?>{},
    this.style,
    this.boundingBox,
    this.zIndex,
    this.minZoom,
    this.maxZoom,
  });

  /// Owning layer identifier.
  final String layerId;

  /// Stable feature identifier within the layer.
  final String featureId;

  /// WKT geometry representation in WGS84 coordinates.
  final String geometryWkt;

  /// Feature geometry category.
  final AgusGeometryKind geometryKind;

  /// Feature display/query properties.
  final Map<String, Object?> properties;

  /// Optional per-feature style override.
  final Map<String, Object?>? style;

  /// Optional WGS84 bounding box.
  final AgusBoundingBox? boundingBox;

  /// Optional per-feature draw order.
  final int? zIndex;

  /// Optional lower zoom bound.
  final int? minZoom;

  /// Optional upper zoom bound.
  final int? maxZoom;
}

/// Query-layer row stored in `agus.query_layers`.
class AgusQueryLayer {
  /// Creates a query-layer snapshot.
  const AgusQueryLayer({
    required this.layerId,
    required this.sqlText,
    required this.isPreset,
    required this.requiredExtensions,
    required this.resultContractVersion,
    required this.lastValidatedAt,
    required this.lastError,
  });

  /// Owning layer identifier.
  final String layerId;

  /// SQL text used as the layer data source.
  final String sqlText;

  /// Whether this query is project-provided rather than user-authored.
  final bool isPreset;

  /// Required DuckDB extensions for this query.
  final List<String> requiredExtensions;

  /// Render contract version expected by native rendering.
  final int resultContractVersion;

  /// Last validation timestamp when present.
  final DateTime? lastValidatedAt;

  /// Last validation error when present.
  final String? lastError;
}

/// Mutable inputs for creating or updating a query layer.
class AgusQueryLayerDraft {
  /// Creates query-layer upsert input.
  const AgusQueryLayerDraft({
    required this.layer,
    required this.sqlText,
    this.isPreset = false,
    this.requiredExtensions = const <String>[],
    this.resultContractVersion = 1,
  });

  /// Base layer metadata. Its kind is forced to [AgusLayerKind.duckdbQuery].
  final AgusLayerDraft layer;

  /// SQL text used as the layer data source.
  final String sqlText;

  /// Whether this query is project-provided rather than user-authored.
  final bool isPreset;

  /// Required DuckDB extensions for this query.
  final List<String> requiredExtensions;

  /// Render contract version expected by native rendering.
  final int resultContractVersion;
}

/// Key/value metadata row stored in `agus.layer_metadata`.
class AgusLayerMetadataEntry {
  /// Creates a layer metadata entry.
  const AgusLayerMetadataEntry({
    required this.layerId,
    required this.key,
    required this.value,
    required this.valueType,
    required this.updatedAt,
  });

  /// Owning layer identifier.
  final String layerId;

  /// Metadata key.
  final String key;

  /// Metadata value stored as text.
  final String value;

  /// Caller-defined value type, such as `string`, `number`, or `url`.
  final String valueType;

  /// Last update timestamp reported by DuckDB.
  final DateTime? updatedAt;
}

/// Search result cache entry stored in `agus.search_result_cache`.
class AgusSearchCacheEntry {
  /// Creates a search cache entry snapshot.
  const AgusSearchCacheEntry({
    required this.cacheId,
    required this.normalizedQuery,
    required this.locale,
    required this.mapDataRevision,
    required this.mapDataFingerprint,
    required this.resultPayload,
    required this.resultCount,
    required this.createdAt,
    required this.updatedAt,
    required this.accessedAt,
    required this.isStale,
    required this.invalidationReason,
  });

  /// Cache entry identifier.
  final String cacheId;

  /// Normalized search query.
  final String normalizedQuery;

  /// Query locale.
  final String locale;

  /// Map data revision or version identifier.
  final String? mapDataRevision;

  /// Map data fingerprint or checksum.
  final String? mapDataFingerprint;

  /// Search result payload as JSON.
  final Map<String, Object?> resultPayload;

  /// Number of results in the payload.
  final int resultCount;

  /// Creation timestamp.
  final DateTime? createdAt;

  /// Last update timestamp.
  final DateTime? updatedAt;

  /// Last access timestamp.
  final DateTime? accessedAt;

  /// Whether the cache entry is stale/invalidated.
  final bool isStale;

  /// Reason for invalidation when stale.
  final String? invalidationReason;
}

/// Mutable inputs for creating or updating a search cache entry.
class AgusSearchCacheDraft {
  /// Creates search cache upsert input.
  const AgusSearchCacheDraft({
    required this.cacheId,
    required this.normalizedQuery,
    required this.locale,
    this.mapDataRevision,
    this.mapDataFingerprint,
    required this.resultPayload,
    required this.resultCount,
    this.isStale = false,
    this.invalidationReason,
  });

  /// Cache entry identifier.
  final String cacheId;

  /// Normalized search query.
  final String normalizedQuery;

  /// Query locale.
  final String locale;

  /// Map data revision or version identifier.
  final String? mapDataRevision;

  /// Map data fingerprint or checksum.
  final String? mapDataFingerprint;

  /// Search result payload as JSON.
  final Map<String, Object?> resultPayload;

  /// Number of results in the payload.
  final int resultCount;

  /// Whether the cache entry is stale/invalidated.
  final bool isStale;

  /// Reason for invalidation when stale.
  final String? invalidationReason;
}

/// Focus center for a layer or feature.
class AgusFocusCenter {
  /// Creates a focus center.
  const AgusFocusCenter({
    required this.longitude,
    required this.latitude,
    required this.calculatedAt,
  });

  /// Center longitude in WGS84.
  final double longitude;

  /// Center latitude in WGS84.
  final double latitude;

  /// Timestamp when the center was calculated.
  final DateTime? calculatedAt;
}

/// Keymap setting stored in `agus.keymap_settings`.
class AgusKeymapSetting {
  /// Creates a keymap setting snapshot.
  const AgusKeymapSetting({
    required this.settingId,
    required this.platform,
    required this.command,
    required this.keybindingPayload,
    required this.isOverride,
    required this.displayName,
    required this.description,
    required this.validationSchemaVersion,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Setting identifier.
  final String settingId;

  /// Platform (e.g., 'macos', 'windows', 'linux', 'android', 'ios').
  final String platform;

  /// Command identifier.
  final String command;

  /// Keybinding payload as JSON.
  final Map<String, Object?> keybindingPayload;

  /// Whether this is a user override.
  final bool isOverride;

  /// Human-readable display name.
  final String? displayName;

  /// Setting description.
  final String? description;

  /// Validation schema version.
  final int validationSchemaVersion;

  /// Creation timestamp.
  final DateTime? createdAt;

  /// Last update timestamp.
  final DateTime? updatedAt;
}

/// Mutable inputs for creating or updating a keymap setting.
class AgusKeymapSettingDraft {
  /// Creates keymap setting upsert input.
  const AgusKeymapSettingDraft({
    required this.settingId,
    required this.platform,
    required this.command,
    required this.keybindingPayload,
    this.isOverride = false,
    this.displayName,
    this.description,
    this.validationSchemaVersion = 1,
  });

  /// Setting identifier.
  final String settingId;

  /// Platform (e.g., 'macos', 'windows', 'linux', 'android', 'ios').
  final String platform;

  /// Command identifier.
  final String command;

  /// Keybinding payload as JSON.
  final Map<String, Object?> keybindingPayload;

  /// Whether this is a user override.
  final bool isOverride;

  /// Human-readable display name.
  final String? displayName;

  /// Setting description.
  final String? description;

  /// Validation schema version.
  final int validationSchemaVersion;
}

/// High-level DuckDB-backed layer persistence API.
class DuckDBLayerStore {
  /// Creates a store rooted at the app writable/support directory.
  const DuckDBLayerStore({required this.writablePath});

  /// App writable/support directory passed to [openDuckDBAppDatabase].
  final String writablePath;

  /// Full path to the app-instance DuckDB database file.
  String get databasePath => p.join(writablePath, 'agus_layers.duckdb');

  /// Opens the app database, loads extensions, and runs migrations.
  void open() {
    final openError = _openDuckDBAppDatabaseWithWalRecovery(
      writablePath: writablePath,
      databasePath: databasePath,
    );
    if (openError != null) throw StateError(openError);
    _repairLayerForeignKeyLimitations();
    _executeChecked('CHECKPOINT;');
  }

  /// Inserts or updates a layer row.
  void upsertLayer(AgusLayerDraft layer) {
    _executeChecked('BEGIN TRANSACTION;\n${_upsertLayerSql(layer)}\nCOMMIT;');
  }

  /// Returns non-deleted layers by default, ordered for UI/rendering.
  List<AgusLayer> listLayers({bool includeDeleted = false}) {
    final result = queryDuckDB('''
SELECT
  layer_id,
  name,
  kind,
  visible,
  locked,
  z_index,
  min_zoom,
  max_zoom,
  style,
  metadata,
  created_at,
  updated_at,
  deleted_at
FROM agus.layers
${includeDeleted ? '' : 'WHERE deleted_at IS NULL'}
ORDER BY z_index ASC, name ASC;
''');
    return _rowsByName(result).map(_layerFromRow).toList(growable: false);
  }

  /// Soft-deletes a layer and its features.
  void deleteLayer(String layerId) {
    final layerIdSql = _sqlString(layerId);
    _executeChecked('''
BEGIN TRANSACTION;
UPDATE agus.layers
SET deleted_at = current_localtimestamp(), updated_at = current_localtimestamp()
WHERE layer_id = $layerIdSql;
UPDATE agus.layer_features
SET deleted_at = current_localtimestamp(), updated_at = current_localtimestamp()
WHERE layer_id = $layerIdSql;
COMMIT;
''');
  }

  /// Changes layer visibility.
  void setLayerVisibility(String layerId, bool visible) {
    _executeChecked('''
UPDATE agus.layers
SET visible = ${_sqlBool(visible)}, updated_at = current_localtimestamp()
WHERE layer_id = ${_sqlString(layerId)};
''');
  }

  /// Changes layer z-order.
  void setLayerZIndex(String layerId, int zIndex) {
    _executeChecked('''
UPDATE agus.layers
SET z_index = $zIndex, updated_at = current_localtimestamp()
WHERE layer_id = ${_sqlString(layerId)};
''');
  }

  /// Inserts or updates a feature row.
  void upsertFeature(AgusLayerFeatureDraft feature) {
    _executeChecked(
        'BEGIN TRANSACTION;\n${_upsertFeatureSql(feature)}\nCOMMIT;');
  }

  /// Returns non-deleted features for [layerId] by default.
  List<AgusLayerFeature> listFeatures(
    String layerId, {
    bool includeDeleted = false,
  }) {
    final result = queryDuckDB('''
SELECT
  layer_id,
  feature_id,
  ST_AsText(geometry) AS geometry_wkt,
  geometry_kind,
  properties,
  style,
  bbox_min_lon,
  bbox_min_lat,
  bbox_max_lon,
  bbox_max_lat,
  z_index,
  min_zoom,
  max_zoom,
  created_at,
  updated_at,
  deleted_at
FROM agus.layer_features
WHERE layer_id = ${_sqlString(layerId)}
${includeDeleted ? '' : 'AND deleted_at IS NULL'}
ORDER BY z_index ASC NULLS LAST, feature_id ASC;
''');
    return _rowsByName(result).map(_featureFromRow).toList(growable: false);
  }

  /// Soft-deletes a feature.
  void deleteFeature(String layerId, String featureId) {
    _executeChecked('''
UPDATE agus.layer_features
SET deleted_at = current_localtimestamp(), updated_at = current_localtimestamp()
WHERE layer_id = ${_sqlString(layerId)}
  AND feature_id = ${_sqlString(featureId)};
''');
  }

  /// Inserts or updates a query layer and optionally validates its SQL contract.
  void upsertQueryLayer(
    AgusQueryLayerDraft queryLayer, {
    bool validate = true,
  }) {
    String? validationError;
    if (validate && !validateRenderableDuckDBQuery(queryLayer.sqlText)) {
      validationError = duckDBLastError();
      throw StateError('Renderable query validation failed: $validationError');
    }

    final layer = queryLayer.layer;
    final baseLayer = AgusLayerDraft(
      layerId: layer.layerId,
      name: layer.name,
      kind: AgusLayerKind.duckdbQuery,
      visible: layer.visible,
      locked: layer.locked,
      zIndex: layer.zIndex,
      minZoom: layer.minZoom,
      maxZoom: layer.maxZoom,
      style: layer.style,
      metadata: layer.metadata,
    );

    _executeChecked('''
BEGIN TRANSACTION;
${_upsertLayerSql(baseLayer)}
INSERT INTO agus.query_layers(
  layer_id,
  sql_text,
  is_preset,
  required_extensions,
  result_contract_version,
  last_validated_at,
  last_error
) VALUES (
  ${_sqlString(layer.layerId)},
  ${_sqlString(queryLayer.sqlText)},
  ${_sqlBool(queryLayer.isPreset)},
  ${_sqlJson(queryLayer.requiredExtensions)},
  ${queryLayer.resultContractVersion},
  ${validate ? 'current_localtimestamp()' : 'NULL'},
  ${_sqlNullableString(validationError)}
)
ON CONFLICT(layer_id) DO UPDATE SET
  sql_text = excluded.sql_text,
  is_preset = excluded.is_preset,
  required_extensions = excluded.required_extensions,
  result_contract_version = excluded.result_contract_version,
  last_validated_at = excluded.last_validated_at,
  last_error = excluded.last_error;
COMMIT;
''');
  }

  /// Returns a query-layer row by [layerId], or `null` when absent.
  AgusQueryLayer? getQueryLayer(String layerId) {
    final result = queryDuckDB('''
SELECT
  layer_id,
  sql_text,
  is_preset,
  required_extensions,
  result_contract_version,
  last_validated_at,
  last_error
FROM agus.query_layers
WHERE layer_id = ${_sqlString(layerId)};
''');
    final rows = _rowsByName(result);
    if (rows.isEmpty) return null;
    return _queryLayerFromRow(rows.first);
  }

  /// Inserts or updates a layer metadata entry.
  void setMetadata({
    required String layerId,
    required String key,
    required String value,
    String valueType = 'string',
  }) {
    _executeChecked('''
INSERT INTO agus.layer_metadata(layer_id, key, value, value_type)
VALUES (
  ${_sqlString(layerId)},
  ${_sqlString(key)},
  ${_sqlString(value)},
  ${_sqlString(valueType)}
)
ON CONFLICT(layer_id, key) DO UPDATE SET
  value = excluded.value,
  value_type = excluded.value_type,
  updated_at = current_localtimestamp();
''');
  }

  /// Returns metadata entries for [layerId].
  List<AgusLayerMetadataEntry> listMetadata(String layerId) {
    final result = queryDuckDB('''
SELECT layer_id, key, value, value_type, updated_at
FROM agus.layer_metadata
WHERE layer_id = ${_sqlString(layerId)}
ORDER BY key ASC;
''');
    return _rowsByName(result).map(_metadataFromRow).toList(growable: false);
  }

  /// Deletes a layer metadata entry.
  void deleteMetadata(String layerId, String key) {
    _executeChecked('''
DELETE FROM agus.layer_metadata
WHERE layer_id = ${_sqlString(layerId)} AND key = ${_sqlString(key)};
''');
  }

  /// Inserts or updates a search cache entry.
  void upsertSearchCache(AgusSearchCacheDraft entry) {
    _executeChecked('''
INSERT INTO agus.search_result_cache(
  cache_id,
  normalized_query,
  locale,
  map_data_revision,
  map_data_fingerprint,
  result_payload,
  result_count,
  is_stale,
  invalidation_reason
) VALUES (
  ${_sqlString(entry.cacheId)},
  ${_sqlString(entry.normalizedQuery)},
  ${_sqlString(entry.locale)},
  ${_sqlNullableString(entry.mapDataRevision)},
  ${_sqlNullableString(entry.mapDataFingerprint)},
  ${_sqlJson(entry.resultPayload)},
  ${entry.resultCount},
  ${_sqlBool(entry.isStale)},
  ${_sqlNullableString(entry.invalidationReason)}
)
ON CONFLICT(cache_id) DO UPDATE SET
  normalized_query = excluded.normalized_query,
  locale = excluded.locale,
  map_data_revision = excluded.map_data_revision,
  map_data_fingerprint = excluded.map_data_fingerprint,
  result_payload = excluded.result_payload,
  result_count = excluded.result_count,
  updated_at = current_localtimestamp(),
  accessed_at = current_localtimestamp(),
  is_stale = excluded.is_stale,
  invalidation_reason = excluded.invalidation_reason;
''');
  }

  /// Returns a search cache entry by [cacheId], or `null` when absent.
  AgusSearchCacheEntry? getSearchCache(String cacheId) {
    final result = queryDuckDB('''
SELECT
  cache_id,
  normalized_query,
  locale,
  map_data_revision,
  map_data_fingerprint,
  result_payload,
  result_count,
  created_at,
  updated_at,
  accessed_at,
  is_stale,
  invalidation_reason
FROM agus.search_result_cache
WHERE cache_id = ${_sqlString(cacheId)};
''');
    final rows = _rowsByName(result);
    if (rows.isEmpty) return null;

    _executeChecked('''
UPDATE agus.search_result_cache
SET accessed_at = current_localtimestamp()
WHERE cache_id = ${_sqlString(cacheId)};
''');

    return _searchCacheFromRow(rows.first);
  }

  /// Searches for cached entries by normalized query and locale.
  List<AgusSearchCacheEntry> searchCache({
    required String normalizedQuery,
    required String locale,
    bool includeStale = false,
  }) {
    final result = queryDuckDB('''
SELECT
  cache_id,
  normalized_query,
  locale,
  map_data_revision,
  map_data_fingerprint,
  result_payload,
  result_count,
  created_at,
  updated_at,
  accessed_at,
  is_stale,
  invalidation_reason
FROM agus.search_result_cache
WHERE normalized_query = ${_sqlString(normalizedQuery)}
  AND locale = ${_sqlString(locale)}
  ${includeStale ? '' : 'AND is_stale = false'}
ORDER BY accessed_at DESC;
''');
    return _rowsByName(result).map(_searchCacheFromRow).toList(growable: false);
  }

  /// Invalidates search cache entries by map data revision.
  void invalidateSearchCacheByRevision(String mapDataRevision) {
    _executeChecked('''
UPDATE agus.search_result_cache
SET
  is_stale = true,
  invalidation_reason = 'map_data_revision_changed',
  updated_at = current_localtimestamp()
WHERE map_data_revision = ${_sqlString(mapDataRevision)}
  AND is_stale = false;
''');
  }

  /// Invalidates all search cache entries.
  void invalidateAllSearchCache({String? reason}) {
    _executeChecked('''
UPDATE agus.search_result_cache
SET
  is_stale = true,
  invalidation_reason = ${_sqlNullableString(reason ?? 'global_invalidation')},
  updated_at = current_localtimestamp()
WHERE is_stale = false;
''');
  }

  /// Deletes a search cache entry.
  void deleteSearchCache(String cacheId) {
    _executeChecked('''
DELETE FROM agus.search_result_cache
WHERE cache_id = ${_sqlString(cacheId)};
''');
  }

  /// Returns the focus center for a layer, or `null` when absent or not calculated.
  AgusFocusCenter? getLayerFocusCenter(String layerId) {
    final result = queryDuckDB('''
SELECT
  focus_center_lon,
  focus_center_lat,
  focus_center_calculated_at
FROM agus.layers
WHERE layer_id = ${_sqlString(layerId)};
''');
    final rows = _rowsByName(result);
    if (rows.isEmpty) return null;

    final row = rows.first;
    final lon = _asDouble(row['focus_center_lon']);
    final lat = _asDouble(row['focus_center_lat']);
    final calculatedAt = _asDateTime(row['focus_center_calculated_at']);

    if (lon == null || lat == null) return null;

    return AgusFocusCenter(
      longitude: lon,
      latitude: lat,
      calculatedAt: calculatedAt,
    );
  }

  /// Sets the focus center for a layer.
  void setLayerFocusCenter(String layerId, double longitude, double latitude) {
    _executeChecked('''
UPDATE agus.layers
SET
  focus_center_lon = ${_sqlNullableDouble(longitude)},
  focus_center_lat = ${_sqlNullableDouble(latitude)},
  focus_center_calculated_at = current_localtimestamp(),
  updated_at = current_localtimestamp()
WHERE layer_id = ${_sqlString(layerId)};
''');
  }

  /// Clears the focus center for a layer.
  void clearLayerFocusCenter(String layerId) {
    _executeChecked('''
UPDATE agus.layers
SET
  focus_center_lon = NULL,
  focus_center_lat = NULL,
  focus_center_calculated_at = NULL,
  updated_at = current_localtimestamp()
WHERE layer_id = ${_sqlString(layerId)};
''');
  }

  /// Returns the focus center for a feature, or `null` when absent or not calculated.
  AgusFocusCenter? getFeatureFocusCenter(String layerId, String featureId) {
    final result = queryDuckDB('''
SELECT
  focus_center_lon,
  focus_center_lat,
  focus_center_calculated_at
FROM agus.layer_features
WHERE layer_id = ${_sqlString(layerId)}
  AND feature_id = ${_sqlString(featureId)};
''');
    final rows = _rowsByName(result);
    if (rows.isEmpty) return null;

    final row = rows.first;
    final lon = _asDouble(row['focus_center_lon']);
    final lat = _asDouble(row['focus_center_lat']);
    final calculatedAt = _asDateTime(row['focus_center_calculated_at']);

    if (lon == null || lat == null) return null;

    return AgusFocusCenter(
      longitude: lon,
      latitude: lat,
      calculatedAt: calculatedAt,
    );
  }

  /// Sets the focus center for a feature.
  void setFeatureFocusCenter(
    String layerId,
    String featureId,
    double longitude,
    double latitude,
  ) {
    _executeChecked('''
UPDATE agus.layer_features
SET
  focus_center_lon = ${_sqlNullableDouble(longitude)},
  focus_center_lat = ${_sqlNullableDouble(latitude)},
  focus_center_calculated_at = current_localtimestamp(),
  updated_at = current_localtimestamp()
WHERE layer_id = ${_sqlString(layerId)}
  AND feature_id = ${_sqlString(featureId)};
''');
  }

  /// Clears the focus center for a feature.
  void clearFeatureFocusCenter(String layerId, String featureId) {
    _executeChecked('''
UPDATE agus.layer_features
SET
  focus_center_lon = NULL,
  focus_center_lat = NULL,
  focus_center_calculated_at = NULL,
  updated_at = current_localtimestamp()
WHERE layer_id = ${_sqlString(layerId)}
  AND feature_id = ${_sqlString(featureId)};
''');
  }

  /// Inserts or updates a keymap setting.
  void upsertKeymapSetting(AgusKeymapSettingDraft setting) {
    _executeChecked('''
INSERT INTO agus.keymap_settings(
  setting_id,
  platform,
  command,
  keybinding_payload,
  is_override,
  display_name,
  description,
  validation_schema_version
) VALUES (
  ${_sqlString(setting.settingId)},
  ${_sqlString(setting.platform)},
  ${_sqlString(setting.command)},
  ${_sqlJson(setting.keybindingPayload)},
  ${_sqlBool(setting.isOverride)},
  ${_sqlNullableString(setting.displayName)},
  ${_sqlNullableString(setting.description)},
  ${setting.validationSchemaVersion}
)
ON CONFLICT(setting_id) DO UPDATE SET
  platform = excluded.platform,
  command = excluded.command,
  keybinding_payload = excluded.keybinding_payload,
  is_override = excluded.is_override,
  display_name = excluded.display_name,
  description = excluded.description,
  validation_schema_version = excluded.validation_schema_version,
  updated_at = current_localtimestamp();
''');
  }

  /// Returns a keymap setting by [settingId], or `null` when absent.
  AgusKeymapSetting? getKeymapSetting(String settingId) {
    final result = queryDuckDB('''
SELECT
  setting_id,
  platform,
  command,
  keybinding_payload,
  is_override,
  display_name,
  description,
  validation_schema_version,
  created_at,
  updated_at
FROM agus.keymap_settings
WHERE setting_id = ${_sqlString(settingId)};
''');
    final rows = _rowsByName(result);
    if (rows.isEmpty) return null;
    return _keymapSettingFromRow(rows.first);
  }

  /// Returns all keymap settings for a platform and optional command.
  List<AgusKeymapSetting> listKeymapSettings({
    required String platform,
    String? command,
  }) {
    final result = queryDuckDB('''
SELECT
  setting_id,
  platform,
  command,
  keybinding_payload,
  is_override,
  display_name,
  description,
  validation_schema_version,
  created_at,
  updated_at
FROM agus.keymap_settings
WHERE platform = ${_sqlString(platform)}
${command != null ? 'AND command = ${_sqlString(command)}' : ''}
ORDER BY command ASC, is_override DESC;
''');
    return _rowsByName(result)
        .map(_keymapSettingFromRow)
        .toList(growable: false);
  }

  /// Deletes a keymap setting.
  void deleteKeymapSetting(String settingId) {
    _executeChecked('''
DELETE FROM agus.keymap_settings
WHERE setting_id = ${_sqlString(settingId)};
''');
  }

  /// Creates a local backup of the current DuckDB file and returns its path.
  Future<String> backup({String? outputDirectory, DateTime? now}) async {
    _executeChecked('CHECKPOINT;');

    final source = File(databasePath);
    if (!await source.exists()) {
      throw StateError('DuckDB database file does not exist: $databasePath');
    }

    final timestamp = _backupTimestamp(now ?? DateTime.now().toUtc());
    final directory = Directory(
      outputDirectory ?? p.join(writablePath, 'duckdb_backups'),
    );
    await directory.create(recursive: true);

    final destination = p.join(
      directory.path,
      'agus_layers_$timestamp.duckdb',
    );
    await source.copy(destination);
    return destination;
  }
}

String _upsertLayerSql(AgusLayerDraft layer) {
  return '''
INSERT INTO agus.layers(
  layer_id,
  name,
  kind,
  visible,
  locked,
  z_index,
  min_zoom,
  max_zoom,
  style,
  metadata,
  deleted_at
) VALUES (
  ${_sqlString(layer.layerId)},
  ${_sqlString(layer.name)},
  ${_sqlString(layer.kind.databaseValue)},
  ${_sqlBool(layer.visible)},
  ${_sqlBool(layer.locked)},
  ${layer.zIndex},
  ${_sqlNullableInt(layer.minZoom)},
  ${_sqlNullableInt(layer.maxZoom)},
  ${_sqlNullableJson(layer.style)},
  ${_sqlNullableJson(layer.metadata)},
  NULL
)
ON CONFLICT(layer_id) DO UPDATE SET
  name = excluded.name,
  kind = excluded.kind,
  visible = excluded.visible,
  locked = excluded.locked,
  z_index = excluded.z_index,
  min_zoom = excluded.min_zoom,
  max_zoom = excluded.max_zoom,
  style = excluded.style,
  metadata = excluded.metadata,
  updated_at = current_localtimestamp(),
  deleted_at = NULL;
''';
}

void _repairLayerForeignKeyLimitations() {
  if (!_layerChildForeignKeysNeedRepair()) {
    return;
  }

  _executeChecked(r'''
BEGIN TRANSACTION;

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
  created_at TIMESTAMP NOT NULL DEFAULT current_localtimestamp(),
  updated_at TIMESTAMP NOT NULL DEFAULT current_localtimestamp(),
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
  updated_at TIMESTAMP NOT NULL DEFAULT current_localtimestamp(),
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
  generated_at TIMESTAMP NOT NULL DEFAULT current_localtimestamp(),
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

COMMIT;
''');
}

String? _openDuckDBAppDatabaseWithWalRecovery({
  required String writablePath,
  required String databasePath,
}) {
  if (openDuckDBAppDatabase(writablePath)) {
    return null;
  }

  final firstError = duckDBLastError();
  if (!_isDuckDBWalReplayFailure(firstError)) {
    return 'DuckDB open failed: $firstError';
  }

  closeDuckDB();
  final walFile = File('$databasePath.wal');
  if (!walFile.existsSync()) {
    return 'DuckDB open failed: $firstError';
  }

  final timestamp = _backupTimestamp(DateTime.now().toUtc());
  final recoveryDirectory = Directory(p.join(writablePath, 'duckdb_recovery'));
  recoveryDirectory.createSync(recursive: true);

  final databaseFile = File(databasePath);
  if (databaseFile.existsSync()) {
    databaseFile.copySync(
      p.join(recoveryDirectory.path, 'agus_layers.$timestamp.duckdb'),
    );
  }

  final quarantinedWalPath = p.join(
    recoveryDirectory.path,
    'agus_layers.$timestamp.duckdb.wal',
  );
  walFile.renameSync(quarantinedWalPath);

  if (openDuckDBAppDatabase(writablePath)) {
    return null;
  }

  final retryError = duckDBLastError();
  return 'DuckDB open failed after quarantining an unreplayable WAL at '
      '$quarantinedWalPath. First failure: $firstError. '
      'Retry failure: $retryError';
}

bool _isDuckDBWalReplayFailure(String error) {
  return error.contains('Failure while replaying WAL file') ||
      error.contains('WriteAheadLogReplayer') ||
      error.contains('.duckdb.wal');
}

bool _layerChildForeignKeysNeedRepair() {
  final result = queryDuckDB(r'''
SELECT count(*) AS foreign_key_count
FROM duckdb_constraints()
WHERE schema_name = 'agus'
  AND constraint_type = 'FOREIGN KEY'
  AND referenced_table = 'layers'
  AND table_name IN (
    'layer_features',
    'query_layers',
    'layer_metadata',
    'layer_render_cache'
  );
''');
  final rows = _rowsByName(result);
  if (rows.isEmpty) {
    return false;
  }
  return (_asInt(rows.first['foreign_key_count']) ?? 0) > 0;
}

String _upsertFeatureSql(AgusLayerFeatureDraft feature) {
  final boundingBox = feature.boundingBox;
  return '''
INSERT INTO agus.layer_features(
  layer_id,
  feature_id,
  geometry,
  geometry_kind,
  properties,
  style,
  bbox_min_lon,
  bbox_min_lat,
  bbox_max_lon,
  bbox_max_lat,
  z_index,
  min_zoom,
  max_zoom,
  deleted_at
) VALUES (
  ${_sqlString(feature.layerId)},
  ${_sqlString(feature.featureId)},
  ST_GeomFromText(${_sqlString(feature.geometryWkt)}),
  ${_sqlString(feature.geometryKind.databaseValue)},
  ${_sqlJson(feature.properties)},
  ${_sqlNullableJson(feature.style)},
  ${_sqlNullableDouble(boundingBox?.minLon)},
  ${_sqlNullableDouble(boundingBox?.minLat)},
  ${_sqlNullableDouble(boundingBox?.maxLon)},
  ${_sqlNullableDouble(boundingBox?.maxLat)},
  ${_sqlNullableInt(feature.zIndex)},
  ${_sqlNullableInt(feature.minZoom)},
  ${_sqlNullableInt(feature.maxZoom)},
  NULL
)
ON CONFLICT(layer_id, feature_id) DO UPDATE SET
  geometry = excluded.geometry,
  geometry_kind = excluded.geometry_kind,
  properties = excluded.properties,
  style = excluded.style,
  bbox_min_lon = excluded.bbox_min_lon,
  bbox_min_lat = excluded.bbox_min_lat,
  bbox_max_lon = excluded.bbox_max_lon,
  bbox_max_lat = excluded.bbox_max_lat,
  z_index = excluded.z_index,
  min_zoom = excluded.min_zoom,
  max_zoom = excluded.max_zoom,
  updated_at = current_localtimestamp(),
  deleted_at = NULL;
''';
}

void _executeChecked(String sql) {
  if (!executeDuckDBSql(sql)) {
    throw StateError('DuckDB statement failed: ${duckDBLastError()}');
  }
}

List<Map<String, Object?>> _rowsByName(DuckDBQueryResult result) {
  return result.rows.map((row) {
    final mapped = <String, Object?>{};
    for (var index = 0; index < result.columns.length; index += 1) {
      mapped[result.columns[index].name] =
          index < row.length ? row[index] : null;
    }
    return mapped;
  }).toList(growable: false);
}

AgusLayer _layerFromRow(Map<String, Object?> row) {
  return AgusLayer(
    layerId: row['layer_id'] as String,
    name: row['name'] as String,
    kind: AgusLayerKind.fromDatabaseValue(row['kind'] as String),
    visible: row['visible'] as bool? ?? false,
    locked: row['locked'] as bool? ?? false,
    zIndex: _asInt(row['z_index']) ?? 0,
    minZoom: _asInt(row['min_zoom']),
    maxZoom: _asInt(row['max_zoom']),
    style: _asStringMap(row['style']),
    metadata: _asStringMap(row['metadata']),
    createdAt: _asDateTime(row['created_at']),
    updatedAt: _asDateTime(row['updated_at']),
    deletedAt: _asDateTime(row['deleted_at']),
  );
}

AgusLayerFeature _featureFromRow(Map<String, Object?> row) {
  final minLon = _asDouble(row['bbox_min_lon']);
  final minLat = _asDouble(row['bbox_min_lat']);
  final maxLon = _asDouble(row['bbox_max_lon']);
  final maxLat = _asDouble(row['bbox_max_lat']);

  return AgusLayerFeature(
    layerId: row['layer_id'] as String,
    featureId: row['feature_id'] as String,
    geometryWkt: row['geometry_wkt'] as String,
    geometryKind: AgusGeometryKind.fromDatabaseValue(
      row['geometry_kind'] as String,
    ),
    properties: _asStringMap(row['properties']) ?? const <String, Object?>{},
    style: _asStringMap(row['style']),
    boundingBox:
        minLon == null || minLat == null || maxLon == null || maxLat == null
            ? null
            : AgusBoundingBox(
                minLon: minLon,
                minLat: minLat,
                maxLon: maxLon,
                maxLat: maxLat,
              ),
    zIndex: _asInt(row['z_index']),
    minZoom: _asInt(row['min_zoom']),
    maxZoom: _asInt(row['max_zoom']),
    createdAt: _asDateTime(row['created_at']),
    updatedAt: _asDateTime(row['updated_at']),
    deletedAt: _asDateTime(row['deleted_at']),
  );
}

AgusQueryLayer _queryLayerFromRow(Map<String, Object?> row) {
  return AgusQueryLayer(
    layerId: row['layer_id'] as String,
    sqlText: row['sql_text'] as String,
    isPreset: row['is_preset'] as bool? ?? false,
    requiredExtensions: _asStringList(row['required_extensions']),
    resultContractVersion: _asInt(row['result_contract_version']) ?? 1,
    lastValidatedAt: _asDateTime(row['last_validated_at']),
    lastError: row['last_error'] as String?,
  );
}

AgusLayerMetadataEntry _metadataFromRow(Map<String, Object?> row) {
  return AgusLayerMetadataEntry(
    layerId: row['layer_id'] as String,
    key: row['key'] as String,
    value: row['value'] as String,
    valueType: row['value_type'] as String,
    updatedAt: _asDateTime(row['updated_at']),
  );
}

AgusSearchCacheEntry _searchCacheFromRow(Map<String, Object?> row) {
  return AgusSearchCacheEntry(
    cacheId: row['cache_id'] as String,
    normalizedQuery: row['normalized_query'] as String,
    locale: row['locale'] as String,
    mapDataRevision: row['map_data_revision'] as String?,
    mapDataFingerprint: row['map_data_fingerprint'] as String?,
    resultPayload:
        _asStringMap(row['result_payload']) ?? const <String, Object?>{},
    resultCount: _asInt(row['result_count']) ?? 0,
    createdAt: _asDateTime(row['created_at']),
    updatedAt: _asDateTime(row['updated_at']),
    accessedAt: _asDateTime(row['accessed_at']),
    isStale: row['is_stale'] as bool? ?? false,
    invalidationReason: row['invalidation_reason'] as String?,
  );
}

AgusKeymapSetting _keymapSettingFromRow(Map<String, Object?> row) {
  return AgusKeymapSetting(
    settingId: row['setting_id'] as String,
    platform: row['platform'] as String,
    command: row['command'] as String,
    keybindingPayload:
        _asStringMap(row['keybinding_payload']) ?? const <String, Object?>{},
    isOverride: row['is_override'] as bool? ?? false,
    displayName: row['display_name'] as String?,
    description: row['description'] as String?,
    validationSchemaVersion: _asInt(row['validation_schema_version']) ?? 1,
    createdAt: _asDateTime(row['created_at']),
    updatedAt: _asDateTime(row['updated_at']),
  );
}

String _sqlString(String value) {
  return "'${value.replaceAll("'", "''")}'";
}

String _sqlNullableString(String? value) {
  return value == null ? 'NULL' : _sqlString(value);
}

String _sqlBool(bool value) {
  return value ? 'true' : 'false';
}

String _sqlJson(Object? value) {
  return '${_sqlString(jsonEncode(value))}::JSON';
}

String _sqlNullableJson(Object? value) {
  return value == null ? 'NULL' : _sqlJson(value);
}

String _sqlNullableInt(int? value) {
  return value == null ? 'NULL' : value.toString();
}

String _sqlNullableDouble(double? value) {
  if (value == null) return 'NULL';
  if (!value.isFinite) {
    throw ArgumentError.value(value, 'value', 'Must be finite');
  }
  return value.toString();
}

int? _asInt(Object? value) {
  return switch (value) {
    null => null,
    int() => value,
    double() => value.toInt(),
    String() => int.tryParse(value),
    _ => null,
  };
}

double? _asDouble(Object? value) {
  return switch (value) {
    null => null,
    int() => value.toDouble(),
    double() => value,
    String() => double.tryParse(value),
    _ => null,
  };
}

DateTime? _asDateTime(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}

Map<String, Object?>? _asStringMap(Object? value) {
  if (value == null) return null;
  if (value is Map<String, Object?>) return Map.unmodifiable(value);
  if (value is Map) {
    return Map.unmodifiable(
      value.map((key, mapValue) => MapEntry(key.toString(), mapValue)),
    );
  }
  return null;
}

List<String> _asStringList(Object? value) {
  if (value is List) {
    return value.map((item) => item.toString()).toList(growable: false);
  }
  return const <String>[];
}

String _backupTimestamp(DateTime value) {
  return value
      .toIso8601String()
      .replaceAll(':', '')
      .replaceAll('.', '')
      .replaceAll('Z', 'Z');
}
