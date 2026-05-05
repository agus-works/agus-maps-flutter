import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'src/agus_maps_api.g.dart';

import 'agus_maps_flutter_bindings_generated.dart';

// Export additional services
export 'mwm_storage.dart';
export 'mirror_service.dart';
export 'src/agus_maps_api.g.dart'
    show
        PlacePageData,
        PlacePageFeatureId,
        PlacePageCoordinates,
        PlacePageIntMetadataEntry,
        PlacePageStringMetadataEntry,
        RenderState;

part 'src/layers/duckdb_layer_store.dart';
part 'src/layers/duckdb_draw_controller.dart';
part 'src/layers/duckdb_layer_widgets.dart';

/// Low-frequency map-ready event emitted by native platforms.
class MapReadyEvent {
  final int surfaceId;

  const MapReadyEvent(this.surfaceId);
}

/// Low-frequency render state change event emitted by native platforms.
class RenderStateChangedEvent {
  final RenderState state;
  final int? surfaceId;

  const RenderStateChangedEvent(this.state, this.surfaceId);
}

/// Column metadata returned from a DuckDB query result.
class DuckDBColumn {
  /// Creates column metadata for a DuckDB result column.
  const DuckDBColumn({required this.name, required this.type});

  /// Column name reported by DuckDB.
  final String name;

  /// DuckDB logical type or alias, such as `VARCHAR`, `JSON`, or `GEOMETRY`.
  final String type;

  static DuckDBColumn _fromJson(Object? value) {
    final map = value as Map<String, Object?>;
    return DuckDBColumn(
      name: map['name'] as String? ?? '',
      type: map['type'] as String? ?? 'INVALID',
    );
  }
}

/// Materialized JSON query result returned by the native DuckDB bridge.
class DuckDBQueryResult {
  /// Creates a materialized query result.
  const DuckDBQueryResult({
    required this.columns,
    required this.rows,
    required this.rowCount,
  });

  /// Result columns in DuckDB result order.
  final List<DuckDBColumn> columns;

  /// Materialized result rows, where each row is ordered like [columns].
  final List<List<Object?>> rows;

  /// Number of materialized rows reported by the native bridge.
  final int rowCount;

  /// Parses the JSON payload returned by [queryDuckDBJson].
  factory DuckDBQueryResult.fromJsonString(String source) {
    final decoded = jsonDecode(source) as Map<String, Object?>;
    return DuckDBQueryResult(
      columns: (decoded['columns'] as List<Object?>? ?? const [])
          .map(DuckDBColumn._fromJson)
          .toList(growable: false),
      rows: (decoded['rows'] as List<Object?>? ?? const [])
          .map((row) => List<Object?>.unmodifiable(row as List<Object?>))
          .toList(growable: false),
      rowCount: decoded['row_count'] as int? ?? 0,
    );
  }
}

/// Low-frequency place page change event emitted by native platforms.
class PlacePageChangedEvent {
  final PlacePageData? placePage;

  const PlacePageChangedEvent(this.placePage);
}

/// Resolved native map appearance.
enum MapThemeMode {
  light,
  dark,
}

/// Flutter-facing appearance preference for the example app and controllers.
enum MapAppearanceMode {
  system,
  light,
  dark,
}

/// Current native map camera state.
class MapCameraPosition {
  final double lat;
  final double lon;
  final int zoom;
  final double bearing;

  const MapCameraPosition({
    required this.lat,
    required this.lon,
    required this.zoom,
    required this.bearing,
  });
}

/// WGS84 latitude/longitude coordinate.
class AgusLatLon {
  /// Creates a coordinate in decimal degrees.
  const AgusLatLon({required this.lat, required this.lon});

  /// Latitude in decimal degrees.
  final double lat;

  /// Longitude in decimal degrees.
  final double lon;
}

/// CoMaps overlay/style layer state.
class MapLayerState {
  final bool outdoors;
  final bool isolines;
  final bool subway;

  const MapLayerState({
    required this.outdoors,
    required this.isolines,
    required this.subway,
  });

  MapLayerState copyWith({
    bool? outdoors,
    bool? isolines,
    bool? subway,
  }) {
    return MapLayerState(
      outdoors: outdoors ?? this.outdoors,
      isolines: isolines ?? this.isolines,
      subway: subway ?? this.subway,
    );
  }
}

/// Native CoMaps search lifecycle state.
enum NativeSearchStatus {
  idle,
  running,
  completed,
  cancelled,
  error;

  static NativeSearchStatus fromNative(int value) {
    if (value < 0 || value >= NativeSearchStatus.values.length) {
      return NativeSearchStatus.error;
    }
    return NativeSearchStatus.values[value];
  }
}

/// Native CoMaps search result type.
enum NativeSearchResultType {
  feature,
  latLon,
  pureSuggest,
  suggestFromFeature,
  postcode;

  static NativeSearchResultType fromNative(int value) {
    if (value < 0 || value >= NativeSearchResultType.values.length) {
      return NativeSearchResultType.feature;
    }
    return NativeSearchResultType.values[value];
  }
}

/// One row from the native CoMaps search engine.
class NativeSearchResult {
  const NativeSearchResult({
    required this.index,
    required this.type,
    required this.isSuggestion,
    required this.hasPoint,
    required this.title,
    required this.subtitle,
    required this.address,
    required this.suggestion,
    required this.lat,
    required this.lon,
  });

  final int index;
  final NativeSearchResultType type;
  final bool isSuggestion;
  final bool hasPoint;
  final String title;
  final String subtitle;
  final String address;
  final String suggestion;
  final double lat;
  final double lon;
}

/// A point-in-time snapshot of native CoMaps search results.
class NativeSearchSnapshot {
  const NativeSearchSnapshot({
    required this.generation,
    required this.status,
    required this.results,
  });

  const NativeSearchSnapshot.empty()
      : generation = 0,
        status = NativeSearchStatus.idle,
        results = const <NativeSearchResult>[];

  final int generation;
  final NativeSearchStatus status;
  final List<NativeSearchResult> results;

  bool get isRunning => status == NativeSearchStatus.running;
}

/// Native CoMaps router engine type.
enum NavigationRouterType {
  vehicle,
  pedestrian,
  bicycle,
  transit,
  ruler;

  static NavigationRouterType fromNative(int value) {
    if (value < 0 || value >= NavigationRouterType.values.length) {
      return NavigationRouterType.vehicle;
    }
    return NavigationRouterType.values[value];
  }
}

/// Native CoMaps route point role.
enum NavigationRoutePointType {
  start,
  intermediate,
  finish;

  static NavigationRoutePointType fromNative(int value) {
    if (value < 0 || value >= NavigationRoutePointType.values.length) {
      return NavigationRoutePointType.start;
    }
    return NavigationRoutePointType.values[value];
  }
}

/// Distance unit system used by native routing and formatted distances.
enum NavigationMeasurementUnits {
  metric,
  imperial;

  static NavigationMeasurementUnits fromNative(int value) {
    return value == NavigationMeasurementUnits.imperial.index
        ? NavigationMeasurementUnits.imperial
        : NavigationMeasurementUnits.metric;
  }
}

/// Speed camera warning behavior used by CoMaps routing.
enum NavigationSpeedCameraMode {
  auto,
  always,
  never;

  static NavigationSpeedCameraMode fromNative(int value) {
    if (value < 0 || value >= NavigationSpeedCameraMode.values.length) {
      return NavigationSpeedCameraMode.auto;
    }
    return NavigationSpeedCameraMode.values[value];
  }
}

/// Native routing session state.
enum NavigationSessionState {
  noValidRoute,
  routeBuilding,
  routeNotStarted,
  onRoute,
  routeNeedsRebuild,
  routeFinished,
  routeNoFollowing,
  routeRebuilding;

  static NavigationSessionState fromNative(int value) {
    if (value < 0 || value >= NavigationSessionState.values.length) {
      return NavigationSessionState.noValidRoute;
    }
    return NavigationSessionState.values[value];
  }
}

/// Units for a distance value already formatted by CoMaps rules.
enum NavigationDistanceUnit {
  meters,
  kilometers,
  feet,
  miles;

  static NavigationDistanceUnit fromNative(int value) {
    if (value < 0 || value >= NavigationDistanceUnit.values.length) {
      return NavigationDistanceUnit.meters;
    }
    return NavigationDistanceUnit.values[value];
  }
}

/// A numeric distance and unit from native routing.
class NavigationDistance {
  const NavigationDistance({required this.value, required this.unit});

  final double value;
  final NavigationDistanceUnit unit;
}

/// Car routing road types that CoMaps should avoid when calculating routes.
class NavigationRoutingOptions {
  const NavigationRoutingOptions({
    this.avoidTolls = false,
    this.avoidMotorways = false,
    this.avoidFerries = false,
    this.avoidUnpavedRoads = false,
  });

  static const int _tollMask = 1 << 1;
  static const int _motorwayMask = 1 << 2;
  static const int _ferryMask = 1 << 3;
  static const int _unpavedMask = 1 << 4;

  final bool avoidTolls;
  final bool avoidMotorways;
  final bool avoidFerries;
  final bool avoidUnpavedRoads;

  int get mask =>
      (avoidTolls ? _tollMask : 0) |
      (avoidMotorways ? _motorwayMask : 0) |
      (avoidFerries ? _ferryMask : 0) |
      (avoidUnpavedRoads ? _unpavedMask : 0);

  static NavigationRoutingOptions fromMask(int mask) {
    return NavigationRoutingOptions(
      avoidTolls: (mask & _tollMask) != 0,
      avoidMotorways: (mask & _motorwayMask) != 0,
      avoidFerries: (mask & _ferryMask) != 0,
      avoidUnpavedRoads: (mask & _unpavedMask) != 0,
    );
  }

  NavigationRoutingOptions copyWith({
    bool? avoidTolls,
    bool? avoidMotorways,
    bool? avoidFerries,
    bool? avoidUnpavedRoads,
  }) {
    return NavigationRoutingOptions(
      avoidTolls: avoidTolls ?? this.avoidTolls,
      avoidMotorways: avoidMotorways ?? this.avoidMotorways,
      avoidFerries: avoidFerries ?? this.avoidFerries,
      avoidUnpavedRoads: avoidUnpavedRoads ?? this.avoidUnpavedRoads,
    );
  }
}

/// Example-app navigation preferences backed by native CoMaps settings.
class NavigationSettings {
  const NavigationSettings({
    this.measurementUnits = NavigationMeasurementUnits.metric,
    this.turnNotificationsEnabled = true,
    this.announceStreetNames = true,
    this.showSpeedLimit = true,
    this.speedCameraMode = NavigationSpeedCameraMode.auto,
    this.routingOptions = const NavigationRoutingOptions(),
  });

  final NavigationMeasurementUnits measurementUnits;
  final bool turnNotificationsEnabled;
  final bool announceStreetNames;
  final bool showSpeedLimit;
  final NavigationSpeedCameraMode speedCameraMode;
  final NavigationRoutingOptions routingOptions;

  NavigationSettings copyWith({
    NavigationMeasurementUnits? measurementUnits,
    bool? turnNotificationsEnabled,
    bool? announceStreetNames,
    bool? showSpeedLimit,
    NavigationSpeedCameraMode? speedCameraMode,
    NavigationRoutingOptions? routingOptions,
  }) {
    return NavigationSettings(
      measurementUnits: measurementUnits ?? this.measurementUnits,
      turnNotificationsEnabled:
          turnNotificationsEnabled ?? this.turnNotificationsEnabled,
      announceStreetNames: announceStreetNames ?? this.announceStreetNames,
      showSpeedLimit: showSpeedLimit ?? this.showSpeedLimit,
      speedCameraMode: speedCameraMode ?? this.speedCameraMode,
      routingOptions: routingOptions ?? this.routingOptions,
    );
  }
}

/// Current native navigation status snapshot.
class NavigationStatus {
  const NavigationStatus({
    required this.isActive,
    required this.isBuilt,
    required this.isBuilding,
    required this.isFollowing,
    required this.isValid,
    required this.hasFollowingInfo,
    required this.routerType,
    required this.sessionState,
    required this.turn,
    required this.nextTurn,
    required this.pedestrianTurn,
    required this.exitNumber,
    required this.totalTimeSeconds,
    required this.completionPercent,
    required this.speedLimitMps,
    required this.distanceToTarget,
    required this.distanceToTurn,
    required this.distanceToNextStop,
    required this.timeToNextStopSeconds,
    required this.indexOfNextStop,
    required this.currentStreet,
    required this.nextStreet,
    required this.nextNextStreet,
  });

  final bool isActive;
  final bool isBuilt;
  final bool isBuilding;
  final bool isFollowing;
  final bool isValid;
  final bool hasFollowingInfo;
  final NavigationRouterType routerType;
  final NavigationSessionState sessionState;
  final int turn;
  final int nextTurn;
  final int pedestrianTurn;
  final int exitNumber;
  final int totalTimeSeconds;
  final double completionPercent;
  final double speedLimitMps;
  final NavigationDistance distanceToTarget;
  final NavigationDistance distanceToTurn;
  final NavigationDistance distanceToNextStop;
  final int timeToNextStopSeconds;
  final int indexOfNextStop;
  final String currentStreet;
  final String nextStreet;
  final String nextNextStreet;

  bool get hasSpeedLimit => speedLimitMps >= 0;
}

/// Broadcast streams for low-frequency native notifications.
class AgusMapsFlutterEvents {
  AgusMapsFlutterEvents._() {
    AgusMapsFlutterApi.setUp(_AgusMapsFlutterApiHandler(this));
  }

  static final AgusMapsFlutterEvents instance = AgusMapsFlutterEvents._();

  final StreamController<MapReadyEvent> _mapReadyController =
      StreamController<MapReadyEvent>.broadcast();
  final StreamController<RenderStateChangedEvent>
      _renderStateChangedController =
      StreamController<RenderStateChangedEvent>.broadcast();
  final StreamController<PlacePageChangedEvent> _placePageChangedController =
      StreamController<PlacePageChangedEvent>.broadcast();

  Stream<MapReadyEvent> get onMapReady => _mapReadyController.stream;
  Stream<RenderStateChangedEvent> get onRenderStateChanged =>
      _renderStateChangedController.stream;
  Stream<PlacePageChangedEvent> get onPlacePageChanged =>
      _placePageChangedController.stream;

  void _emitMapReady(int surfaceId) {
    _mapReadyController.add(MapReadyEvent(surfaceId));
  }

  void _emitRenderStateChanged(RenderState state, int? surfaceId) {
    _renderStateChangedController.add(
      RenderStateChangedEvent(state, surfaceId),
    );
  }

  void _emitPlacePageChanged(PlacePageData? placePage) {
    _placePageChangedController.add(PlacePageChangedEvent(placePage));
  }
}

class _AgusMapsFlutterApiHandler extends AgusMapsFlutterApi {
  final AgusMapsFlutterEvents _events;

  _AgusMapsFlutterApiHandler(this._events);

  @override
  void onMapReady(int surfaceId) {
    _events._emitMapReady(surfaceId);
  }

  @override
  void onRenderStateChanged(RenderState state, int? surfaceId) {
    _events._emitRenderStateChanged(state, surfaceId);
  }

  @override
  void onPlacePageChanged(PlacePageData? placePage) {
    // Place page data arrives pre-localized from native layer.
    // No Dart-side localization needed - native handles all type translations.
    _events._emitPlacePageChanged(placePage);
  }
}

// NOTE: PlacePageLocalization class has been removed.
// All localization is now handled by native code via setLocale().
// POI type names arrive pre-localized in place page subtitle.

/// Get the current place page data, if available.
/// Place page data arrives pre-localized from native layer.
Future<PlacePageData?> getCurrentPlacePage() async {
  try {
    return await AgusMapsHostApi().getCurrentPlacePage();
  } catch (error) {
    debugPrint('[AgusMap] Failed to fetch place page: $error');
    return null;
  }
}

void closePlacePage() {
  AgusMapsHostApi().clearPlacePageSelection();
}

/// Start a native CoMaps search and return its generation id.
///
/// When [interactive] is true, native CoMaps also runs viewport search so
/// results visible in the current map viewport are marked on the map.
int startNativeSearch(
  String query, {
  String locale = 'en',
  bool interactive = true,
  bool isCategory = false,
}) {
  final trimmedQuery = query.trim();
  if (trimmedQuery.isEmpty) {
    cancelNativeSearch();
    return -1;
  }

  final queryPtr = trimmedQuery.toNativeUtf8().cast<Char>();
  final localePtr = locale.toNativeUtf8().cast<Char>();
  try {
    return _bindings.comaps_search_start(
      queryPtr,
      localePtr,
      interactive ? 1 : 0,
      isCategory ? 1 : 0,
    );
  } on ArgumentError catch (error) {
    if (kDebugMode) {
      debugPrint('[AgusMap] Native search is unavailable: $error');
    }
    return -2;
  } finally {
    malloc.free(queryPtr);
    malloc.free(localePtr);
  }
}

/// Return the latest native CoMaps search snapshot.
NativeSearchSnapshot getNativeSearchSnapshot() {
  Pointer<AgusSearchResults> snapshotPtr;
  try {
    snapshotPtr = _bindings.comaps_search_copy_results();
  } on ArgumentError catch (error) {
    if (kDebugMode) {
      debugPrint('[AgusMap] Native search snapshot is unavailable: $error');
    }
    return const NativeSearchSnapshot.empty();
  }

  if (snapshotPtr == nullptr) {
    return const NativeSearchSnapshot.empty();
  }

  try {
    final snapshot = snapshotPtr.ref;
    final results = <NativeSearchResult>[];
    final resultCount = snapshot.result_count;
    final rowsPtr = snapshot.results;
    if (resultCount > 0 && rowsPtr != nullptr) {
      for (var i = 0; i < resultCount; i++) {
        final row = (rowsPtr + i).ref;
        results.add(
          NativeSearchResult(
            index: row.index,
            type: NativeSearchResultType.fromNative(row.result_type),
            isSuggestion: row.is_suggestion != 0,
            hasPoint: row.has_point != 0,
            title: _nativeSearchString(row.title),
            subtitle: _nativeSearchString(row.subtitle),
            address: _nativeSearchString(row.address),
            suggestion: _nativeSearchString(row.suggestion),
            lat: row.lat,
            lon: row.lon,
          ),
        );
      }
    }

    return NativeSearchSnapshot(
      generation: snapshot.generation,
      status: NativeSearchStatus.fromNative(snapshot.status),
      results: List<NativeSearchResult>.unmodifiable(results),
    );
  } finally {
    _bindings.comaps_search_results_free(snapshotPtr);
  }
}

/// Select a native CoMaps search result by index.
int showNativeSearchResult(int index) {
  try {
    return _bindings.comaps_search_show_result(index);
  } on ArgumentError catch (error) {
    if (kDebugMode) {
      debugPrint('[AgusMap] Native search selection is unavailable: $error');
    }
    return -1;
  }
}

/// Cancel native CoMaps search and clear cached native results.
void cancelNativeSearch() {
  try {
    _bindings.comaps_search_cancel();
  } on ArgumentError catch (error) {
    if (kDebugMode) {
      debugPrint('[AgusMap] Native search cancel is unavailable: $error');
    }
  }
}

/// Select the native CoMaps router engine.
int setNavigationRouter(NavigationRouterType routerType) {
  try {
    return _bindings.comaps_navigation_set_router(routerType.index);
  } on ArgumentError catch (error) {
    if (kDebugMode) {
      debugPrint('[AgusMap] Navigation router is unavailable: $error');
    }
    return -1;
  }
}

/// Return the currently selected native CoMaps router engine.
NavigationRouterType getNavigationRouter() {
  try {
    return NavigationRouterType.fromNative(
      _bindings.comaps_navigation_get_router(),
    );
  } on ArgumentError catch (error) {
    if (kDebugMode) {
      debugPrint('[AgusMap] Navigation router query failed: $error');
    }
    return NavigationRouterType.vehicle;
  }
}

/// Add or replace a native route point.
int addNavigationRoutePoint({
  required NavigationRoutePointType type,
  required double lat,
  required double lon,
  String title = '',
  String subtitle = '',
  int intermediateIndex = 0,
  bool isMyPosition = false,
  bool reorderIntermediatePoints = true,
}) {
  final titlePtr = title.toNativeUtf8().cast<Char>();
  final subtitlePtr = subtitle.toNativeUtf8().cast<Char>();
  try {
    return _bindings.comaps_navigation_add_route_point(
      type.index,
      titlePtr,
      subtitlePtr,
      lat,
      lon,
      intermediateIndex,
      isMyPosition ? 1 : 0,
      reorderIntermediatePoints ? 1 : 0,
    );
  } on ArgumentError catch (error) {
    if (kDebugMode) {
      debugPrint('[AgusMap] Add route point is unavailable: $error');
    }
    return -1;
  } finally {
    malloc.free(titlePtr);
    malloc.free(subtitlePtr);
  }
}

/// Remove a native route point.
void removeNavigationRoutePoint(
  NavigationRoutePointType type, {
  int intermediateIndex = 0,
}) {
  try {
    _bindings.comaps_navigation_remove_route_point(
      type.index,
      intermediateIndex,
    );
  } on ArgumentError catch (error) {
    if (kDebugMode) {
      debugPrint('[AgusMap] Remove route point is unavailable: $error');
    }
  }
}

/// Clear all native route points.
void clearNavigationRoutePoints() {
  try {
    _bindings.comaps_navigation_clear_route_points();
  } on ArgumentError catch (error) {
    if (kDebugMode) {
      debugPrint('[AgusMap] Clear route points is unavailable: $error');
    }
  }
}

/// Ask native CoMaps to calculate a route from the current route points.
int buildNavigationRoute() {
  try {
    return _bindings.comaps_navigation_build_route();
  } on ArgumentError catch (error) {
    if (kDebugMode) {
      debugPrint('[AgusMap] Build route is unavailable: $error');
    }
    return -1;
  }
}

/// Enter native route-following mode after a route has been built.
int followNavigationRoute() {
  try {
    return _bindings.comaps_navigation_follow_route();
  } on ArgumentError catch (error) {
    if (kDebugMode) {
      debugPrint('[AgusMap] Follow route is unavailable: $error');
    }
    return -1;
  }
}

/// Close native routing and optionally remove route points.
void closeNavigationRoute({bool removeRoutePoints = true}) {
  try {
    _bindings.comaps_navigation_close_route(removeRoutePoints ? 1 : 0);
  } on ArgumentError catch (error) {
    if (kDebugMode) {
      debugPrint('[AgusMap] Close route is unavailable: $error');
    }
  }
}

/// Return a snapshot of the native navigation state.
NavigationStatus? getNavigationStatus() {
  Pointer<AgusNavigationStatus> statusPtr;
  try {
    statusPtr = _bindings.comaps_navigation_copy_status();
  } on ArgumentError catch (error) {
    if (kDebugMode) {
      debugPrint('[AgusMap] Navigation status is unavailable: $error');
    }
    return null;
  }

  if (statusPtr == nullptr) {
    return null;
  }

  try {
    final status = statusPtr.ref;
    return NavigationStatus(
      isActive: status.is_active != 0,
      isBuilt: status.is_built != 0,
      isBuilding: status.is_building != 0,
      isFollowing: status.is_following != 0,
      isValid: status.is_valid != 0,
      hasFollowingInfo: status.has_following_info != 0,
      routerType: NavigationRouterType.fromNative(status.router_type),
      sessionState: NavigationSessionState.fromNative(
        status.route_session_state,
      ),
      turn: status.turn,
      nextTurn: status.next_turn,
      pedestrianTurn: status.pedestrian_turn,
      exitNumber: status.exit_number,
      totalTimeSeconds: status.total_time_seconds,
      completionPercent: status.completion_percent,
      speedLimitMps: status.speed_limit_mps,
      distanceToTarget: NavigationDistance(
        value: status.distance_to_target,
        unit: NavigationDistanceUnit.fromNative(
          status.distance_to_target_units,
        ),
      ),
      distanceToTurn: NavigationDistance(
        value: status.distance_to_turn,
        unit: NavigationDistanceUnit.fromNative(status.distance_to_turn_units),
      ),
      distanceToNextStop: NavigationDistance(
        value: status.distance_to_next_stop,
        unit: NavigationDistanceUnit.fromNative(
          status.distance_to_next_stop_units,
        ),
      ),
      timeToNextStopSeconds: status.time_to_next_stop_seconds,
      indexOfNextStop: status.index_of_next_stop,
      currentStreet: _nativeSearchString(status.current_street),
      nextStreet: _nativeSearchString(status.next_street),
      nextNextStreet: _nativeSearchString(status.next_next_street),
    );
  } finally {
    _bindings.comaps_navigation_status_free(statusPtr);
  }
}

/// Apply native navigation preferences.
void applyNavigationSettings(
  NavigationSettings settings, {
  String? turnLocale,
}) {
  setNavigationMeasurementUnits(settings.measurementUnits);
  setNavigationTurnNotificationsEnabled(settings.turnNotificationsEnabled);
  if (turnLocale != null) {
    setNavigationTurnNotificationsLocale(turnLocale);
  }
  setNavigationSpeedCameraMode(settings.speedCameraMode);
  setNavigationRoutingOptions(settings.routingOptions);
}

/// Set metric or imperial units for native distance formatting.
void setNavigationMeasurementUnits(NavigationMeasurementUnits units) {
  try {
    _bindings.comaps_navigation_set_measurement_units(units.index);
  } on ArgumentError catch (error) {
    if (kDebugMode) {
      debugPrint('[AgusMap] Measurement units are unavailable: $error');
    }
  }
}

/// Return native measurement units.
NavigationMeasurementUnits getNavigationMeasurementUnits() {
  try {
    return NavigationMeasurementUnits.fromNative(
      _bindings.comaps_navigation_get_measurement_units(),
    );
  } on ArgumentError catch (error) {
    if (kDebugMode) {
      debugPrint('[AgusMap] Measurement units query failed: $error');
    }
    return NavigationMeasurementUnits.metric;
  }
}

/// Enable or disable native turn notification generation.
void setNavigationTurnNotificationsEnabled(bool enabled) {
  try {
    _bindings.comaps_navigation_set_turn_notifications_enabled(
      enabled ? 1 : 0,
    );
  } on ArgumentError catch (error) {
    if (kDebugMode) {
      debugPrint('[AgusMap] Turn notifications are unavailable: $error');
    }
  }
}

/// Return whether native turn notifications are enabled.
bool getNavigationTurnNotificationsEnabled() {
  try {
    return _bindings.comaps_navigation_get_turn_notifications_enabled() != 0;
  } on ArgumentError catch (error) {
    if (kDebugMode) {
      debugPrint('[AgusMap] Turn notification query failed: $error');
    }
    return false;
  }
}

/// Set the locale used by native turn notification text generation.
void setNavigationTurnNotificationsLocale(String locale) {
  final localePtr =
      _turnNotificationsSoundLocale(locale).toNativeUtf8().cast<Char>();
  try {
    _bindings.comaps_navigation_set_turn_notifications_locale(localePtr);
  } on ArgumentError catch (error) {
    if (kDebugMode) {
      debugPrint('[AgusMap] Turn notification locale is unavailable: $error');
    }
  } finally {
    malloc.free(localePtr);
  }
}

String _turnNotificationsSoundLocale(String locale) {
  final normalized = locale.trim().replaceAll('_', '-');
  if (normalized.isEmpty) return normalized;

  const supportedRegionalLocales = {'pt-BR', 'es-MX', 'zh-Hans', 'zh-Hant'};
  if (supportedRegionalLocales.contains(normalized)) return normalized;

  final separator = normalized.indexOf('-');
  if (separator <= 0) return normalized;
  return normalized.substring(0, separator);
}

/// Set speed camera warning behavior for native navigation.
void setNavigationSpeedCameraMode(NavigationSpeedCameraMode mode) {
  try {
    _bindings.comaps_navigation_set_speed_camera_mode(mode.index);
  } on ArgumentError catch (error) {
    if (kDebugMode) {
      debugPrint('[AgusMap] Speed camera mode is unavailable: $error');
    }
  }
}

/// Return the current native speed camera warning mode.
NavigationSpeedCameraMode getNavigationSpeedCameraMode() {
  try {
    return NavigationSpeedCameraMode.fromNative(
      _bindings.comaps_navigation_get_speed_camera_mode(),
    );
  } on ArgumentError catch (error) {
    if (kDebugMode) {
      debugPrint('[AgusMap] Speed camera mode query failed: $error');
    }
    return NavigationSpeedCameraMode.auto;
  }
}

/// Set road types that native car routing should avoid.
void setNavigationRoutingOptions(NavigationRoutingOptions options) {
  try {
    _bindings.comaps_navigation_set_avoid_routing_options(options.mask);
  } on ArgumentError catch (error) {
    if (kDebugMode) {
      debugPrint('[AgusMap] Routing options are unavailable: $error');
    }
  }
}

/// Return road types that native car routing avoids.
NavigationRoutingOptions getNavigationRoutingOptions() {
  try {
    return NavigationRoutingOptions.fromMask(
      _bindings.comaps_navigation_get_avoid_routing_options(),
    );
  } on ArgumentError catch (error) {
    if (kDebugMode) {
      debugPrint('[AgusMap] Routing options query failed: $error');
    }
    return const NavigationRoutingOptions();
  }
}

String _nativeSearchString(Pointer<Char> pointer) {
  if (pointer == nullptr) {
    return '';
  }
  return pointer.cast<Utf8>().toDartString();
}

/// A very short-lived native function.
///
/// For very short-lived functions, it is fine to call them on the main isolate.
/// They will block the Dart execution while running the native function, so
/// only do this for native functions which are guaranteed to be short-lived.
int sum(int a, int b) => _bindings.sum(a, b);

/// A longer lived native function, which occupies the thread calling it.
///
/// Do not call these kind of native functions in the main isolate. They will
/// block Dart execution. This will cause dropped frames in Flutter applications.
/// Instead, call these native functions on a separate isolate.
///
/// Modify this to suit your own use case. Example use cases:
///
/// 1. Reuse a single isolate for various different kinds of requests.
/// 2. Use multiple helper isolates for parallel execution.
Future<int> sumAsync(int a, int b) async {
  final SendPort helperIsolateSendPort = await _helperIsolateSendPort;
  final int requestId = _nextSumRequestId++;
  final _SumRequest request = _SumRequest(requestId, a, b);
  final Completer<int> completer = Completer<int>();
  _sumRequests[requestId] = completer;
  helperIsolateSendPort.send(request);
  return completer.future;
}

final AgusMapsHostApi _hostApi = AgusMapsHostApi();
final AgusMapsFlutterEvents _flutterEvents = AgusMapsFlutterEvents.instance;

/// Access to low-frequency native event streams.
AgusMapsFlutterEvents get mapsFlutterEvents => _flutterEvents;

Future<String> extractMap(String assetPath) async {
  return _hostApi.extractMap(assetPath);
}

/// Extract all CoMaps data files (classificator, types, categories, etc.)
/// Returns the path to the directory containing the extracted files.
Future<String> extractDataFiles() async {
  return _hostApi.extractDataFiles();
}

Future<String> getApkPath() async {
  return _hostApi.getApkPath();
}

void init(String apkPath, String storagePath) {
  final apkPathPtr = apkPath.toNativeUtf8().cast<Char>();
  final storagePathPtr = storagePath.toNativeUtf8().cast<Char>();
  _bindings.comaps_init(apkPathPtr, storagePathPtr);
  malloc.free(apkPathPtr);
  malloc.free(storagePathPtr);
}

/// Initialize CoMaps with separate resource and writable paths
void initWithPaths(String resourcePath, String writablePath) {
  final resourcePathPtr = resourcePath.toNativeUtf8().cast<Char>();
  final writablePathPtr = writablePath.toNativeUtf8().cast<Char>();
  _bindings.comaps_init_paths(resourcePathPtr, writablePathPtr);
  malloc.free(resourcePathPtr);
  malloc.free(writablePathPtr);
}

void _ensureDuckDBBridgeSupported() {
  if (!(Platform.isMacOS || Platform.isIOS || Platform.isAndroid)) {
    throw UnsupportedError(
      'DuckDB bridge is currently wired on Apple and Android only',
    );
  }
}

void _ensureNativeDuckDBLayerRenderingSupported() {
  if (!(Platform.isMacOS || Platform.isIOS || Platform.isAndroid)) {
    throw UnsupportedError(
      'Native DuckDB layer rendering is currently wired on Apple and Android only',
    );
  }
}

String _nativeDuckDBString(Pointer<Char> value) {
  if (value == nullptr) return '';
  return value.cast<Utf8>().toDartString();
}

String? _nativeNullableDuckDBString(Pointer<Char> value) {
  if (value == nullptr) return null;
  return value.cast<Utf8>().toDartString();
}

/// Linked DuckDB library version for the native persistence bridge.
String duckDBLibraryVersion() {
  _ensureDuckDBBridgeSupported();
  return _nativeDuckDBString(_bindings.agus_duckdb_library_version());
}

/// Last native DuckDB bridge error, or an empty string.
String duckDBLastError() {
  _ensureDuckDBBridgeSupported();
  return _nativeDuckDBString(_bindings.agus_duckdb_last_error());
}

/// Opens `writablePath/agus_layers.duckdb`, loads extensions, and migrates it.
bool openDuckDBAppDatabase(String writablePath) {
  _ensureDuckDBBridgeSupported();
  final writablePathPtr = writablePath.toNativeUtf8().cast<Char>();
  try {
    return _bindings.agus_duckdb_open_app_database(writablePathPtr) == 1;
  } finally {
    malloc.free(writablePathPtr);
  }
}

/// Closes the current app-instance DuckDB connection.
void closeDuckDB() {
  _ensureDuckDBBridgeSupported();
  _bindings.agus_duckdb_close();
}

/// Whether the app-instance DuckDB connection is open.
bool isDuckDBOpen() {
  _ensureDuckDBBridgeSupported();
  return _bindings.agus_duckdb_is_open() == 1;
}

/// Executes unrestricted SQL against the app-instance DuckDB connection.
bool executeDuckDBSql(String sql) {
  _ensureDuckDBBridgeSupported();
  final sqlPtr = sql.toNativeUtf8().cast<Char>();
  try {
    return _bindings.agus_duckdb_execute(sqlPtr) == 1;
  } finally {
    malloc.free(sqlPtr);
  }
}

/// Executes SQL and returns a JSON payload with columns, rows, and row count.
///
/// Throws a [StateError] with [duckDBLastError] when native execution fails.
String queryDuckDBJson(String sql) {
  _ensureDuckDBBridgeSupported();
  final sqlPtr = sql.toNativeUtf8().cast<Char>();
  try {
    final json = _nativeNullableDuckDBString(
      _bindings.agus_duckdb_query_json(sqlPtr),
    );
    if (json == null) {
      throw StateError('DuckDB query failed: ${duckDBLastError()}');
    }
    return json;
  } finally {
    malloc.free(sqlPtr);
  }
}

/// Executes SQL and returns a parsed materialized DuckDB result.
DuckDBQueryResult queryDuckDB(String sql) {
  return DuckDBQueryResult.fromJsonString(queryDuckDBJson(sql));
}

/// Validates whether SQL satisfies the renderable query-layer contract.
bool validateRenderableDuckDBQuery(String sql) {
  _ensureDuckDBBridgeSupported();
  final sqlPtr = sql.toNativeUtf8().cast<Char>();
  try {
    return _bindings.agus_duckdb_validate_render_query(sqlPtr) == 1;
  } finally {
    malloc.free(sqlPtr);
  }
}

/// Applies embedded app schema migrations and verifies recorded checksums.
bool runDuckDBMigrations() {
  _ensureDuckDBBridgeSupported();
  return _bindings.agus_duckdb_run_migrations() == 1;
}

/// Executes a SQL migration file against the app-instance DuckDB connection.
bool applyDuckDBMigrationFile(String path) {
  _ensureDuckDBBridgeSupported();
  final pathPtr = path.toNativeUtf8().cast<Char>();
  try {
    return _bindings.agus_duckdb_apply_migration_file(pathPtr) == 1;
  } finally {
    malloc.free(pathPtr);
  }
}

/// Enables or disables native Drape rendering for visible DuckDB layers.
///
/// Android, macOS, and iOS render DuckDB-backed points and line/polygon
/// outlines by submitting native user marks to CoMaps Drape. The renderer
/// refreshes as the viewport changes while enabled.
void setDuckDBMapLayerRenderingEnabled(bool enabled) {
  _ensureDuckDBBridgeSupported();
  _ensureNativeDuckDBLayerRenderingSupported();
  _bindings.agus_duckdb_set_rendering_enabled(enabled ? 1 : 0);
}

/// Refreshes visible DuckDB map layers into the native Drape renderer.
///
/// Returns the number of features submitted. A negative value means the native
/// map or DuckDB connection is not ready yet.
int refreshDuckDBMapLayers() {
  _ensureDuckDBBridgeSupported();
  _ensureNativeDuckDBLayerRenderingSupported();
  return _bindings.agus_duckdb_refresh_render_layers();
}

/// Renders committed-feature edit handles in the native Drape scene.
///
/// This is visual-only state for the currently selected feature. Persistence
/// remains owned by the Dart layer store and the draw controller.
void setDuckDBEditHandlesFromWkt(String geometryWkt) {
  setDuckDBInteractionGeometryFromWkt(
    AgusDrapeInteractionMode.editingFeature,
    geometryWkt,
  );
}

/// Renders transient drawing/editing geometry in the native Drape scene.
void setDuckDBInteractionGeometryFromWkt(
  AgusDrapeInteractionMode mode,
  String geometryWkt,
) {
  _ensureDuckDBBridgeSupported();
  _ensureNativeDuckDBLayerRenderingSupported();
  final geometryWktPtr = geometryWkt.toNativeUtf8().cast<Char>();
  try {
    _bindings.agus_duckdb_set_interaction_geometry_from_wkt(
      switch (mode) {
        AgusDrapeInteractionMode.inactive => 0,
        AgusDrapeInteractionMode.drawing => 1,
        AgusDrapeInteractionMode.editingFeature => 2,
      },
      geometryWktPtr,
    );
  } finally {
    malloc.free(geometryWktPtr);
  }
}

/// Clears native Drape drawing/edit handles for the selected DuckDB feature.
void clearDuckDBEditHandles() {
  _ensureDuckDBBridgeSupported();
  _ensureNativeDuckDBLayerRenderingSupported();
  _bindings.agus_duckdb_clear_edit_handles();
}

/// Set the locale for native POI type localization.
///
/// This controls how POI type names are translated in place page data
/// (e.g., "amenity-fuel" → "Gas Station", "amenity-compressed_air" → "Compressed Air").
///
/// **When to call:**
/// - After [initWithPaths] so the resource directory with localization files is known
/// - Before creating the map surface or displaying any place pages for best results
/// - Can be called at any time to change locale (affects subsequent place page requests)
///
/// **Behavior:**
/// - If not called, the system locale is auto-detected (may not work reliably on all platforms)
/// - Explicitly calling this is recommended for consistent behavior across platforms
///
/// **Example:**
/// ```dart
/// final dataPath = await extractDataFiles();
/// initWithPaths(dataPath, dataPath);
/// setLocale(ui.PlatformDispatcher.instance.locale.toLanguageTag()); // e.g., "en-US"
/// await createMapSurface();
/// ```
///
/// [localeTag] - BCP 47 locale tag (e.g., "en-US", "zh-Hans", "de", "ja")
void setLocale(String localeTag) {
  final localeTagPtr = localeTag.toNativeUtf8().cast<Char>();
  try {
    _bindings.comaps_set_locale(localeTagPtr);
  } on ArgumentError {
    // Symbol may not exist on platforms where the binary was built before this feature.
    // Native will fall back to auto-detection based on system locale.
    if (kDebugMode) {
      debugPrint(
        '[AgusMap] setLocale: Symbol not found, using native auto-detection',
      );
    }
  } finally {
    malloc.free(localeTagPtr);
  }
}

void loadMap(String path) {
  final pathPtr = path.toNativeUtf8().cast<Char>();
  _bindings.comaps_load_map_path(pathPtr);
  malloc.free(pathPtr);
}

/// Register a single MWM map file directly by full path.
///
/// This bypasses the version folder scanning and registers the map file
/// directly with the rendering engine. Use this for MWM files that are
/// not in the standard version directory structure.
///
/// Returns 0 on success, negative values on error:
///   -1: Framework not initialized (call after map surface is created)
///   -2: Exception during registration
///   >0: MwmSet::RegResult error code
int registerSingleMap(String fullPath) {
  // Normalize path separators for Windows (convert / to \)
  String normalizedPath = fullPath;
  if (Platform.isWindows) {
    normalizedPath = fullPath.replaceAll('/', '\\');
  }
  final pathPtr = normalizedPath.toNativeUtf8().cast<Char>();
  try {
    return _bindings.comaps_register_single_map(pathPtr);
  } finally {
    malloc.free(pathPtr);
  }
}

/// Register a single MWM map file directly by full path, with an explicit
/// snapshot version (e.g. 251209).
///
/// This avoids the native side defaulting the LocalCountryFile version to 0,
/// which can cause `VersionTooOld (2)` for World/WorldCoasts and any region
/// where the engine expects a specific snapshot version.
int registerSingleMapWithVersion(String fullPath, int version) {
  String normalizedPath = fullPath;
  if (Platform.isWindows) {
    normalizedPath = fullPath.replaceAll('/', '\\');
  }
  final pathPtr = normalizedPath.toNativeUtf8().cast<Char>();
  try {
    try {
      return _bindings.comaps_register_single_map_with_version(
          pathPtr, version);
    } on ArgumentError {
      // Symbol may not exist on some platforms/binaries. Fall back to legacy API.
      return _bindings.comaps_register_single_map(pathPtr);
    }
  } finally {
    malloc.free(pathPtr);
  }
}

/// Debug: List all registered MWMs and their bounds.
/// Output goes to Android logcat (tag: AgusMapsFlutterNative).
void debugListMwms() {
  _bindings.comaps_debug_list_mwms();
}

/// Debug: Check if a lat/lon point is covered by any registered MWM.
/// Output goes to Android logcat (tag: AgusMapsFlutterNative).
///
/// Use this to verify that a specific location (like Manila) is covered
/// by one of the registered MWM files.
void debugCheckPoint(double lat, double lon) {
  _bindings.comaps_debug_check_point(lat, lon);
}

void setView(double lat, double lon, int zoom) {
  _bindings.comaps_set_view(lat, lon, zoom);
}

/// Return the current native viewport center, or null if the map is not ready.
({double lat, double lon})? getViewportCenter() {
  final latPtr = calloc<Double>();
  final lonPtr = calloc<Double>();
  try {
    final result = _bindings.comaps_get_viewport_center(latPtr, lonPtr);
    if (result == 0) {
      return null;
    }
    return (lat: latPtr.value, lon: lonPtr.value);
  } finally {
    calloc.free(latPtr);
    calloc.free(lonPtr);
  }
}

/// Return the current native draw scale/zoom, or null if unavailable.
int? getCurrentZoom() {
  final zoom = _bindings.comaps_get_current_zoom();
  return zoom < 0 ? null : zoom;
}

/// Return the current native camera state, or null if the map is not ready.
MapCameraPosition? getCameraPosition() {
  final center = getViewportCenter();
  final zoom = getCurrentZoom();
  if (center == null || zoom == null) {
    return null;
  }
  return MapCameraPosition(
    lat: center.lat,
    lon: center.lon,
    zoom: zoom,
    bearing: getCurrentBearing(),
  );
}

/// Return the current native camera state, or null if the map is not ready.
MapCameraPosition? getMapCameraPosition() => getCameraPosition();

/// Converts physical screen coordinates to a WGS84 coordinate.
///
/// The coordinates must be in the native map surface's physical pixel space.
/// Flutter overlays should multiply logical local positions by the device pixel
/// ratio before calling this helper.
AgusLatLon? screenPointToLatLon(double physicalX, double physicalY) {
  if (!(Platform.isMacOS ||
      Platform.isIOS ||
      Platform.isAndroid ||
      Platform.isWindows ||
      Platform.isLinux)) {
    throw UnsupportedError(
      'Screen-to-coordinate projection is currently wired on desktop, Apple, and Android only',
    );
  }

  final latPtr = malloc<Double>();
  final lonPtr = malloc<Double>();
  try {
    final result = _bindings.comaps_screen_to_latlon(
      physicalX,
      physicalY,
      latPtr,
      lonPtr,
    );
    if (result != 1) return null;
    return AgusLatLon(lat: latPtr.value, lon: lonPtr.value);
  } finally {
    malloc.free(latPtr);
    malloc.free(lonPtr);
  }
}

/// Converts a WGS84 coordinate to physical screen coordinates.
///
/// The returned offset is in the native map surface's physical pixel space.
/// Flutter overlays should divide it by the device pixel ratio before using it
/// as a logical local position.
Offset? latLonToScreenPoint(double lat, double lon) {
  if (!(Platform.isMacOS ||
      Platform.isIOS ||
      Platform.isAndroid ||
      Platform.isWindows ||
      Platform.isLinux)) {
    throw UnsupportedError(
      'Coordinate-to-screen projection is currently wired on desktop, Apple, and Android only',
    );
  }

  final xPtr = malloc<Double>();
  final yPtr = malloc<Double>();
  try {
    final result = _bindings.comaps_latlon_to_screen(
      lat,
      lon,
      xPtr,
      yPtr,
    );
    if (result != 1) return null;
    return Offset(xPtr.value, yPtr.value);
  } finally {
    malloc.free(xPtr);
    malloc.free(yPtr);
  }
}

/// Zoom in by one native step, centered on the viewport.
void zoomInMap({bool animated = true}) {
  _bindings.comaps_zoom_in(animated ? 1 : 0);
}

/// Zoom in by one native step, centered on the viewport.
void zoomIn({bool animated = true}) => zoomInMap(animated: animated);

/// Zoom out by one native step, centered on the viewport.
void zoomOutMap({bool animated = true}) {
  _bindings.comaps_zoom_out(animated ? 1 : 0);
}

/// Zoom out by one native step, centered on the viewport.
void zoomOut({bool animated = true}) => zoomOutMap(animated: animated);

/// Return the current bearing in degrees where 0 is north-up.
double getCurrentBearing() {
  return _bindings.comaps_get_current_bearing();
}

/// Rotate the map to [degrees], where 0 is north-up.
void setMapBearing(double degrees, {bool animated = true}) {
  _bindings.comaps_set_bearing(degrees, animated ? 1 : 0);
}

/// Rotate the map to [degrees], where 0 is north-up.
void setBearing(double degrees, {bool animated = true}) {
  setMapBearing(degrees, animated: animated);
}

/// Reset the map bearing to north-up.
void resetMapBearing({bool animated = true}) {
  _bindings.comaps_reset_bearing(animated ? 1 : 0);
}

/// Reset the map bearing to north-up.
void resetBearing({bool animated = true}) {
  resetMapBearing(animated: animated);
}

/// Enable or disable 3D buildings and 3D map mode.
void set3dBuildingsEnabled(bool enabled) {
  _bindings.comaps_set_3d_buildings_enabled(enabled ? 1 : 0);
}

/// Return whether 3D buildings were enabled through this plugin API.
bool get3dBuildingsEnabled() {
  return _bindings.comaps_get_3d_buildings_enabled() != 0;
}

/// Apply a resolved light or dark native map theme.
void setMapTheme(MapThemeMode theme) {
  _bindings.comaps_set_map_theme(theme == MapThemeMode.dark ? 1 : 0);
}

/// Return the currently active native map theme.
MapThemeMode getMapTheme() {
  return _bindings.comaps_get_map_theme_is_dark() != 0
      ? MapThemeMode.dark
      : MapThemeMode.light;
}

/// Enable or disable the outdoors map style layer.
void setOutdoorsEnabled(bool enabled) {
  _bindings.comaps_set_outdoors_enabled(enabled ? 1 : 0);
}

/// Enable or disable contour lines.
void setIsolinesEnabled(bool enabled) {
  _bindings.comaps_set_isolines_enabled(enabled ? 1 : 0);
}

/// Enable or disable the subway/transit layer.
void setSubwayEnabled(bool enabled) {
  _bindings.comaps_set_subway_enabled(enabled ? 1 : 0);
}

/// Apply CoMaps layer state.
///
/// Subway/transit is mutually exclusive with outdoors and isolines, matching
/// CoMaps mobile behavior. When [state.subway] is true, outdoors and isolines
/// are disabled even if their fields are also true.
void setMapLayerState(MapLayerState state) {
  if (state.subway) {
    setOutdoorsEnabled(false);
    setIsolinesEnabled(false);
    setSubwayEnabled(true);
    return;
  }

  setSubwayEnabled(false);
  setOutdoorsEnabled(state.outdoors);
  setIsolinesEnabled(state.isolines);
}

/// Return the currently active CoMaps layer state.
MapLayerState getMapLayerState() {
  final outdoorsPtr = calloc<Int>();
  final isolinesPtr = calloc<Int>();
  final subwayPtr = calloc<Int>();
  try {
    _bindings.comaps_get_map_layer_state(
      outdoorsPtr,
      isolinesPtr,
      subwayPtr,
    );
    return MapLayerState(
      outdoors: outdoorsPtr.value != 0,
      isolines: isolinesPtr.value != 0,
      subway: subwayPtr.value != 0,
    );
  } finally {
    calloc.free(outdoorsPtr);
    calloc.free(isolinesPtr);
    calloc.free(subwayPtr);
  }
}

/// Set map label language.
///
/// Pass null or an empty string for automatic language selection. Pass
/// `'default'` for local/native place names, or a language code such as `en`,
/// `es`, `de`, `fr`, `ja`, or `zh` for a specific map label language.
void setMapLanguage(String? languageCode) {
  final normalizedCode = languageCode?.trim() ?? '';
  final languageCodePtr = normalizedCode.toNativeUtf8().cast<Char>();
  try {
    _bindings.comaps_set_map_language(languageCodePtr);
  } finally {
    malloc.free(languageCodePtr);
  }
}

/// Request a native renderer refresh for the current viewport.
///
/// Call this after registering maps to make the native renderer process pending
/// map data without recreating the Flutter texture.
void invalidateMap() {
  _bindings.comaps_invalidate();
}

/// Force a complete redraw by updating the map style.
///
/// This clears all render groups and forces the BackendRenderer to re-request
/// all tiles from scratch. Use this after registering map files to ensure
/// tiles are loaded for newly registered regions.
///
/// This is more heavy-handed than [invalidateMap] and should be called when
/// maps are registered AFTER the DrapeEngine has been initialized, as the
/// engine may have already calculated tile coverage before the maps were
/// available.
void forceRedraw() {
  _bindings.comaps_force_redraw();
}

/// Touch event types
enum TouchType {
  none, // 0
  down, // 1
  move, // 2
  up, // 3
  cancel, // 4
}

/// Send a touch event to the map engine.
///
/// [type] is the touch event type (down, move, up, cancel).
/// [id1], [x1], [y1] are the first pointer's ID and coordinates.
/// [id2], [x2], [y2] are the second pointer's data (use -1 for id2 if single touch).
void sendTouchEvent(
  TouchType type,
  int id1,
  double x1,
  double y1, {
  int id2 = -1,
  double x2 = 0,
  double y2 = 0,
}) {
  _bindings.comaps_touch(type.index, id1, x1, y1, id2, x2, y2);
}

/// Scale (zoom) the map by a factor, centered on a specific pixel point.
///
/// [factor] is the zoom factor (>1 zooms in, <1 zooms out).
/// Use `exp(scrollDelta)` for smooth Google Maps-like scrolling.
/// [pixelX], [pixelY] are the screen coordinates to zoom towards (in physical pixels).
/// [animated] controls whether to animate the zoom transition.
///
/// This is the preferred method for scroll wheel zoom on desktop platforms,
/// matching the behavior of the Qt implementation.
void scaleMap(
  double factor,
  double pixelX,
  double pixelY, {
  bool animated = false,
}) {
  _bindings.comaps_scale(factor, pixelX, pixelY, animated ? 1 : 0);
}

/// Scroll/pan the map by pixel distance.
///
/// [distanceX], [distanceY] are the distances to scroll in physical pixels.
void scrollMap(double distanceX, double distanceY) {
  _bindings.comaps_scroll(distanceX, distanceY);
}

/// Create a map rendering surface with the given dimensions.
/// If width/height are not specified, uses the screen size.
/// [density] is the device pixel ratio (e.g., 1.5 for 150% scaling on Windows).
Future<int> createMapSurface({int? width, int? height, double? density}) async {
  final request = CreateMapSurfaceRequest(
    width: width,
    height: height,
    density: density,
  );
  return _hostApi.createMapSurface(request);
}

/// Resize the map surface to new dimensions.
///
/// [density] is optional; on Windows it updates visual scale when display DPI changes.
Future<void> resizeMapSurface(int width, int height, {double? density}) async {
  final request = ResizeMapSurfaceRequest(
    width: width,
    height: height,
    density: density,
  );
  await _hostApi.resizeMapSurface(request);
}

/// Destroy the active map surface if one exists.
Future<bool> destroyMapSurface() {
  return _hostApi.destroyMapSurface();
}

/// Controller for programmatic control of an AgusMap.
///
/// Use this to move the map, change zoom level, and other operations.
class AgusMapController {
  /// Move the map to the specified coordinates and zoom level.
  ///
  /// [lat] and [lon] specify the center point in WGS84 coordinates.
  /// [zoom] is the zoom level (typically 0-20, where higher is more zoomed in).
  void moveToLocation(double lat, double lon, int zoom) {
    setView(lat, lon, zoom);
  }

  /// Animate the map to the specified coordinates.
  /// Currently this is the same as moveToLocation; animation support
  /// will be added in a future version.
  void animateToLocation(double lat, double lon, int zoom) {
    // TODO: Implement animated camera movement
    setView(lat, lon, zoom);
  }

  /// Zoom in by one native step.
  void zoomIn({bool animated = true}) {
    zoomInMap(animated: animated);
  }

  /// Zoom out by one native step.
  void zoomOut({bool animated = true}) {
    zoomOutMap(animated: animated);
  }

  /// Return the latest camera state reported by native code.
  MapCameraPosition? getCameraPosition() {
    return getMapCameraPosition();
  }

  /// Rotate the map to [degrees], where 0 is north-up.
  void setBearing(double degrees, {bool animated = true}) {
    setMapBearing(degrees, animated: animated);
  }

  /// Reset the map bearing to north-up.
  void resetBearing({bool animated = true}) {
    resetMapBearing(animated: animated);
  }
}

/// Controls how [AgusMap] reacts to Flutter layout size changes.
enum AgusMapResizePolicy {
  /// Preserve the native map surface during mobile keyboard occlusion.
  ///
  /// This keeps the renderer stable while search fields, result panels, and
  /// keyboards are layered above the map. Real viewport changes such as
  /// rotation, split-screen resizing, and device-pixel-ratio changes still
  /// resize the surface.
  stableViewport,

  /// Resize the native map surface whenever Flutter layout constraints change.
  resizeWithLayout,
}

/// A Flutter widget that displays a CoMaps map.
///
/// The widget handles initialization, sizing, and gesture events.
class AgusMap extends StatefulWidget {
  /// Initial latitude for the map center.
  final double? initialLat;

  /// Initial longitude for the map center.
  final double? initialLon;

  /// Initial zoom level (0-20).
  final int? initialZoom;

  /// Callback when the map is ready.
  final VoidCallback? onMapReady;

  /// Callback when a place page (POI) is available after a tap.
  ///
  /// The callback receives null if no place page is available.
  final ValueChanged<PlacePageData?>? onPlacePage;

  /// Observes map taps before place-page lookup.
  ///
  /// Return true when an editor consumes the tap, such as adding a sketch
  /// vertex. Drag gestures still go to the native map unless a pointer-down
  /// callback captures a specific pointer.
  final bool Function(Offset localPosition)? onMapTap;

  /// Optional pointer-down hook for map-native editors.
  ///
  /// Return true to capture this pointer and prevent CoMaps from using it for
  /// pan/zoom until the matching up/cancel event.
  final bool Function(Offset localPosition)? onMapPointerDown;

  /// Receives moves for pointers captured by [onMapPointerDown].
  final void Function(Offset localPosition)? onMapPointerMove;

  /// Receives up/cancel for pointers captured by [onMapPointerDown].
  final void Function(Offset localPosition)? onMapPointerUp;

  /// Controller for programmatic map control.
  /// If not provided, the map can only be controlled via gestures.
  final AgusMapController? controller;

  /// Whether the map is currently visible.
  ///
  /// When false, resize operations are skipped to avoid unnecessary
  /// memory allocations (e.g., CVPixelBuffer recreation on iOS).
  /// This is important when using IndexedStack where the map widget
  /// remains in the tree but is not visible.
  ///
  /// The resize will be applied when the map becomes visible again.
  final bool isVisible;

  /// User-defined scale multiplier for labels/icons.
  ///
  /// This does not change zoom; it adjusts visual scale only.
  final double userScale;

  /// Policy for native surface resizing when Flutter layout changes.
  final AgusMapResizePolicy resizePolicy;

  const AgusMap({
    super.key,
    this.initialLat,
    this.initialLon,
    this.initialZoom,
    this.onMapReady,
    this.onPlacePage,
    this.onMapTap,
    this.onMapPointerDown,
    this.onMapPointerMove,
    this.onMapPointerUp,
    this.controller,
    this.isVisible = true,
    this.userScale = 1.0,
    this.resizePolicy = AgusMapResizePolicy.stableViewport,
  });

  @override
  State<AgusMap> createState() => _AgusMapState();
}

class _TapState {
  final Offset startPosition;
  final Duration startTime;
  bool moved = false;

  _TapState(this.startPosition, this.startTime);
}

class _AgusMapState extends State<AgusMap> with WidgetsBindingObserver {
  static int? _sharedTextureId;
  static Size? _sharedLogicalSize;
  static int? _sharedPhysicalWidth;
  static int? _sharedPhysicalHeight;
  static double _sharedDevicePixelRatio = 1.0;
  static double _sharedUserScale = 1.0;
  static double _sharedVisualScale = 1.0;
  static bool _sharedNativeInitialized = false;
  static bool _sharedReadyCallbackDelivered = false;

  int? _textureId;
  Size? _currentSize; // Logical size
  int? _currentPhysicalWidth;
  int? _currentPhysicalHeight;
  bool _surfaceCreated = false;
  double _devicePixelRatio = 1.0;
  double _userScale = 1.0;
  double _visualScale = 1.0;
  double _lastPanZoomRotation = 0.0;
  double _lastPanZoomBearing = 0.0;

  // Track pending resize to apply when becoming visible
  Size? _pendingResizeSize;
  double? _pendingResizePixelRatio;
  double? _pendingResizeUserScale;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _scheduleMetricsResize();
  }

  void _scheduleMetricsResize() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final renderObject = context.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) return;

      final size = renderObject.size;
      if (size.width <= 0 || size.height <= 0) return;

      final resizeSize = _effectiveResizeSize(size);
      final pixelRatio = View.of(context).devicePixelRatio;
      final userScale = widget.userScale;

      if (!_surfaceCreated) {
        if (widget.isVisible) {
          _createSurface(resizeSize, pixelRatio, userScale);
        } else {
          _pendingResizeSize = resizeSize;
          _pendingResizePixelRatio = pixelRatio;
          _pendingResizeUserScale = userScale;
        }
        return;
      }

      if (_currentSize == resizeSize &&
          _devicePixelRatio == pixelRatio &&
          _userScale == userScale) {
        return;
      }

      if (widget.isVisible) {
        _handleResize(resizeSize, pixelRatio, userScale);
      } else {
        _pendingResizeSize = resizeSize;
        _pendingResizePixelRatio = pixelRatio;
        _pendingResizeUserScale = userScale;
      }
    });
  }

  @override
  void didUpdateWidget(AgusMap oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Apply pending resize when becoming visible
    if (widget.isVisible && !oldWidget.isVisible) {
      if (_pendingResizeSize != null && _pendingResizePixelRatio != null) {
        debugPrint('[AgusMap] Applying deferred resize on visibility change');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handleResize(
            _pendingResizeSize!,
            _pendingResizePixelRatio!,
            _pendingResizeUserScale ?? widget.userScale,
          );
          _pendingResizeSize = null;
          _pendingResizePixelRatio = null;
          _pendingResizeUserScale = null;
        });
      }
    }
  }

  Future<void> _createSurface(
    Size logicalSize,
    double pixelRatio,
    double userScale,
  ) async {
    if (_surfaceCreated) return;
    if (_sharedTextureId != null) {
      _attachSharedSurface(logicalSize, pixelRatio, userScale);
      return;
    }

    _surfaceCreated = true;
    _devicePixelRatio = pixelRatio;
    _userScale = userScale;

    // Convert logical pixels to physical pixels for crisp rendering
    final physicalWidth = Platform.isWindows
        ? (logicalSize.width * pixelRatio).round()
        : (logicalSize.width * pixelRatio).toInt();
    final physicalHeight = Platform.isWindows
        ? (logicalSize.height * pixelRatio).round()
        : (logicalSize.height * pixelRatio).toInt();

    final visualScale = pixelRatio * userScale;
    _currentPhysicalWidth = physicalWidth;
    _currentPhysicalHeight = physicalHeight;
    _visualScale = visualScale;
    if (kDebugMode) {
      debugPrint(
        '[AgusMap] Creating surface: ${logicalSize.width.toInt()}x${logicalSize.height.toInt()} logical, ${physicalWidth}x$physicalHeight physical (ratio: $pixelRatio, userScale: ${userScale.toStringAsFixed(2)}, visual: ${visualScale.toStringAsFixed(3)})',
      );
      if (Platform.isWindows) {
        debugPrint(
          '[AgusMap] Windows DPR diagnostic: logical=${logicalSize.width.toStringAsFixed(2)}x${logicalSize.height.toStringAsFixed(2)} '
          'dpr=${pixelRatio.toStringAsFixed(3)} userScale=${userScale.toStringAsFixed(2)} physical=${physicalWidth}x$physicalHeight',
        );
      }
    }

    final textureId = await createMapSurface(
      width: physicalWidth,
      height: physicalHeight,
      density: visualScale,
    );

    _sharedTextureId = textureId;
    _sharedLogicalSize = logicalSize;
    _sharedPhysicalWidth = physicalWidth;
    _sharedPhysicalHeight = physicalHeight;
    _sharedDevicePixelRatio = pixelRatio;
    _sharedUserScale = userScale;
    _sharedVisualScale = visualScale;

    // Set initial view if specified
    if (widget.initialLat != null && widget.initialLon != null) {
      setView(widget.initialLat!, widget.initialLon!, widget.initialZoom ?? 14);
    }
    _sharedNativeInitialized = true;

    if (!mounted) return;

    setState(() {
      _textureId = textureId;
      _currentSize = logicalSize;
    });

    _notifyMapReadyOnce();
  }

  void _attachSharedSurface(
    Size logicalSize,
    double pixelRatio,
    double userScale,
  ) {
    final textureId = _sharedTextureId;
    if (textureId == null) return;

    _surfaceCreated = true;
    _textureId = textureId;
    _currentSize = _sharedLogicalSize;
    _currentPhysicalWidth = _sharedPhysicalWidth;
    _currentPhysicalHeight = _sharedPhysicalHeight;
    _devicePixelRatio = _sharedDevicePixelRatio;
    _userScale = _sharedUserScale;
    _visualScale = _sharedVisualScale;

    if (mounted) {
      setState(() {});
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.isVisible) return;
      _handleResize(logicalSize, pixelRatio, userScale);
      if (_sharedNativeInitialized) {
        _notifyMapReadyOnce();
      }
    });
  }

  void _notifyMapReadyOnce() {
    if (_sharedReadyCallbackDelivered) return;
    _sharedReadyCallbackDelivered = true;
    widget.onMapReady?.call();
  }

  Future<void> _handleResize(
    Size newLogicalSize,
    double pixelRatio,
    double userScale,
  ) async {
    if (_currentSize == newLogicalSize &&
        _devicePixelRatio == pixelRatio &&
        _userScale == userScale) {
      return;
    }
    if (_textureId == null) return;

    // Convert logical pixels to physical pixels
    final physicalWidth = Platform.isWindows
        ? (newLogicalSize.width * pixelRatio).round()
        : (newLogicalSize.width * pixelRatio).toInt();
    final physicalHeight = Platform.isWindows
        ? (newLogicalSize.height * pixelRatio).round()
        : (newLogicalSize.height * pixelRatio).toInt();

    if (physicalWidth <= 0 || physicalHeight <= 0) return;

    final visualScale = pixelRatio * userScale;
    final sizeUnchanged = physicalWidth == _currentPhysicalWidth &&
        physicalHeight == _currentPhysicalHeight;
    final scaleUnchanged = _sameVisualScale(visualScale, _visualScale);

    _currentSize = newLogicalSize;
    _currentPhysicalWidth = physicalWidth;
    _currentPhysicalHeight = physicalHeight;
    _devicePixelRatio = pixelRatio;
    _userScale = userScale;
    _visualScale = visualScale;
    _sharedLogicalSize = newLogicalSize;
    _sharedPhysicalWidth = physicalWidth;
    _sharedPhysicalHeight = physicalHeight;
    _sharedDevicePixelRatio = pixelRatio;
    _sharedUserScale = userScale;
    _sharedVisualScale = visualScale;

    if (sizeUnchanged && scaleUnchanged) {
      return;
    }

    if (kDebugMode) {
      debugPrint(
        '[AgusMap] Resizing: ${newLogicalSize.width.toInt()}x${newLogicalSize.height.toInt()} logical, ${physicalWidth}x$physicalHeight physical (ratio: $pixelRatio, userScale: ${userScale.toStringAsFixed(2)}, visual: ${visualScale.toStringAsFixed(3)})',
      );
      if (Platform.isWindows) {
        debugPrint(
          '[AgusMap] Windows DPR diagnostic (resize): logical=${newLogicalSize.width.toStringAsFixed(2)}x${newLogicalSize.height.toStringAsFixed(2)} '
          'dpr=${pixelRatio.toStringAsFixed(3)} userScale=${userScale.toStringAsFixed(2)} physical=${physicalWidth}x$physicalHeight',
        );
      }
    }

    await resizeMapSurface(physicalWidth, physicalHeight, density: visualScale);

    if (mounted) {
      setState(() {});
    }
  }

  bool _sameVisualScale(double left, double right) {
    return (left - right).abs() < 0.0001;
  }

  bool _preservesViewportDuringKeyboard() {
    return widget.resizePolicy == AgusMapResizePolicy.stableViewport &&
        (Platform.isAndroid || Platform.isIOS);
  }

  Size _effectiveResizeSize(Size layoutSize) {
    if (!_preservesViewportDuringKeyboard()) return layoutSize;

    final currentSize = _currentSize;
    if (currentSize == null) return layoutSize;

    final keyboardVisible = View.of(context).viewInsets.bottom > 0;
    if (!keyboardVisible) return layoutSize;

    final sameWidth = (layoutSize.width - currentSize.width).abs() < 0.5;
    final heightShrank = layoutSize.height < currentSize.height;
    if (sameWidth && heightShrank) {
      return currentSize;
    }

    return layoutSize;
  }

  // Track active pointers for multitouch
  final Map<int, Offset> _activePointers = {};
  final Map<int, _TapState> _tapStates = {};
  final Set<int> _editorCapturedPointers = <int>{};
  bool _hadMultiplePointers = false;

  static const double _tapSlop = 8.0;
  static const Duration _tapTimeout = Duration(milliseconds: 350);

  void _handlePointerDown(PointerDownEvent event) {
    if (widget.onMapPointerDown?.call(event.localPosition) ?? false) {
      _editorCapturedPointers.add(event.pointer);
      return;
    }

    _activePointers[event.pointer] = event.localPosition;
    _tapStates[event.pointer] = _TapState(event.localPosition, event.timeStamp);
    if (_activePointers.length > 1) {
      _hadMultiplePointers = true;
    }
    _sendTouchEvent(TouchType.down, event.pointer, event.localPosition);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_editorCapturedPointers.contains(event.pointer)) {
      widget.onMapPointerMove?.call(event.localPosition);
      return;
    }

    _activePointers[event.pointer] = event.localPosition;
    final tap = _tapStates[event.pointer];
    if (tap != null) {
      final distance = (event.localPosition - tap.startPosition).distance;
      if (distance > _tapSlop) {
        tap.moved = true;
      }
    }
    _sendTouchEvent(TouchType.move, event.pointer, event.localPosition);
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (_editorCapturedPointers.remove(event.pointer)) {
      widget.onMapPointerUp?.call(event.localPosition);
      return;
    }

    _sendTouchEvent(TouchType.up, event.pointer, event.localPosition);
    final tap = _tapStates.remove(event.pointer);
    _activePointers.remove(event.pointer);

    if (_activePointers.isEmpty) {
      if (tap != null &&
          !tap.moved &&
          !_hadMultiplePointers &&
          (event.timeStamp - tap.startTime) <= _tapTimeout) {
        final consumed = widget.onMapTap?.call(tap.startPosition) ?? false;
        if (!consumed) {
          _emitPlacePageIfAvailable();
        }
      }
      _hadMultiplePointers = false;
      _tapStates.clear();
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (_editorCapturedPointers.remove(event.pointer)) {
      widget.onMapPointerUp?.call(event.localPosition);
      return;
    }

    _sendTouchEvent(TouchType.cancel, event.pointer, event.localPosition);
    _activePointers.remove(event.pointer);
    _tapStates.remove(event.pointer);
    if (_activePointers.isEmpty) {
      _hadMultiplePointers = false;
      _tapStates.clear();
    }
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) return;
    if (_activePointers.isNotEmpty) {
      return; // don't interfere with real drag/pinch
    }

    if (event is PointerScrollEvent) {
      // Use direct scale API similar to Qt CoMaps implementation
      // Qt uses: factor = angleDelta.y() / 3.0 / 360.0, then exp(factor)
      // Flutter's scrollDelta.dy is typically ~100 per notch (platform-dependent)
      // We tune the divisor for a good zoom feel similar to Google Maps
      final dy = event.scrollDelta.dy;

      // Calculate zoom factor - larger divisor = slower zoom
      // 3.0 * 360.0 = 1080 matches Qt behavior
      // We use a slightly smaller value for faster, more responsive zoom
      final factor = -dy / 600.0; // Negative because scroll down = zoom out

      // Convert logical position to physical pixels
      final pixelX = event.localPosition.dx * _devicePixelRatio;
      final pixelY = event.localPosition.dy * _devicePixelRatio;

      // Apply exponential zoom factor for smooth, proportional zooming
      // exp(factor) ensures zoom rate is consistent regardless of current zoom level
      scaleMap(exp(factor), pixelX, pixelY, animated: false);
    }
  }

  void _handlePointerPanZoomStart(PointerPanZoomStartEvent event) {
    if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) return;
    _lastPanZoomRotation = 0.0;
    _lastPanZoomBearing = getCurrentBearing();
  }

  void _handlePointerPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) return;

    final rotationDelta = event.rotation - _lastPanZoomRotation;
    _lastPanZoomRotation = event.rotation;
    if (rotationDelta.abs() < 0.0005) return;

    _lastPanZoomBearing = _normalizeBearingDegrees(
      _lastPanZoomBearing + rotationDelta * 180 / pi,
    );
    setMapBearing(_lastPanZoomBearing, animated: false);
  }

  void _handlePointerPanZoomEnd(PointerPanZoomEndEvent event) {
    if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) return;
    _lastPanZoomRotation = 0.0;
    _lastPanZoomBearing = getCurrentBearing();
  }

  double _normalizeBearingDegrees(double degrees) {
    final normalized = degrees % 360.0;
    return normalized < 0 ? normalized + 360.0 : normalized;
  }

  void _sendTouchEvent(TouchType type, int pointerId, Offset position) {
    // Use cached pixel ratio for coordinate conversion (matches surface dimensions)
    final pixelRatio = _devicePixelRatio;

    // Convert logical coordinates to physical pixels
    final x1 = position.dx * pixelRatio;
    final y1 = position.dy * pixelRatio;

    // Check for second pointer (multitouch)
    int id2 = -1;
    double x2 = 0;
    double y2 = 0;

    for (final entry in _activePointers.entries) {
      if (entry.key != pointerId) {
        id2 = entry.key;
        x2 = entry.value.dx * pixelRatio;
        y2 = entry.value.dy * pixelRatio;
        break;
      }
    }

    sendTouchEvent(type, pointerId, x1, y1, id2: id2, x2: x2, y2: y2);
  }

  void _emitPlacePageIfAvailable() {
    if (widget.onPlacePage == null) {
      return;
    }

    Future.delayed(const Duration(milliseconds: 60), () async {
      if (!mounted) return;
      final data = await getCurrentPlacePage();
      if (!mounted) return;
      widget.onPlacePage?.call(data);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth ||
            !constraints.hasBoundedHeight ||
            !constraints.maxWidth.isFinite ||
            !constraints.maxHeight.isFinite ||
            constraints.maxWidth <= 0 ||
            constraints.maxHeight <= 0) {
          return const SizedBox.shrink();
        }

        final layoutSize = Size(constraints.maxWidth, constraints.maxHeight);
        final resizeSize = _effectiveResizeSize(layoutSize);
        final pixelRatio = MediaQuery.of(context).devicePixelRatio;
        final userScale = widget.userScale;

        // Create surface on first layout (only if visible)
        if (!_surfaceCreated && resizeSize.width > 0 && resizeSize.height > 0) {
          if (widget.isVisible) {
            // Use post-frame callback to avoid calling during build
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _createSurface(resizeSize, pixelRatio, userScale);
            });
          }
        } else if (_surfaceCreated &&
            (_currentSize != resizeSize ||
                _devicePixelRatio != pixelRatio ||
                _userScale != userScale)) {
          // Handle resize or pixel ratio change
          if (widget.isVisible) {
            // Apply resize immediately when visible
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _handleResize(resizeSize, pixelRatio, userScale);
            });
          } else {
            // Defer resize until visible to avoid unnecessary memory allocations
            // (e.g., keyboard open/close causing CVPixelBuffer recreation on iOS)
            _pendingResizeSize = resizeSize;
            _pendingResizePixelRatio = pixelRatio;
            _pendingResizeUserScale = userScale;
          }
        }

        if (_textureId == null) {
          return const SizedBox.expand();
        }

        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _handlePointerDown,
          onPointerMove: _handlePointerMove,
          onPointerUp: _handlePointerUp,
          onPointerCancel: _handlePointerCancel,
          onPointerSignal: _handlePointerSignal,
          onPointerPanZoomStart: _handlePointerPanZoomStart,
          onPointerPanZoomUpdate: _handlePointerPanZoomUpdate,
          onPointerPanZoomEnd: _handlePointerPanZoomEnd,
          child: SizedBox(
            width: layoutSize.width,
            height: layoutSize.height,
            child: Texture(
              textureId: _textureId!,
              filterQuality:
                  Platform.isWindows ? FilterQuality.none : FilterQuality.low,
            ),
          ),
        );
      },
    );
  }
}

const String _libName = 'agus_maps_flutter';

/// The dynamic library in which the symbols for [AgusMapsFlutterBindings] can be found.
final DynamicLibrary _dylib = () {
  if (Platform.isMacOS) {
    return DynamicLibrary.open('$_libName.framework/$_libName');
  }
  if (Platform.isIOS) {
    // On iOS, the plugin is linked into the main executable
    // Use process() to look up symbols from the app itself
    return DynamicLibrary.process();
  }
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open('lib$_libName.so');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('$_libName.dll');
  }
  throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
}();

/// The bindings to the native functions in [_dylib].
final AgusMapsFlutterBindings _bindings = AgusMapsFlutterBindings(_dylib);

/// A request to compute `sum`.
///
/// Typically sent from one isolate to another.
class _SumRequest {
  final int id;
  final int a;
  final int b;

  const _SumRequest(this.id, this.a, this.b);
}

/// A response with the result of `sum`.
///
/// Typically sent from one isolate to another.
class _SumResponse {
  final int id;
  final int result;

  const _SumResponse(this.id, this.result);
}

/// Counter to identify [_SumRequest]s and [_SumResponse]s.
int _nextSumRequestId = 0;

/// Mapping from [_SumRequest] `id`s to the completers corresponding to the correct future of the pending request.
final Map<int, Completer<int>> _sumRequests = <int, Completer<int>>{};

/// The SendPort belonging to the helper isolate.
Future<SendPort> _helperIsolateSendPort = () async {
  // The helper isolate is going to send us back a SendPort, which we want to
  // wait for.
  final Completer<SendPort> completer = Completer<SendPort>();

  // Receive port on the main isolate to receive messages from the helper.
  // We receive two types of messages:
  // 1. A port to send messages on.
  // 2. Responses to requests we sent.
  final ReceivePort receivePort = ReceivePort()
    ..listen((dynamic data) {
      if (data is SendPort) {
        // The helper isolate sent us the port on which we can sent it requests.
        completer.complete(data);
        return;
      }
      if (data is _SumResponse) {
        // The helper isolate sent us a response to a request we sent.
        final Completer<int> completer = _sumRequests[data.id]!;
        _sumRequests.remove(data.id);
        completer.complete(data.result);
        return;
      }
      throw UnsupportedError('Unsupported message type: ${data.runtimeType}');
    });

  // Start the helper isolate.
  await Isolate.spawn((SendPort sendPort) async {
    final ReceivePort helperReceivePort = ReceivePort()
      ..listen((dynamic data) {
        // On the helper isolate listen to requests and respond to them.
        if (data is _SumRequest) {
          final int result = _bindings.sum_long_running(data.a, data.b);
          final _SumResponse response = _SumResponse(data.id, result);
          sendPort.send(response);
          return;
        }
        throw UnsupportedError('Unsupported message type: ${data.runtimeType}');
      });

    // Send the port to the main isolate on which we can receive requests.
    sendPort.send(helperReceivePort.sendPort);
  }, receivePort.sendPort);

  // Wait until the helper isolate has sent us back the SendPort on which we
  // can start sending requests.
  return completer.future;
}();
