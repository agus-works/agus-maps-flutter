/// Service for discovering and downloading MWM files from CoMaps CDN servers.
///
/// This is the runtime library for Flutter apps. For build-time tools,
/// see `tool/map_downloader.dart` and `tool/check_mirrors.dart`.
///
/// CoMaps CDN URL structure: `<base>/maps/<version>/<file>`
/// Example: `https://mapgen-fi-1.comaps.app/maps/260106/Gibraltar.mwm`
library;

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

// Re-export shared utilities
export 'src/mirror_utils.dart'
    show
        comapsMetaserverUrl,
        defaultMirrors,
        MirrorConfig,
        MirrorStatus,
        Snapshot,
        MwmRegion,
        CountriesData;

import 'src/mirror_utils.dart' as utils;

/// Represents a mirror server hosting MWM files.
///
/// Extends [MirrorConfig] with runtime state (latency, availability).
class Mirror {
  final String name;
  final String baseUrl;
  int? latencyMs;
  bool isAvailable;

  Mirror({
    required this.name,
    required this.baseUrl,
    this.latencyMs,
    this.isAvailable = true,
  });

  /// Create from MirrorConfig
  factory Mirror.fromConfig(utils.MirrorConfig config) {
    return Mirror(name: config.name, baseUrl: config.baseUrl);
  }

  /// Convert to MirrorConfig
  utils.MirrorConfig toConfig() => utils.MirrorConfig(name: name, baseUrl: baseUrl);

  @override
  String toString() => 'Mirror($name, ${latencyMs}ms, available=$isAvailable)';
}

/// Service for discovering and downloading MWM files from CoMaps CDN servers.
///
/// CoMaps CDN URL structure: `<base>/maps/<version>/<file>`
/// Example: `https://mapgen-fi-1.comaps.app/maps/260106/Gibraltar.mwm`
class MirrorService {
  /// CoMaps CDN servers (official, verified working).
  /// These servers host CoMaps-specific MWM files with features like:
  /// - Improved routing engine with conditional restrictions
  /// - More dense altitude contour lines
  /// - Additional POIs (EV charging stations, etc.)
  /// - Enhanced map colors for light/dark modes
  ///
  /// URL structure: `<base>/maps/<version>/<file>`
  static final List<Mirror> defaultMirrors = utils.defaultMirrors
      .map((c) => Mirror.fromConfig(c))
      .toList();

  final http.Client _client;
  final List<Mirror> mirrors;

  MirrorService({http.Client? client, List<Mirror>? customMirrors})
    : _client = client ?? http.Client(),
      mirrors = customMirrors ?? List.from(defaultMirrors);

  /// Measure latency to each mirror using a HEAD request.
  ///
  /// Updates [Mirror.latencyMs] and [Mirror.isAvailable] for each mirror.
  Future<void> measureLatencies() async {
    await Future.wait(
      mirrors.map((m) async {
        try {
          final stopwatch = Stopwatch()..start();
          final response = await _client
              .head(Uri.parse(m.baseUrl))
              .timeout(const Duration(seconds: 10));
          stopwatch.stop();

          m.latencyMs = stopwatch.elapsedMilliseconds;
          m.isAvailable = response.statusCode == 200 ||
              response.statusCode == 301 ||
              response.statusCode == 302;
        } catch (e) {
          m.latencyMs = null;
          m.isAvailable = false;
        }
      }),
    );
  }

  /// Get the fastest available mirror.
  ///
  /// Returns null if no mirrors are available.
  /// Call [measureLatencies] first for accurate results.
  Mirror? getFastestMirror() {
    final available = mirrors.where((m) => m.isAvailable).toList();
    if (available.isEmpty) return null;
    return available.reduce(
      (a, b) => (a.latencyMs ?? 999999) < (b.latencyMs ?? 999999) ? a : b,
    );
  }

  /// Generate candidate snapshot versions dynamically based on current date.
  ///
  /// Versions are in YYMMDD format. We generate candidates for:
  /// - Today and the past [daysToProbe] days
  /// - Returns list sorted newest first
  static List<String> generateCandidateVersions({int daysToProbe = 90}) {
    return utils.MirrorService.generateCandidateVersions(daysToProbe: daysToProbe);
  }

  /// Get list of available snapshots from a mirror.
  ///
  /// CoMaps CDN doesn't provide directory listings, so we dynamically probe
  /// versions based on the current date (going back 90 days).
  /// Results are sorted by date, newest first.
  Future<List<utils.Snapshot>> getSnapshots(Mirror mirror) async {
    final snapshots = <utils.Snapshot>[];
    final candidates = generateCandidateVersions();

    // Probe candidate versions until we find one
    for (final version in candidates) {
      final testUrl = utils.MirrorService.buildDownloadUrl(
        mirror.baseUrl, version, 'countries.txt');
      try {
        final response = await _client
            .head(Uri.parse(testUrl))
            .timeout(const Duration(seconds: 3));
        if (response.statusCode == 200) {
          snapshots.add(utils.Snapshot(version: version));
          // Found one, we can stop or continue to find more
          // For now, just find the first (latest) one to be efficient
          break;
        }
      } catch (e) {
        // Skip unavailable snapshots
      }
    }

    // Sort by date, newest first
    snapshots.sort((a, b) => b.date.compareTo(a.date));
    return snapshots;
  }

  /// Get list of available regions in a snapshot.
  ///
  /// Fetches and parses countries.txt (JSON format) from the CoMaps CDN.
  ///
  /// URL: `<base>/maps/<version>/countries.txt`
  Future<List<utils.MwmRegion>> getRegions(Mirror mirror, utils.Snapshot snapshot) async {
    final url = utils.MirrorService.buildDownloadUrl(
      mirror.baseUrl, snapshot.version, 'countries.txt');
    try {
      final response = await _client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final countriesData = utils.CountriesData.fromJson(json);
        return countriesData.allRegions;
      }
    } catch (e) {
      // countries.txt not available or parse error
    }

    throw Exception(
      'Could not fetch regions from CoMaps CDN. '
      'URL: $url',
    );
  }

  /// Build the full download URL for a region.
  ///
  /// CoMaps CDN URL structure: `<base>/maps/<version>/<file>`
  String getDownloadUrl(Mirror mirror, utils.Snapshot snapshot, utils.MwmRegion region) {
    return utils.MirrorService.buildDownloadUrl(
      mirror.baseUrl, snapshot.version, region.fileName);
  }

  /// Get file size via HEAD request.
  ///
  /// Useful when size isn't available from the directory listing.
  Future<int?> getFileSize(String url) async {
    try {
      final response = await _client.head(Uri.parse(url));
      final contentLength = response.headers['content-length'];
      return contentLength != null ? int.tryParse(contentLength) : null;
    } catch (e) {
      return null;
    }
  }

  /// Download a file directly to disk with progress callback.
  ///
  /// Streams data directly to the destination file to avoid holding
  /// the entire file in memory. This is critical for large map files
  /// (100MB+) to prevent iOS memory exhaustion (EXC_RESOURCE).
  ///
  /// [destination] is the file to write to (will be created/overwritten).
  /// [onProgress] is called with (bytesReceived, totalBytes).
  /// Returns the total number of bytes written.
  Future<int> downloadToFile(
    String url,
    File destination, {
    void Function(int received, int total)? onProgress,
  }) async {
    final request = http.Request('GET', Uri.parse(url));
    final response = await _client.send(request);

    if (response.statusCode != 200) {
      throw Exception('Download failed: HTTP ${response.statusCode}');
    }

    final contentLength = response.contentLength ?? 0;
    int received = 0;

    // Ensure parent directory exists
    await destination.parent.create(recursive: true);

    // Stream directly to file - never hold entire file in memory
    final sink = destination.openWrite();
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, contentLength);
      }
    } finally {
      await sink.close();
    }

    return received;
  }

  /// Download a file with progress callback (legacy in-memory version).
  ///
  /// **WARNING:** This method accumulates the entire file in memory.
  /// For large files, use [downloadToFile] instead to stream directly
  /// to disk and avoid memory exhaustion on iOS.
  ///
  /// Returns the downloaded bytes.
  /// [onProgress] is called with (bytesReceived, totalBytes).
  @Deprecated('Use downloadToFile() for large files to avoid memory exhaustion')
  Future<List<int>> downloadWithProgress(
    String url, {
    void Function(int received, int total)? onProgress,
  }) async {
    final request = http.Request('GET', Uri.parse(url));
    final response = await _client.send(request);

    if (response.statusCode != 200) {
      throw Exception('Download failed: HTTP ${response.statusCode}');
    }

    final contentLength = response.contentLength ?? 0;
    final bytes = <int>[];
    int received = 0;

    await for (final chunk in response.stream) {
      bytes.addAll(chunk);
      received += chunk.length;
      onProgress?.call(received, contentLength);
    }

    return bytes;
  }

  /// Dispose of the HTTP client.
  void dispose() {
    _client.close();
  }
}
