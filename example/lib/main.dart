import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:agus_maps_flutter/agus_maps_flutter.dart' as agus_maps_flutter;
import 'package:agus_maps_flutter/mwm_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'about_tab.dart';
import 'downloads_cache.dart';
import 'downloads_tab.dart';
import 'features/map/widgets/adaptive_layer_manager.dart';
import 'features/workbench/vscode_workbench.dart';
import 'features/workbench/workbench_controller.dart';
import 'features/workbench/workbench_panels.dart';
import 'settings_tab.dart';
import 'place_page_sheet.dart';
import 'shared/adaptive/form_factor.dart';
import 'shared/layout/adaptive_app_scaffold.dart';

void main() {
  // Ensure Flutter bindings are initialized before using platform channels
  // (required for SharedPreferences, path_provider, etc.)
  WidgetsFlutterBinding.ensureInitialized();
  // NOTE: PlacePageLocalization has been removed. All localization is now
  // handled by native code via setLocale(). No Dart-side preloading needed.
  runApp(const MyApp());
}

/// A favorite location entry.
class FavoriteLocation {
  final String name;
  final double lat;
  final double lon;
  final int zoom;

  const FavoriteLocation({
    required this.name,
    required this.lat,
    required this.lon,
    required this.zoom,
  });
}

/// Hardcoded favorite locations.
const List<FavoriteLocation> kFavorites = [
  FavoriteLocation(
    name: 'Gibraltar',
    lat: 36.1407,
    lon: -5.3535,
    zoom: 14,
  ),
  FavoriteLocation(
    name: 'Philippines',
    lat: 11.840743046600755,
    lon: 123.11028882297192,
    zoom: 6,
  ),
];

enum MapSearchResultSource {
  native,
  coordinate,
  favorite,
}

class MapSearchResult {
  final String title;
  final String subtitle;
  final double lat;
  final double lon;
  final int zoom;
  final List<String> keywords;
  final MapSearchResultSource source;
  final int? nativeIndex;
  final bool isSuggestion;
  final String suggestion;

  const MapSearchResult({
    required this.title,
    required this.subtitle,
    required this.lat,
    required this.lon,
    required this.zoom,
    this.keywords = const [],
    this.source = MapSearchResultSource.favorite,
    this.nativeIndex,
    this.isSuggestion = false,
    this.suggestion = '',
  });

  bool get isNative => source == MapSearchResultSource.native;

  bool matches(List<String> terms) {
    final searchText = '$title $subtitle ${keywords.join(' ')}'.toLowerCase();
    return terms.every(searchText.contains);
  }

  int score(List<String> terms) {
    final normalizedTitle = title.toLowerCase();
    final normalizedSubtitle = subtitle.toLowerCase();
    final normalizedKeywords = keywords.join(' ').toLowerCase();
    var score = title.length;
    for (final term in terms) {
      if (normalizedTitle == term) {
        score -= 40;
      } else if (normalizedTitle.startsWith(term)) {
        score -= 25;
      } else if (normalizedTitle.contains(term)) {
        score -= 15;
      } else if (normalizedSubtitle.contains(term)) {
        score -= 8;
      } else if (normalizedKeywords.contains(term)) {
        score -= 4;
      }
    }
    return score;
  }
}

class _MapEditBanner extends StatelessWidget {
  const _MapEditBanner({
    required this.message,
    required this.isError,
  });

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background =
        isError ? colorScheme.errorContainer : colorScheme.primaryContainer;
    final foreground =
        isError ? colorScheme.onErrorContainer : colorScheme.onPrimaryContainer;

    return Align(
      alignment: Alignment.topLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(
              blurRadius: 12,
              color: Color(0x33000000),
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isError ? Icons.error_outline : Icons.open_with,
                size: 16,
                color: foreground,
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopActivityEmptyState extends StatelessWidget {
  const _DesktopActivityEmptyState({
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopSearchResultRow extends StatelessWidget {
  const _DesktopSearchResultRow({
    required this.result,
    required this.icon,
    required this.routeEnabled,
    required this.onTap,
    required this.onRoute,
  });

  final MapSearchResult result;
  final IconData icon;
  final bool routeEnabled;
  final VoidCallback onTap;
  final VoidCallback? onRoute;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: colorScheme.outlineVariant),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: 8, right: 2),
          child: Row(
            children: [
              Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.05),
                    ),
                    Text(
                      result.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        height: 1.05,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (onRoute != null)
                IconButton(
                  tooltip: 'Route',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  padding: EdgeInsets.zero,
                  iconSize: 16,
                  onPressed: routeEnabled ? onRoute : null,
                  icon: const Icon(Icons.alt_route),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopFavoriteRow extends StatelessWidget {
  const _DesktopFavoriteRow({
    required this.favorite,
    required this.onTap,
  });

  final FavoriteLocation favorite;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: colorScheme.outlineVariant),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Icon(
                Icons.location_on_outlined,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  favorite.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              Text(
                '${favorite.lat.toStringAsFixed(4)}, '
                '${favorite.lon.toStringAsFixed(4)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'z${favorite.zoom}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopStaticStatus extends StatelessWidget {
  const _DesktopStaticStatus({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 24, color: colorScheme.primary),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationFix {
  final double lat;
  final double lon;
  final int zoom;
  final String? message;

  const _LocationFix({
    required this.lat,
    required this.lon,
    required this.zoom,
    this.message,
  });
}

class _RouteDestination {
  final String title;
  final String subtitle;
  final double lat;
  final double lon;

  const _RouteDestination({
    required this.title,
    required this.subtitle,
    required this.lat,
    required this.lon,
  });
}

class _NavigationPlan {
  final _RouteDestination destination;
  final String startLabel;

  const _NavigationPlan({
    required this.destination,
    required this.startLabel,
  });
}

/// Default location when app starts.
///
/// Keep this inside the bundled Gibraltar map so a clean install does not ask
/// CoMaps to open country files that have not been downloaded yet.
const FavoriteLocation kDefaultLocation = FavoriteLocation(
  name: 'Gibraltar',
  lat: 36.1407,
  lon: -5.3535,
  zoom: 14,
);

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  String _status = 'Initializing...';
  String _debug = '';
  bool _dataReady = false;
  int _currentTabIndex = 0; // Start on Map tab
  double _mapScale = 1.0;
  ThemeMode _interfaceThemeMode = ThemeMode.system;
  agus_maps_flutter.MapAppearanceMode _mapAppearanceMode =
      agus_maps_flutter.MapAppearanceMode.system;
  String _mapLanguageCode = '';
  bool _buildings3dEnabled = false;
  agus_maps_flutter.MapLayerState _mapLayerState =
      const agus_maps_flutter.MapLayerState(
    outdoors: false,
    isolines: false,
    subway: false,
  );
  agus_maps_flutter.NavigationSettings _navigationSettings =
      const agus_maps_flutter.NavigationSettings();
  bool _nativeSurfaceReady = false;
  bool _isLocating = false;
  bool _searchOpen = false;
  final ValueNotifier<double> _currentBearing = ValueNotifier<double>(0.0);
  bool _reportedInvalidBearing = false;
  agus_maps_flutter.PlacePageData? _placePage;
  agus_maps_flutter.DuckDBLayerStore? _duckDBLayerStore;
  agus_maps_flutter.DuckDBLayerDrawController? _duckDBDrawController;
  String _activeDuckDBLayerId = _userDrawLayerId;
  String _duckDBLayerStoreStatus = 'DuckDB layer store is starting';
  final WorkbenchController _workbenchController = WorkbenchController();
  final GlobalKey _mapViewportKey = GlobalKey();
  bool _duckDBLayerPanelVisible = true;

  int? _bundledMwmVersion;
  String? _dataPath;
  Timer? _bearingTimer;
  Timer? _editHandleProjectionTimer;
  Timer? _searchDebounceTimer;
  Timer? _searchPollTimer;
  Timer? _navigationPollTimer;
  int _activeSearchGeneration = 0;
  DateTime? _activeSearchStartedAt;
  bool _nativeSearchRunning = false;
  bool _navigationActionInProgress = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<MapSearchResult> _searchResults = const [];
  _NavigationPlan? _navigationPlan;
  agus_maps_flutter.NavigationStatus? _navigationStatus;

  final agus_maps_flutter.AgusMapController _mapController =
      agus_maps_flutter.AgusMapController();

  static const String _userDrawLayerId = 'example_user_draw';

  // MWM storage for tracking downloaded maps
  MwmStorage? _mwmStorage;

  @override
  void initState() {
    super.initState();
    // Defer initialization to after the first frame is rendered.
    // This ensures Flutter platform channels (SharedPreferences, path_provider)
    // are fully registered before we try to use them. On Android with Impeller,
    // platform channels may not be ready during initState().
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _initData();
      _loadSettings();
    });
  }

  @override
  void dispose() {
    _bearingTimer?.cancel();
    _editHandleProjectionTimer?.cancel();
    _searchDebounceTimer?.cancel();
    _searchPollTimer?.cancel();
    _navigationPollTimer?.cancel();
    agus_maps_flutter.cancelNativeSearch();
    _currentBearing.dispose();
    _duckDBDrawController?.dispose();
    _workbenchController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  static const String _prefsKeyMapScale = 'map_scale_multiplier';
  static const String _prefsKeyInterfaceTheme = 'interface_theme_mode';
  static const String _prefsKeyMapAppearance = 'map_appearance_mode';
  static const String _prefsKeyMapLanguage = 'map_language_code';
  static const Duration _nativeSearchTimeout = Duration(seconds: 12);
  static const String _prefsKeyBuildings3d = 'buildings_3d_enabled';
  static const String _prefsKeyLayerOutdoors = 'layer_outdoors_enabled';
  static const String _prefsKeyLayerIsolines = 'layer_isolines_enabled';
  static const String _prefsKeyLayerSubway = 'layer_subway_enabled';
  static const String _prefsKeyNavigationUnits = 'navigation_units';
  static const String _prefsKeyNavigationVoice = 'navigation_voice_enabled';
  static const String _prefsKeyNavigationStreetNames =
      'navigation_street_names_enabled';
  static const String _prefsKeyNavigationSpeedLimit =
      'navigation_speed_limit_enabled';
  static const String _prefsKeyNavigationSpeedCameras =
      'navigation_speed_camera_mode';
  static const String _prefsKeyNavigationAvoidTolls = 'navigation_avoid_tolls';
  static const String _prefsKeyNavigationAvoidMotorways =
      'navigation_avoid_motorways';
  static const String _prefsKeyNavigationAvoidFerries =
      'navigation_avoid_ferries';
  static const String _prefsKeyNavigationAvoidUnpaved =
      'navigation_avoid_unpaved';

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final scale = prefs.getDouble(_prefsKeyMapScale) ?? 1.0;
      final interfaceTheme = _themeModeFromName(
        prefs.getString(_prefsKeyInterfaceTheme),
      );
      final mapAppearance = _mapAppearanceFromName(
        prefs.getString(_prefsKeyMapAppearance),
      );
      final mapLanguage = prefs.getString(_prefsKeyMapLanguage) ?? '';
      final buildings3d = prefs.getBool(_prefsKeyBuildings3d) ?? false;
      final layers = agus_maps_flutter.MapLayerState(
        outdoors: prefs.getBool(_prefsKeyLayerOutdoors) ?? false,
        isolines: prefs.getBool(_prefsKeyLayerIsolines) ?? false,
        subway: prefs.getBool(_prefsKeyLayerSubway) ?? false,
      );
      final navigationSettings = agus_maps_flutter.NavigationSettings(
        measurementUnits: _navigationUnitsFromName(
          prefs.getString(_prefsKeyNavigationUnits),
        ),
        turnNotificationsEnabled:
            prefs.getBool(_prefsKeyNavigationVoice) ?? true,
        announceStreetNames:
            prefs.getBool(_prefsKeyNavigationStreetNames) ?? true,
        showSpeedLimit: prefs.getBool(_prefsKeyNavigationSpeedLimit) ?? true,
        speedCameraMode: _speedCameraModeFromName(
          prefs.getString(_prefsKeyNavigationSpeedCameras),
        ),
        routingOptions: agus_maps_flutter.NavigationRoutingOptions(
          avoidTolls: prefs.getBool(_prefsKeyNavigationAvoidTolls) ?? false,
          avoidMotorways:
              prefs.getBool(_prefsKeyNavigationAvoidMotorways) ?? false,
          avoidFerries: prefs.getBool(_prefsKeyNavigationAvoidFerries) ?? false,
          avoidUnpavedRoads:
              prefs.getBool(_prefsKeyNavigationAvoidUnpaved) ?? false,
        ),
      );
      if (!mounted) return;
      setState(() {
        _mapScale = scale;
        _interfaceThemeMode = interfaceTheme;
        _mapAppearanceMode = mapAppearance;
        _mapLanguageCode = mapLanguage;
        _buildings3dEnabled = buildings3d;
        _mapLayerState = layers;
        _navigationSettings = navigationSettings;
      });
      _applyNativeMapSettings();
      _applyNativeNavigationSettings();
    } catch (e) {
      _log('Warning: Failed to load settings: $e');
    }
  }

  ThemeMode _themeModeFromName(String? value) {
    return ThemeMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => ThemeMode.system,
    );
  }

  agus_maps_flutter.MapAppearanceMode _mapAppearanceFromName(String? value) {
    return agus_maps_flutter.MapAppearanceMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => agus_maps_flutter.MapAppearanceMode.system,
    );
  }

  agus_maps_flutter.NavigationMeasurementUnits _navigationUnitsFromName(
    String? value,
  ) {
    return agus_maps_flutter.NavigationMeasurementUnits.values.firstWhere(
      (units) => units.name == value,
      orElse: () => agus_maps_flutter.NavigationMeasurementUnits.metric,
    );
  }

  agus_maps_flutter.NavigationSpeedCameraMode _speedCameraModeFromName(
    String? value,
  ) {
    return agus_maps_flutter.NavigationSpeedCameraMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => agus_maps_flutter.NavigationSpeedCameraMode.auto,
    );
  }

  agus_maps_flutter.MapThemeMode _resolveMapTheme() {
    switch (_mapAppearanceMode) {
      case agus_maps_flutter.MapAppearanceMode.light:
        return agus_maps_flutter.MapThemeMode.light;
      case agus_maps_flutter.MapAppearanceMode.dark:
        return agus_maps_flutter.MapThemeMode.dark;
      case agus_maps_flutter.MapAppearanceMode.system:
        final brightness = ui.PlatformDispatcher.instance.platformBrightness;
        return brightness == Brightness.dark
            ? agus_maps_flutter.MapThemeMode.dark
            : agus_maps_flutter.MapThemeMode.light;
    }
  }

  void _applyNativeMapSettings() {
    if (!_nativeSurfaceReady) return;
    agus_maps_flutter.set3dBuildingsEnabled(_buildings3dEnabled);
    agus_maps_flutter.setMapTheme(_resolveMapTheme());
    agus_maps_flutter.setMapLanguage(_mapLanguageCode);
    agus_maps_flutter.setMapLayerState(_mapLayerState);
  }

  void _applyNativeNavigationSettings() {
    if (!_nativeSurfaceReady) return;
    agus_maps_flutter.applyNavigationSettings(
      _navigationSettings,
      turnLocale: ui.PlatformDispatcher.instance.locale.toLanguageTag(),
    );
  }

  Future<void> _previewRouteToPlace(
    agus_maps_flutter.PlacePageData place,
  ) async {
    await _previewRouteToDestination(
      _RouteDestination(
        title: place.title.isNotEmpty ? place.title : 'Map point',
        subtitle: place.address.isNotEmpty ? place.address : place.subtitle,
        lat: place.lat,
        lon: place.lon,
      ),
    );
  }

  Future<void> _previewRouteToSearchResult(MapSearchResult result) async {
    if (result.isSuggestion) return;
    await _previewRouteToDestination(
      _RouteDestination(
        title: result.title,
        subtitle: result.subtitle,
        lat: result.lat,
        lon: result.lon,
      ),
    );
  }

  Future<void> _previewRouteToDestination(
    _RouteDestination destination,
  ) async {
    if (!_nativeSurfaceReady) {
      _showMapMessage('Map is still starting.');
      return;
    }
    if (_navigationActionInProgress) return;
    if (!_isValidCoordinate(destination.lat, destination.lon)) {
      _showMapMessage('This place does not have routeable coordinates.');
      return;
    }

    setState(() {
      _navigationActionInProgress = true;
    });

    try {
      _applyNativeNavigationSettings();
      final start = _routePreviewStart(destination);
      final startLabel = _routeStartLabel(start, destination);

      agus_maps_flutter.closeNavigationRoute(removeRoutePoints: true);
      agus_maps_flutter.clearNavigationRoutePoints();
      agus_maps_flutter.setNavigationRouter(
        agus_maps_flutter.NavigationRouterType.vehicle,
      );

      final startResult = agus_maps_flutter.addNavigationRoutePoint(
        type: agus_maps_flutter.NavigationRoutePointType.start,
        title: startLabel,
        subtitle: 'Route preview start',
        lat: start.lat,
        lon: start.lon,
      );
      final finishResult = agus_maps_flutter.addNavigationRoutePoint(
        type: agus_maps_flutter.NavigationRoutePointType.finish,
        title: destination.title,
        subtitle: destination.subtitle,
        lat: destination.lat,
        lon: destination.lon,
      );

      if (startResult < 0 || finishResult < 0) {
        _showMapMessage('Unable to set route points.');
        return;
      }

      final buildResult = agus_maps_flutter.buildNavigationRoute();
      if (buildResult < 0) {
        _showMapMessage('Unable to start route calculation.');
        return;
      }

      agus_maps_flutter.closePlacePage();
      setState(() {
        _navigationPlan = _NavigationPlan(
          destination: destination,
          startLabel: startLabel,
        );
        _navigationStatus = agus_maps_flutter.getNavigationStatus();
        _placePage = null;
        _searchOpen = false;
        _clearSearchState();
        _currentTabIndex = 0;
      });
      _startNavigationStatusPolling();
      _showMapMessage('Building route from $startLabel.');
    } finally {
      if (mounted) {
        setState(() {
          _navigationActionInProgress = false;
        });
      }
    }
  }

  _LocationFix _routePreviewStart(_RouteDestination destination) {
    final center = agus_maps_flutter.getViewportCenter();
    if (center != null &&
        _isValidCoordinate(center.lat, center.lon) &&
        _distanceMeters(
              center.lat,
              center.lon,
              destination.lat,
              destination.lon,
            ) >
            150) {
      return _LocationFix(
        lat: center.lat,
        lon: center.lon,
        zoom: agus_maps_flutter.getCurrentZoom() ?? 14,
      );
    }

    if (_distanceMeters(
          kDefaultLocation.lat,
          kDefaultLocation.lon,
          destination.lat,
          destination.lon,
        ) >
        150) {
      return _LocationFix(
        lat: kDefaultLocation.lat,
        lon: kDefaultLocation.lon,
        zoom: kDefaultLocation.zoom,
      );
    }

    return _LocationFix(
      lat: destination.lat + 0.01,
      lon: destination.lon,
      zoom: 14,
    );
  }

  String _routeStartLabel(
    _LocationFix start,
    _RouteDestination destination,
  ) {
    final center = agus_maps_flutter.getViewportCenter();
    if (center != null &&
        _distanceMeters(start.lat, start.lon, center.lat, center.lon) < 5 &&
        _distanceMeters(
              center.lat,
              center.lon,
              destination.lat,
              destination.lon,
            ) >
            150) {
      return 'map center';
    }
    if (_distanceMeters(
          start.lat,
          start.lon,
          kDefaultLocation.lat,
          kDefaultLocation.lon,
        ) <
        5) {
      return kDefaultLocation.name;
    }
    return 'nearby point';
  }

  bool _isValidCoordinate(double lat, double lon) {
    return lat.isFinite && lon.isFinite && lat.abs() <= 90 && lon.abs() <= 180;
  }

  double _distanceMeters(
    double startLat,
    double startLon,
    double finishLat,
    double finishLon,
  ) {
    const earthRadiusMeters = 6371000.0;
    final startLatRadians = startLat * pi / 180;
    final finishLatRadians = finishLat * pi / 180;
    final deltaLatRadians = (finishLat - startLat) * pi / 180;
    final deltaLonRadians = (finishLon - startLon) * pi / 180;
    final halfChordLength =
        sin(deltaLatRadians / 2) * sin(deltaLatRadians / 2) +
            cos(startLatRadians) *
                cos(finishLatRadians) *
                sin(deltaLonRadians / 2) *
                sin(deltaLonRadians / 2);
    final angularDistance = 2 *
        atan2(
          sqrt(halfChordLength),
          sqrt(1 - halfChordLength),
        );
    return earthRadiusMeters * angularDistance;
  }

  void _startNavigationStatusPolling() {
    _navigationPollTimer?.cancel();
    _navigationPollTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _refreshNavigationStatus(),
    );
    _refreshNavigationStatus();
  }

  void _refreshNavigationStatus() {
    if (!_nativeSurfaceReady || !mounted) return;
    setState(() {
      _navigationStatus = agus_maps_flutter.getNavigationStatus();
    });
  }

  void _startRouteFollowing() {
    if (_navigationActionInProgress) return;
    final result = agus_maps_flutter.followNavigationRoute();
    _refreshNavigationStatus();
    if (result > 0) {
      _showMapMessage('Guidance started.');
    } else {
      _showMapMessage('Guidance needs a built route and location updates.');
    }
  }

  void _clearNavigationRoute() {
    _navigationPollTimer?.cancel();
    agus_maps_flutter.closeNavigationRoute(removeRoutePoints: true);
    if (!mounted) return;
    setState(() {
      _navigationPlan = null;
      _navigationStatus = null;
      _navigationActionInProgress = false;
    });
    _showMapMessage('Route cleared.');
  }

  Future<void> _updateMapScale(double value) async {
    final clamped = value.clamp(0.25, 3.0).toDouble();
    if (clamped == _mapScale) return;
    setState(() {
      _mapScale = clamped;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefsKeyMapScale, clamped);
    } catch (e) {
      _log('Warning: Failed to save map scale: $e');
    }
  }

  void _resetMapScale() {
    _updateMapScale(1.0);
  }

  Future<void> _updateInterfaceThemeMode(ThemeMode mode) async {
    if (mode == _interfaceThemeMode) return;
    setState(() {
      _interfaceThemeMode = mode;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyInterfaceTheme, mode.name);
  }

  Future<void> _updateMapAppearanceMode(
    agus_maps_flutter.MapAppearanceMode mode,
  ) async {
    if (mode == _mapAppearanceMode) return;
    setState(() {
      _mapAppearanceMode = mode;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyMapAppearance, mode.name);
    _applyNativeMapSettings();
  }

  Future<void> _updateMapLanguage(String languageCode) async {
    if (languageCode == _mapLanguageCode) return;
    setState(() {
      _mapLanguageCode = languageCode;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyMapLanguage, languageCode);
    _applyNativeMapSettings();
  }

  Future<void> _updateBuildings3d(bool enabled) async {
    if (enabled == _buildings3dEnabled) return;
    setState(() {
      _buildings3dEnabled = enabled;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyBuildings3d, enabled);
    _applyNativeMapSettings();
  }

  Future<void> _updateMapLayerState(
    agus_maps_flutter.MapLayerState state,
  ) async {
    if (state.outdoors == _mapLayerState.outdoors &&
        state.isolines == _mapLayerState.isolines &&
        state.subway == _mapLayerState.subway) {
      return;
    }
    setState(() {
      _mapLayerState = state;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyLayerOutdoors, state.outdoors);
    await prefs.setBool(_prefsKeyLayerIsolines, state.isolines);
    await prefs.setBool(_prefsKeyLayerSubway, state.subway);
    _applyNativeMapSettings();
  }

  Future<void> _updateNavigationSettings(
    agus_maps_flutter.NavigationSettings settings,
  ) async {
    setState(() {
      _navigationSettings = settings;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKeyNavigationUnits,
      settings.measurementUnits.name,
    );
    await prefs.setBool(
      _prefsKeyNavigationVoice,
      settings.turnNotificationsEnabled,
    );
    await prefs.setBool(
      _prefsKeyNavigationStreetNames,
      settings.announceStreetNames,
    );
    await prefs.setBool(
      _prefsKeyNavigationSpeedLimit,
      settings.showSpeedLimit,
    );
    await prefs.setString(
      _prefsKeyNavigationSpeedCameras,
      settings.speedCameraMode.name,
    );
    await prefs.setBool(
      _prefsKeyNavigationAvoidTolls,
      settings.routingOptions.avoidTolls,
    );
    await prefs.setBool(
      _prefsKeyNavigationAvoidMotorways,
      settings.routingOptions.avoidMotorways,
    );
    await prefs.setBool(
      _prefsKeyNavigationAvoidFerries,
      settings.routingOptions.avoidFerries,
    );
    await prefs.setBool(
      _prefsKeyNavigationAvoidUnpaved,
      settings.routingOptions.avoidUnpavedRoads,
    );
    _applyNativeNavigationSettings();
  }

  Future<void> _initData() async {
    try {
      _log('Starting initialization...');

      // NOTE: PlacePageLocalization has been removed. All localization is now
      // handled by native code via setLocale(). The locale will be set after
      // initWithPaths() is called.

      // Initialize MWM storage
      _log('Initializing MWM storage...');
      _mwmStorage = await MwmStorage.create();

      // Clean up any partial downloads from interrupted sessions.
      // These are .mwm.download files that were being written when the app was killed.
      // If not cleaned up, RegisterAllMaps() would try to load them and crash.
      _log('Cleaning up partial downloads...');
      await _cleanupPartialDownloads();

      // Validate existing metadata against actual files on disk.
      // After reinstall, SharedPreferences may persist but files are deleted.
      _log('Validating stored MWM metadata...');
      final orphanedRegions = await _mwmStorage!.getOrphanedRegions();
      if (orphanedRegions.isNotEmpty) {
        _log(
            'Found ${orphanedRegions.length} orphaned regions: $orphanedRegions');
        _log('Pruning orphaned metadata...');
        await _mwmStorage!.pruneOrphaned();
        _log('Orphaned metadata pruned.');
      } else {
        _log('All stored metadata is valid.');
      }

      // 1. Extract CoMaps data files (classificator.txt, types.txt, etc.)
      _log('Extracting data files...');
      final dataPath = await agus_maps_flutter.extractDataFiles();
      _dataPath = dataPath;
      _log('Data path: $dataPath');
      await _cleanupPartialDownloads(dataPath);

      // 2. Extract ICU data for transliteration.
      _log('Extracting icudt75l.dat...');
      final icuDataPath = await _prepareBundledResourceFile(
        extractedPath:
            await agus_maps_flutter.extractMap('assets/maps/icudt75l.dat'),
        dataPath: dataPath,
      );
      _log('ICU data path: $icuDataPath');

      _bundledMwmVersion = await _readBundledMapAssetVersion() ??
          await _readBundledMwmVersion(dataPath);
      _log('Bundled MWM version: ${_bundledMwmVersion ?? 'unknown'}');

      // 3. Extract bundled maps before surface creation. CoMaps scans the
      // writable directory during native surface creation. World/WorldCoasts
      // must be in the resource root, while country maps must be under the
      // current version directory before RegisterAllMaps() runs.
      _log('Extracting World.mwm...');
      final worldPath = await _prepareBundledCountryMap(
        extractedPath:
            await agus_maps_flutter.extractMap('assets/maps/World.mwm'),
        dataPath: dataPath,
        version: _bundledMwmVersion,
      );

      _log('Extracting WorldCoasts.mwm...');
      final coastsPath = await _prepareBundledCountryMap(
        extractedPath:
            await agus_maps_flutter.extractMap('assets/maps/WorldCoasts.mwm'),
        dataPath: dataPath,
        version: _bundledMwmVersion,
      );

      _log('Extracting Gibraltar.mwm...');
      final extractedGibraltarPath =
          await agus_maps_flutter.extractMap('assets/maps/Gibraltar.mwm');
      final gibraltarPath = await _prepareBundledCountryMap(
        extractedPath: extractedGibraltarPath,
        dataPath: dataPath,
        version: _bundledMwmVersion,
      );
      _log('Bundled map paths: [$worldPath, $coastsPath, $gibraltarPath]');

      await _recordBundledMap('World', worldPath);
      await _recordBundledMap('WorldCoasts', coastsPath);
      await _recordBundledMap('Gibraltar', gibraltarPath);

      // 4. Initialize with extracted data files
      _log('Calling initWithPaths()...');
      agus_maps_flutter.initWithPaths(dataPath, dataPath);
      _log('initWithPaths() complete');

      // 5. Set the locale for native POI type localization
      // This ensures type names like "amenity-fuel" are translated to "Gas Station"
      // in the place page subtitle. Use the platform's current locale.
      final localeTag = ui.PlatformDispatcher.instance.locale.toLanguageTag();
      _log('Setting locale: $localeTag');
      agus_maps_flutter.setLocale(localeTag);

      _initializeDuckDBProjectLayers();
      _log('Bundled maps will be registered during surface creation...');

      if (!mounted) return;
      setState(() {
        _status = 'Data ready - creating map...';
        _dataReady = true;
      });
    } catch (e, stackTrace) {
      _log('ERROR: $e\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _status = 'Error: $e';
      });
    }
  }

  void _onMapReady() {
    // Kick off async work without blocking the widget callback.
    unawaited(_onMapReadyAsync());
  }

  void _handlePlacePage(agus_maps_flutter.PlacePageData? data) {
    if (!mounted) return;
    if (data == null) {
      _log('Place page cleared.');
    } else {
      final rawType = data.rawTypes.isNotEmpty ? data.rawTypes.first : '';
      // NOTE: Subtitle is now pre-localized by native code.
      // No Dart-side localizeTypeKey() call needed.
      _log(
        'Place page received: title="${data.title}" '
        'subtitle="${data.subtitle}" '
        'rawType="$rawType" '
        'address="${data.address}" '
        'coords="${data.coordinates.decimal ?? ''}" '
        'metadataTags=${data.metadataTags.map((entry) => entry.key).toList()}',
      );
    }
    setState(() {
      _placePage = data;
    });
  }

  void _closePlacePage() {
    agus_maps_flutter.closePlacePage();
    if (!mounted) return;
    setState(() {
      _placePage = null;
    });
  }

  Future<void> _onMapReadyAsync() async {
    _log('Map surface ready. Bundled maps are already registered.');
    _nativeSurfaceReady = true;
    _applyNativeMapSettings();
    _applyNativeNavigationSettings();
    _enableDuckDBNativeLayerRendering();
    _startBearingUpdates();
    _startEditHandleProjectionUpdates();

    // Re-register all previously downloaded maps from MwmStorage
    // This is crucial: downloaded maps are only stored as metadata,
    // they need to be re-registered with the native engine on each app start
    var registeredDownloadedMaps = 0;
    if (_mwmStorage != null) {
      final allMaps = _mwmStorage!.getAll();
      _log('Re-registering ${allMaps.length} maps from storage...');
      for (final metadata in allMaps) {
        // Skip bundled maps (already registered above)
        if (metadata.isBundled) continue;

        if (!await File(metadata.filePath).exists()) {
          _log(
            'Skipping missing downloaded map ${metadata.regionName}: '
            '${metadata.filePath}',
          );
          await _mwmStorage!.remove(metadata.regionName);
          continue;
        }

        _log(
            'Re-registering downloaded: ${metadata.regionName} at ${metadata.filePath}');
        final parsed = int.tryParse(metadata.snapshotVersion);
        final result = parsed != null
            ? agus_maps_flutter.registerSingleMapWithVersion(
                metadata.filePath,
                parsed,
              )
            : agus_maps_flutter.registerSingleMap(metadata.filePath);
        _log('  Result: $result');
        registeredDownloadedMaps++;
      }
    }

    if (registeredDownloadedMaps > 0) {
      // Downloaded maps are registered after DrapeEngine initialization, so the
      // viewport needs a refresh to pick up their tile coverage.
      _log('Refreshing map viewport for downloaded maps...');
      agus_maps_flutter.invalidateMap();
      agus_maps_flutter.forceRedraw();
    }

    if (kDebugMode) {
      _log('Debug: Listing all registered MWMs...');
      agus_maps_flutter.debugListMwms();

      _log('Debug: Checking Gibraltar coverage...');
      agus_maps_flutter.debugCheckPoint(36.1407, -5.3535);
    }

    if (mounted) {
      setState(() {
        _status = 'Map ready!';
      });
    }
  }

  void _initializeDuckDBProjectLayers() {
    if (_duckDBLayerStore != null) return;
    if (_dataPath == null) {
      _log('DuckDB project layer store deferred: data path is not ready.');
      if (mounted) {
        setState(() {
          _duckDBLayerStoreStatus = 'Waiting for app data path';
        });
      }
      return;
    }

    try {
      if (mounted) {
        setState(() {
          _duckDBLayerStoreStatus = 'Opening DuckDB project layer store...';
        });
      }
      final store = agus_maps_flutter.DuckDBLayerStore(writablePath: _dataPath!)
        ..open();
      store.upsertLayer(
        const agus_maps_flutter.AgusLayerDraft(
          layerId: _userDrawLayerId,
          name: 'User drawings',
          kind: agus_maps_flutter.AgusLayerKind.userDraw,
          visible: true,
          zIndex: 1000,
        ),
      );

      final controller = agus_maps_flutter.DuckDBLayerDrawController(
        store: store,
        layerId: _activeDuckDBLayerId,
        projector: _projectDrawPoint,
        coordinateProjector: _projectMapCoordinate,
        nativeEditGeometryRenderer: _renderDuckDBEditGeometry,
        onCommitted: _refreshDuckDBNativeLayers,
      );

      _duckDBDrawController?.dispose();
      if (mounted) {
        setState(() {
          _duckDBLayerStore = store;
          _duckDBDrawController = controller;
          _duckDBLayerStoreStatus = 'DuckDB project layer store ready';
        });
      }
      _log('DuckDB drawing layer store enabled.');
      _enableDuckDBNativeLayerRendering();
    } catch (error, stackTrace) {
      if (mounted) {
        setState(() {
          _duckDBLayerStoreStatus =
              'DuckDB layer store unavailable - see DEBUG CONSOLE';
        });
      }
      _log('DuckDB drawing layer store unavailable: $error\n$stackTrace');
    }
  }

  void _enableDuckDBNativeLayerRendering() {
    if (!_nativeSurfaceReady) return;
    if (_duckDBLayerStore == null) {
      _initializeDuckDBProjectLayers();
      return;
    }

    try {
      agus_maps_flutter.setDuckDBMapLayerRenderingEnabled(true);
      final count = agus_maps_flutter.refreshDuckDBMapLayers();
      _log('DuckDB layer rendering enabled: $count visible features.');
    } catch (error, stackTrace) {
      _log(
        'DuckDB native layer rendering unavailable; '
        'drawing layer persistence remains enabled: $error\n$stackTrace',
      );
    }
  }

  void _setActiveDuckDBLayer(String layerId) {
    final store = _duckDBLayerStore;
    if (store == null || layerId == _activeDuckDBLayerId) return;

    final previousTool =
        _duckDBDrawController?.tool ?? agus_maps_flutter.AgusDrawTool.none;
    final controller = agus_maps_flutter.DuckDBLayerDrawController(
      store: store,
      layerId: layerId,
      projector: _projectDrawPoint,
      coordinateProjector: _projectMapCoordinate,
      nativeEditGeometryRenderer: _renderDuckDBEditGeometry,
      onCommitted: _refreshDuckDBNativeLayers,
    )..setTool(previousTool);

    _duckDBDrawController?.dispose();
    setState(() {
      _activeDuckDBLayerId = layerId;
      _duckDBDrawController = controller;
    });
    _log('Active edit layer changed: $layerId');
  }

  void _setDuckDBDrawTool(agus_maps_flutter.AgusDrawTool tool) {
    final controller = _duckDBDrawController;
    if (controller == null) return;
    controller.setTool(tool);
    _workbenchController.selectEditorTab(WorkbenchEditorTab.map);
    setState(() {});
  }

  void _editDuckDBFeature(agus_maps_flutter.AgusLayerFeature feature) {
    if (feature.layerId != _activeDuckDBLayerId) {
      _setActiveDuckDBLayer(feature.layerId);
    }

    final controller = _duckDBDrawController;
    if (controller == null) {
      _log('Move ignored because the DuckDB draw controller is unavailable.');
      return;
    }

    try {
      controller.beginEditFeature(feature);
      _workbenchController.selectEditorTab(WorkbenchEditorTab.map);
      setState(() {});
      _log(
        'Editing feature vertices: ${feature.featureId}. '
        'Drag visible handles on the map to update geometry.',
      );
    } catch (error, stackTrace) {
      _log('Feature edit setup failed: $error\n$stackTrace');
    }
  }

  agus_maps_flutter.AgusLatLon? _projectDrawPoint(Offset localPosition) {
    final pixelRatio = View.of(context).devicePixelRatio;
    return agus_maps_flutter.screenPointToLatLon(
      localPosition.dx * pixelRatio,
      localPosition.dy * pixelRatio,
    );
  }

  Offset? _projectMapCoordinate(agus_maps_flutter.AgusLatLon coordinate) {
    final pixelRatio = View.of(context).devicePixelRatio;
    final physicalOffset = agus_maps_flutter.latLonToScreenPoint(
      coordinate.lat,
      coordinate.lon,
    );
    if (physicalOffset == null) return null;
    return physicalOffset / pixelRatio;
  }

  bool _handleDuckDBMapTap(Offset localPosition) {
    return _duckDBDrawController?.handleMapTap(localPosition) ?? false;
  }

  bool _handleDuckDBMapPointerDown(Offset localPosition) {
    return _duckDBDrawController?.handlePointerDown(localPosition) ?? false;
  }

  void _handleDuckDBMapPointerMove(Offset localPosition) {
    final controller = _duckDBDrawController;
    if (controller == null) return;
    unawaited(controller.handlePointerMove(localPosition));
  }

  void _handleDuckDBMapPointerUp(Offset localPosition) {
    final controller = _duckDBDrawController;
    if (controller == null) return;
    unawaited(controller.handlePointerUp());
  }

  void _renderDuckDBEditGeometry(
    agus_maps_flutter.AgusDrapeInteractionMode mode,
    String? geometryWkt,
  ) {
    if (!_nativeSurfaceReady ||
        !(Platform.isMacOS || Platform.isIOS || Platform.isAndroid)) {
      return;
    }
    if (mode == agus_maps_flutter.AgusDrapeInteractionMode.inactive ||
        geometryWkt == null) {
      agus_maps_flutter.clearDuckDBEditHandles();
      return;
    }
    agus_maps_flutter.setDuckDBInteractionGeometryFromWkt(mode, geometryWkt);
  }

  String _drawToolLabel(agus_maps_flutter.AgusDrawTool tool) {
    return switch (tool) {
      agus_maps_flutter.AgusDrawTool.pin => 'point',
      agus_maps_flutter.AgusDrawTool.segment => 'segment',
      agus_maps_flutter.AgusDrawTool.line => 'line',
      agus_maps_flutter.AgusDrawTool.polygon => 'polygon',
      agus_maps_flutter.AgusDrawTool.none => 'map',
    };
  }

  Future<void> _refreshDuckDBNativeLayers() async {
    if (!_nativeSurfaceReady) {
      _log('DuckDB layer renderer refresh deferred: map surface is not ready.');
      return;
    }
    try {
      final count = agus_maps_flutter.refreshDuckDBMapLayers();
      _log('DuckDB layer renderer refreshed: $count visible features.');
    } catch (error, stackTrace) {
      _log(
        'DuckDB layer renderer refresh failed; '
        'project layer changes remain persisted: $error\n$stackTrace',
      );
    }
  }

  void _startBearingUpdates() {
    _bearingTimer?.cancel();
    _bearingTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || _currentTabIndex != 0 || !_nativeSurfaceReady) return;
      final bearing = _normalizeNativeBearing(
        agus_maps_flutter.getCurrentBearing(),
      );
      if (bearing == null) return;
      if ((bearing - _currentBearing.value).abs() < 0.25) return;
      _currentBearing.value = bearing;
    });
  }

  void _startEditHandleProjectionUpdates() {
    _editHandleProjectionTimer?.cancel();
    _editHandleProjectionTimer =
        Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (!mounted || !_nativeSurfaceReady) return;
      final controller = _duckDBDrawController;
      if (controller == null || !controller.isEditingFeature) return;
      controller.reprojectEditedFeatureVertices();
    });
  }

  double? _normalizeNativeBearing(double bearing) {
    if (!bearing.isFinite) {
      if (!_reportedInvalidBearing) {
        _reportedInvalidBearing = true;
        _log('Ignored non-finite native bearing: $bearing');
      }
      return null;
    }
    _reportedInvalidBearing = false;
    final normalized = bearing % 360;
    return normalized < 0 ? normalized + 360 : normalized;
  }

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _clearSearchState();
      }
    });
    if (_searchOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocusNode.requestFocus();
      });
    }
  }

  void _onSearchChanged(String query) {
    final terms = _searchTerms(query);
    if (terms.isEmpty) {
      _searchDebounceTimer?.cancel();
      _searchPollTimer?.cancel();
      agus_maps_flutter.cancelNativeSearch();
      setState(() {
        _searchResults = const [];
        _nativeSearchRunning = false;
      });
      return;
    }

    setState(() {
      _searchResults = _buildSupplementalSearchResults(query, terms);
      _nativeSearchRunning = _nativeSurfaceReady;
    });

    _searchDebounceTimer?.cancel();
    if (!_nativeSurfaceReady) return;

    _searchDebounceTimer = Timer(const Duration(milliseconds: 250), () {
      _startNativeSearch(query);
    });
  }

  void _clearSearchState() {
    _searchDebounceTimer?.cancel();
    _searchPollTimer?.cancel();
    agus_maps_flutter.cancelNativeSearch();
    _searchFocusNode.unfocus();
    _searchController.clear();
    _searchResults = const [];
    _nativeSearchRunning = false;
    _activeSearchGeneration = 0;
    _activeSearchStartedAt = null;
  }

  void _startNativeSearch(String query) {
    final trimmedQuery = query.trim();
    if (!mounted || trimmedQuery.isEmpty) return;
    if (_searchController.text.trim() != trimmedQuery) return;

    final generation = agus_maps_flutter.startNativeSearch(
      trimmedQuery,
      locale: ui.PlatformDispatcher.instance.locale.toLanguageTag(),
      interactive: true,
    );

    if (generation < 0) {
      if (!mounted) return;
      _searchPollTimer?.cancel();
      setState(() {
        _nativeSearchRunning = false;
        _activeSearchGeneration = 0;
        _activeSearchStartedAt = null;
      });
      return;
    }

    _activeSearchGeneration = generation;
    _activeSearchStartedAt = DateTime.now();
    _searchPollTimer?.cancel();
    _searchPollTimer = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => _pollNativeSearch(trimmedQuery, generation),
    );
    _pollNativeSearch(trimmedQuery, generation);
  }

  void _pollNativeSearch(String query, int generation) {
    if (generation != _activeSearchGeneration) return;
    if (!mounted || !_searchOpen || _searchController.text.trim() != query) {
      _searchPollTimer?.cancel();
      return;
    }

    final snapshot = agus_maps_flutter.getNativeSearchSnapshot();
    if (snapshot.generation != generation) return;

    final startedAt = _activeSearchStartedAt;
    final timedOut = startedAt != null &&
        DateTime.now().difference(startedAt) > _nativeSearchTimeout;

    final terms = _searchTerms(query);
    final nativeResults = snapshot.results
        .map(_nativeSearchResultToExampleResult)
        .where((result) => result.title.isNotEmpty)
        .toList(growable: false);
    final supplementalResults = _buildSupplementalSearchResults(query, terms);
    final mergedResults = _dedupeSearchResults([
      ...supplementalResults.where(
        (result) => result.source == MapSearchResultSource.coordinate,
      ),
      ...nativeResults,
      ...supplementalResults.where(
        (result) => result.source != MapSearchResultSource.coordinate,
      ),
    ]).take(20).toList(growable: false);

    setState(() {
      _searchResults = mergedResults;
      _nativeSearchRunning = snapshot.isRunning && !timedOut;
    });

    if (!snapshot.isRunning || timedOut) {
      if (timedOut) {
        _log('Native search timed out for "$query" after '
            '${_nativeSearchTimeout.inSeconds}s');
        agus_maps_flutter.cancelNativeSearch();
        _activeSearchGeneration = 0;
        _activeSearchStartedAt = null;
      }
      _searchPollTimer?.cancel();
    }
  }

  MapSearchResult _nativeSearchResultToExampleResult(
    agus_maps_flutter.NativeSearchResult result,
  ) {
    final title = result.title.isNotEmpty ? result.title : result.suggestion;
    final subtitleParts = <String>[
      if (result.subtitle.isNotEmpty) result.subtitle,
      if (result.address.isNotEmpty && result.address != result.subtitle)
        result.address,
    ];
    final subtitle = result.isSuggestion
        ? 'Suggestion'
        : subtitleParts.isEmpty
            ? 'Map result'
            : subtitleParts.join(' - ');

    return MapSearchResult(
      title: title,
      subtitle: subtitle,
      lat: result.lat,
      lon: result.lon,
      zoom: result.type == agus_maps_flutter.NativeSearchResultType.latLon
          ? 15
          : 17,
      source: MapSearchResultSource.native,
      nativeIndex: result.index,
      isSuggestion: result.isSuggestion,
      suggestion: result.suggestion,
    );
  }

  List<MapSearchResult> _buildSupplementalSearchResults(
    String query,
    List<String> terms,
  ) {
    final results = <MapSearchResult>[];
    final coordinateResult = _coordinateSearchResult(query);
    if (coordinateResult != null) {
      results.add(coordinateResult);
    }

    final favoriteResults = kFavorites
        .map(
          (favorite) => MapSearchResult(
            title: favorite.name,
            subtitle: 'Saved map target',
            lat: favorite.lat,
            lon: favorite.lon,
            zoom: favorite.zoom,
            keywords: const ['favorite', 'region'],
            source: MapSearchResultSource.favorite,
          ),
        )
        .where((result) => result.matches(terms))
        .toList(growable: false)
      ..sort((a, b) => a.score(terms).compareTo(b.score(terms)));

    results.addAll(favoriteResults);
    return _dedupeSearchResults(results).take(6).toList(growable: false);
  }

  List<String> _searchTerms(String query) => query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((term) => term.isNotEmpty)
      .toList(growable: false);

  MapSearchResult? _coordinateSearchResult(String query) {
    final match = RegExp(
      r'^\s*(-?\d+(?:\.\d+)?)\s*[, ]\s*(-?\d+(?:\.\d+)?)\s*$',
    ).firstMatch(query);
    if (match == null) return null;

    final lat = double.tryParse(match.group(1)!);
    final lon = double.tryParse(match.group(2)!);
    if (lat == null || lon == null) return null;
    if (lat.abs() > 90 || lon.abs() > 180) return null;

    return MapSearchResult(
      title: '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}',
      subtitle: 'Coordinates',
      lat: lat,
      lon: lon,
      zoom: 15,
      keywords: const ['coordinates', 'lat lon', 'latitude longitude'],
      source: MapSearchResultSource.coordinate,
    );
  }

  List<MapSearchResult> _dedupeSearchResults(List<MapSearchResult> results) {
    final seen = <String>{};
    final unique = <MapSearchResult>[];
    for (final result in results) {
      final key = result.nativeIndex == null
          ? '${result.title}|${result.lat}|${result.lon}'.toLowerCase()
          : 'native:${result.nativeIndex}';
      if (seen.add(key)) {
        unique.add(result);
      }
    }
    return unique;
  }

  void _focusSearchResult(MapSearchResult result) {
    if (result.isSuggestion) {
      final suggestion =
          result.suggestion.isNotEmpty ? result.suggestion : result.title;
      _searchController.value = TextEditingValue(
        text: suggestion,
        selection: TextSelection.collapsed(offset: suggestion.length),
      );
      _onSearchChanged(suggestion);
      _searchFocusNode.requestFocus();
      return;
    }

    var selectedNativeResult = false;
    if (result.isNative && result.nativeIndex != null) {
      selectedNativeResult =
          agus_maps_flutter.showNativeSearchResult(result.nativeIndex!) > 0;
    }

    if (!selectedNativeResult) {
      _mapController.moveToLocation(result.lat, result.lon, result.zoom);
    }

    setState(() {
      _searchOpen = false;
      _currentTabIndex = 0;
      _clearSearchState();
    });
  }

  void _zoomIn() {
    _mapController.zoomIn();
  }

  void _zoomOut() {
    _mapController.zoomOut();
  }

  void _resetNorth() {
    _mapController.resetBearing();
    _currentBearing.value = 0.0;
  }

  Future<void> _centerOnCurrentPosition() async {
    if (_isLocating) return;
    setState(() {
      _isLocating = true;
    });

    try {
      if (Platform.isMacOS) {
        final estimatedLocation = await _getNetworkEstimatedLocation();
        if (estimatedLocation != null) {
          _focusLocation(estimatedLocation);
          return;
        }

        _showMapMessage(
            'Unable to estimate current location from the network.');
        return;
      }

      final deviceLocation = await _getDeviceLocation();
      if (deviceLocation != null) {
        _focusLocation(deviceLocation);
        return;
      }

      final estimatedLocation = await _getNetworkEstimatedLocation();
      if (estimatedLocation != null) {
        _focusLocation(estimatedLocation);
        return;
      }

      _showMapMessage('Unable to estimate current location.');
    } catch (error) {
      _log('Location failed: $error');
      _showMapMessage('Unable to estimate current location.');
    } finally {
      if (mounted) {
        setState(() {
          _isLocating = false;
        });
      }
    }
  }

  Future<_LocationFix?> _getDeviceLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled().timeout(
      const Duration(seconds: 2),
      onTimeout: () => false,
    );
    if (!serviceEnabled) {
      _log('Location services are disabled; falling back to estimate.');
      return null;
    }

    var permission = await Geolocator.checkPermission().timeout(
      const Duration(seconds: 2),
      onTimeout: () => LocationPermission.denied,
    );
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission().timeout(
        const Duration(seconds: 8),
        onTimeout: () => LocationPermission.denied,
      );
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      _log('Location permission is not available: $permission');
      return null;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      return _LocationFix(
        lat: position.latitude,
        lon: position.longitude,
        zoom: 15,
      );
    } catch (error) {
      _log('Precise location failed: $error');
    }

    try {
      final position = await Geolocator.getLastKnownPosition().timeout(
        const Duration(seconds: 2),
      );
      if (position != null) {
        return _LocationFix(
          lat: position.latitude,
          lon: position.longitude,
          zoom: 14,
          message: 'Using last known device location.',
        );
      }
    } catch (error) {
      _log('Last known location failed: $error');
    }

    return null;
  }

  Future<_LocationFix?> _getNetworkEstimatedLocation() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);

    try {
      final request = await client
          .getUrl(Uri.parse('https://ipapi.co/json/'))
          .timeout(const Duration(seconds: 4));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, 'agus-maps-example');

      final response = await request.close().timeout(
            const Duration(seconds: 6),
          );
      if (response.statusCode != HttpStatus.ok) {
        _log('Network location returned HTTP ${response.statusCode}');
        return null;
      }

      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 4));
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic> || decoded['error'] == true) {
        return null;
      }

      final lat =
          _jsonDouble(decoded['latitude']) ?? _jsonDouble(decoded['lat']);
      final lon =
          _jsonDouble(decoded['longitude']) ?? _jsonDouble(decoded['lon']);
      if (lat == null || lon == null || lat.abs() > 90 || lon.abs() > 180) {
        return null;
      }

      final placeParts = <Object?>[
        decoded['city'],
        decoded['region'],
        decoded['country_name'] ?? decoded['country'],
      ]
          .whereType<String>()
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList();
      final place = placeParts.take(2).join(', ');

      return _LocationFix(
        lat: lat,
        lon: lon,
        zoom: 11,
        message: place.isEmpty
            ? 'Using approximate network location.'
            : 'Using approximate network location near $place.',
      );
    } catch (error) {
      _log('Network location estimate failed: $error');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  double? _jsonDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  void _focusLocation(_LocationFix location) {
    final zoom = agus_maps_flutter.getCurrentZoom() ?? location.zoom;
    _mapController.moveToLocation(
      location.lat,
      location.lon,
      max(zoom, location.zoom),
    );

    final message = location.message;
    if (message != null) {
      _showMapMessage(message);
    }
  }

  void _showMapMessage(String message) {
    if (!mounted) return;
    _scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _log(String msg) {
    if (kDebugMode) {
      debugPrint('[AgusDemo] $msg');
    }
    if (mounted) {
      setState(() {
        _debug += '$msg\n';
      });
    }
  }

  Future<String> _prepareBundledCountryMap({
    required String extractedPath,
    required String dataPath,
    required int? version,
  }) async {
    final fileName = File(extractedPath).uri.pathSegments.last;
    if (_isRootCoMapsResource(fileName)) {
      return _prepareBundledResourceFile(
        extractedPath: extractedPath,
        dataPath: dataPath,
      );
    }
    if (version == null) {
      return extractedPath;
    }

    final versionDir = Directory('$dataPath/$version');
    await versionDir.create(recursive: true);

    final source = File(extractedPath);
    final target = File('${versionDir.path}/$fileName');
    final targetExists = await target.exists();
    if (!targetExists || await target.length() != await source.length()) {
      await source.copy(target.path);
    }
    await _deleteStaleVersionedBundledMap(
      dataPath: dataPath,
      fileName: fileName,
      keepVersion: version,
    );
    if (!_sameFilePath(source.path, target.path) && await source.exists()) {
      await source.delete();
    }
    return target.path;
  }

  Future<void> _deleteStaleVersionedBundledMap({
    required String dataPath,
    required String fileName,
    required int keepVersion,
  }) async {
    final dataDir = Directory(dataPath);
    if (!await dataDir.exists()) return;

    await for (final entity in dataDir.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = entity.uri.pathSegments
          .where((segment) => segment.isNotEmpty)
          .lastOrNull;
      if (name == null || int.tryParse(name) == keepVersion) continue;
      if (!RegExp(r'^\d+$').hasMatch(name)) continue;

      final staleMap = File('${entity.path}/$fileName');
      if (await staleMap.exists()) {
        await staleMap.delete();
      }
    }
  }

  Future<void> _recordBundledMap(String regionName, String filePath) async {
    final storage = _mwmStorage;
    if (storage == null) return;

    final existing = storage.getByRegion(regionName);
    if (existing != null && !existing.isBundled) {
      return;
    }

    final file = File(filePath);
    await storage.upsert(
      MwmMetadata(
        regionName: regionName,
        snapshotVersion: _bundledMwmVersion?.toString() ?? 'bundled',
        fileSize: await file.length(),
        downloadDate: DateTime.now(),
        filePath: filePath,
        isBundled: true,
      ),
    );
  }

  bool _isRootCoMapsResource(String fileName) {
    return fileName == 'World.mwm' ||
        fileName == 'WorldCoasts.mwm' ||
        fileName == 'icudt75l.dat';
  }

  Future<String> _prepareBundledResourceFile({
    required String extractedPath,
    required String dataPath,
  }) async {
    final fileName = File(extractedPath).uri.pathSegments.last;
    final source = File(extractedPath);
    final target = File('$dataPath/$fileName');

    if (_sameFilePath(source.path, target.path)) {
      return target.path;
    }

    final targetExists = await target.exists();
    if (!targetExists || await target.length() != await source.length()) {
      await source.copy(target.path);
    }
    return target.path;
  }

  bool _sameFilePath(String left, String right) {
    String normalize(String value) {
      final normalized = value.replaceAll('\\', '/');
      return Platform.isWindows ? normalized.toLowerCase() : normalized;
    }

    return normalize(left) == normalize(right);
  }

  Future<int?> _readBundledMwmVersion(String dataPath) async {
    try {
      final file = File('$dataPath/countries.txt');
      if (!await file.exists()) {
        return null;
      }
      final contents = await file.readAsString();
      // countries.txt is JSON: { "v": 251209, "id": "Countries", ... }
      // Parse the "v" field which contains the MWM snapshot version.
      final match = RegExp(r'"v"\s*:\s*(\d+)').firstMatch(contents);
      if (match != null) {
        return int.tryParse(match.group(1)!);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<int?> _readBundledMapAssetVersion() async {
    try {
      final contents = await rootBundle.loadString('assets/maps/.mwm_version');
      return int.tryParse(contents.trim());
    } catch (_) {
      return null;
    }
  }

  /// Clean up partial downloads from interrupted sessions.
  ///
  /// When the app is killed during a download, the partial .mwm.download file
  /// remains on disk. If not cleaned up, RegisterAllMaps() might crash trying
  /// to load corrupted/incomplete map files.
  Future<void> _cleanupPartialDownloads([String? dataPath]) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      int cleanedCount = 0;

      final dirsToCheck = [
        Directory('${dir.path}/agus_maps_flutter/maps'),
        if (dataPath != null) Directory(dataPath),
      ];

      for (final checkDir in dirsToCheck) {
        if (!await checkDir.exists()) continue;

        await for (final entity in checkDir.list(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is File && entity.path.endsWith('.mwm.download')) {
            _log('Removing partial download: ${entity.path}');
            await entity.delete();
            cleanedCount++;
          }
        }
      }

      if (cleanedCount > 0) {
        _log('Cleaned up $cleanedCount partial download(s)');
      }
    } catch (e) {
      _log('Warning: Failed to clean up partial downloads: $e');
      // Don't rethrow - cleanup failure shouldn't prevent app startup
    }
  }

  Future<void> _clearCachedData() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.delete_sweep_outlined, color: Colors.red),
                SizedBox(width: 8),
                Text('Clear Cached Data'),
              ],
            ),
            content: const Text(
              'Clear downloaded maps, cached download lists, and saved settings?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Clear'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    try {
      _log('Clearing cached maps and settings...');
      await DownloadsCacheService().clearCache();
      await _mwmStorage?.deleteAllDownloaded();
      await _mwmStorage?.clear();
      await _deleteCachedMapDirectories();

      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      _mwmStorage = await MwmStorage.create();

      if (!mounted) return;
      setState(() {
        _mapScale = 1.0;
        _interfaceThemeMode = ThemeMode.system;
        _mapAppearanceMode = agus_maps_flutter.MapAppearanceMode.system;
        _mapLanguageCode = '';
        _buildings3dEnabled = false;
        _mapLayerState = const agus_maps_flutter.MapLayerState(
          outdoors: false,
          isolines: false,
          subway: false,
        );
        _navigationSettings = const agus_maps_flutter.NavigationSettings();
      });
      _applyNativeMapSettings();
      _applyNativeNavigationSettings();
      _showMapMessage(
        'Cached data cleared. Restart the app to reload bundled maps.',
      );
    } catch (e, stackTrace) {
      _log('Failed to clear cached data: $e\n$stackTrace');
      _showMapMessage('Failed to clear cached data: $e');
    }
  }

  Future<void> _deleteCachedMapDirectories() async {
    final documentsDir = await getApplicationDocumentsDirectory();
    await _deleteDirectoryIfExists(
      Directory('${documentsDir.path}/agus_maps_flutter/maps'),
    );

    final dataPath = _dataPath;
    if (dataPath == null) return;

    final dataDir = Directory(dataPath);
    if (!await dataDir.exists()) return;

    await for (final entity in dataDir.list(followLinks: false)) {
      final name = entity.uri.pathSegments
          .where((segment) => segment.isNotEmpty)
          .lastOrNull;
      if (name == null) continue;

      try {
        if (entity is Directory && RegExp(r'^\d+$').hasMatch(name)) {
          await entity.delete(recursive: true);
        } else if (entity is File && entity.path.endsWith('.mwm.download')) {
          await entity.delete();
        } else if (entity is File &&
            entity.path.endsWith('.mwm') &&
            !_isRootCoMapsResource(name)) {
          await entity.delete();
        }
      } catch (e) {
        _log('Warning: failed to delete cached map item ${entity.path}: $e');
      }
    }
  }

  Future<void> _deleteDirectoryIfExists(Directory directory) async {
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } catch (e) {
      _log('Warning: failed to delete ${directory.path}: $e');
    }
  }

  void _onFavoriteSelected(FavoriteLocation favorite) {
    // Navigate to the map and move to the selected location
    _mapController.moveToLocation(favorite.lat, favorite.lon, favorite.zoom);
    _workbenchController.selectEditorTab(WorkbenchEditorTab.map);
    setState(() {
      _currentTabIndex = 0; // Switch to Map tab
    });
  }

  Widget _buildShellForFormFactor(BuildContext context) {
    final formFactor = context.exampleFormFactor;
    if (formFactor.isDesktop) {
      return _buildDesktopWorkbench(context);
    }
    return _buildAdaptiveTabScaffold(context);
  }

  Widget _buildAdaptiveTabScaffold(BuildContext context) {
    return AdaptiveAppScaffold(
      title: 'Agus Maps',
      resizeToAvoidBottomInset: _currentTabIndex != 0,
      selectedIndex: _currentTabIndex,
      onDestinationSelected: (index) {
        setState(() {
          _currentTabIndex = index;
        });
      },
      destinations: const [
        AdaptiveScaffoldDestination(
          icon: Icon(Icons.map_outlined),
          selectedIcon: Icon(Icons.map),
          label: 'Map',
        ),
        AdaptiveScaffoldDestination(
          icon: Icon(Icons.favorite_border),
          selectedIcon: Icon(Icons.favorite),
          label: 'Favorites',
        ),
        AdaptiveScaffoldDestination(
          icon: Icon(Icons.download_outlined),
          selectedIcon: Icon(Icons.download),
          label: 'Downloads',
        ),
        AdaptiveScaffoldDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: 'Settings',
        ),
        AdaptiveScaffoldDestination(
          icon: Icon(Icons.info_outline),
          selectedIcon: Icon(Icons.info),
          label: 'About',
        ),
      ],
      body: IndexedStack(
        index: _currentTabIndex,
        children: [
          _buildMapTab(
            context,
            isVisible: _currentTabIndex == 0,
            useWorkbenchLayout: false,
          ),
          _buildFavoritesTab(context),
          _buildDownloadsTab(isVisible: _currentTabIndex == 2),
          SettingsTab(
            mapScale: _mapScale,
            interfaceThemeMode: _interfaceThemeMode,
            mapAppearanceMode: _mapAppearanceMode,
            mapLanguageCode: _mapLanguageCode,
            buildings3dEnabled: _buildings3dEnabled,
            layerState: _mapLayerState,
            navigationSettings: _navigationSettings,
            onMapScaleChanged: _updateMapScale,
            onResetMapScale: _resetMapScale,
            onInterfaceThemeModeChanged: _updateInterfaceThemeMode,
            onMapAppearanceModeChanged: _updateMapAppearanceMode,
            onMapLanguageChanged: _updateMapLanguage,
            onBuildings3dChanged: _updateBuildings3d,
            onLayerStateChanged: _updateMapLayerState,
            onNavigationSettingsChanged: _updateNavigationSettings,
            onClearCachedData: _clearCachedData,
          ),
          const AboutTab(),
        ],
      ),
    );
  }

  Widget _buildDesktopWorkbench(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: VSCodeWorkbench(
        controller: _workbenchController,
        activityBuilder: _buildWorkbenchActivity,
        editorBuilder: _buildWorkbenchEditor,
        panelBuilder: _buildWorkbenchPanel,
        secondarySideBarBuilder: _buildWorkbenchSecondarySideBar,
      ),
    );
  }

  Widget _buildWorkbenchActivity(
    BuildContext context,
    WorkbenchActivity activity,
  ) {
    return switch (activity) {
      WorkbenchActivity.explorer => AdaptiveLayerManager(
          formFactor: ExampleFormFactor.desktop,
          nativeLayerState: _mapLayerState,
          buildings3dEnabled: _buildings3dEnabled,
          onNativeLayerStateChanged: _updateMapLayerState,
          onBuildings3dChanged: _updateBuildings3d,
          layerStore: _duckDBLayerStore,
          activeLayerId: _activeDuckDBLayerId,
          activeDrawTool: _duckDBDrawController?.tool,
          layerStoreStatus: _duckDBLayerStoreStatus,
          onRenderingRefresh: _refreshDuckDBNativeLayers,
          onActiveLayerChanged: _setActiveDuckDBLayer,
          onDrawToolChanged: _setDuckDBDrawTool,
          onEditFeature: _editDuckDBFeature,
        ),
      WorkbenchActivity.mapPresentation => AdaptiveMapPresentationPanel(
          formFactor: ExampleFormFactor.desktop,
          nativeLayerState: _mapLayerState,
          buildings3dEnabled: _buildings3dEnabled,
          onNativeLayerStateChanged: _updateMapLayerState,
          onBuildings3dChanged: _updateBuildings3d,
        ),
      WorkbenchActivity.search => _buildDesktopSearchActivity(context),
      WorkbenchActivity.favorites => _buildDesktopFavoritesActivity(context),
      WorkbenchActivity.downloads => _buildDownloadsTab(
          isVisible: _workbenchController.state.activeActivity ==
              WorkbenchActivity.downloads,
        ),
      WorkbenchActivity.settings => SettingsTab(
          mapScale: _mapScale,
          interfaceThemeMode: _interfaceThemeMode,
          mapAppearanceMode: _mapAppearanceMode,
          mapLanguageCode: _mapLanguageCode,
          buildings3dEnabled: _buildings3dEnabled,
          layerState: _mapLayerState,
          navigationSettings: _navigationSettings,
          onMapScaleChanged: _updateMapScale,
          onResetMapScale: _resetMapScale,
          onInterfaceThemeModeChanged: _updateInterfaceThemeMode,
          onMapAppearanceModeChanged: _updateMapAppearanceMode,
          onMapLanguageChanged: _updateMapLanguage,
          onBuildings3dChanged: _updateBuildings3d,
          onLayerStateChanged: _updateMapLayerState,
          onNavigationSettingsChanged: _updateNavigationSettings,
          onClearCachedData: _clearCachedData,
        ),
      WorkbenchActivity.about => const AboutTab(),
    };
  }

  Widget _buildWorkbenchEditor(
    BuildContext context,
    WorkbenchEditorTab tab,
  ) {
    return switch (tab) {
      WorkbenchEditorTab.blank => const BlankEditorPlaceholder(),
      WorkbenchEditorTab.map => _buildMapTab(
          context,
          isVisible: _workbenchController.state.activeEditorTab ==
              WorkbenchEditorTab.map,
          useWorkbenchLayout: true,
        ),
    };
  }

  Widget _buildWorkbenchPanel(BuildContext context, WorkbenchPanelTab tab) {
    return switch (tab) {
      WorkbenchPanelTab.pointOfInterest =>
        PointOfInterestPanel(placePage: _placePage),
      WorkbenchPanelTab.debugConsole => DebugConsolePanel(log: _debug),
    };
  }

  Widget _buildWorkbenchSecondarySideBar(
    BuildContext context,
    WorkbenchSecondarySideBarTab tab,
  ) {
    return switch (tab) {
      WorkbenchSecondarySideBarTab.properties =>
        PropertiesSideBar(placePage: _placePage),
      WorkbenchSecondarySideBarTab.inspector => const InspectorSideBar(),
    };
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: _scaffoldMessengerKey,
      themeMode: _interfaceThemeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: Builder(
        builder: (context) {
          return _buildShellForFormFactor(context);
        },
      ),
    );
  }

  /// Full-screen map tab.
  Widget _buildMapTab(
    BuildContext context, {
    required bool isVisible,
    required bool useWorkbenchLayout,
  }) {
    if (!_dataReady) {
      final theme = Theme.of(context);
      final colorScheme = theme.colorScheme;
      return ColoredBox(
        color: colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(
                child: Icon(
                  Icons.map_outlined,
                  size: 40,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: 16),
              Center(child: Text(_status)),
              const SizedBox(height: 16),
              Expanded(
                flex: 2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLowest,
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _debug,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final routePanelVisible = _navigationPlan != null;
    final controlsBottom = routePanelVisible
        ? 168.0
        : _placePage == null
            ? 24.0
            : 248.0;
    final uiSpec = context.exampleUiSpec;
    final formFactor = uiSpec.formFactor;
    final dockedPanelWidth = uiSpec.dockedPanelWidth;
    final dockedColumnWidth = max(uiSpec.searchOverlayWidth, dockedPanelWidth);
    final drawController = _duckDBDrawController;
    final layerStore = _duckDBLayerStore;

    return Stack(
      children: [
        agus_maps_flutter.AgusMap(
          key: _mapViewportKey,
          initialLat: kDefaultLocation.lat,
          initialLon: kDefaultLocation.lon,
          initialZoom: kDefaultLocation.zoom,
          onMapReady: _onMapReady,
          onPlacePage: _handlePlacePage,
          onMapTap: _handleDuckDBMapTap,
          onMapPointerDown: _handleDuckDBMapPointerDown,
          onMapPointerMove: _handleDuckDBMapPointerMove,
          onMapPointerUp: _handleDuckDBMapPointerUp,
          controller: _mapController,
          isVisible: isVisible,
          userScale: _mapScale,
          resizePolicy: agus_maps_flutter.AgusMapResizePolicy.stableViewport,
        ),
        if (!useWorkbenchLayout && formFactor.isMobile)
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: _buildSearchOverlay(context),
          )
        else if (!useWorkbenchLayout)
          Positioned(
            top: 16,
            left: 16,
            child: SizedBox(
              width: dockedColumnWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: uiSpec.searchOverlayWidth,
                    child: _buildSearchOverlay(context),
                  ),
                  if (_duckDBLayerPanelVisible) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: dockedPanelWidth,
                      child: AdaptiveLayerManager(
                        formFactor: formFactor,
                        nativeLayerState: _mapLayerState,
                        buildings3dEnabled: _buildings3dEnabled,
                        onNativeLayerStateChanged: _updateMapLayerState,
                        onBuildings3dChanged: _updateBuildings3d,
                        layerStore: layerStore,
                        activeLayerId: _activeDuckDBLayerId,
                        activeDrawTool: drawController?.tool,
                        layerStoreStatus: _duckDBLayerStoreStatus,
                        onRenderingRefresh: _refreshDuckDBNativeLayers,
                        onActiveLayerChanged: _setActiveDuckDBLayer,
                        onDrawToolChanged: _setDuckDBDrawTool,
                        onEditFeature: _editDuckDBFeature,
                        onClose: () {
                          setState(() {
                            _duckDBLayerPanelVisible = false;
                          });
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        if (drawController != null)
          Positioned(
            left: 12,
            bottom: controlsBottom,
            child: AnimatedBuilder(
              animation: drawController,
              builder: (context, child) {
                if (!drawController.isEditing) return const SizedBox.shrink();
                return agus_maps_flutter.DuckDBLayerDrawToolbar(
                  controller: drawController,
                  axis: uiSpec.mapToolbarAxis,
                  onCommitted: (featureId) {
                    _log('DuckDB feature committed: $featureId');
                  },
                );
              },
            ),
          ),
        if (drawController != null)
          Positioned(
            left: useWorkbenchLayout
                ? 12
                : formFactor.isMobile
                    ? 12
                    : dockedColumnWidth + 28,
            right: 84,
            top: 76,
            child: AnimatedBuilder(
              animation: drawController,
              builder: (context, child) {
                if (!drawController.isDrawing) {
                  return const SizedBox.shrink();
                }
                return agus_maps_flutter.DuckDBLayerMetadataForm(
                  controller: drawController,
                );
              },
            ),
          ),
        if (drawController != null)
          Positioned(
            left: useWorkbenchLayout
                ? 12
                : formFactor.isMobile
                    ? 12
                    : dockedColumnWidth + 28,
            right: 84,
            top: 12,
            child: AnimatedBuilder(
              animation: drawController,
              builder: (context, child) {
                final error = drawController.lastError;
                if (!drawController.isEditing && error == null) {
                  return const SizedBox.shrink();
                }
                final message = drawController.isDrawing
                    ? 'Drawing ${_drawToolLabel(drawController.tool)}: '
                        'click to add vertices; drag to pan; check to commit or X to cancel.'
                    : 'Editing feature: drag visible vertices on the map.';
                return _MapEditBanner(
                  message: error ?? message,
                  isError: error != null,
                );
              },
            ),
          ),
        Positioned(
          right: 12,
          bottom: controlsBottom,
          child: _buildMapControls(
            context,
            formFactor,
            showLayerButton: !useWorkbenchLayout,
          ),
        ),
        if (_navigationPlan != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _buildNavigationPanel(context),
          ),
        if (_placePage != null && !useWorkbenchLayout)
          PlacePageSheet(
            data: _placePage!,
            onClose: _closePlacePage,
            onRouteTo: () => unawaited(_previewRouteToPlace(_placePage!)),
            routeInProgress: _navigationActionInProgress,
          ),
      ],
    );
  }

  Widget _buildSearchOverlay(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final resultPanelMaxHeight = max(
      120.0,
      min(220.0, screenHeight - viewInsets.bottom - 140.0),
    );
    return Material(
      color: colorScheme.surface,
      elevation: 3,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            onChanged: _onSearchChanged,
            onTap: () {
              if (!_searchOpen) _toggleSearch();
            },
            decoration: InputDecoration(
              hintText: 'Search map',
              prefixIcon: IconButton(
                tooltip: _searchOpen ? 'Close search' : 'Open search',
                icon: Icon(_searchOpen ? Icons.close : Icons.search),
                onPressed: _toggleSearch,
              ),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                    ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          if (_searchOpen && _searchController.text.isNotEmpty)
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: resultPanelMaxHeight),
              child: _searchResults.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _nativeSearchRunning ? 'Searching...' : 'No results',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: _searchResults.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final result = _searchResults[index];
                        return ListTile(
                          leading: Icon(_searchResultIcon(result)),
                          title: Text(result.title),
                          subtitle: Text(result.subtitle),
                          trailing: result.isSuggestion
                              ? null
                              : IconButton(
                                  tooltip: 'Route',
                                  icon: const Icon(Icons.alt_route),
                                  onPressed: _navigationActionInProgress
                                      ? null
                                      : () => unawaited(
                                            _previewRouteToSearchResult(
                                              result,
                                            ),
                                          ),
                                ),
                          onTap: () => _focusSearchResult(result),
                        );
                      },
                    ),
            ),
        ],
      ),
    );
  }

  Widget _buildDesktopSearchActivity(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasQuery = _searchController.text.trim().isNotEmpty;
    final statusText = _nativeSearchRunning ? 'Searching...' : 'No results';

    return ColoredBox(
      color: colorScheme.surface,
      child: Column(
        children: [
          SizedBox(
            height: 34,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: colorScheme.outlineVariant),
                ),
              ),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                style: theme.textTheme.bodySmall,
                onChanged: _onSearchChanged,
                onTap: () {
                  if (!_searchOpen) {
                    setState(() {
                      _searchOpen = true;
                    });
                  }
                },
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search',
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  prefixIcon: const Icon(Icons.search, size: 16),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 30,
                    minHeight: 30,
                  ),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints.tightFor(
                            width: 30,
                            height: 30,
                          ),
                          padding: EdgeInsets.zero,
                          iconSize: 16,
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged('');
                          },
                          icon: const Icon(Icons.close),
                        ),
                  suffixIconConstraints: const BoxConstraints(
                    minWidth: 30,
                    minHeight: 30,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: !hasQuery
                ? _DesktopActivityEmptyState(
                    icon: Icons.search,
                    message:
                        'Type to search places, coordinates, or favorites.',
                  )
                : _searchResults.isEmpty
                    ? _DesktopActivityEmptyState(
                        icon: Icons.manage_search,
                        message: statusText,
                      )
                    : ListView.builder(
                        padding: EdgeInsets.zero,
                        itemExtent: 36,
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) {
                          final result = _searchResults[index];
                          return _DesktopSearchResultRow(
                            result: result,
                            icon: _searchResultIcon(result),
                            routeEnabled: !_navigationActionInProgress &&
                                !result.isSuggestion,
                            onTap: () => _focusSearchResult(result),
                            onRoute: result.isSuggestion
                                ? null
                                : () => unawaited(
                                      _previewRouteToSearchResult(result),
                                    ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  IconData _searchResultIcon(MapSearchResult result) {
    if (result.isSuggestion) return Icons.north_west;
    return switch (result.source) {
      MapSearchResultSource.coordinate => Icons.my_location_outlined,
      MapSearchResultSource.favorite => Icons.favorite_border,
      MapSearchResultSource.native => Icons.place_outlined,
    };
  }

  Future<void> _showLayerManagerSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final height = MediaQuery.sizeOf(context).height * 0.82;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: height),
            child: SingleChildScrollView(
              child: AdaptiveLayerManager(
                formFactor: ExampleFormFactor.mobile,
                nativeLayerState: _mapLayerState,
                buildings3dEnabled: _buildings3dEnabled,
                onNativeLayerStateChanged: _updateMapLayerState,
                onBuildings3dChanged: _updateBuildings3d,
                layerStore: _duckDBLayerStore,
                layerStoreStatus: _duckDBLayerStoreStatus,
                onRenderingRefresh: _refreshDuckDBNativeLayers,
                onEditFeature: _editDuckDBFeature,
                onClose: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMapControls(
    BuildContext context,
    ExampleFormFactor formFactor, {
    required bool showLayerButton,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface,
      elevation: 3,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showLayerButton) ...[
            IconButton(
              tooltip: 'Layers',
              icon: Icon(
                formFactor.isMobile
                    ? Icons.layers_outlined
                    : _duckDBLayerPanelVisible
                        ? Icons.layers
                        : Icons.layers_outlined,
              ),
              onPressed: () {
                if (formFactor.isMobile) {
                  unawaited(_showLayerManagerSheet());
                  return;
                }
                setState(() {
                  _duckDBLayerPanelVisible = !_duckDBLayerPanelVisible;
                });
              },
            ),
            const Divider(height: 1),
          ],
          IconButton(
            tooltip: 'Zoom in',
            icon: const Icon(Icons.add),
            onPressed: _zoomIn,
          ),
          const Divider(height: 1),
          IconButton(
            tooltip: 'Zoom out',
            icon: const Icon(Icons.remove),
            onPressed: _zoomOut,
          ),
          const Divider(height: 1),
          IconButton(
            tooltip: 'Reset north',
            icon: ValueListenableBuilder<double>(
              valueListenable: _currentBearing,
              child: const Icon(Icons.navigation),
              builder: (context, bearing, child) {
                final safeBearing = bearing.isFinite ? bearing : 0.0;
                final angle = -safeBearing * pi / 180;
                if (angle == 0.0 || !angle.isFinite) {
                  return child!;
                }
                return Transform.rotate(angle: angle, child: child);
              },
            ),
            onPressed: _resetNorth,
          ),
          const Divider(height: 1),
          IconButton(
            tooltip: 'Current position',
            icon: _isLocating
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location),
            onPressed: _isLocating ? null : _centerOnCurrentPosition,
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationPanel(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final plan = _navigationPlan;
    if (plan == null) return const SizedBox.shrink();

    final status = _navigationStatus;
    final canStart = status != null &&
        status.isBuilt &&
        status.isValid &&
        !status.isFollowing &&
        !_navigationActionInProgress;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Material(
          color: colorScheme.surface,
          elevation: 6,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final summary = Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: colorScheme.primaryContainer,
                      child: Icon(
                        status?.isFollowing == true
                            ? Icons.navigation
                            : Icons.alt_route,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            plan.destination.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium,
                          ),
                          Text(
                            _navigationStatusText(status, plan),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );

                final actions = Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconButton(
                      tooltip: 'Refresh route status',
                      icon: const Icon(Icons.refresh),
                      onPressed: _refreshNavigationStatus,
                    ),
                    FilledButton.icon(
                      onPressed: canStart ? _startRouteFollowing : null,
                      icon: const Icon(Icons.navigation),
                      label: const Text('Start'),
                    ),
                    IconButton(
                      tooltip: 'Clear route',
                      icon: const Icon(Icons.close),
                      onPressed: _clearNavigationRoute,
                    ),
                  ],
                );

                if (constraints.maxWidth < 430) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      summary,
                      const SizedBox(height: 8),
                      Align(alignment: Alignment.centerRight, child: actions),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: summary),
                    const SizedBox(width: 8),
                    actions,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  String _navigationStatusText(
    agus_maps_flutter.NavigationStatus? status,
    _NavigationPlan plan,
  ) {
    if (_navigationActionInProgress) return 'Preparing route...';
    if (status == null) return 'Route requested from ${plan.startLabel}';
    if (status.isBuilding) return 'Building route from ${plan.startLabel}...';
    if (status.isFollowing) {
      return _appendRouteSummary('Guidance active', status);
    }
    if (status.isBuilt && status.isValid) {
      return _appendRouteSummary('Route ready from ${plan.startLabel}', status);
    }
    if (status.isActive && !status.isValid) {
      return 'No valid route for these points';
    }
    return _navigationSessionText(status.sessionState);
  }

  String _appendRouteSummary(
    String prefix,
    agus_maps_flutter.NavigationStatus status,
  ) {
    final details = <String>[];
    final distance = _formatNavigationDistance(status.distanceToTarget);
    if (distance.isNotEmpty) details.add(distance);
    final duration = _formatNavigationDuration(status.totalTimeSeconds);
    if (duration.isNotEmpty) details.add(duration);
    if (details.isEmpty) return prefix;
    return '$prefix - ${details.join(' - ')}';
  }

  String _formatNavigationDistance(
    agus_maps_flutter.NavigationDistance distance,
  ) {
    if (!distance.value.isFinite || distance.value <= 0) return '';
    final suffix = switch (distance.unit) {
      agus_maps_flutter.NavigationDistanceUnit.meters => 'm',
      agus_maps_flutter.NavigationDistanceUnit.kilometers => 'km',
      agus_maps_flutter.NavigationDistanceUnit.feet => 'ft',
      agus_maps_flutter.NavigationDistanceUnit.miles => 'mi',
    };
    final value = switch (distance.unit) {
      agus_maps_flutter.NavigationDistanceUnit.meters ||
      agus_maps_flutter.NavigationDistanceUnit.feet =>
        distance.value.round().toString(),
      agus_maps_flutter.NavigationDistanceUnit.kilometers ||
      agus_maps_flutter.NavigationDistanceUnit.miles =>
        distance.value.toStringAsFixed(distance.value >= 10 ? 0 : 1),
    };
    return '$value $suffix';
  }

  String _formatNavigationDuration(int totalSeconds) {
    if (totalSeconds <= 0) return '';
    final duration = Duration(seconds: totalSeconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${max(1, duration.inMinutes)}m';
  }

  String _navigationSessionText(
    agus_maps_flutter.NavigationSessionState sessionState,
  ) {
    return switch (sessionState) {
      agus_maps_flutter.NavigationSessionState.noValidRoute =>
        'Waiting for route',
      agus_maps_flutter.NavigationSessionState.routeBuilding =>
        'Building route...',
      agus_maps_flutter.NavigationSessionState.routeNotStarted => 'Route ready',
      agus_maps_flutter.NavigationSessionState.onRoute => 'On route',
      agus_maps_flutter.NavigationSessionState.routeNeedsRebuild =>
        'Route needs rebuild',
      agus_maps_flutter.NavigationSessionState.routeFinished =>
        'Route finished',
      agus_maps_flutter.NavigationSessionState.routeNoFollowing =>
        'Route preview ready',
      agus_maps_flutter.NavigationSessionState.routeRebuilding =>
        'Rebuilding route...',
    };
  }

  Widget _buildDesktopFavoritesActivity(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return ColoredBox(
      color: colorScheme.surface,
      child: Column(
        children: [
          SizedBox(
            height: 28,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLowest,
                border: Border(
                  bottom: BorderSide(color: colorScheme.outlineVariant),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${kFavorites.length} FAVORITES',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemExtent: 30,
              itemCount: kFavorites.length,
              itemBuilder: (context, index) {
                final favorite = kFavorites[index];
                return _DesktopFavoriteRow(
                  favorite: favorite,
                  onTap: () => _onFavoriteSelected(favorite),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Full-screen favorites tab.
  Widget _buildFavoritesTab(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            border: Border(
              bottom: BorderSide(color: theme.dividerColor),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.favorite, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Favorites',
                style: theme.textTheme.titleLarge,
              ),
            ],
          ),
        ),
        // List
        Expanded(
          child: ListView.builder(
            itemCount: kFavorites.length,
            itemBuilder: (context, index) {
              final favorite = kFavorites[index];
              return ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.location_on),
                ),
                title: Text(favorite.name),
                subtitle: Text(
                  '${favorite.lat.toStringAsFixed(4)}, ${favorite.lon.toStringAsFixed(4)}',
                ),
                trailing: Text(
                  'Zoom ${favorite.zoom}',
                  style: theme.textTheme.bodySmall,
                ),
                onTap: () => _onFavoriteSelected(favorite),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Full-screen downloads tab.
  Widget _buildDownloadsTab({required bool isVisible}) {
    final dataPath = _dataPath;
    if (_mwmStorage == null || dataPath == null) {
      if (context.exampleFormFactor.isDesktop) {
        return const Center(
          child: _DesktopStaticStatus(
            icon: Icons.cloud_download_outlined,
            title: 'Preparing Downloads',
            subtitle: 'Initializing map catalog storage...',
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    return DownloadsTab(
      mwmStorage: _mwmStorage!,
      dataPath: dataPath,
      isVisible: isVisible,
      onMapsChanged: () {
        setState(() {});
      },
    );
  }
}
