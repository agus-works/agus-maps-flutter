import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:agus_design/agus_design.dart';
import 'package:agus_maps_flutter/agus_maps_flutter.dart' as agus_maps_flutter;
import 'package:agus_maps_flutter/mirror_service.dart';
import 'package:agus_maps_flutter/mwm_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'about_tab.dart';
import 'downloads_cache.dart';
import 'downloads_tab.dart';
import 'features/map/widgets/adaptive_layer_manager.dart';
import 'features/workbench/interaction_state_controller.dart';
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
  
  Map<String, Object?> toJson() => {
    'title': title,
    'subtitle': subtitle,
    'lat': lat,
    'lon': lon,
    'zoom': zoom,
    'source': source.name,
    'nativeIndex': nativeIndex,
    'isSuggestion': isSuggestion,
    'suggestion': suggestion,
  };
  
  static MapSearchResult fromJson(Map<String, Object?> json) {
    return MapSearchResult(
      title: json['title'] as String? ?? '',
      subtitle: json['subtitle'] as String? ?? '',
      lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
      lon: (json['lon'] as num?)?.toDouble() ?? 0.0,
      zoom: (json['zoom'] as num?)?.toInt() ?? 15,
      source: MapSearchResultSource.values.firstWhere(
        (s) => s.name == json['source'],
        orElse: () => MapSearchResultSource.favorite,
      ),
      nativeIndex: json['nativeIndex'] as int?,
      isSuggestion: json['isSuggestion'] as bool? ?? false,
      suggestion: json['suggestion'] as String? ?? '',
    );
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
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
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
              children: [
                Icon(
                  isError ? Icons.error_outline : Icons.open_with,
                  size: 16,
                  color: foreground,
                ),
                const SizedBox(width: 8),
                Expanded(
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

enum _PendingDrawingDecision { stay, cancel, commit }

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
  agus_maps_flutter.AgusLayerFeature? _activeDuckDBFeature;
  String _duckDBLayerStoreStatus = 'DuckDB layer store is starting';
  int _duckDBLayerRevision = 0;
  final WorkbenchController _workbenchController = WorkbenchController();
  final AppInteractionStateController _interactionStateController =
      AppInteractionStateController();
  final GlobalKey _mapViewportKey = GlobalKey();
  final GlobalKey _downloadsTabKey = GlobalKey(debugLabel: 'downloads-tab');
  bool _duckDBLayerPanelVisible = true;
  bool _mobileLayerManagerVisible = false;

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
  String? _lastCachedQuery;
  _NavigationPlan? _navigationPlan;
  agus_maps_flutter.NavigationStatus? _navigationStatus;

  final agus_maps_flutter.AgusMapController _mapController =
      agus_maps_flutter.AgusMapController();

  static const String _userDrawLayerId = 'example_user_draw';

  // MWM storage for tracking downloaded maps
  MwmStorage? _mwmStorage;
  final Set<String> _hiddenMwmLayerRegions = <String>{};
  MwmLayerOrderMode _mwmLayerOrderMode = MwmLayerOrderMode.byMap;
  CachedDownloadsData? _commandDownloadsCache;
  bool _commandDownloadsLoading = false;

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
    _interactionStateController.dispose();
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
  static const String _prefsKeyHiddenMwmLayers = 'hidden_mwm_layers';
  static const String _prefsKeyMwmLayerOrder = 'mwm_layer_order_mode';

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
      final hiddenMwmLayers =
          prefs.getStringList(_prefsKeyHiddenMwmLayers) ?? const <String>[];
      final mwmLayerOrder = MwmLayerOrderMode.values.firstWhere(
        (mode) => mode.name == prefs.getString(_prefsKeyMwmLayerOrder),
        orElse: () => MwmLayerOrderMode.byMap,
      );
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
        _hiddenMwmLayerRegions
          ..clear()
          ..addAll(hiddenMwmLayers);
        _mwmLayerOrderMode = mwmLayerOrder;
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
      _interactionStateController.enterRouting();
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
    _interactionStateController.enterIdle();
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
      unawaited(_refreshCommandDownloadsFeed());
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
        if (_hiddenMwmLayerRegions.contains(metadata.regionName)) {
          _log('Skipping hidden downloaded map ${metadata.regionName}');
          continue;
        }

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
      _activeDuckDBFeature = null;
      _duckDBDrawController = controller;
    });
    _log('Active edit layer changed: $layerId');
  }

  Future<void> _requestActiveDuckDBLayer(String layerId) async {
    final controller = _duckDBDrawController;
    if (controller == null ||
        layerId == _activeDuckDBLayerId ||
        !controller.isEditing) {
      _setActiveDuckDBLayer(layerId);
      return;
    }

    final canCommitPendingDrawing =
        controller.isDrawing && controller.canCommit;
    final decision = await showDialog<_PendingDrawingDecision>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Switch active layer?'),
        content: const Text(
          'A drawing or feature edit is in progress. Commit or cancel it before '
          'switching to another active layer.',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_PendingDrawingDecision.stay),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_PendingDrawingDecision.cancel),
            child: const Text('Cancel drawing'),
          ),
          FilledButton(
            onPressed: canCommitPendingDrawing
                ? () =>
                    Navigator.of(context).pop(_PendingDrawingDecision.commit)
                : null,
            child: const Text('Commit'),
          ),
        ],
      ),
    );

    if (!mounted ||
        decision == null ||
        decision == _PendingDrawingDecision.stay) {
      return;
    }
    if (decision == _PendingDrawingDecision.commit) {
      await controller.commit();
    } else {
      controller.cancel();
    }
    if (!mounted) return;
    _setActiveDuckDBLayer(layerId);
  }

  void _setDuckDBDrawTool(agus_maps_flutter.AgusDrawTool tool) {
    final controller = _duckDBDrawController;
    if (controller == null) return;

    // Handle state transitions based on the tool
    if (tool == agus_maps_flutter.AgusDrawTool.none) {
      // Exiting drawing mode
      controller.setTool(tool);
      _interactionStateController.enterIdle();
    } else if (!controller.isEditing) {
      // Starting a new drawing - safe to proceed
      _interactionStateController.enterDrawing(tool: tool.name);
      controller.setTool(tool);
    } else {
      // Drawing or editing is in progress - do nothing, rely on command enablement
      return;
    }

    _workbenchController.selectEditorTab(WorkbenchEditorTab.map);
    setState(() {
      if (tool != agus_maps_flutter.AgusDrawTool.none) {
        _mobileLayerManagerVisible = false;
      }
    });
  }

  Future<void> _editDuckDBFeature(
    agus_maps_flutter.AgusLayerFeature feature,
  ) async {
    if (feature.layerId != _activeDuckDBLayerId) {
      await _requestActiveDuckDBLayer(feature.layerId);
      if (!mounted || feature.layerId != _activeDuckDBLayerId) return;
    }

    final controller = _duckDBDrawController;
    if (controller == null) {
      _log('Move ignored because the DuckDB draw controller is unavailable.');
      return;
    }

    try {
      controller.beginEditFeature(feature);
      _interactionStateController.enterEditingFeature(featureId: feature.featureId);
      _workbenchController.selectEditorTab(WorkbenchEditorTab.map);
      setState(() {
        _activeDuckDBFeature = feature;
        _mobileLayerManagerVisible = false;
      });
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
      if (mounted) {
        setState(() {
          _duckDBLayerRevision++;
        });
      }
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
      if (controller == null || !controller.isEditing) return;
      controller.reprojectVertices();
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
        _interactionStateController.enterIdle();
      } else {
        _mobileLayerManagerVisible = false;
        _interactionStateController.enterSearch();
      }
    });
    if (_searchOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocusNode.requestFocus();
      });
    }
  }

  void _openSearch([String? query]) {
    if (query != null && query != _searchController.text) {
      _searchController.text = query;
      _searchController.selection = TextSelection.collapsed(
        offset: _searchController.text.length,
      );
      _onSearchChanged(query);
    }
    if (!_searchOpen) {
      setState(() {
        _searchOpen = true;
        _mobileLayerManagerVisible = false;
      });
      _interactionStateController.enterSearch(query: query);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_searchFocusNode.hasFocus) {
        _searchFocusNode.requestFocus();
      }
    });
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
    _lastCachedQuery = null;
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

  /// Computes a stable map data revision fingerprint based on MWM metadata.
  String _computeMapDataRevision() {
    final storage = _mwmStorage;
    if (storage == null) return 'no-mwm';
    
    final allMaps = storage.getAll();
    if (allMaps.isEmpty) return 'empty-mwm';
    
    // Sort by region name for stable fingerprint
    final sorted = allMaps.toList()
      ..sort((a, b) => a.regionName.compareTo(b.regionName));
    
    // Compute fingerprint from visible map names and versions
    final visibleMaps = sorted
        .where((m) => !_hiddenMwmLayerRegions.contains(m.regionName))
        .map((m) => '${m.regionName}:${m.snapshotVersion}')
        .join(',');
    
    return visibleMaps.isEmpty ? 'all-hidden' : visibleMaps;
  }
  
  /// Attempts to retrieve cached search results.
  List<MapSearchResult>? _getCachedSearchResults(
    String query,
    String locale,
  ) {
    final store = _duckDBLayerStore;
    if (store == null) return null;
    
    final normalizedQuery = query.trim().toLowerCase();
    final mapRevision = _computeMapDataRevision();
    
    try {
      final cached = store.searchCache(
        normalizedQuery: normalizedQuery,
        locale: locale,
        includeStale: false,
      );
      
      if (cached.isEmpty) return null;
      
      final entry = cached.first;
      if (entry.mapDataRevision != mapRevision) return null;
      
      final payload = entry.resultPayload['results'] as List<Object?>?;
      if (payload == null) return null;
      
      return payload
          .cast<Map<String, Object?>>()
          .map(MapSearchResult.fromJson)
          .toList(growable: false);
    } catch (e) {
      _log('Failed to retrieve cached search results: $e');
      return null;
    }
  }
  
  /// Caches search results for the given query.
  void _cacheSearchResults(
    String query,
    String locale,
    List<MapSearchResult> results,
  ) {
    final store = _duckDBLayerStore;
    if (store == null) return;
    
    final normalizedQuery = query.trim().toLowerCase();
    final mapRevision = _computeMapDataRevision();
    
    try {
      store.upsertSearchCache(
        agus_maps_flutter.AgusSearchCacheDraft(
          cacheId: '$normalizedQuery:$locale',
          normalizedQuery: normalizedQuery,
          locale: locale,
          mapDataRevision: mapRevision,
          mapDataFingerprint: mapRevision,
          resultPayload: {
            'results': results.map((r) => r.toJson()).toList(),
          },
          resultCount: results.length,
        ),
      );
      _lastCachedQuery = query;
    } catch (e) {
      _log('Failed to cache search results: $e');
    }
  }

  void _startNativeSearch(String query) {
    final trimmedQuery = query.trim();
    if (!mounted || trimmedQuery.isEmpty) return;
    if (_searchController.text.trim() != trimmedQuery) return;

    // Check cache first
    final locale = ui.PlatformDispatcher.instance.locale.toLanguageTag();
    final cachedResults = _getCachedSearchResults(trimmedQuery, locale);
    if (cachedResults != null && cachedResults.isNotEmpty) {
      setState(() {
        _searchResults = cachedResults;
        _nativeSearchRunning = false;
      });
      _log('Using cached search results for "$trimmedQuery" (${cachedResults.length} results)');
      // Still start native search in background to refresh cache
    }

    final generation = agus_maps_flutter.startNativeSearch(
      trimmedQuery,
      locale: locale,
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

    // Cache results when search completes successfully
    if (!snapshot.isRunning && !timedOut && mergedResults.isNotEmpty) {
      if (_lastCachedQuery != query) {
        _cacheSearchResults(query, ui.PlatformDispatcher.instance.locale.toLanguageTag(), mergedResults);
      }
    }

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
    
    // Keep search results visible after selection
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
      bodySafeAreaTop: _currentTabIndex != 0,
      bodySafeAreaLeft: _currentTabIndex != 0,
      bodySafeAreaRight: _currentTabIndex != 0,
      bodySafeAreaBottom: _currentTabIndex != 0,
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
        statusBarBuilder: _buildWorkbenchStatusBar,
        commandGroups: _buildWorkbenchCommandGroups(),
        commandAsyncProviders: _buildWorkbenchCommandAsyncProviders(),
      ),
    );
  }

  List<AgusCommandAsyncProvider> _buildWorkbenchCommandAsyncProviders() {
    return [
      (query) async {
        final trimmed = query.trim();
        if (trimmed.length < 2) return const <AgusCommandGroup>[];
        return [
          AgusCommandGroup(
            heading: 'Location Search',
            items: [
              AgusCommandItem(
                id: 'location-search-$trimmed',
                label: 'Search Location: $trimmed',
                icon: Icons.place_outlined,
                keywords: const ['native', 'place', 'address', 'coordinates'],
                onSelected: () {
                  _workbenchController.selectActivity(WorkbenchActivity.search);
                  _openSearch(trimmed);
                },
              ),
            ],
          ),
        ];
      },
    ];
  }

  List<AgusCommandGroup> _buildWorkbenchCommandGroups() {
    AgusCommandItem activityCommand({
      required String id,
      required String label,
      required IconData icon,
      required WorkbenchActivity activity,
      List<String> keywords = const <String>[],
    }) {
      return AgusCommandItem(
        id: id,
        label: label,
        icon: icon,
        keywords: keywords,
        onSelected: () {
          _workbenchController.selectActivity(activity);
        },
      );
    }

    AgusCommandItem drawCommand({
      required agus_maps_flutter.AgusDrawTool tool,
      required String label,
      required IconData icon,
      List<String> keywords = const <String>[],
    }) {
      final enabled = _duckDBLayerStore != null &&
          _interactionStateController.isOperationAllowed('draw');

      return AgusCommandItem(
        id: 'draw-${tool.name}',
        label: label,
        icon: icon,
        keywords: keywords,
        enabled: enabled,
        onSelected: () {
          if (!enabled) {
            final reason = _interactionStateController.disabledReason('draw');
            if (reason != null) {
              _showSnackBar(reason);
            }
            return;
          }
          _workbenchController.selectEditorTab(WorkbenchEditorTab.map);
          _workbenchController.selectActivity(WorkbenchActivity.explorer);
          _setDuckDBDrawTool(tool);
        },
      );
    }

    AgusCommandItem favoriteCommand(FavoriteLocation favorite) {
      return AgusCommandItem(
        id: 'favorite-${favorite.name.toLowerCase()}',
        label: 'Focus ${favorite.name}',
        icon: Icons.center_focus_strong,
        keywords: [
          'map',
          'location',
          favorite.lat.toStringAsFixed(4),
          favorite.lon.toStringAsFixed(4),
        ],
        onSelected: () {
          _workbenchController.selectEditorTab(WorkbenchEditorTab.map);
          _mapController.moveToLocation(
            favorite.lat,
            favorite.lon,
            favorite.zoom,
          );
          setState(() {
            _currentTabIndex = 0;
          });
        },
      );
    }

    AgusCommandItem mwmLayerCommand(MwmLayerInfo layer) {
      return AgusCommandItem(
        id: 'mwm-layer-${layer.regionName}',
        label: 'Focus MWM Map: ${layer.regionName}',
        icon: Icons.map_outlined,
        keywords: [
          'mwm',
          'layer',
          'focus',
          layer.snapshotVersion,
          if (layer.isBundled) 'bundled' else 'downloaded',
        ],
        onSelected: () => _focusMwmLayer(layer),
      );
    }

    AgusCommandItem mwmDownloadCommand(MwmRegion region) {
      final downloaded = _mwmStorage?.getByRegion(region.name);
      final latestVersion = _commandDownloadsCache?.snapshotVersion;
      final hasUpdate = downloaded != null &&
          latestVersion != null &&
          (_mwmStorage?.hasUpdate(region.name, latestVersion) ?? false);
      return AgusCommandItem(
        id: 'mwm-download-${region.name}',
        label: downloaded == null
            ? 'Download Map: ${region.displayName}'
            : hasUpdate
                ? 'Update Map: ${region.displayName}'
                : 'Open Downloaded Map: ${region.displayName}',
        icon: downloaded == null
            ? Icons.download_outlined
            : hasUpdate
                ? Icons.system_update_alt
                : Icons.map_outlined,
        keywords: [
          'mwm',
          'comaps',
          'download',
          'map',
          region.name,
          if (downloaded != null) 'installed',
          if (hasUpdate) 'update',
        ],
        onSelected: () {
          if (downloaded != null && !hasUpdate) {
            _focusMwmLayer(
              MwmLayerInfo(
                regionName: downloaded.regionName,
                snapshotVersion: downloaded.snapshotVersion,
                fileSize: downloaded.fileSize,
                filePath: downloaded.filePath,
                isBundled: downloaded.isBundled,
                visible:
                    !_hiddenMwmLayerRegions.contains(downloaded.regionName),
              ),
            );
            return;
          }
          unawaited(_downloadMwmRegionFromCommand(region));
        },
      );
    }

    final mwmLayers = _mwmLayerInfos();
    final cachedMwmRegions = _commandDownloadsCache == null
        ? <MwmRegion>[]
        : _flattenMwmRegions(_commandDownloadsCache!.regions)
            .where((region) => region.name != 'WorldCoasts')
            .toList();
    cachedMwmRegions.sort((a, b) => a.displayName.compareTo(b.displayName));

    return [
      AgusCommandGroup(
        heading: 'Navigation',
        items: [
          activityCommand(
            id: 'show-project-layers',
            label: 'Show Project Layers',
            icon: Icons.account_tree_outlined,
            activity: WorkbenchActivity.explorer,
            keywords: const ['explorer', 'layers', 'duckdb'],
          ),
          AgusCommandItem(
            id: 'search-map',
            label: 'Search Map',
            icon: Icons.search,
            keywords: const ['places', 'coordinates', 'favorites'],
            onSelected: () {
              _workbenchController.selectActivity(WorkbenchActivity.search);
              _openSearch();
            },
          ),
          activityCommand(
            id: 'show-downloads',
            label: 'Show Downloads',
            icon: Icons.download_outlined,
            activity: WorkbenchActivity.downloads,
            keywords: const ['maps', 'mwm', 'update'],
          ),
          activityCommand(
            id: 'show-favorites',
            label: 'Show Favorites',
            icon: Icons.favorite_border,
            activity: WorkbenchActivity.favorites,
            keywords: const ['locations', 'places'],
          ),
          activityCommand(
            id: 'open-settings',
            label: 'Open Settings',
            icon: Icons.settings_outlined,
            activity: WorkbenchActivity.settings,
            keywords: const ['preferences'],
          ),
        ],
      ),
      AgusCommandGroup(
        heading: 'Workbench',
        items: [
          AgusCommandItem(
            id: 'open-map-editor',
            label: 'Open Map Editor',
            icon: Icons.map_outlined,
            keywords: const ['editor'],
            onSelected: () {
              _workbenchController.selectEditorTab(WorkbenchEditorTab.map);
            },
          ),
          AgusCommandItem(
            id: 'toggle-panel',
            label: 'Toggle Panel',
            icon: Icons.horizontal_split_outlined,
            keywords: const ['bottom', 'debug', 'poi'],
            onSelected: _workbenchController.togglePanel,
          ),
          AgusCommandItem(
            id: 'toggle-secondary-sidebar',
            label: 'Toggle Properties Sidebar',
            icon: Icons.vertical_split_outlined,
            keywords: const ['inspector', 'right pane'],
            onSelected: _workbenchController.toggleSecondarySideBar,
          ),
        ],
      ),
      AgusCommandGroup(
        heading: 'Drawing',
        items: [
          drawCommand(
            tool: agus_maps_flutter.AgusDrawTool.pin,
            label: 'Draw Point Feature',
            icon: Icons.add_location_alt_outlined,
          ),
          drawCommand(
            tool: agus_maps_flutter.AgusDrawTool.segment,
            label: 'Draw Segment Feature',
            icon: Icons.linear_scale,
          ),
          drawCommand(
            tool: agus_maps_flutter.AgusDrawTool.line,
            label: 'Draw Line Feature',
            icon: Icons.timeline,
          ),
          drawCommand(
            tool: agus_maps_flutter.AgusDrawTool.polygon,
            label: 'Draw Polygon Feature',
            icon: Icons.polyline_outlined,
          ),
        ],
      ),
      AgusCommandGroup(
        heading: 'Map Focus',
        items: [for (final favorite in kFavorites) favoriteCommand(favorite)],
      ),
      if (mwmLayers.isNotEmpty)
        AgusCommandGroup(
          heading: 'MWM Layers',
          items: [for (final layer in mwmLayers) mwmLayerCommand(layer)],
        ),
      AgusCommandGroup(
        heading: _commandDownloadsLoading
            ? 'MWM Downloads (loading)'
            : 'MWM Downloads',
        items: [
          AgusCommandItem(
            id: 'refresh-mwm-command-feed',
            label: 'Refresh MWM Catalog',
            icon: Icons.refresh,
            keywords: const ['downloads', 'maps', 'mirror', 'cache'],
            enabled: !_commandDownloadsLoading,
            onSelected: () {
              unawaited(_refreshCommandDownloadsFeed(forceNetwork: true));
            },
          ),
          for (final region in cachedMwmRegions) mwmDownloadCommand(region),
        ],
      ),
    ];
  }

  AgusStatusBar _buildWorkbenchStatusBar(
    BuildContext context,
    WorkbenchLayoutState state,
  ) {
    final layerStoreReady = _duckDBLayerStore != null;
    final hasError = _status.toLowerCase().startsWith('error');
    final activeLayerName = _activeDuckDBLayerName();
    final activeFeatureName = _activeDuckDBFeatureName();

    // Build map telemetry items when Explorer is active and map editor is visible
    final showMapTelemetry = state.activeActivity == WorkbenchActivity.explorer &&
        state.activeEditorTab == WorkbenchEditorTab.map;
    final mapTelemetryItems = showMapTelemetry ? _buildMapTelemetryItems(context) : <AgusStatusBarItem>[];

    return AgusStatusBar(
      leftItems: [
        AgusStatusBarItem(
          id: 'map-status',
          label: _status,
          icon: hasError ? Icons.error_outline : Icons.public,
          progress: !_dataReady && !hasError,
          severity: hasError
              ? AgusStatusBarItemSeverity.error
              : AgusStatusBarItemSeverity.standard,
        ),
        AgusStatusBarItem(
          id: 'activity',
          label: state.activeActivity.label,
          icon: state.activeActivity.icon,
        ),
        if (_placePage != null)
          const AgusStatusBarItem(
            id: 'selection',
            label: 'Place selected',
            icon: Icons.place,
          ),
        // Add map telemetry items (zoom, bearing, center, selected point)
        ...mapTelemetryItems,
      ],
      rightItems: [
        AgusStatusBarItem(
          id: 'layers',
          label: layerStoreReady ? 'Layers ready' : 'Layers starting',
          icon: Icons.layers_outlined,
          progress: !layerStoreReady,
        ),
        AgusStatusBarItem(
          id: 'active-layer',
          label: 'Layer: $activeLayerName',
          icon: Icons.layers_outlined,
        ),
        AgusStatusBarItem(
          id: 'active-feature',
          label: 'Feature: $activeFeatureName',
          icon: Icons.polyline_outlined,
        ),
        AgusStatusBarItem(
          id: 'map-scale',
          label: '${_mapScale.toStringAsFixed(2)}x',
          icon: Icons.zoom_in_map,
        ),
        AgusStatusBarItem(
          id: 'editor',
          label: state.activeEditorTab.label,
          icon: state.activeEditorTab.icon,
        ),
      ],
    );
  }

  List<AgusStatusBarItem> _buildMapTelemetryItems(BuildContext context) {
    // Get current map state from native APIs
    final center = agus_maps_flutter.getViewportCenter();
    final zoom = agus_maps_flutter.getCurrentZoom();
    final bearing = agus_maps_flutter.getCurrentBearing();

    // Return empty list if map state is not available
    if (center == null || zoom == null) {
      return <AgusStatusBarItem>[];
    }

    // Get selected point from place page if available
    double? selectedLat;
    double? selectedLon;
    if (_placePage != null) {
      selectedLat = _placePage!.lat;
      selectedLon = _placePage!.lon;
    }

    // Build telemetry model
    final telemetry = MapTelemetry(
      zoom: zoom,
      centerLat: center.lat,
      centerLon: center.lon,
      bearing: bearing,
      selectedPointLat: selectedLat,
      selectedPointLon: selectedLon,
    );

    // Build status bar items with copy-to-clipboard support
    return MapTelemetryStatusBarBuilder.buildItems(
      context: context,
      telemetry: telemetry,
    );
  }

  String _activeDuckDBLayerName() {
    final store = _duckDBLayerStore;
    if (store == null) return _activeDuckDBLayerId;
    for (final layer in store.listLayers()) {
      if (layer.layerId == _activeDuckDBLayerId) return layer.name;
    }
    return _activeDuckDBLayerId;
  }

  String _activeDuckDBFeatureName() {
    final feature = _activeDuckDBFeature;
    if (feature == null) return 'None';
    final title = feature.properties['title'];
    if (title is String && title.trim().isNotEmpty) return title.trim();
    return feature.featureId;
  }

  List<MwmLayerInfo> _mwmLayerInfos() {
    final storage = _mwmStorage;
    if (storage == null) return const <MwmLayerInfo>[];
    // Use the new getAllOrdered method which returns all versions sorted
    final maps = storage.getAllOrdered(_mwmLayerOrderMode);
    return [
      for (final metadata in maps)
        MwmLayerInfo(
          regionName: metadata.regionName,
          snapshotVersion: metadata.snapshotVersion,
          fileSize: metadata.fileSize,
          filePath: metadata.filePath,
          isBundled: metadata.isBundled,
          visible: metadata.isBundled ||
              !_hiddenMwmLayerRegions.contains(metadata.regionName),
          isActive: metadata.isActive,
        ),
    ];
  }

  Future<void> _setMwmLayerVisibility(
    String regionName,
    bool visible,
  ) async {
    final metadata = _mwmStorage?.getByRegion(regionName);
    if (!visible && metadata?.isBundled == true) {
      _hiddenMwmLayerRegions.remove(regionName);
      _showSnackBar(
        'Bundled map $regionName cannot be hidden until native MWM '
        'unregistration is available.',
      );
      return;
    }

    if (visible) {
      _hiddenMwmLayerRegions.remove(regionName);
    } else {
      _hiddenMwmLayerRegions.add(regionName);
    }
    
    // Invalidate search cache when map visibility changes
    final store = _duckDBLayerStore;
    if (store != null) {
      store.invalidateAllSearchCache(reason: 'mwm_visibility:$regionName:$visible');
    }
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _prefsKeyHiddenMwmLayers,
      _hiddenMwmLayerRegions.toList()..sort(),
    );

    if (visible) {
      if (metadata != null && !metadata.isBundled) {
        _registerMwmMetadata(metadata);
      }
    }

    if (!mounted) return;
    setState(() {});
    _showSnackBar(
      visible
          ? 'Enabled $regionName. Downloaded maps are registered immediately.'
          : 'Disabled $regionName. It will be skipped on the next map startup.',
    );
  }

  Future<void> _setMwmLayerOrderMode(MwmLayerOrderMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyMwmLayerOrder, mode.name);
    if (!mounted) return;
    setState(() {
      _mwmLayerOrderMode = mode;
    });
  }

  void _focusMwmLayer(MwmLayerInfo layer) {
    final fix = _knownLocationForMapName(layer.regionName);
    if (fix != null) {
      _workbenchController.selectEditorTab(WorkbenchEditorTab.map);
      _mapController.moveToLocation(fix.lat, fix.lon, fix.zoom);
      _showSnackBar(fix.message ?? 'Focused ${layer.regionName}');
      return;
    }
    _workbenchController.selectActivity(WorkbenchActivity.search);
    _openSearch(layer.regionName);
    _showSnackBar('Searching for ${layer.regionName}');
  }

  void _focusProjectLayer(String layerId) {
    final store = _duckDBLayerStore;
    if (store == null) return;

    final focusCenter = store.getLayerFocusCenter(layerId);
    if (focusCenter == null) {
      _showSnackBar('Cannot focus: layer center not calculated');
      return;
    }

    _workbenchController.selectEditorTab(WorkbenchEditorTab.map);
    _mapController.moveToLocation(
      focusCenter.latitude,
      focusCenter.longitude,
      14, // Default zoom level
    );
    _showSnackBar('Focused on layer');
  }

  void _focusProjectFeature(agus_maps_flutter.AgusLayerFeature feature) {
    final store = _duckDBLayerStore;
    if (store == null) return;

    final focusCenter = store.getFeatureFocusCenter(feature.layerId, feature.featureId);
    if (focusCenter == null) {
      _showSnackBar('Cannot focus: feature center not calculated');
      return;
    }

    _workbenchController.selectEditorTab(WorkbenchEditorTab.map);
    _mapController.moveToLocation(
      focusCenter.latitude,
      focusCenter.longitude,
      16, // Higher zoom for features
    );
    _showSnackBar('Focused on feature');
  }

  Future<void> _deleteMwmLayer(MwmLayerInfo layer) async {
    final storage = _mwmStorage;
    if (storage == null) return;
    final result = await storage.deleteMap(layer.regionName);
    if (!mounted) return;
    setState(() {});
    
    // Invalidate search cache when map is deleted
    final store = _duckDBLayerStore;
    if (store != null) {
      store.invalidateAllSearchCache(reason: 'mwm_deleted:${layer.regionName}');
    }
    
    _showSnackBar(
      result.success
          ? 'Deleted ${layer.regionName}'
          : result.error ?? 'Could not delete ${layer.regionName}',
    );
  }

  void _updateMwmLayer(MwmLayerInfo layer) {
    final region = _cachedRegionByName(layer.regionName);
    if (region == null) {
      _workbenchController.selectActivity(WorkbenchActivity.downloads);
      _showSnackBar('Open Downloads to refresh ${layer.regionName}.');
      return;
    }
    unawaited(_downloadMwmRegionFromCommand(region));
  }

  MwmRegion? _cachedRegionByName(String regionName) {
    final cache = _commandDownloadsCache;
    if (cache == null) return null;
    for (final region in _flattenMwmRegions(cache.regions)) {
      if (region.name == regionName) return region;
    }
    return null;
  }

  List<MwmRegion> _flattenMwmRegions(List<MwmRegion> regions) {
    return [
      for (final region in regions)
        if (region.isGroup) ..._flattenMwmRegions(region.children) else region,
    ];
  }

  _LocationFix? _knownLocationForMapName(String regionName) {
    final normalized = regionName.toLowerCase().replaceAll('_', ' ');
    if (normalized == 'gibraltar') {
      return const _LocationFix(
        lat: 36.1407,
        lon: -5.3535,
        zoom: 14,
        message: 'Focused Gibraltar',
      );
    }
    if (normalized == 'world' || normalized == 'worldcoasts') {
      return const _LocationFix(
        lat: 20,
        lon: 0,
        zoom: 2,
        message: 'Focused the world map',
      );
    }
    for (final favorite in kFavorites) {
      if (favorite.name.toLowerCase() == normalized) {
        return _LocationFix(
          lat: favorite.lat,
          lon: favorite.lon,
          zoom: favorite.zoom,
          message: 'Focused ${favorite.name}',
        );
      }
    }
    return null;
  }

  int _registerMwmMetadata(MwmMetadata metadata) {
    // Invalidate search cache when map is registered
    final store = _duckDBLayerStore;
    if (store != null) {
      store.invalidateAllSearchCache(reason: 'mwm_registered:${metadata.regionName}');
    }
    
    final parsed = int.tryParse(metadata.snapshotVersion);
    return parsed != null
        ? agus_maps_flutter.registerSingleMapWithVersion(
            metadata.filePath,
            parsed,
          )
        : agus_maps_flutter.registerSingleMap(metadata.filePath);
  }

  void _showSnackBar(String message) {
    _scaffoldMessengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _refreshCommandDownloadsFeed({bool forceNetwork = false}) async {
    if (_commandDownloadsLoading) return;
    if (!mounted) return;
    setState(() {
      _commandDownloadsLoading = true;
    });
    final cacheService = DownloadsCacheService();
    try {
      final cached = await cacheService.loadCache();
      if (cached != null && mounted) {
        setState(() {
          _commandDownloadsCache = cached;
        });
      }
      if (cached != null && (!forceNetwork || !cached.isStale())) {
        if (!mounted) return;
        setState(() {
          _commandDownloadsLoading = false;
        });
        return;
      }

      final mirrorService = MirrorService();
      await mirrorService.measureLatencies();
      final mirror = mirrorService.getFastestMirror();
      if (mirror == null) {
        if (!mounted) return;
        setState(() {
          _commandDownloadsCache = cached;
          _commandDownloadsLoading = false;
        });
        return;
      }
      final snapshots = await mirrorService.getSnapshots(mirror);
      if (snapshots.isEmpty) {
        if (!mounted) return;
        setState(() {
          _commandDownloadsCache = cached;
          _commandDownloadsLoading = false;
        });
        return;
      }
      final snapshot = snapshots.first;
      final countries = await mirrorService.getCountriesData(mirror, snapshot);
      final fresh = CachedDownloadsData(
        mirrorName: mirror.name,
        mirrorBaseUrl: mirror.baseUrl,
        snapshotVersion: snapshot.version,
        regions: countries.regions,
        cachedAt: DateTime.now(),
      );
      await cacheService.saveCache(fresh);
      if (!mounted) return;
      setState(() {
        _commandDownloadsCache = fresh;
        _commandDownloadsLoading = false;
      });
    } catch (e) {
      _log('Warning: Failed to refresh command downloads feed: $e');
      if (!mounted) return;
      setState(() {
        _commandDownloadsLoading = false;
      });
    }
  }

  Future<void> _downloadMwmRegionFromCommand(MwmRegion region) async {
    final cache = _commandDownloadsCache;
    final storage = _mwmStorage;
    final dataPath = _dataPath;
    if (cache == null || storage == null || dataPath == null) {
      _workbenchController.selectActivity(WorkbenchActivity.downloads);
      _showSnackBar('Downloads are still preparing.');
      return;
    }

    final existing = storage.getByRegion(region.name);
    if (existing != null &&
        !storage.hasUpdate(region.name, cache.snapshotVersion)) {
      _showSnackBar('${region.displayName} is already downloaded.');
      return;
    }

    if (!mounted) return;
    setState(() {
      _status = existing == null
          ? 'Downloading ${region.displayName}...'
          : 'Updating ${region.displayName}...';
    });

    final mirrorService = MirrorService(customMirrors: [cache.mirror]);
    final url =
        mirrorService.getDownloadUrl(cache.mirror, cache.snapshot, region);
    final mapsDir =
        _targetMwmDirectory(region, cache.snapshotVersion, dataPath);
    final filePath = '${mapsDir.path}/${region.fileName}';
    final tempFile = File('$filePath.download');
    final finalFile = File(filePath);
    try {
      await mapsDir.create(recursive: true);
      final bytesWritten = await mirrorService.downloadToFile(url, tempFile);
      if (region.sizeBytes > 0 && bytesWritten != region.sizeBytes) {
        await tempFile.delete();
        throw Exception(
          'Downloaded size mismatch: expected ${region.sizeBytes} bytes, '
          'got $bytesWritten bytes',
        );
      }
      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      await tempFile.rename(filePath);
      await storage.upsert(
        MwmMetadata(
          regionName: region.name,
          snapshotVersion: cache.snapshotVersion,
          fileSize: bytesWritten,
          downloadDate: DateTime.now(),
          filePath: filePath,
          isBundled: false,
        ),
      );
      final metadata = storage.getByRegion(region.name);
      if (metadata != null && !_hiddenMwmLayerRegions.contains(region.name)) {
        _registerMwmMetadata(metadata);
      }
      agus_maps_flutter.invalidateMap();
      agus_maps_flutter.forceRedraw();
      if (!mounted) return;
      setState(() {
        _status = 'Map ready!';
      });
      _showSnackBar(
        existing == null
            ? 'Downloaded ${region.displayName}'
            : 'Updated ${region.displayName}',
      );
    } catch (e) {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      if (!mounted) return;
      setState(() {
        _status = 'Map ready!';
      });
      _showSnackBar('Failed to download ${region.displayName}: $e');
    }
  }

  Directory _targetMwmDirectory(
    MwmRegion region,
    String snapshotVersion,
    String dataPath,
  ) {
    if (region.fileName == 'World.mwm' ||
        region.fileName == 'WorldCoasts.mwm') {
      return Directory(dataPath);
    }
    return Directory('$dataPath/$snapshotVersion');
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
          layerStoreRevision: _duckDBLayerRevision,
          mwmLayers: _mwmLayerInfos(),
          mwmLayerOrderMode: _mwmLayerOrderMode,
          onMwmLayerVisibilityChanged: (regionName, visible) {
            unawaited(_setMwmLayerVisibility(regionName, visible));
          },
          onMwmLayerDeleted: (layer) {
            unawaited(_deleteMwmLayer(layer));
          },
          onMwmLayerUpdated: _updateMwmLayer,
          onMwmLayerFocused: _focusMwmLayer,
          onProjectLayerFocused: _focusProjectLayer,
          onFeatureFocused: _focusProjectFeature,
          onMwmLayerOrderChanged: (mode) {
            unawaited(_setMwmLayerOrderMode(mode));
          },
          onRenderingRefresh: _refreshDuckDBNativeLayers,
          onActiveLayerChanged: (layerId) {
            unawaited(_requestActiveDuckDBLayer(layerId));
          },
          onActiveFeatureChanged: (feature) {
            setState(() {
              _activeDuckDBFeature = feature;
            });
          },
          onDrawToolChanged: _setDuckDBDrawTool,
          onEditFeature: (feature) => unawaited(_editDuckDBFeature(feature)),
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
      theme: AgusThemeData.light().toThemeData(),
      darkTheme: AgusThemeData.dark().toThemeData(),
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
    final mediaPadding = MediaQuery.paddingOf(context);
    final screenSize = MediaQuery.sizeOf(context);
    final screenHeight = screenSize.height;
    final mobileLandscape =
        formFactor.isMobile && screenSize.width > screenSize.height;
    final mobileSidePanelWidth = min(
      390.0,
      max(320.0, screenSize.width * 0.46),
    );
    final mobileLayerPanelHeight = min(420.0, max(280.0, screenHeight * 0.46));
    final mobileOverlayTop = formFactor.isMobile ? mediaPadding.top + 10 : 12.0;
    final mobileControlsRight = max(12.0, mediaPadding.right + 12) +
        (mobileLandscape && (_mobileLayerManagerVisible || _placePage != null)
            ? mobileSidePanelWidth + 12
            : 0);
    final effectiveControlsBottom = formFactor.isMobile
        ? mobileLandscape
            ? max(mediaPadding.bottom + 12, routePanelVisible ? 116.0 : 12.0)
            : max(
                controlsBottom,
                _mobileLayerManagerVisible ? mobileLayerPanelHeight + 24 : 24.0,
              )
        : controlsBottom;
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
        if (!useWorkbenchLayout && formFactor.isMobile && _searchOpen)
          if (mobileLandscape)
            Positioned(
              top: mobileOverlayTop,
              bottom: mediaPadding.bottom + 10,
              left: 12,
              width: mobileSidePanelWidth,
              child: _buildSearchOverlay(context, expandToFill: true),
            )
          else
            Positioned(
              top: mobileOverlayTop,
              left: 12,
              right: 12,
              child: _buildSearchOverlay(context),
            )
        else if (!useWorkbenchLayout && !formFactor.isMobile)
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
                        layerStoreRevision: _duckDBLayerRevision,
                        mwmLayers: _mwmLayerInfos(),
                        mwmLayerOrderMode: _mwmLayerOrderMode,
                        onMwmLayerVisibilityChanged: (regionName, visible) {
                          unawaited(
                            _setMwmLayerVisibility(regionName, visible),
                          );
                        },
                        onMwmLayerDeleted: (layer) {
                          unawaited(_deleteMwmLayer(layer));
                        },
                        onMwmLayerUpdated: _updateMwmLayer,
                        onMwmLayerFocused: _focusMwmLayer,
                        onProjectLayerFocused: _focusProjectLayer,
                        onFeatureFocused: _focusProjectFeature,
                        onMwmLayerOrderChanged: (mode) {
                          unawaited(_setMwmLayerOrderMode(mode));
                        },
                        onRenderingRefresh: _refreshDuckDBNativeLayers,
                        onActiveLayerChanged: (layerId) {
                          unawaited(_requestActiveDuckDBLayer(layerId));
                        },
                        onActiveFeatureChanged: (feature) {
                          setState(() {
                            _activeDuckDBFeature = feature;
                          });
                        },
                        onDrawToolChanged: _setDuckDBDrawTool,
                        onEditFeature: (feature) =>
                            unawaited(_editDuckDBFeature(feature)),
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
        if (drawController != null && !formFactor.isMobile)
          Positioned.fill(
            child: agus_maps_flutter.DuckDBLayerDrawOverlay(
              controller: drawController,
            ),
          ),
        if (drawController != null && !formFactor.isMobile)
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
                    _interactionStateController.enterIdle();
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
            top: formFactor.isMobile ? mediaPadding.top + 74 : 76,
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
            top: mobileOverlayTop,
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
        if (formFactor.isMobile)
          Positioned(
            top: mobileOverlayTop,
            right: mobileControlsRight,
            bottom: effectiveControlsBottom,
            child: _buildMapControls(
              context,
              formFactor,
              showLayerButton: !useWorkbenchLayout,
            ),
          )
        else
          Positioned(
            right: 12,
            bottom: effectiveControlsBottom,
            child: _buildMapControls(
              context,
              formFactor,
              showLayerButton: !useWorkbenchLayout,
            ),
          ),
        if (!useWorkbenchLayout &&
            formFactor.isMobile &&
            _mobileLayerManagerVisible)
          _buildMobileLayerManagerOverlay(
            context,
            mobileLayerPanelHeight,
            mobileLandscape: mobileLandscape,
            sidePanelWidth: mobileSidePanelWidth,
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
            mobileLandscape: mobileLandscape,
          ),
      ],
    );
  }

  Widget _buildSearchOverlay(
    BuildContext context, {
    bool expandToFill = false,
  }) {
    final theme = Theme.of(context);
    final colors = AgusThemeData.colorsOf(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final resultPanelMaxHeight = max(
      120.0,
      min(220.0, screenHeight - viewInsets.bottom - 140.0),
    );
    final hasSearchResults = _searchOpen && _searchController.text.isNotEmpty;
    final resultPanel = _searchResults.isEmpty
        ? Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Align(
              alignment: Alignment.topLeft,
              child: Text(
                _nativeSearchRunning ? 'Searching...' : 'No results',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          )
        : ListView.separated(
            shrinkWrap: !expandToFill,
            padding: EdgeInsets.zero,
            itemCount: _searchResults.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: colors.sideBarBorder),
            itemBuilder: (context, index) {
              final result = _searchResults[index];
              return _DesktopSearchResultRow(
                result: result,
                icon: _searchResultIcon(result),
                routeEnabled:
                    !_navigationActionInProgress && !result.isSuggestion,
                onTap: () => _focusSearchResult(result),
                onRoute: result.isSuggestion
                    ? null
                    : () => unawaited(_previewRouteToSearchResult(result)),
              );
            },
          );

    return Material(
      color: colors.sideBarBackground,
      elevation: 3,
      borderRadius: BorderRadius.circular(4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: colors.sideBarBorder),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          mainAxisSize: expandToFill ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: AgusSearchBox(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      placeholder: 'Search map',
                      onTap: _openSearch,
                      onChanged: _onSearchChanged,
                      onSubmitted: (_) {
                        if (_searchResults.isNotEmpty) {
                          _focusSearchResult(_searchResults.first);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  AgusButton.icon(
                    icon: _searchOpen ? Icons.close : Icons.search,
                    tooltip: _searchOpen ? 'Close search' : 'Open search',
                    onPressed: _toggleSearch,
                  ),
                ],
              ),
            ),
            if (hasSearchResults)
              if (expandToFill)
                Expanded(child: resultPanel)
              else
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: resultPanelMaxHeight),
                  child: resultPanel,
                ),
          ],
        ),
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
            height: 42,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: colorScheme.outlineVariant),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(7),
                child: AgusSearchBox(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  placeholder: 'Search',
                  onTap: _openSearch,
                  onChanged: _onSearchChanged,
                  onSubmitted: (_) {
                    if (_searchResults.isNotEmpty) {
                      _focusSearchResult(_searchResults.first);
                    }
                  },
                ),
              ),
            ),
          ),
          Expanded(
            child: !hasQuery
                ? const AgusEmptyState(
                    icon: Icons.search,
                    title: 'Search',
                    message:
                        'Type to search places, coordinates, or favorites.',
                  )
                : _searchResults.isEmpty
                    ? AgusEmptyState(
                        icon: Icons.manage_search,
                        title: 'Search results',
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

  Widget _buildMobileLayerManagerOverlay(
    BuildContext context,
    double panelHeight, {
    required bool mobileLandscape,
    required double sidePanelWidth,
  }) {
    final mediaPadding = MediaQuery.paddingOf(context);
    if (mobileLandscape) {
      return Positioned(
        top: mediaPadding.top + 10,
        right: mediaPadding.right + 10,
        bottom: mediaPadding.bottom + 10,
        width: sidePanelWidth,
        child: AdaptiveLayerManager(
          formFactor: ExampleFormFactor.mobile,
          nativeLayerState: _mapLayerState,
          buildings3dEnabled: _buildings3dEnabled,
          onNativeLayerStateChanged: _updateMapLayerState,
          onBuildings3dChanged: _updateBuildings3d,
          layerStore: _duckDBLayerStore,
          activeLayerId: _activeDuckDBLayerId,
          activeDrawTool: _duckDBDrawController?.tool,
          layerStoreStatus: _duckDBLayerStoreStatus,
          mwmLayers: _mwmLayerInfos(),
          mwmLayerOrderMode: _mwmLayerOrderMode,
          onMwmLayerVisibilityChanged: (regionName, visible) {
            unawaited(_setMwmLayerVisibility(regionName, visible));
          },
          onMwmLayerDeleted: (layer) {
            unawaited(_deleteMwmLayer(layer));
          },
          onMwmLayerUpdated: _updateMwmLayer,
          onMwmLayerFocused: _focusMwmLayer,
          onProjectLayerFocused: _focusProjectLayer,
          onFeatureFocused: _focusProjectFeature,
          onMwmLayerOrderChanged: (mode) {
            unawaited(_setMwmLayerOrderMode(mode));
          },
          onRenderingRefresh: _refreshDuckDBNativeLayers,
          onActiveLayerChanged: _setActiveDuckDBLayer,
          onDrawToolChanged: _setDuckDBDrawTool,
          onEditFeature: _editDuckDBFeature,
          onClose: () {
            setState(() {
              _mobileLayerManagerVisible = false;
            });
          },
        ),
      );
    }

    return Positioned(
      left: 10,
      right: 10,
      bottom: 10,
      height: panelHeight,
      child: AdaptiveLayerManager(
        formFactor: ExampleFormFactor.mobile,
        nativeLayerState: _mapLayerState,
        buildings3dEnabled: _buildings3dEnabled,
        onNativeLayerStateChanged: _updateMapLayerState,
        onBuildings3dChanged: _updateBuildings3d,
        layerStore: _duckDBLayerStore,
        activeLayerId: _activeDuckDBLayerId,
        activeDrawTool: _duckDBDrawController?.tool,
        layerStoreStatus: _duckDBLayerStoreStatus,
        mwmLayers: _mwmLayerInfos(),
        mwmLayerOrderMode: _mwmLayerOrderMode,
        onMwmLayerVisibilityChanged: (regionName, visible) {
          unawaited(_setMwmLayerVisibility(regionName, visible));
        },
        onMwmLayerDeleted: (layer) {
          unawaited(_deleteMwmLayer(layer));
        },
        onMwmLayerUpdated: _updateMwmLayer,
        onMwmLayerFocused: _focusMwmLayer,
        onProjectLayerFocused: _focusProjectLayer,
        onFeatureFocused: _focusProjectFeature,
        onMwmLayerOrderChanged: (mode) {
          unawaited(_setMwmLayerOrderMode(mode));
        },
        onRenderingRefresh: _refreshDuckDBNativeLayers,
        onActiveLayerChanged: _setActiveDuckDBLayer,
        onDrawToolChanged: _setDuckDBDrawTool,
        onEditFeature: _editDuckDBFeature,
        onClose: () {
          setState(() {
            _mobileLayerManagerVisible = false;
          });
        },
      ),
    );
  }

  Widget _buildMobileMapToolButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    bool active = false,
    Widget? iconWidget,
    bool enabled = true,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final background = active
        ? colorScheme.primaryContainer.withValues(alpha: 0.96)
        : colorScheme.surface.withValues(alpha: 0.94);
    final foreground = enabled
        ? active
            ? colorScheme.onPrimaryContainer
            : colorScheme.onSurface
        : colorScheme.onSurface.withValues(alpha: 0.38);
    final borderColor = active
        ? colorScheme.primary.withValues(alpha: 0.45)
        : colorScheme.outlineVariant.withValues(alpha: 0.72);
    final child = iconWidget ?? Icon(icon, color: foreground);

    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: label,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                blurRadius: 16,
                color: Colors.black.withValues(alpha: 0.22),
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                blurRadius: 3,
                color: Colors.black.withValues(alpha: 0.10),
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Material(
            color: background,
            shape: CircleBorder(side: BorderSide(color: borderColor)),
            clipBehavior: Clip.antiAlias,
            child: InkResponse(
              onTap: enabled ? onPressed : null,
              containedInkWell: true,
              radius: 26,
              child: SizedBox.square(
                dimension: 48,
                child: IconTheme(
                  data: IconThemeData(color: foreground, size: 24),
                  child: Center(child: child),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileDrawingActionButtons(
    agus_maps_flutter.DuckDBLayerDrawController controller,
  ) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        if (!controller.isEditing) return const SizedBox.shrink();
        final buttons = <Widget>[
          if (controller.isDrawing)
            _buildMobileMapToolButton(
              label: 'Undo vertex',
              icon: Icons.undo,
              enabled: controller.vertices.isNotEmpty &&
                  !controller.isCommitting &&
                  !controller.isEditingFeature,
              onPressed: controller.undoLastVertex,
            ),
          _buildMobileMapToolButton(
            label: 'Commit feature',
            icon: Icons.check,
            active: controller.canCommit,
            enabled: controller.canCommit,
            iconWidget: controller.isCommitting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            onPressed: () => unawaited(_commitDuckDBFeature(controller)),
          ),
          _buildMobileMapToolButton(
            label: controller.isEditingFeature
                ? 'Cancel feature edit'
                : 'Cancel drawing',
            icon: Icons.close,
            active: true,
            enabled: !controller.isCommitting,
            onPressed: () {
              controller.cancel();
              _interactionStateController.enterIdle();
            },
          ),
        ];

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < buttons.length; index++) ...[
              if (index > 0) const SizedBox(height: 10),
              buttons[index],
            ],
          ],
        );
      },
    );
  }

  Future<void> _commitDuckDBFeature(
    agus_maps_flutter.DuckDBLayerDrawController controller,
  ) async {
    try {
      final featureId = await controller.commit();
      if (featureId != null) {
        _log('DuckDB feature committed: $featureId');
        _interactionStateController.enterIdle();
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Feature commit failed: $error')),
      );
    }
  }

  Widget _buildMapControls(
    BuildContext context,
    ExampleFormFactor formFactor, {
    required bool showLayerButton,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    if (formFactor.isMobile) {
      final drawController = _duckDBDrawController;
      final compactForOpenSheet = _mobileLayerManagerVisible ||
          _placePage != null ||
          _navigationPlan != null;
      final buttons = <Widget>[
        if (drawController != null)
          _buildMobileDrawingActionButtons(drawController),
        _buildMobileMapToolButton(
          label: _searchOpen ? 'Close search' : 'Search',
          icon: _searchOpen ? Icons.close : Icons.search,
          active: _searchOpen,
          onPressed: _toggleSearch,
        ),
        if (showLayerButton)
          _buildMobileMapToolButton(
            label: _mobileLayerManagerVisible ? 'Close layers' : 'Layers',
            icon: _mobileLayerManagerVisible
                ? Icons.layers
                : Icons.layers_outlined,
            active: _mobileLayerManagerVisible,
            onPressed: () {
              setState(() {
                final nextVisible = !_mobileLayerManagerVisible;
                _mobileLayerManagerVisible = nextVisible;
                if (nextVisible && _searchOpen) {
                  _searchOpen = false;
                  _clearSearchState();
                }
              });
            },
          ),
        if (!compactForOpenSheet) ...[
          _buildMobileMapToolButton(
            label: 'Zoom in',
            icon: Icons.add,
            onPressed: _zoomIn,
          ),
          _buildMobileMapToolButton(
            label: 'Zoom out',
            icon: Icons.remove,
            onPressed: _zoomOut,
          ),
          _buildMobileMapToolButton(
            label: 'Reset north',
            icon: Icons.navigation,
            iconWidget: ValueListenableBuilder<double>(
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
        ],
        _buildMobileMapToolButton(
          label: 'Current position',
          icon: Icons.my_location,
          enabled: !_isLocating,
          iconWidget: _isLocating
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.my_location),
          onPressed: _centerOnCurrentPosition,
        ),
      ];

      return ClipRect(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SingleChildScrollView(
            reverse: true,
            clipBehavior: Clip.hardEdge,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var index = 0; index < buttons.length; index++) ...[
                  if (index > 0) const SizedBox(height: 10),
                  buttons[index],
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Material(
      color: colorScheme.surface,
      elevation: 3,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (formFactor.isMobile) ...[
            _buildMobileMapToolButton(
              label: _searchOpen ? 'Close' : 'Search',
              icon: _searchOpen ? Icons.close : Icons.search,
              active: _searchOpen,
              onPressed: _toggleSearch,
            ),
            const Divider(height: 1),
          ],
          if (showLayerButton) ...[
            if (formFactor.isMobile)
              _buildMobileMapToolButton(
                label: 'Layers',
                icon: _mobileLayerManagerVisible
                    ? Icons.layers
                    : Icons.layers_outlined,
                active: _mobileLayerManagerVisible,
                onPressed: () {
                  setState(() {
                    final nextVisible = !_mobileLayerManagerVisible;
                    _mobileLayerManagerVisible = nextVisible;
                    if (nextVisible && _searchOpen) {
                      _searchOpen = false;
                      _clearSearchState();
                    }
                  });
                },
              )
            else
              IconButton(
                tooltip: 'Layers',
                icon: Icon(
                  _duckDBLayerPanelVisible
                      ? Icons.layers
                      : Icons.layers_outlined,
                ),
                onPressed: () {
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
      key: _downloadsTabKey,
      mwmStorage: _mwmStorage!,
      dataPath: dataPath,
      isVisible: isVisible,
      onMapsChanged: () {
        setState(() {});
        unawaited(_refreshCommandDownloadsFeed());
      },
    );
  }
}
