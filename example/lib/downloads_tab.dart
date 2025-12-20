import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:agus_maps_flutter/mirror_service.dart';
import 'package:agus_maps_flutter/mwm_storage.dart';
import 'package:agus_maps_flutter/agus_maps_flutter.dart' as agus;
import 'package:fuzzywuzzy/fuzzywuzzy.dart' as fuzz;
import 'package:storage_space/storage_space.dart';
import 'downloads_cache.dart';

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
  measuringLatencies,
  selectingMirror,
  loadingSnapshots,
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
      LoadingStep.measuringLatencies => 'Measuring mirror latencies...',
      LoadingStep.selectingMirror => 'Selecting fastest mirror...',
      LoadingStep.loadingSnapshots => 'Loading available snapshots...',
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
  final VoidCallback? onMapsChanged;
  final bool isVisible;

  const DownloadsTab({
    super.key,
    required this.mwmStorage,
    this.onMapsChanged,
    this.isVisible = false,
  });

  @override
  State<DownloadsTab> createState() => _DownloadsTabState();
}

class _DownloadsTabState extends State<DownloadsTab> {
  final MirrorService _mirrorService = MirrorService();
  final DownloadsCacheService _cacheService = DownloadsCacheService();

  Mirror? _selectedMirror;
  Snapshot? _selectedSnapshot;
  List<Snapshot> _snapshots = [];
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

  // Download tracking - maps region name to progress (0.0 to 1.0)
  final Map<String, double> _downloadProgress = {};
  final Map<String, String> _downloadErrors = {};

  // Track active downloads for limiting concurrent downloads
  final Set<String> _activeDownloads = {};

  // Disk space
  int _availableSpaceBytes = 0;

  // Track if we've initialized data (for lazy loading)
  bool _hasInitialized = false;

  // Track if data came from cache (for UI feedback)
  bool _loadedFromCache = false;

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

    // Use extractAllSorted for relevance-sorted fuzzy search
    // This returns results sorted by best match score (highest first)
    final results = fuzz.extractAllSorted<MwmRegion>(
      query: _searchQuery,
      choices: _regions,
      cutoff: kFuzzySearchThreshold,
      getter: (region) => region.displayName,
    );

    _filteredRegions = results.map((r) => r.choice).toList();
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
              // Use cached data
              _selectedMirror = cached.mirror;
              _selectedSnapshot = cached.snapshot;
              _snapshots = [cached.snapshot];
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

              // Optionally refresh snapshots in background
              _refreshSnapshotsInBackground();
              return;
            }
          } else {
            // No internet, use cache anyway
            _selectedMirror = cached.mirror;
            _selectedSnapshot = cached.snapshot;
            _snapshots = [cached.snapshot];
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

      // Measure mirror latencies
      _setLoadingStep(LoadingStep.measuringLatencies);
      debugPrint('[Downloads] Measuring mirror latencies...');
      await _mirrorService.measureLatencies();

      // Select fastest available mirror
      _setLoadingStep(LoadingStep.selectingMirror);
      _selectedMirror = _mirrorService.getFastestMirror();
      debugPrint('[Downloads] Selected mirror: $_selectedMirror');

      if (_selectedMirror == null) {
        throw Exception(
          'No mirrors available. All mirror servers may be down.',
        );
      }

      // Load snapshots
      _setLoadingStep(LoadingStep.loadingSnapshots);
      debugPrint(
        '[Downloads] Loading snapshots from ${_selectedMirror!.baseUrl}...',
      );
      _snapshots = await _mirrorService.getSnapshots(_selectedMirror!);
      debugPrint('[Downloads] Found ${_snapshots.length} snapshots');

      if (_snapshots.isEmpty) {
        throw Exception('No map versions available from mirror.');
      }

      _selectedSnapshot = _snapshots.first;

      // Load regions
      _setLoadingStep(LoadingStep.loadingRegions);
      await _loadRegions();

      // Save to cache
      if (_regions.isNotEmpty &&
          _selectedMirror != null &&
          _selectedSnapshot != null) {
        await _cacheService.saveCache(
          CachedDownloadsData(
            mirrorName: _selectedMirror!.name,
            mirrorBaseUrl: _selectedMirror!.baseUrl,
            snapshotVersion: _selectedSnapshot!.version,
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

  /// Refresh snapshots list in background without blocking UI.
  Future<void> _refreshSnapshotsInBackground() async {
    if (_selectedMirror == null || !_hasInternet) return;

    try {
      final snapshots = await _mirrorService.getSnapshots(_selectedMirror!);
      if (mounted && snapshots.isNotEmpty) {
        setState(() {
          _snapshots = snapshots;
        });
        debugPrint(
          '[Downloads] Background refresh found ${snapshots.length} snapshots',
        );
      }
    } catch (e) {
      debugPrint('[Downloads] Background refresh failed: $e');
    }
  }

  Future<void> _loadRegions() async {
    if (_selectedMirror == null || _selectedSnapshot == null) return;

    setState(() => _isLoading = true);
    try {
      debugPrint(
        '[Downloads] Loading regions for snapshot ${_selectedSnapshot!.version}...',
      );
      _regions = await _mirrorService.getRegions(
        _selectedMirror!,
        _selectedSnapshot!,
      );
      _filteredRegions = List.from(_regions);
      _applySearch(); // Re-apply any existing search
      debugPrint('[Downloads] Found ${_regions.length} regions');
      _error = null;

      // Update cache with new regions
      if (_regions.isNotEmpty) {
        await _cacheService.saveCache(
          CachedDownloadsData(
            mirrorName: _selectedMirror!.name,
            mirrorBaseUrl: _selectedMirror!.baseUrl,
            snapshotVersion: _selectedSnapshot!.version,
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
        // Desktop platforms - use df command
        final dir = await getApplicationDocumentsDirectory();
        final stat = await Process.run('df', ['-B1', dir.path]);
        if (stat.exitCode == 0) {
          final lines = (stat.stdout as String).split('\n');
          if (lines.length > 1) {
            final parts = lines[1].split(RegExp(r'\s+'));
            if (parts.length >= 4) {
              _availableSpaceBytes = int.tryParse(parts[3]) ?? 0;
              debugPrint(
                '[Downloads] Disk space from df: '
                '${(_availableSpaceBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB free',
              );
            }
          }
        }
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
    if (_selectedMirror == null || _selectedSnapshot == null) return;

    // Check concurrent download limit
    if (!_canStartDownload) {
      _showError(
        'Maximum $kMaxConcurrentDownloads concurrent downloads allowed. '
        'Please wait for a download to complete.',
      );
      return;
    }

    final url = _mirrorService.getDownloadUrl(
      _selectedMirror!,
      _selectedSnapshot!,
      region,
    );

    // Get file size
    int fileSize =
        region.sizeBytes ?? await _mirrorService.getFileSize(url) ?? 0;

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

    // Start download
    setState(() {
      _downloadProgress[region.name] = 0.0;
      _downloadErrors.remove(region.name);
      _activeDownloads.add(region.name);
    });

    try {
      final dir = await getApplicationDocumentsDirectory();
      final filePath = '${dir.path}/${region.fileName}';
      final file = File(filePath);

      // Stream directly to file to avoid memory exhaustion on iOS.
      // Large map files (100MB+) would otherwise cause EXC_RESOURCE.
      final bytesWritten = await _mirrorService.downloadToFile(
        url,
        file,
        onProgress: (received, total) {
          if (mounted && total > 0) {
            setState(() {
              _downloadProgress[region.name] = received / total;
            });
          }
        },
      );

      // Save metadata
      await widget.mwmStorage.upsert(
        MwmMetadata(
          regionName: region.name,
          snapshotVersion: _selectedSnapshot!.version,
          fileSize: bytesWritten,
          downloadDate: DateTime.now(),
          filePath: filePath,
          isBundled: false,
        ),
      );

      // Register with map engine
      final result = agus.registerSingleMap(filePath);
      debugPrint('Registered ${region.name}: result=$result');

      // Update disk space
      _availableSpaceBytes -= bytesWritten;

      // Notify parent
      widget.onMapsChanged?.call();

      if (mounted) {
        setState(() {
          _downloadProgress.remove(region.name);
          _activeDownloads.remove(region.name);
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Downloaded ${region.name}')));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloadProgress.remove(region.name);
          _activeDownloads.remove(region.name);
          _downloadErrors[region.name] = e.toString();
        });
      }
    }
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
    return Column(
      children: [
        // Header with selector and status
        _buildHeader(),

        // Region list
        Expanded(child: _buildRegionList()),
      ],
    );
  }

  Widget _buildHeader() {
    final downloadedCount = widget.mwmStorage.getAll().length;
    final availableGb = _availableSpaceBytes / (1024 * 1024 * 1024);
    final activeCount = _activeDownloads.length;

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
                tooltip: 'Force refresh',
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
          Row(
            children: [
              _buildStatusChip(
                Icons.check_circle,
                '$downloadedCount installed',
                Colors.green,
              ),
              const SizedBox(width: 8),
              _buildStatusChip(
                Icons.storage,
                '${availableGb.toStringAsFixed(1)} GB free',
                _availableSpaceBytes < kLowSpaceWarningBytes
                    ? Colors.orange
                    : Colors.grey,
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Mirror/Snapshot selector (compact)
          Row(
            children: [
              Expanded(
                child: DropdownButton<Snapshot>(
                  value: _selectedSnapshot,
                  isExpanded: true,
                  underline: const SizedBox(),
                  style: Theme.of(context).textTheme.bodySmall,
                  items: _snapshots.map((s) {
                    return DropdownMenuItem(
                      value: s,
                      child: Text('${s.version} (${s.formattedDate})'),
                    );
                  }).toList(),
                  onChanged: (s) {
                    setState(() => _selectedSnapshot = s);
                    _loadRegions();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _selectedMirror?.name ?? 'No mirror',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
              if (_selectedMirror?.latencyMs != null)
                Text(
                  ' (${_selectedMirror!.latencyMs}ms)',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
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
      return const Center(child: CircularProgressIndicator());
    }

    if (_regions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _hasInternet ? Icons.map_outlined : Icons.wifi_off,
                size: 48,
                color: Colors.grey,
              ),
              const SizedBox(height: 16),
              Text(
                _hasInternet
                    ? 'No regions available'
                    : 'No Internet Connection',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _hasInternet
                    ? 'Could not load map regions from mirror servers.\nTry selecting a different snapshot or tap Refresh.'
                    : 'Connect to the internet to browse and download maps.',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _init(forceRefresh: true),
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
        ),
      );
    }

    // Use filtered regions for display
    final regionsToShow = _filteredRegions;

    // Show "no results" if search returned nothing
    if (_searchQuery.isNotEmpty && regionsToShow.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                'No regions found',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'No regions match "$_searchQuery".\nTry a different search term.',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    // Separate downloaded and available regions
    final downloaded = <MwmRegion>[];
    final available = <MwmRegion>[];

    for (final region in regionsToShow) {
      if (widget.mwmStorage.isDownloaded(region.name)) {
        downloaded.add(region);
      } else {
        available.add(region);
      }
    }

    return ListView(
      children: [
        // Result count when searching
        if (_searchQuery.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Found ${regionsToShow.length} region${regionsToShow.length == 1 ? '' : 's'}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ),

        // Downloaded section
        if (downloaded.isNotEmpty) ...[
          _buildSectionHeader('Installed (${downloaded.length})', Colors.green),
          ...downloaded.map((r) => _buildRegionTile(r, isDownloaded: true)),
        ],

        // Available section
        if (available.isNotEmpty) ...[
          _buildSectionHeader('Available (${available.length})', Colors.blue),
          ...available.map((r) => _buildRegionTile(r, isDownloaded: false)),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: color.withOpacity(0.05),
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

  Widget _buildRegionTile(MwmRegion region, {required bool isDownloaded}) {
    final progress = _downloadProgress[region.name];
    final error = _downloadErrors[region.name];
    final isDownloading = progress != null;

    return ListTile(
      dense: true,
      leading: Icon(
        isDownloaded
            ? Icons.check_circle
            : isDownloading
                ? Icons.downloading
                : Icons.circle_outlined,
        color: isDownloaded
            ? Colors.green
            : isDownloading
                ? Colors.blue
                : Colors.grey,
        size: 20,
      ),
      title: Text(region.displayName, style: const TextStyle(fontSize: 14)),
      subtitle: error != null
          ? Text(
              error,
              style: const TextStyle(color: Colors.red, fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : Text('${region.sizeMB} MB', style: const TextStyle(fontSize: 11)),
      trailing: _buildTrailing(region, isDownloaded, isDownloading, progress),
      onTap: error != null
          ? () {
              setState(() {
                _downloadErrors.remove(region.name);
              });
            }
          : null,
    );
  }

  Widget _buildTrailing(
    MwmRegion region,
    bool isDownloaded,
    bool isDownloading,
    double? progress,
  ) {
    if (isDownloading && progress != null) {
      return SizedBox(
        width: 60,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(value: progress, strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Text(
              '${(progress * 100).toInt()}%',
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
      );
    }

    if (isDownloaded) {
      final meta = widget.mwmStorage.getByRegion(region.name);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: meta?.isBundled == true
              ? Colors.blue.shade100
              : Colors.green.shade100,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          meta?.isBundled == true ? 'bundled' : 'installed',
          style: TextStyle(
            fontSize: 10,
            color: meta?.isBundled == true
                ? Colors.blue.shade800
                : Colors.green.shade800,
          ),
        ),
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
          ? 'Download'
          : 'Max $kMaxConcurrentDownloads concurrent downloads',
    );
  }
}
