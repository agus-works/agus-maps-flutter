import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:agus_design/agus_design.dart';
import 'package:agus_maps_flutter/mirror_service.dart';
import 'package:agus_maps_flutter/mwm_storage.dart';
import 'package:agus_maps_flutter/agus_maps_flutter.dart' as agus;
import 'package:fuzzywuzzy/fuzzywuzzy.dart' as fuzz;
import 'package:storage_space/storage_space.dart';
import 'downloads_cache.dart';
import 'shared/adaptive/form_factor.dart';

/// Minimum disk space required after download (128 MB).
const int kMinRemainingSpaceBytes = 128 * 1024 * 1024;

/// Warning threshold for low disk space (1 GB).
const int kLowSpaceWarningBytes = 1024 * 1024 * 1024;

/// Maximum concurrent downloads.
const int kMaxConcurrentDownloads = 3;

/// Fuzzy search threshold (0-100). Lower = more lenient matching.
const int kFuzzySearchThreshold = 50;

/// Loading status steps.
enum LoadingStep {
  idle,
  checkingCache,
  loadingFromCache,
  validatingCache,
  discoveringMirrors,
  selectingMirror,
  loadingRegions,
  done,
}

extension LoadingStepMessage on LoadingStep {
  String get message {
    return switch (this) {
      LoadingStep.idle => '',
      LoadingStep.checkingCache => 'Checking local cache...',
      LoadingStep.loadingFromCache => 'Loading from cache...',
      LoadingStep.validatingCache => 'Validating cached data...',
      LoadingStep.discoveringMirrors => 'Discovering available mirrors...',
      LoadingStep.selectingMirror => 'Selecting fastest mirror...',
      LoadingStep.loadingRegions => 'Loading regions...',
      LoadingStep.done => 'Done!',
    };
  }
}

/// Check internet connectivity by attempting to reach Google's DNS.
Future<bool> checkInternetConnectivity() async {
  try {
    final result = await InternetAddress.lookup(
      'google.com',
    ).timeout(const Duration(seconds: 5));
    return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
  } on SocketException catch (_) {
    return false;
  } on TimeoutException catch (_) {
    return false;
  }
}

/// Downloads tab widget for managing map downloads.
class DownloadsTab extends StatefulWidget {
  final MwmStorage mwmStorage;
  final String dataPath;
  final VoidCallback? onMapsChanged;
  final bool isVisible;

  const DownloadsTab({
    super.key,
    required this.mwmStorage,
    required this.dataPath,
    this.onMapsChanged,
    this.isVisible = false,
  });

  @override
  State<DownloadsTab> createState() => _DownloadsTabState();
}

class _DownloadsTabState extends State<DownloadsTab> {
  final MirrorService _mirrorService = MirrorService();
  final DownloadsCacheService _cacheService = DownloadsCacheService();

  // Mirror discovery results - contains all mirrors with their status
  List<MirrorDiscoveryResult> _discoveredMirrors = [];

  // Currently selected mirror and snapshot
  MirrorDiscoveryResult? _selectedMirrorResult;
  List<MwmRegion> _regions = [];

  bool _isLoading = false;
  LoadingStep _loadingStep = LoadingStep.idle;
  String? _error;
  bool _hasInternet = true;
  Timer? _connectivityTimer;

  // Search
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<MwmRegion> _filteredRegions = [];
  final Set<String> _expandedRegionIds = {};

  // Download tracking - maps region name to progress (0.0 to 1.0)
  final Map<String, double> _downloadProgress = {};
  final Map<String, String> _downloadErrors = {};

  // Track active downloads for limiting concurrent downloads
  final Set<String> _activeDownloads = {};
  final Set<String> _downloadCancellationRequests = {};
  final Set<String> _cancelledGroupDownloads = {};

  // Disk space
  int _availableSpaceBytes = 0;

  // Track if we've initialized data (for lazy loading)
  bool _hasInitialized = false;

  // Track if data came from cache (for UI feedback)
  bool _loadedFromCache = false;

  // UI state for mirror selector
  bool _showMirrorSelector = false;

  @override
  void initState() {
    super.initState();
    // Don't init immediately - wait for visibility
    // Periodically check connectivity
    _connectivityTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _checkConnectivity(),
    );
    // Listen to search input
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void didUpdateWidget(DownloadsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Lazy load: only init when tab becomes visible for the first time
    if (widget.isVisible && !_hasInitialized && !_isLoading) {
      _hasInitialized = true;
      // Use post-frame callback to avoid blocking UI
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _init();
      });
    }
  }

  @override
  void dispose() {
    _downloadCancellationRequests.addAll(_activeDownloads);
    _connectivityTimer?.cancel();
    _searchController.dispose();
    _mirrorService.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    if (query == _searchQuery) return;

    setState(() {
      _searchQuery = query;
      _applySearch();
    });
  }

  void _applySearch() {
    if (_searchQuery.isEmpty) {
      _filteredRegions = List.from(_regions);
      return;
    }

    final searchableRegions = _flattenRegions(_regions);
    // Use extractAllSorted for relevance-sorted fuzzy search
    // This returns results sorted by best match score (highest first)
    final results = fuzz.extractAllSorted<MwmRegion>(
      query: _searchQuery,
      choices: searchableRegions,
      cutoff: kFuzzySearchThreshold,
      getter: (region) => region.displayName,
    );

    _filteredRegions = results.map((r) => r.choice).toList();
  }

  List<MwmRegion> _flattenRegions(Iterable<MwmRegion> regions) {
    return [
      for (final region in regions) ...[
        region,
        ..._flattenRegions(region.children),
      ],
    ];
  }

  List<MwmRegion> get _browserRootRegions {
    return [
      for (final region in _regions) _asBrowserRoot(region),
    ];
  }

  MwmRegion _asBrowserRoot(MwmRegion region) {
    if (region.isGroup) return region;
    return MwmRegion(
      id: region.id,
      sizeBytes: 0,
      subregions: [region],
    );
  }

  Future<void> _checkConnectivity() async {
    final hasInternet = await checkInternetConnectivity();
    if (mounted && hasInternet != _hasInternet) {
      setState(() => _hasInternet = hasInternet);
      // If we regained connectivity and have no regions, retry
      if (hasInternet && _regions.isEmpty && _error != null) {
        _init();
      }
    }
  }

  Future<void> _init({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
      _loadingStep = LoadingStep.checkingCache;
      _error = null;
    });

    try {
      // Validate MWM storage against actual files on disk.
      // After reinstall, metadata may reference deleted files.
      final orphanedRegions = await widget.mwmStorage.getOrphanedRegions();
      if (orphanedRegions.isNotEmpty) {
        debugPrint(
          '[Downloads] Found ${orphanedRegions.length} orphaned MWM entries: '
          '$orphanedRegions',
        );
        await widget.mwmStorage.pruneOrphaned();
        debugPrint('[Downloads] Pruned orphaned MWM metadata');
      }

      // First check connectivity
      _hasInternet = await checkInternetConnectivity();

      // Try to load from cache first (unless forcing refresh)
      if (!forceRefresh) {
        _setLoadingStep(LoadingStep.loadingFromCache);
        final cached = await _cacheService.loadCache();

        if (cached != null) {
          debugPrint(
            '[Downloads] Found cached data with ${cached.regions.length} regions',
          );

          // Validate cache in background if we have internet
          if (_hasInternet) {
            _setLoadingStep(LoadingStep.validatingCache);
            final isValid = await _cacheService.validateCache(cached);

            if (!isValid) {
              debugPrint('[Downloads] Cache invalid, will refresh from server');
            } else {
              // Use cached data - create a discovery result for the cached mirror
              final cachedMirror = cached.mirror;
              _selectedMirrorResult = MirrorDiscoveryResult(
                mirror: cachedMirror,
                latestSnapshot: cached.snapshot,
              );
              _discoveredMirrors = [_selectedMirrorResult!];
              _regions = cached.regions;
              _filteredRegions = List.from(_regions);
              _loadedFromCache = true;

              // Update disk space
              await _updateDiskSpace();

              if (mounted) {
                setState(() {
                  _isLoading = false;
                  _loadingStep = LoadingStep.done;
                });
              }

              debugPrint(
                '[Downloads] Loaded ${_regions.length} regions from cache',
              );

              // Discover mirrors in background to update availability
              _discoverMirrorsInBackground();
              return;
            }
          } else {
            // No internet, use cache anyway
            final cachedMirror = cached.mirror;
            _selectedMirrorResult = MirrorDiscoveryResult(
              mirror: cachedMirror,
              latestSnapshot: cached.snapshot,
            );
            _discoveredMirrors = [_selectedMirrorResult!];
            _regions = cached.regions;
            _filteredRegions = List.from(_regions);
            _loadedFromCache = true;

            await _updateDiskSpace();

            if (mounted) {
              setState(() {
                _isLoading = false;
                _loadingStep = LoadingStep.done;
              });
            }
            debugPrint('[Downloads] No internet, using cached data');
            return;
          }
        }
      }

      // No cache or forced refresh - need internet
      if (!_hasInternet) {
        throw Exception(
          'No internet connection. Please check your network settings.',
        );
      }

      // Discover all mirrors and their availability
      _setLoadingStep(LoadingStep.discoveringMirrors);
      debugPrint('[Downloads] Discovering available mirrors...');
      _discoveredMirrors = await _mirrorService.discoverMirrors();

      final operationalMirrors =
          _discoveredMirrors.where((m) => m.isOperational).toList();
      debugPrint(
          '[Downloads] Found ${operationalMirrors.length}/${_discoveredMirrors.length} operational mirrors');

      for (final result in _discoveredMirrors) {
        debugPrint('[Downloads]   ${result.mirror.name}: ${result.statusText}');
      }

      // Select fastest available mirror
      _setLoadingStep(LoadingStep.selectingMirror);
      if (operationalMirrors.isEmpty) {
        throw Exception(
          'No mirrors available. All mirror servers may be down.',
        );
      }

      _selectedMirrorResult = operationalMirrors.first;
      debugPrint(
          '[Downloads] Selected mirror: ${_selectedMirrorResult!.mirror.name}');

      // Load regions
      _setLoadingStep(LoadingStep.loadingRegions);
      await _loadRegions();

      // Save to cache
      if (_regions.isNotEmpty && _selectedMirrorResult != null) {
        await _cacheService.saveCache(
          CachedDownloadsData(
            mirrorName: _selectedMirrorResult!.mirror.name,
            mirrorBaseUrl: _selectedMirrorResult!.mirror.baseUrl,
            snapshotVersion: _selectedMirrorResult!.latestSnapshot!.version,
            regions: _regions,
            cachedAt: DateTime.now(),
          ),
        );
      }

      _loadedFromCache = false;

      // Get disk space
      await _updateDiskSpace();

      _error = null;
    } catch (e, stackTrace) {
      debugPrint('[Downloads] Error: $e');
      debugPrint('[Downloads] Stack: $stackTrace');
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingStep = LoadingStep.done;
        });
      }
    }
  }

  void _setLoadingStep(LoadingStep step) {
    if (mounted) {
      setState(() => _loadingStep = step);
    }
    debugPrint('[Downloads] ${step.message}');
  }

  /// Discover mirrors in background to update availability display.
  Future<void> _discoverMirrorsInBackground() async {
    if (!_hasInternet) return;

    try {
      final results = await _mirrorService.discoverMirrors();
      if (mounted && results.isNotEmpty) {
        setState(() {
          _discoveredMirrors = results;
        });
        debugPrint(
          '[Downloads] Background discovery found ${results.where((m) => m.isOperational).length} operational mirrors',
        );
      }
    } catch (e) {
      debugPrint('[Downloads] Background mirror discovery failed: $e');
    }
  }

  Future<void> _loadRegions() async {
    if (_selectedMirrorResult == null ||
        _selectedMirrorResult!.latestSnapshot == null) {
      return;
    }

    setState(() => _isLoading = true);
    try {
      final snapshot = _selectedMirrorResult!.latestSnapshot!;
      debugPrint(
        '[Downloads] Loading regions for snapshot ${snapshot.version}...',
      );
      final countriesData = await _mirrorService.getCountriesData(
        _selectedMirrorResult!.mirror,
        snapshot,
      );
      _regions = countriesData.regions;
      _filteredRegions = List.from(_regions);
      _applySearch(); // Re-apply any existing search
      debugPrint(
        '[Downloads] Found ${_regions.length} root regions '
        'and ${countriesData.leafRegions.length} downloadable maps',
      );
      _error = null;

      // Update cache with new regions
      if (_regions.isNotEmpty) {
        await _cacheService.saveCache(
          CachedDownloadsData(
            mirrorName: _selectedMirrorResult!.mirror.name,
            mirrorBaseUrl: _selectedMirrorResult!.mirror.baseUrl,
            snapshotVersion: snapshot.version,
            regions: _regions,
            cachedAt: DateTime.now(),
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('[Downloads] Error loading regions: $e');
      debugPrint('[Downloads] Stack: $stackTrace');
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Switch to a different mirror and reload regions.
  Future<void> _switchMirror(MirrorDiscoveryResult newMirror) async {
    if (!newMirror.isOperational) {
      _showError(
          'Mirror "${newMirror.mirror.name}" is not available: ${newMirror.error}');
      return;
    }

    setState(() {
      _selectedMirrorResult = newMirror;
      _showMirrorSelector = false;
    });

    debugPrint('[Downloads] Switching to mirror: ${newMirror.mirror.name}');
    await _loadRegions();
  }

  Future<void> _updateDiskSpace() async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        // Use storage_space package for Android/iOS
        final storageSpace = await getStorageSpace(
          lowOnSpaceThreshold: kLowSpaceWarningBytes,
          fractionDigits: 2,
        );
        _availableSpaceBytes = storageSpace.free;
        debugPrint(
          '[Downloads] Disk space from storage_space: '
          '${storageSpace.freeSize} free, '
          '${storageSpace.totalSize} total, '
          '${storageSpace.usagePercent}% used',
        );
      } else {
        // Desktop platforms (macOS, Linux, Windows) - skip disk space check
        // Use a large default to allow downloads without restrictions
        _availableSpaceBytes = 100 * 1024 * 1024 * 1024; // 100 GB
        debugPrint('[Downloads] Desktop platform - skipping disk space check');
      }
    } catch (e, stackTrace) {
      debugPrint('[Downloads] Error getting disk space: $e');
      debugPrint('[Downloads] Stack: $stackTrace');
      // Fallback to a large default to allow downloads
      _availableSpaceBytes = 100 * 1024 * 1024 * 1024; // 100 GB
    }
    if (mounted) setState(() {});
  }

  /// Check if we can start a new download (respecting concurrent limit).
  bool get _canStartDownload =>
      _activeDownloads.length < kMaxConcurrentDownloads;

  /// Start downloading a region.
  Future<void> _downloadRegion(MwmRegion region) async {
    if (region.isGroup) {
      await _downloadGroupRegion(region);
      return;
    }
    await _downloadLeafRegion(region);
  }

  Future<void> _downloadGroupRegion(MwmRegion region) async {
    final pendingRegions = _pendingLeafRegions(region);
    if (pendingRegions.isEmpty) return;

    final updateCount = pendingRegions.where(_isLeafOutdated).length;
    final actionLabel = updateCount > 0 ? 'Update' : 'Download';

    final totalSizeMb =
        pendingRegions.fold<int>(0, (sum, r) => sum + r.sizeBytes) ~/
            (1024 * 1024);
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('$actionLabel Region'),
            content: Text(
              '$actionLabel ${pendingRegions.length} map files for '
              '"${region.displayName}" ($totalSizeMb MB)?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(actionLabel),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    for (final leaf in pendingRegions) {
      if (!mounted) return;
      if (_cancelledGroupDownloads.contains(region.id)) break;
      await _downloadLeafRegion(leaf, showSnackBar: false);
    }

    final cancelled = _cancelledGroupDownloads.remove(region.id);
    if (cancelled) {
      _downloadCancellationRequests.removeAll(
        pendingRegions.map((leaf) => leaf.name),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('$actionLabel cancelled for ${region.displayName}')),
        );
      }
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('$actionLabel complete for ${region.displayName}')),
      );
    }
  }

  Future<void> _downloadLeafRegion(
    MwmRegion region, {
    bool showSnackBar = true,
  }) async {
    if (_selectedMirrorResult == null ||
        _selectedMirrorResult!.latestSnapshot == null) {
      return;
    }
    if (_downloadCancellationRequests.remove(region.name)) {
      return;
    }

    // Check concurrent download limit
    if (!_canStartDownload) {
      _showError(
        'Maximum $kMaxConcurrentDownloads concurrent downloads allowed. '
        'Please wait for a download to complete.',
      );
      return;
    }

    final url = _mirrorService.getDownloadUrl(
      _selectedMirrorResult!.mirror,
      _selectedMirrorResult!.latestSnapshot!,
      region,
    );

    // Get file size (use region metadata, fallback to HEAD request if 0)
    int fileSize = region.sizeBytes > 0
        ? region.sizeBytes
        : (await _mirrorService.getFileSize(url) ?? 0);

    // Check disk space
    final remainingAfter = _availableSpaceBytes - fileSize;
    final availableMb = _availableSpaceBytes ~/ (1024 * 1024);
    final fileSizeMb = fileSize ~/ (1024 * 1024);
    final remainingMbAfter = remainingAfter ~/ (1024 * 1024);

    debugPrint(
      '[Downloads] Disk space check: '
      'available=$availableMb MB, fileSize=$fileSizeMb MB, '
      'remainingAfter=$remainingMbAfter MB, '
      'minRequired=${kMinRemainingSpaceBytes ~/ (1024 * 1024)} MB',
    );

    if (remainingAfter < kMinRemainingSpaceBytes) {
      _showError(
        'Insufficient disk space.\n'
        'Detected: $availableMb MB available\n'
        'File size: $fileSizeMb MB\n'
        'Need at least ${kMinRemainingSpaceBytes ~/ (1024 * 1024)} MB remaining after download.',
      );
      return;
    }

    if (remainingAfter < kLowSpaceWarningBytes) {
      final remainingMb = remainingAfter ~/ (1024 * 1024);
      final proceed = await _showWarning(
        'After download, only $remainingMb MB will remain.\n\nContinue anyway?',
      );
      if (!proceed) return;
    }

    final wasDownloaded = widget.mwmStorage.isDownloaded(region.name);

    // Start download
    setState(() {
      _downloadProgress[region.name] = 0.0;
      _downloadErrors.remove(region.name);
      _activeDownloads.add(region.name);
    });

    try {
      final snapshot = _selectedMirrorResult!.latestSnapshot!;
      final mapsDir = _targetDirectory(region, snapshot.version);
      await mapsDir.create(recursive: true);
      final filePath = '${mapsDir.path}/${region.fileName}';
      final tempPath =
          '$filePath.download'; // Temp file to prevent corrupted .mwm on crash
      final tempFile = File(tempPath);
      final finalFile = File(filePath);

      // Stream to temp file first. If app is killed during download,
      // the partial .download file won't be loaded by RegisterAllMaps().
      final bytesWritten = await _mirrorService.downloadToFile(
        url,
        tempFile,
        isCancelled: () => _downloadCancellationRequests.contains(region.name),
        onProgress: (received, total) {
          if (mounted && total > 0) {
            setState(() {
              _downloadProgress[region.name] = received / total;
            });
          }
        },
      );

      if (fileSize > 0 && bytesWritten != fileSize) {
        await tempFile.delete();
        throw Exception(
          'Downloaded size mismatch: expected $fileSize bytes, got $bytesWritten bytes',
        );
      }

      // Rename temp file to final .mwm only after successful download
      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      await tempFile.rename(filePath);

      // Save metadata
      await widget.mwmStorage.upsert(
        MwmMetadata(
          regionName: region.name,
          snapshotVersion: snapshot.version,
          fileSize: bytesWritten,
          downloadDate: DateTime.now(),
          filePath: filePath,
          isBundled: false,
        ),
      );

      // Register with map engine
      final version = int.tryParse(snapshot.version);
      final result = version != null
          ? agus.registerSingleMapWithVersion(filePath, version)
          : agus.registerSingleMap(filePath);
      debugPrint('Registered ${region.name}: result=$result');

      // Update disk space
      _availableSpaceBytes -= bytesWritten;

      // Notify parent
      widget.onMapsChanged?.call();

      if (mounted) {
        setState(() {
          _downloadProgress.remove(region.name);
          _activeDownloads.remove(region.name);
          _downloadCancellationRequests.remove(region.name);
        });
        if (showSnackBar) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(
            SnackBar(
              content: Text(
                wasDownloaded
                    ? 'Updated ${region.name}'
                    : 'Downloaded ${region.name}',
              ),
            ),
          );
        }
      }
    } on DownloadCancelledException {
      final snapshot = _selectedMirrorResult!.latestSnapshot!;
      final mapsDir = _targetDirectory(region, snapshot.version);
      final filePath = '${mapsDir.path}/${region.fileName}';
      final tempFile = File('$filePath.download');
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      if (mounted) {
        setState(() {
          _downloadProgress.remove(region.name);
          _activeDownloads.remove(region.name);
          _downloadCancellationRequests.remove(region.name);
        });
        if (showSnackBar) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Cancelled ${region.displayName}')),
          );
        }
      }
    } catch (e) {
      final snapshot = _selectedMirrorResult!.latestSnapshot!;
      final mapsDir = _targetDirectory(region, snapshot.version);
      final filePath = '${mapsDir.path}/${region.fileName}';
      final tempFile = File('$filePath.download');
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      if (mounted) {
        setState(() {
          _downloadProgress.remove(region.name);
          _activeDownloads.remove(region.name);
          _downloadCancellationRequests.remove(region.name);
          _downloadErrors[region.name] = e.toString();
        });
      }
    }
  }

  void _cancelDownload(MwmRegion region) {
    setState(() {
      if (region.isGroup) {
        _cancelledGroupDownloads.add(region.id);
        for (final leaf in region.leafRegions) {
          if (_activeDownloads.contains(leaf.name)) {
            _downloadCancellationRequests.add(leaf.name);
          }
        }
      } else if (_activeDownloads.contains(region.name)) {
        _downloadCancellationRequests.add(region.name);
      }
    });
  }

  Directory _targetDirectory(MwmRegion region, String snapshotVersion) {
    if (_isRootMapFile(region.fileName)) {
      return Directory(widget.dataPath);
    }
    return Directory('${widget.dataPath}/$snapshotVersion');
  }

  bool _isRootMapFile(String fileName) {
    return fileName == 'World.mwm' || fileName == 'WorldCoasts.mwm';
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  bool get _usesStaticProgress =>
      Platform.isMacOS ||
      Platform.isLinux ||
      Platform.isWindows ||
      context.exampleFormFactor.isDesktop;

  Future<bool> _showWarning(String message) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning, color: Colors.orange),
                SizedBox(width: 8),
                Text('Low Disk Space'),
              ],
            ),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Download Anyway'),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // No internet connection banner
        if (!_hasInternet)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            color: Colors.red,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.wifi_off, color: Colors.white, size: 16),
                SizedBox(width: 8),
                Text(
                  'No Internet Connection',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),

        // Main content
        Expanded(child: _buildMainContent()),
      ],
    );
  }

  Widget _buildMainContent() {
    if (_isLoading && _regions.isEmpty) {
      return _buildLoadingView();
    }

    if (_error != null && _regions.isEmpty) {
      return _buildErrorView();
    }

    return _buildContent();
  }

  Widget _buildLoadingView() {
    if (_usesStaticProgress) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: _StaticDesktopProgress(
            icon: Icons.cloud_download_outlined,
            label: _loadingStep.message,
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 24),
            Text(
              _loadingStep.message,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Please wait...',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(
              'Error loading downloads',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _init,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (context.exampleFormFactor.isDesktop) {
      return _buildCompactDesktopContent();
    }

    return Column(
      children: [
        // Header with selector and status
        _buildHeader(),

        // Region list
        Expanded(child: _buildRegionList()),
      ],
    );
  }

  Widget _buildCompactDesktopContent() {
    final downloadedCount = widget.mwmStorage.getAll().length;
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          _buildCompactDesktopHeader(),
          Expanded(
            child: AgusViewContainer(
              views: [
                AgusView(
                  id: 'downloads-regions',
                  title: 'MWM Maps',
                  icon: Icons.public_outlined,
                  countLabel: _searchQuery.isEmpty
                      ? '$downloadedCount installed'
                      : '${_filteredRegions.length} results',
                  actions: [
                    IconButton(
                      tooltip: 'Refresh downloads',
                      onPressed: () => _init(forceRefresh: true),
                      icon: const Icon(Icons.refresh, size: 16),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints.tightFor(width: 28, height: 24),
                    ),
                  ],
                  child: _buildRegionList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactDesktopHeader() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final downloadedCount = widget.mwmStorage.getAll().length;
    final activeCount = _activeDownloads.length;
    final snapshotLabel = _selectedMirrorResult?.latestSnapshot?.version ??
        _selectedMirrorResult?.statusText ??
        'latest';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
        child: Column(
          children: [
            SizedBox(
              height: 30,
              child: TextField(
                controller: _searchController,
                style: theme.textTheme.bodySmall,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 16),
                  prefixIconConstraints: const BoxConstraints.tightFor(
                    width: 28,
                  ),
                  hintText: 'Search map regions',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  border: const OutlineInputBorder(),
                  suffixIcon: _searchQuery.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                          icon: const Icon(Icons.close, size: 14),
                          visualDensity: VisualDensity.compact,
                        ),
                ),
                onChanged: (value) => setState(() => _searchQuery = value),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _CompactDownloadsStatus(
                  label: '$downloadedCount installed',
                  icon: Icons.check_circle_outline,
                ),
                const SizedBox(width: 6),
                _CompactDownloadsStatus(
                  label: '$activeCount active',
                  icon: Icons.downloading,
                ),
                const Spacer(),
                Flexible(
                  child: Tooltip(
                    message: 'Snapshot',
                    child: Text(
                      snapshotLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final downloadedCount = widget.mwmStorage.getAll().length;
    final availableGb = _availableSpaceBytes / (1024 * 1024 * 1024);
    final activeCount = _activeDownloads.length;
    final operationalMirrorCount =
        _discoveredMirrors.where((m) => m.isOperational).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row with refresh button
          Row(
            children: [
              Icon(
                Icons.download,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Downloads',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (_loadedFromCache)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'cached',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.orange,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              if (activeCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$activeCount/$kMaxConcurrentDownloads',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: () => _init(forceRefresh: true),
                tooltip: 'Refresh mirrors & regions',
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Search bar
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search regions...',
              hintStyle: const TextStyle(fontSize: 14),
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                      },
                    )
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surface,
            ),
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 8),
          // Status row
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildStatusChip(
                Icons.check_circle,
                '$downloadedCount installed',
                Colors.green,
              ),
              _buildStatusChip(
                Icons.storage,
                '${availableGb.toStringAsFixed(1)} GB free',
                _availableSpaceBytes < kLowSpaceWarningBytes
                    ? Colors.orange
                    : Colors.grey,
              ),
              _buildStatusChip(
                Icons.dns,
                '$operationalMirrorCount/${_discoveredMirrors.length} mirrors',
                operationalMirrorCount > 0 ? Colors.blue : Colors.red,
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Mirror selector (expandable)
          _buildMirrorSelector(),
        ],
      ),
    );
  }

  Widget _buildMirrorSelector() {
    final selectedMirror = _selectedMirrorResult;
    final snapshot = selectedMirror?.latestSnapshot;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected mirror display (tappable to expand)
        InkWell(
          onTap: () =>
              setState(() => _showMirrorSelector = !_showMirrorSelector),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).dividerColor,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  selectedMirror?.isOperational == true
                      ? Icons.check_circle
                      : Icons.error,
                  size: 16,
                  color: selectedMirror?.isOperational == true
                      ? Colors.green
                      : Colors.red,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selectedMirror?.mirror.name ?? 'No mirror selected',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (snapshot != null)
                        Text(
                          'Version ${snapshot.version} • ${snapshot.formattedDate}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                    ],
                  ),
                ),
                if (selectedMirror?.mirror.latencyMs != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${selectedMirror!.mirror.latencyMs}ms',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                Icon(
                  _showMirrorSelector
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 20,
                  color: Colors.grey,
                ),
              ],
            ),
          ),
        ),
        // Expandable mirror list
        if (_showMirrorSelector) ...[
          const SizedBox(height: 4),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _discoveredMirrors.length,
                itemBuilder: (context, index) {
                  final result = _discoveredMirrors[index];
                  final isSelected =
                      result.mirror.baseUrl == selectedMirror?.mirror.baseUrl;
                  final showDivider = index < _discoveredMirrors.length - 1;
                  return InkWell(
                    onTap: result.isOperational
                        ? () => _switchMirror(result)
                        : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withValues(alpha: 0.3)
                            : null,
                        border: showDivider
                            ? Border(
                                bottom: BorderSide(
                                  color: Theme.of(context)
                                      .dividerColor
                                      .withValues(alpha: 0.5),
                                ),
                              )
                            : null,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            result.isOperational
                                ? Icons.check_circle
                                : Icons.cancel,
                            size: 16,
                            color: result.isOperational
                                ? Colors.green
                                : Colors.red.shade300,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  result.mirror.name,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    color: result.isOperational
                                        ? null
                                        : Colors.grey,
                                  ),
                                ),
                                Text(
                                  result.statusText,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: result.isOperational
                                        ? Colors.grey.shade600
                                        : Colors.red.shade300,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (result.mirror.latencyMs != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    _getLatencyColor(result.mirror.latencyMs!)
                                        .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${result.mirror.latencyMs}ms',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: _getLatencyColor(
                                      result.mirror.latencyMs!),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          if (isSelected) ...[
                            const SizedBox(width: 8),
                            Icon(
                              Icons.check,
                              size: 16,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ],
    );
  }

  Color _getLatencyColor(int latencyMs) {
    if (latencyMs < 200) return Colors.green;
    if (latencyMs < 500) return Colors.orange;
    return Colors.red;
  }

  Widget _buildStatusChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
  }

  Widget _buildRegionList() {
    if (_isLoading) {
      if (_usesStaticProgress) {
        return Center(
          child: _StaticDesktopProgress(
            icon: Icons.folder_open_outlined,
            label: _loadingStep.message,
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }

    if (_regions.isEmpty) {
      return _DownloadsEmptyState(
        icon: _hasInternet ? Icons.map_outlined : Icons.wifi_off,
        title: _hasInternet ? 'No regions available' : 'No Internet Connection',
        message: _hasInternet
            ? 'Could not load map regions from mirror servers.\nTry selecting a different snapshot or tap Refresh.'
            : 'Connect to the internet to browse and download maps.',
        action: ElevatedButton.icon(
          onPressed: () => _init(forceRefresh: true),
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh'),
        ),
      );
    }

    final regionsToShow = _filteredRegions;

    // Show "no results" if search returned nothing
    if (_searchQuery.isNotEmpty && regionsToShow.isEmpty) {
      return _DownloadsEmptyState(
        icon: Icons.search_off,
        title: 'No regions found',
        message:
            'No regions match "$_searchQuery".\nTry a different search term.',
      );
    }

    final items = <_ListItem>[];
    if (_searchQuery.isNotEmpty) {
      items.add(_ListItem.searchCount(regionsToShow.length));
      for (final region in regionsToShow) {
        _addRegionItems(items, region, depth: 0);
      }
    } else {
      final rootRegions = _browserRootRegions;
      items.add(
          _ListItem.header('Regions (${rootRegions.length})', Colors.blue));
      for (final region in rootRegions) {
        _addRegionItems(items, region, depth: 0);
      }
    }

    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        switch (item.type) {
          case _ListItemType.searchCount:
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Found ${item.count} result${item.count == 1 ? '' : 's'}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            );
          case _ListItemType.header:
            return context.exampleFormFactor.isDesktop
                ? _buildCompactSectionHeader(item.title!)
                : _buildSectionHeader(item.title!, item.color!);
          case _ListItemType.region:
            return context.exampleFormFactor.isDesktop
                ? _buildCompactRegionTile(item.region!, depth: item.depth)
                : _buildRegionTile(item.region!, depth: item.depth);
        }
      },
    );
  }

  void _addRegionItems(
    List<_ListItem> items,
    MwmRegion region, {
    required int depth,
  }) {
    items.add(_ListItem.region(region, depth: depth));
    if (!region.isGroup || !_expandedRegionIds.contains(region.id)) return;

    for (final child in region.children) {
      _addRegionItems(items, child, depth: depth + 1);
    }
  }

  Widget _buildSectionHeader(String title, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: color.withValues(alpha: 0.05),
      child: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: color,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildCompactSectionHeader(String title) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
      ),
    );
  }

  Widget _buildCompactRegionTile(MwmRegion region, {required int depth}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDownloaded = _isRegionDownloaded(region);
    final isOutdated = _isRegionOutdated(region);
    final progress = region.isLeaf ? _downloadProgress[region.name] : null;
    final error = _regionError(region);
    final isDownloading = _isRegionDownloading(region);
    final isExpanded = _expandedRegionIds.contains(region.id);
    final downloadedLeafCount = _downloadedLeafCount(region);
    final leafCount = region.leafRegions.length;
    final statusColor = isOutdated
        ? Colors.orange
        : isDownloaded
            ? Colors.green
            : isDownloading
                ? Colors.blue
                : downloadedLeafCount > 0
                    ? Colors.orange
                    : colorScheme.onSurfaceVariant;

    return InkWell(
      onTap: region.isGroup
          ? () {
              setState(() {
                if (isExpanded) {
                  _expandedRegionIds.remove(region.id);
                } else {
                  _expandedRegionIds.add(region.id);
                }
              });
            }
          : error != null
              ? () {
                  setState(() {
                    _downloadErrors.remove(region.name);
                  });
                }
              : null,
      child: Container(
        height: 30,
        padding: EdgeInsets.only(left: 8 + depth * 14, right: 4),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              child: region.isGroup
                  ? Icon(
                      isExpanded ? Icons.expand_more : Icons.chevron_right,
                      size: 16,
                      color: colorScheme.onSurfaceVariant,
                    )
                  : const SizedBox(),
            ),
            Icon(
              region.isGroup
                  ? Icons.folder_outlined
                  : isDownloaded
                      ? Icons.check_circle_outline
                      : isDownloading
                          ? Icons.downloading
                          : Icons.circle_outlined,
              color: statusColor,
              size: 16,
            ),
            const SizedBox(width: 6),
            Expanded(
              flex: 5,
              child: Text(
                region.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight:
                      region.isGroup ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            Expanded(
              flex: 4,
              child: Text(
                error ??
                    _regionSubtitle(region, downloadedLeafCount, leafCount),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color:
                      error == null ? colorScheme.onSurfaceVariant : Colors.red,
                ),
              ),
            ),
            _buildCompactTrailing(
              region,
              isDownloaded,
              isDownloading,
              progress,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRegionTile(MwmRegion region, {required int depth}) {
    final isDownloaded = _isRegionDownloaded(region);
    final isOutdated = _isRegionOutdated(region);
    final progress = region.isLeaf ? _downloadProgress[region.name] : null;
    final error = _regionError(region);
    final isDownloading = _isRegionDownloading(region);
    final isExpanded = _expandedRegionIds.contains(region.id);
    final downloadedLeafCount = _downloadedLeafCount(region);
    final leafCount = region.leafRegions.length;
    final statusColor = isOutdated
        ? Colors.orange
        : isDownloaded
            ? Colors.green
            : isDownloading
                ? Colors.blue
                : downloadedLeafCount > 0
                    ? Colors.orange
                    : Colors.grey;

    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.only(
        left: 16 + (depth * 20),
        right: 8,
      ),
      leading: SizedBox(
        width: region.isGroup ? 48 : 24,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (region.isGroup)
              Icon(
                isExpanded ? Icons.expand_more : Icons.chevron_right,
                color: Colors.grey,
                size: 20,
              ),
            Icon(
              region.isGroup
                  ? Icons.folder_outlined
                  : isDownloaded
                      ? Icons.check_circle
                      : isDownloading
                          ? Icons.downloading
                          : Icons.circle_outlined,
              color: statusColor,
              size: 20,
            ),
          ],
        ),
      ),
      title: Text(
        region.displayName,
        style: TextStyle(
          fontSize: 14,
          fontWeight: region.isGroup ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      subtitle: error != null
          ? Text(
              error,
              style: const TextStyle(color: Colors.red, fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : Text(
              _regionSubtitle(region, downloadedLeafCount, leafCount),
              style: const TextStyle(fontSize: 11),
            ),
      trailing: _buildTrailing(region, isDownloaded, isDownloading, progress),
      onTap: region.isGroup
          ? () {
              setState(() {
                if (isExpanded) {
                  _expandedRegionIds.remove(region.id);
                } else {
                  _expandedRegionIds.add(region.id);
                }
              });
            }
          : error != null
              ? () {
                  setState(() {
                    _downloadErrors.remove(region.name);
                  });
                }
              : null,
    );
  }

  int _downloadedLeafCount(MwmRegion region) {
    return region.leafRegions
        .where((leaf) => widget.mwmStorage.isDownloaded(leaf.name))
        .length;
  }

  int _outdatedLeafCount(MwmRegion region) {
    return region.leafRegions.where(_isLeafOutdated).length;
  }

  List<MwmRegion> _pendingLeafRegions(MwmRegion region) {
    return region.leafRegions
        .where(
          (leaf) =>
              !widget.mwmStorage.isDownloaded(leaf.name) ||
              _isLeafOutdated(leaf),
        )
        .toList();
  }

  bool _isRegionDownloaded(MwmRegion region) {
    final leaves = region.leafRegions;
    return leaves.isNotEmpty &&
        leaves.every((leaf) => widget.mwmStorage.isDownloaded(leaf.name));
  }

  bool _isRegionOutdated(MwmRegion region) {
    return region.leafRegions.any(_isLeafOutdated);
  }

  bool _isLeafOutdated(MwmRegion region) {
    final latest = _selectedMirrorResult?.latestSnapshot?.version;
    if (latest == null) return false;
    return widget.mwmStorage.hasUpdate(region.name, latest);
  }

  String _regionSubtitle(
    MwmRegion region,
    int downloadedLeafCount,
    int leafCount,
  ) {
    if (region.isGroup) {
      final outdatedCount = _outdatedLeafCount(region);
      final parts = [
        '$downloadedLeafCount/$leafCount maps',
        '${region.sizeMB} MB',
        if (outdatedCount > 0)
          '$outdatedCount update${outdatedCount == 1 ? '' : 's'}',
      ];
      return parts.join(' • ');
    }

    final metadata = widget.mwmStorage.getByRegion(region.name);
    final parts = ['${region.sizeMB} MB'];
    if (metadata != null) {
      parts.add('Version ${metadata.snapshotVersion}');
    }
    if (_isLeafOutdated(region)) {
      parts.add('Update available');
    }
    return parts.join(' • ');
  }

  bool _isRegionDownloading(MwmRegion region) {
    return region.leafRegions
        .any((leaf) => _activeDownloads.contains(leaf.name));
  }

  String? _regionError(MwmRegion region) {
    if (region.isLeaf) return _downloadErrors[region.name];
    for (final leaf in region.leafRegions) {
      final error = _downloadErrors[leaf.name];
      if (error != null) return error;
    }
    return null;
  }

  bool _isRegionBundled(MwmRegion region) {
    final leaves = region.leafRegions;
    return leaves.isNotEmpty &&
        leaves.every(
          (leaf) => widget.mwmStorage.getByRegion(leaf.name)?.isBundled == true,
        );
  }

  Widget _buildCompactTrailing(
    MwmRegion region,
    bool isDownloaded,
    bool isDownloading,
    double? progress,
  ) {
    if (region.isGroup && isDownloading) {
      return SizedBox(
        width: 32,
        child: Center(
          child: _CompactDownloadIconButton(
            tooltip: 'Cancel download',
            icon: Icons.close,
            color: Colors.red.shade500,
            onPressed: () => _cancelDownload(region),
          ),
        ),
      );
    }

    if (isDownloading && progress != null) {
      return SizedBox(
        width: 82,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _CompactProgressBar(value: progress),
            const SizedBox(width: 4),
            Text(
              '${(progress * 100).toInt()}%',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(width: 2),
            _CompactDownloadIconButton(
              tooltip: 'Cancel download',
              icon: Icons.close,
              color: Colors.red.shade500,
              onPressed: () => _cancelDownload(region),
            ),
          ],
        ),
      );
    }

    if (isDownloaded) {
      final isBundled = _isRegionBundled(region);
      final isOutdated = _isRegionOutdated(region);
      return SizedBox(
        width: 74,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (isOutdated)
              _CompactDownloadIconButton(
                tooltip: region.isGroup ? 'Update maps' : 'Update map',
                icon: Icons.system_update_alt,
                color: Colors.orange.shade700,
                onPressed:
                    _canStartDownload ? () => _downloadRegion(region) : null,
              ),
            if (!isBundled)
              _CompactDownloadIconButton(
                tooltip: region.isGroup ? 'Delete maps' : 'Delete map',
                icon: Icons.delete_outline,
                color: Colors.red.shade400,
                onPressed: () => _confirmDeleteRegion(region),
              ),
            if (isBundled)
              Tooltip(
                message: 'Bundled',
                child: Icon(
                  Icons.inventory_2_outlined,
                  size: 15,
                  color: Colors.blue.shade700,
                ),
              ),
          ],
        ),
      );
    }

    return SizedBox(
      width: 32,
      child: Align(
        alignment: Alignment.centerRight,
        child: _CompactDownloadIconButton(
          tooltip: _canStartDownload
              ? region.isGroup
                  ? 'Download missing maps'
                  : 'Download'
              : 'Max $kMaxConcurrentDownloads concurrent downloads',
          icon: Icons.download,
          color: _canStartDownload ? Colors.blue : Colors.grey,
          onPressed: _canStartDownload ? () => _downloadRegion(region) : null,
        ),
      ),
    );
  }

  Widget _buildTrailing(
    MwmRegion region,
    bool isDownloaded,
    bool isDownloading,
    double? progress,
  ) {
    if (region.isGroup && isDownloading) {
      return IconButton(
        tooltip: 'Cancel download',
        icon: const Icon(Icons.close),
        color: Colors.red.shade500,
        onPressed: () => _cancelDownload(region),
      );
    }

    if (isDownloading && progress != null) {
      return SizedBox(
        width: 112,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_usesStaticProgress)
              const Icon(Icons.downloading_outlined, size: 18)
            else
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 2,
                ),
              ),
            const SizedBox(width: 4),
            Text(
              '${(progress * 100).toInt()}%',
              style: const TextStyle(fontSize: 11),
            ),
            IconButton(
              tooltip: 'Cancel download',
              icon: const Icon(Icons.close, size: 18),
              color: Colors.red.shade500,
              onPressed: () => _cancelDownload(region),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      );
    }

    if (isDownloaded) {
      final isBundled = _isRegionBundled(region);
      final isOutdated = _isRegionOutdated(region);

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isBundled ? Colors.blue.shade100 : Colors.green.shade100,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _installedVersionLabel(region) ??
                  (isBundled ? 'bundled' : 'installed'),
              style: TextStyle(
                fontSize: 10,
                color: isBundled ? Colors.blue.shade800 : Colors.green.shade800,
              ),
            ),
          ),
          if (isOutdated)
            IconButton(
              icon: const Icon(Icons.system_update_alt, size: 20),
              color: Colors.orange.shade700,
              onPressed:
                  _canStartDownload ? () => _downloadRegion(region) : null,
              tooltip: region.isGroup ? 'Update maps' : 'Update map',
            ),
          // Show delete button for non-bundled maps
          if (!isBundled)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              color: Colors.red.shade400,
              onPressed: () => _confirmDeleteRegion(region),
              tooltip: region.isGroup ? 'Delete maps' : 'Delete map',
            ),
        ],
      );
    }

    // Show download button
    return IconButton(
      icon: Icon(
        Icons.download,
        color: _canStartDownload ? Colors.blue : Colors.grey,
      ),
      onPressed: _canStartDownload ? () => _downloadRegion(region) : null,
      tooltip: _canStartDownload
          ? region.isGroup
              ? 'Download missing maps'
              : 'Download'
          : 'Max $kMaxConcurrentDownloads concurrent downloads',
    );
  }

  String? _installedVersionLabel(MwmRegion region) {
    final versions = <String>{};
    for (final leaf in region.leafRegions) {
      final metadata = widget.mwmStorage.getByRegion(leaf.name);
      if (metadata == null) continue;
      versions.add(metadata.snapshotVersion);
    }
    if (versions.isEmpty) return null;
    if (versions.length == 1) {
      final version = versions.first;
      return version == 'bundled' ? 'bundled' : 'v$version';
    }
    return 'mixed';
  }

  /// Show confirmation dialog before deleting a region.
  Future<void> _confirmDeleteRegion(MwmRegion region) async {
    final sizeMb =
        (_installedRegionSizeBytes(region) / (1024 * 1024)).toStringAsFixed(1);
    final mapCount = region.leafRegions.length;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: Colors.red),
            SizedBox(width: 8),
            Text('Delete Map'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              region.isGroup
                  ? 'Delete $mapCount maps for "${region.displayName}"?'
                  : 'Are you sure you want to delete "${region.displayName}"?',
            ),
            const SizedBox(height: 8),
            Text(
              'This will free up $sizeMb MB of storage.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Text(
              'You can re-download it from the server at any time.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteRegion(region);
    }
  }

  int _installedRegionSizeBytes(MwmRegion region) {
    return region.leafRegions.fold<int>(0, (sum, leaf) {
      return sum + (widget.mwmStorage.getByRegion(leaf.name)?.fileSize ?? 0);
    });
  }

  /// Delete a downloaded region.
  Future<void> _deleteRegion(MwmRegion region) async {
    debugPrint('[Downloads] Deleting ${region.name}...');

    final results = <DeleteResult>[];
    for (final leaf in region.leafRegions) {
      final metadata = widget.mwmStorage.getByRegion(leaf.name);
      if (metadata != null && !metadata.isBundled) {
        results.add(await widget.mwmStorage.deleteMap(leaf.name));
      }
    }

    if (results.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'No downloaded maps to delete for ${region.displayName}')),
        );
      }
      return;
    }

    final failures = results.where((result) => !result.success).toList();

    if (failures.isEmpty) {
      for (final result in results) {
        if (result.deletedBytes != null) {
          _availableSpaceBytes += result.deletedBytes!;
        }
      }

      // Notify parent that maps changed
      widget.onMapsChanged?.call();

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted ${region.displayName}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete: ${failures.first.error}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

/// Item types for the virtualized list
enum _ListItemType { searchCount, header, region }

class _CompactDownloadsStatus extends StatelessWidget {
  const _CompactDownloadsStatus({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 3),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _CompactDownloadIconButton extends StatelessWidget {
  const _CompactDownloadIconButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, color: color, size: 15),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 24, height: 24),
    );
  }
}

class _StaticDesktopProgress extends StatelessWidget {
  const _StaticDesktopProgress({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 24, color: colorScheme.primary),
        const SizedBox(height: 8),
        Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelLarge,
        ),
        const SizedBox(height: 4),
        Text(
          'Loading map catalog...',
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _DownloadsEmptyState extends StatelessWidget {
  const _DownloadsEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 190;
        final theme = Theme.of(context);
        final content = Padding(
          padding: EdgeInsets.all(compact ? 12 : 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: compact ? 32 : 48,
                color: Colors.grey,
              ),
              SizedBox(height: compact ? 8 : 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: compact
                    ? theme.textTheme.titleSmall
                    : theme.textTheme.titleMedium,
              ),
              SizedBox(height: compact ? 4 : 8),
              Text(
                message,
                textAlign: TextAlign.center,
                maxLines: compact ? 2 : null,
                overflow: compact ? TextOverflow.ellipsis : null,
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
              if (action != null) ...[
                SizedBox(height: compact ? 8 : 16),
                action!,
              ],
            ],
          ),
        );

        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(child: content),
          ),
        );
      },
    );
  }
}

class _CompactProgressBar extends StatelessWidget {
  const _CompactProgressBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final clampedValue = value.clamp(0.0, 1.0).toDouble();

    return SizedBox(
      width: 18,
      height: 4,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: clampedValue,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.primary,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Helper class for ListView.builder items
class _ListItem {
  final _ListItemType type;
  final int? count;
  final String? title;
  final Color? color;
  final MwmRegion? region;
  final int depth;

  const _ListItem._({
    required this.type,
    this.depth = 0,
    this.count,
    this.title,
    this.color,
    this.region,
  });

  factory _ListItem.searchCount(int count) =>
      _ListItem._(type: _ListItemType.searchCount, count: count);

  factory _ListItem.header(String title, Color color) =>
      _ListItem._(type: _ListItemType.header, title: title, color: color);

  factory _ListItem.region(MwmRegion region, {int depth = 0}) =>
      _ListItem._(type: _ListItemType.region, region: region, depth: depth);
}
