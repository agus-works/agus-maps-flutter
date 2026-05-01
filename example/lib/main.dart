import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:agus_maps_flutter/agus_maps_flutter.dart' as agus_maps_flutter;
import 'package:agus_maps_flutter/mwm_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'about_tab.dart';
import 'downloads_tab.dart';
import 'settings_tab.dart';
import 'place_page_sheet.dart';

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

class MapSearchResult {
  final String title;
  final String subtitle;
  final double lat;
  final double lon;
  final int zoom;

  const MapSearchResult({
    required this.title,
    required this.subtitle,
    required this.lat,
    required this.lon,
    required this.zoom,
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
  bool _nativeSurfaceReady = false;
  bool _isLocating = false;
  bool _searchOpen = false;
  double _currentBearing = 0.0;
  agus_maps_flutter.PlacePageData? _placePage;

  int? _bundledMwmVersion;
  Timer? _bearingTimer;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<MapSearchResult> _searchResults = const [];

  final agus_maps_flutter.AgusMapController _mapController =
      agus_maps_flutter.AgusMapController();

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
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  static const String _prefsKeyMapScale = 'map_scale_multiplier';
  static const String _prefsKeyInterfaceTheme = 'interface_theme_mode';
  static const String _prefsKeyMapAppearance = 'map_appearance_mode';
  static const String _prefsKeyMapLanguage = 'map_language_code';
  static const String _prefsKeyBuildings3d = 'buildings_3d_enabled';
  static const String _prefsKeyLayerOutdoors = 'layer_outdoors_enabled';
  static const String _prefsKeyLayerIsolines = 'layer_isolines_enabled';
  static const String _prefsKeyLayerSubway = 'layer_subway_enabled';

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
      if (!mounted) return;
      setState(() {
        _mapScale = scale;
        _interfaceThemeMode = interfaceTheme;
        _mapAppearanceMode = mapAppearance;
        _mapLanguageCode = mapLanguage;
        _buildings3dEnabled = buildings3d;
        _mapLayerState = layers;
      });
      _applyNativeMapSettings();
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
    agus_maps_flutter.invalidateMap();
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

      // 1. Extract ICU data for transliteration
      _log('Extracting icudt75l.dat...');
      await agus_maps_flutter.extractMap('assets/maps/icudt75l.dat');

      // 2. Extract CoMaps data files (classificator.txt, types.txt, etc.)
      _log('Extracting data files...');
      String dataPath = await agus_maps_flutter.extractDataFiles();
      _log('Data path: $dataPath');

      _bundledMwmVersion = await _readBundledMwmVersion(dataPath);
      _log('Bundled MWM version: ${_bundledMwmVersion ?? 'unknown'}');

      // 3. Extract bundled maps before surface creation. CoMaps scans the
      // writable directory during native surface creation, so country maps must
      // be under the current version directory before RegisterAllMaps() runs.
      _log('Extracting World.mwm...');
      final worldPath =
          await agus_maps_flutter.extractMap('assets/maps/World.mwm');

      _log('Extracting WorldCoasts.mwm...');
      final coastsPath =
          await agus_maps_flutter.extractMap('assets/maps/WorldCoasts.mwm');

      _log('Extracting Gibraltar.mwm...');
      final extractedGibraltarPath =
          await agus_maps_flutter.extractMap('assets/maps/Gibraltar.mwm');
      final gibraltarPath = await _prepareBundledCountryMap(
        extractedPath: extractedGibraltarPath,
        dataPath: dataPath,
        version: _bundledMwmVersion,
      );
      _log('Bundled map paths: [$worldPath, $coastsPath, $gibraltarPath]');

      // Record bundled maps in storage (if not already there)
      final worldFile = File(worldPath);
      final coastsFile = File(coastsPath);
      final gibraltarFile = File(gibraltarPath);

      if (!_mwmStorage!.isDownloaded('World')) {
        await _mwmStorage!.upsert(MwmMetadata(
          regionName: 'World',
          snapshotVersion: 'bundled',
          fileSize: await worldFile.length(),
          downloadDate: DateTime.now(),
          filePath: worldPath,
          isBundled: true,
        ));
      }
      if (!_mwmStorage!.isDownloaded('WorldCoasts')) {
        await _mwmStorage!.upsert(MwmMetadata(
          regionName: 'WorldCoasts',
          snapshotVersion: 'bundled',
          fileSize: await coastsFile.length(),
          downloadDate: DateTime.now(),
          filePath: coastsPath,
          isBundled: true,
        ));
      }
      if (!_mwmStorage!.isDownloaded('Gibraltar')) {
        await _mwmStorage!.upsert(MwmMetadata(
          regionName: 'Gibraltar',
          snapshotVersion: 'bundled',
          fileSize: await gibraltarFile.length(),
          downloadDate: DateTime.now(),
          filePath: gibraltarPath,
          isBundled: true,
        ));
      }

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
    _startBearingUpdates();

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

  void _startBearingUpdates() {
    _bearingTimer?.cancel();
    _bearingTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (!mounted || _currentTabIndex != 0 || !_nativeSurfaceReady) return;
      final bearing = agus_maps_flutter.getCurrentBearing();
      if ((bearing - _currentBearing).abs() < 0.5) return;
      setState(() {
        _currentBearing = bearing;
      });
    });
  }

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _searchController.clear();
        _searchResults = const [];
      }
    });
    if (_searchOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocusNode.requestFocus();
      });
    }
  }

  void _onSearchChanged(String query) {
    final normalized = query.trim().toLowerCase();
    final results = normalized.isEmpty
        ? const <MapSearchResult>[]
        : kFavorites
            .where(
                (favorite) => favorite.name.toLowerCase().contains(normalized))
            .map((favorite) => MapSearchResult(
                  title: favorite.name,
                  subtitle: 'Demo location',
                  lat: favorite.lat,
                  lon: favorite.lon,
                  zoom: favorite.zoom,
                ))
            .toList();
    setState(() {
      _searchResults = results;
    });
  }

  void _focusSearchResult(MapSearchResult result) {
    _mapController.moveToLocation(result.lat, result.lon, result.zoom);
    _searchFocusNode.unfocus();
    setState(() {
      _searchOpen = false;
      _searchController.clear();
      _searchResults = const [];
      _currentTabIndex = 0;
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
    setState(() {
      _currentBearing = 0.0;
    });
  }

  Future<void> _centerOnCurrentPosition() async {
    if (_isLocating) return;
    setState(() {
      _isLocating = true;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showMapMessage('Location services are disabled.');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showMapMessage('Location permission is not available.');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final zoom = agus_maps_flutter.getCurrentZoom() ?? 15;
      _mapController.moveToLocation(
        position.latitude,
        position.longitude,
        max(zoom, 15),
      );
    } catch (error) {
      _log('Location failed: $error');
      _showMapMessage('Unable to get current location.');
    } finally {
      if (mounted) {
        setState(() {
          _isLocating = false;
        });
      }
    }
  }

  void _showMapMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
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
    if (version == null ||
        fileName == 'World.mwm' ||
        fileName == 'WorldCoasts.mwm') {
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
    return target.path;
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

  /// Clean up partial downloads from interrupted sessions.
  ///
  /// When the app is killed during a download, the partial .mwm.download file
  /// remains on disk. If not cleaned up, RegisterAllMaps() might crash trying
  /// to load corrupted/incomplete map files.
  Future<void> _cleanupPartialDownloads() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      int cleanedCount = 0;

      // Check both the root documents and the maps subdirectory
      final dirsToCheck = [
        dir,
        Directory('${dir.path}/agus_maps_flutter/maps'),
      ];

      for (final checkDir in dirsToCheck) {
        if (!checkDir.existsSync()) continue;

        final files = checkDir.listSync();
        for (final entity in files) {
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

  void _onFavoriteSelected(FavoriteLocation favorite) {
    // Navigate to the map and move to the selected location
    _mapController.moveToLocation(favorite.lat, favorite.lon, favorite.zoom);
    setState(() {
      _currentTabIndex = 0; // Switch to Map tab
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
      home: Scaffold(
        body: SafeArea(
          // Use IndexedStack to keep all tabs alive (especially the map)
          // This prevents the map from being unmounted/remounted when switching tabs
          child: IndexedStack(
            index: _currentTabIndex,
            children: [
              _buildMapTab(),
              _buildFavoritesTab(),
              _buildDownloadsTab(),
              SettingsTab(
                mapScale: _mapScale,
                interfaceThemeMode: _interfaceThemeMode,
                mapAppearanceMode: _mapAppearanceMode,
                mapLanguageCode: _mapLanguageCode,
                buildings3dEnabled: _buildings3dEnabled,
                layerState: _mapLayerState,
                onMapScaleChanged: _updateMapScale,
                onResetMapScale: _resetMapScale,
                onInterfaceThemeModeChanged: _updateInterfaceThemeMode,
                onMapAppearanceModeChanged: _updateMapAppearanceMode,
                onMapLanguageChanged: _updateMapLanguage,
                onBuildings3dChanged: _updateBuildings3d,
                onLayerStateChanged: _updateMapLayerState,
              ),
              const AboutTab(),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentTabIndex,
          onDestinationSelected: (index) {
            setState(() {
              _currentTabIndex = index;
            });
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map),
              label: 'Map',
            ),
            NavigationDestination(
              icon: Icon(Icons.favorite_border),
              selectedIcon: Icon(Icons.favorite),
              label: 'Favorites',
            ),
            NavigationDestination(
              icon: Icon(Icons.download_outlined),
              selectedIcon: Icon(Icons.download),
              label: 'Downloads',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings',
            ),
            NavigationDestination(
              icon: Icon(Icons.info_outline),
              selectedIcon: Icon(Icons.info),
              label: 'About',
            ),
          ],
        ),
      ),
    );
  }

  /// Full-screen map tab.
  Widget _buildMapTab() {
    if (!_dataReady) {
      return Container(
        color: Colors.grey[200],
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(_status),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _debug,
                    style:
                        const TextStyle(fontSize: 10, fontFamily: 'monospace'),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        agus_maps_flutter.AgusMap(
          initialLat: kDefaultLocation.lat,
          initialLon: kDefaultLocation.lon,
          initialZoom: kDefaultLocation.zoom,
          onMapReady: _onMapReady,
          onPlacePage: _handlePlacePage,
          controller: _mapController,
          isVisible:
              _currentTabIndex == 0, // Only resize when map tab is active
          userScale: _mapScale,
        ),
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: _buildSearchOverlay(),
        ),
        Positioned(
          right: 12,
          bottom: _placePage == null ? 24 : 248,
          child: _buildMapControls(),
        ),
        if (_placePage != null)
          PlacePageSheet(
            data: _placePage!,
            onClose: _closePlacePage,
          ),
      ],
    );
  }

  Widget _buildSearchOverlay() {
    final colorScheme = Theme.of(context).colorScheme;
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
              constraints: const BoxConstraints(maxHeight: 220),
              child: _searchResults.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'No results',
                          style: Theme.of(context).textTheme.bodyMedium,
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
                          leading: const Icon(Icons.place_outlined),
                          title: Text(result.title),
                          subtitle: Text(result.subtitle),
                          onTap: () => _focusSearchResult(result),
                        );
                      },
                    ),
            ),
        ],
      ),
    );
  }

  Widget _buildMapControls() {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface,
      elevation: 3,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
            icon: Transform.rotate(
              angle: _currentBearing * pi / 180,
              child: const Icon(Icons.navigation),
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

  /// Full-screen favorites tab.
  Widget _buildFavoritesTab() {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.favorite,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Favorites',
                style: Theme.of(context).textTheme.titleLarge,
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
                  style: Theme.of(context).textTheme.bodySmall,
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
  Widget _buildDownloadsTab() {
    if (_mwmStorage == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return DownloadsTab(
      mwmStorage: _mwmStorage!,
      isVisible: _currentTabIndex == 2, // Downloads tab is index 2
      onMapsChanged: () {
        setState(() {});
      },
    );
  }
}
