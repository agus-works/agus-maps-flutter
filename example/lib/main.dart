import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';

import 'package:agus_maps_flutter/agus_maps_flutter.dart' as agus_maps_flutter;
import 'package:agus_maps_flutter/mwm_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'downloads_tab.dart';
import 'settings_tab.dart';

void main() {
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

/// Default location when app starts (Philippines).
const FavoriteLocation kDefaultLocation = FavoriteLocation(
  name: 'Philippines',
  lat: 11.840743046600755,
  lon: 123.11028882297192,
  zoom: 6,
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

  final agus_maps_flutter.AgusMapController _mapController =
      agus_maps_flutter.AgusMapController();

  // Store map paths for registration after Framework is ready
  final List<String> _mapPathsToRegister = [];

  // MWM storage for tracking downloaded maps
  MwmStorage? _mwmStorage;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    try {
      _log('Starting initialization...');

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

      // 1. Extract map files and store paths for later registration
      _log('Extracting World.mwm...');
      final worldPath =
          await agus_maps_flutter.extractMap('assets/maps/World.mwm');
      _mapPathsToRegister.add(worldPath);

      _log('Extracting WorldCoasts.mwm...');
      final coastsPath =
          await agus_maps_flutter.extractMap('assets/maps/WorldCoasts.mwm');
      _mapPathsToRegister.add(coastsPath);

      /*
      _log('Extracting Gibraltar.mwm...');
      String mapPath =
          await agus_maps_flutter.extractMap('assets/maps/Gibraltar.mwm');
      _mapPathsToRegister.add(mapPath);
      _log('Map paths: $_mapPathsToRegister');
      */
      
      // Temporary: Use Philippines/World as default to debug style errors with Gibraltar
      _log('Skipping Gibraltar extraction (debug mode)');

      // Record bundled maps in storage (if not already there)
      final worldFile = File(worldPath);
      final coastsFile = File(coastsPath);
      // final gibraltarFile = File(mapPath);

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
      /*
      if (!_mwmStorage!.isDownloaded('Gibraltar')) {
        await _mwmStorage!.upsert(MwmMetadata(
          regionName: 'Gibraltar',
          snapshotVersion: 'bundled',
          fileSize: await gibraltarFile.length(),
          downloadDate: DateTime.now(),
          filePath: mapPath,
          isBundled: true,
        ));
      }
      */

      // 2. Extract ICU data for transliteration
      _log('Extracting icudt75l.dat...');
      await agus_maps_flutter.extractMap('assets/maps/icudt75l.dat');

      // 3. Extract CoMaps data files (classificator.txt, types.txt, etc.)
      _log('Extracting data files...');
      String dataPath = await agus_maps_flutter.extractDataFiles();
      _log('Data path: $dataPath');

      // 4. Initialize with extracted data files
      _log('Calling initWithPaths()...');
      agus_maps_flutter.initWithPaths(dataPath, dataPath);
      _log('initWithPaths() complete');

      // NOTE: Don't call loadMap() here - Framework isn't ready yet!
      // Maps will be registered in _onMapReady() after surface creation.
      _log('Maps will be registered after surface creation...');

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
    _log('Map surface ready! Registering maps...');

    // Register bundled maps (extracted during init)
    for (final path in _mapPathsToRegister) {
      final result = agus_maps_flutter.registerSingleMap(path);
      _log('Registered bundled $path: result=$result');
    }

    // Re-register all previously downloaded maps from MwmStorage
    // This is crucial: downloaded maps are only stored as metadata,
    // they need to be re-registered with the native engine on each app start
    if (_mwmStorage != null) {
      final allMaps = _mwmStorage!.getAll();
      _log('Re-registering ${allMaps.length} maps from storage...');
      for (final metadata in allMaps) {
        // Skip bundled maps (already registered above)
        if (metadata.isBundled) continue;

        _log(
            'Re-registering downloaded: ${metadata.regionName} at ${metadata.filePath}');
        final result = agus_maps_flutter.registerSingleMap(metadata.filePath);
        _log('  Result: $result');
      }
    }

    // Force invalidate the map viewport after registering maps
    // This ensures the DrapeEngine reloads tiles with the newly registered maps
    _log('Invalidating map viewport...');
    agus_maps_flutter.invalidateMap();

    // Force a complete redraw to ensure tiles are loaded for newly registered maps
    // This is necessary because maps are registered AFTER DrapeEngine initialization,
    // so the engine may have calculated tile coverage before maps were available
    _log('Forcing complete tile reload...');
    agus_maps_flutter.forceRedraw();

    // Debug: List all registered MWMs and check Manila coverage
    _log('Debug: Listing all registered MWMs...');
    agus_maps_flutter.debugListMwms();

    // Check Manila, Philippines (14.5995, 120.9842)
    _log('Debug: Checking Manila coverage...');
    agus_maps_flutter.debugCheckPoint(14.5995, 120.9842);

    setState(() {
      _status = 'Map ready!';
    });
  }

  void _log(String msg) {
    debugPrint('[AgusDemo] $msg');
    if (mounted) {
      setState(() {
        _debug += '$msg\n';
      });
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
      final files = dir.listSync();
      int cleanedCount = 0;

      for (final entity in files) {
        if (entity is File && entity.path.endsWith('.mwm.download')) {
          _log('Removing partial download: ${entity.path}');
          await entity.delete();
          cleanedCount++;
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
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
              const SettingsTab(),
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

    return agus_maps_flutter.AgusMap(
      initialLat: kDefaultLocation.lat,
      initialLon: kDefaultLocation.lon,
      initialZoom: kDefaultLocation.zoom,
      onMapReady: _onMapReady,
      controller: _mapController,
      isVisible: _currentTabIndex == 0, // Only resize when map tab is active
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
