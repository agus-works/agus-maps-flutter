/// Shared utilities for CoMaps CDN mirror operations.
///
/// This library provides reusable components for:
/// - Mirror server configuration and discovery
/// - Dynamic snapshot version probing
/// - Countries list parsing from countries.txt (JSON format)
/// - MWM region metadata
///
/// Used by both:
/// - Runtime library (`lib/mirror_service.dart`) for Flutter apps
/// - Build tools (`tool/map_downloader.dart`, `tool/check_mirrors.dart`)

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// CoMaps metaserver URL for discovering active servers
const String comapsMetaserverUrl = 'https://cdn-us-1.comaps.app/servers';

/// Default CoMaps CDN servers (verified working)
/// URL structure: `<base>/maps/<version>/<file>`
const List<MirrorConfig> defaultMirrors = [
  MirrorConfig(
    name: 'CoMaps MapGen Finland',
    baseUrl: 'https://mapgen-fi-1.comaps.app/',
  ),
  MirrorConfig(
    name: 'CoMaps CDN US',
    baseUrl: 'https://cdn-us-2.comaps.tech/',
  ),
  MirrorConfig(
    name: 'CoMaps CDN Germany',
    baseUrl: 'https://comaps.firewall-gateway.de/',
  ),
];

/// Mirror server configuration
class MirrorConfig {
  final String name;
  final String baseUrl;

  const MirrorConfig({
    required this.name,
    required this.baseUrl,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'baseUrl': baseUrl,
  };

  @override
  String toString() => 'MirrorConfig($name, $baseUrl)';
}

/// Result of checking a mirror's availability
class MirrorStatus {
  final MirrorConfig mirror;
  final bool isAccessible;
  final int? latencyMs;
  final String? latestSnapshot;
  final String? error;
  final bool isFromMetaserver;

  const MirrorStatus({
    required this.mirror,
    required this.isAccessible,
    this.latencyMs,
    this.latestSnapshot,
    this.error,
    this.isFromMetaserver = false,
  });

  bool get isOperational => isAccessible && latestSnapshot != null;

  Map<String, dynamic> toJson() => {
    'mirror': mirror.toJson(),
    'isAccessible': isAccessible,
    'latencyMs': latencyMs,
    'latestSnapshot': latestSnapshot,
    'error': error,
    'isFromMetaserver': isFromMetaserver,
    'isOperational': isOperational,
  };
}

/// Represents a snapshot version (YYMMDD format)
///
/// Snapshot versions use YYMMDD format (e.g., "260108" for January 8, 2026).
class Snapshot {
  final String version;
  final DateTime date;

  Snapshot({required this.version}) : date = _parseDate(version);

  static DateTime _parseDate(String v) {
    if (v.length != 6) {
      throw FormatException('Invalid snapshot version: $v (expected YYMMDD)');
    }
    final year = 2000 + int.parse(v.substring(0, 2));
    final month = int.parse(v.substring(2, 4));
    final day = int.parse(v.substring(4, 6));
    return DateTime(year, month, day);
  }

  String get formattedDate =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {
    'version': version,
    'date': formattedDate,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Snapshot &&
          runtimeType == other.runtimeType &&
          version == other.version;

  @override
  int get hashCode => version.hashCode;

  @override
  String toString() => 'Snapshot($version, $formattedDate)';
}

/// Represents a downloadable MWM region from countries.txt (JSON format)
class MwmRegion {
  final String id;
  final int sizeBytes;
  final String? sha1Base64;
  final List<String>? oldNames;
  final List<MwmRegion>? subregions;

  MwmRegion({
    required this.id,
    required this.sizeBytes,
    this.sha1Base64,
    this.oldNames,
    this.subregions,
  });

  /// Alias for [id] for backward compatibility
  String get name => id;

  String get fileName => '$id.mwm';

  String get sizeMB => (sizeBytes / (1024 * 1024)).toStringAsFixed(2);

  /// Human-readable display name with underscores replaced by spaces
  String get displayName => Uri.decodeComponent(id).replaceAll('_', ' ');

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name, // For backward compatibility with cache
    'fileName': fileName,
    'sizeBytes': sizeBytes,
    'sizeMB': sizeMB,
    'sha1Base64': sha1Base64,
    if (oldNames != null) 'oldNames': oldNames,
    if (subregions != null) 'subregions': subregions!.map((r) => r.toJson()).toList(),
  };

  /// Create from CoMaps countries.txt JSON format
  /// Also supports legacy cache format with 'name' field
  factory MwmRegion.fromJson(Map<String, dynamic> json) {
    final subregionsJson = json['g'] as List<dynamic>?;
    // Support both 'id' (countries.txt) and 'name' (legacy cache) formats
    final id = json['id'] as String? ?? json['name'] as String;
    // Support both 's' (countries.txt) and 'sizeBytes' (legacy cache) formats
    final sizeBytes = json['s'] as int? ?? json['sizeBytes'] as int? ?? 0;
    return MwmRegion(
      id: id,
      sizeBytes: sizeBytes,
      sha1Base64: json['sha1_base64'] as String?,
      oldNames: (json['old'] as List<dynamic>?)?.cast<String>(),
      subregions: subregionsJson?.map((j) => MwmRegion.fromJson(j as Map<String, dynamic>)).toList(),
    );
  }

  @override
  String toString() => 'MwmRegion($id, $sizeMB MB)';
}

/// Parsed countries.txt data (JSON format from CoMaps CDN)
class CountriesData {
  final int version;
  final List<MwmRegion> regions;

  CountriesData({
    required this.version,
    required this.regions,
  });

  /// Get all regions flattened (including subregions)
  List<MwmRegion> get allRegions {
    final result = <MwmRegion>[];
    void addRegions(List<MwmRegion> regions) {
      for (final region in regions) {
        result.add(region);
        if (region.subregions != null) {
          addRegions(region.subregions!);
        }
      }
    }
    addRegions(regions);
    return result;
  }

  /// Find a region by ID
  MwmRegion? findRegion(String id) {
    for (final region in allRegions) {
      if (region.id == id) return region;
    }
    return null;
  }

  /// Get total size of all regions
  int get totalSizeBytes => allRegions.fold(0, (sum, r) => sum + r.sizeBytes);

  Map<String, dynamic> toJson() => {
    'version': version,
    'totalRegions': allRegions.length,
    'totalSizeBytes': totalSizeBytes,
    'totalSizeMB': (totalSizeBytes / (1024 * 1024)).toStringAsFixed(2),
    'regions': regions.map((r) => r.toJson()).toList(),
  };

  factory CountriesData.fromJson(Map<String, dynamic> json) {
    final regionsJson = json['g'] as List<dynamic>? ?? [];
    return CountriesData(
      version: json['v'] as int,
      regions: regionsJson.map((j) => MwmRegion.fromJson(j as Map<String, dynamic>)).toList(),
    );
  }
}

/// Service for interacting with CoMaps CDN mirrors
///
/// CoMaps CDN URL structure: `<base>/maps/<version>/<file>`
/// Example: `https://mapgen-fi-1.comaps.app/maps/260106/Gibraltar.mwm`
class MirrorService {
  final http.Client _client;
  final List<MirrorConfig> mirrors;

  MirrorService({
    http.Client? client,
    List<MirrorConfig>? customMirrors,
  })  : _client = client ?? http.Client(),
        mirrors = customMirrors ?? List.from(defaultMirrors);

  /// Generate candidate snapshot versions dynamically based on current date.
  ///
  /// Versions are in YYMMDD format. We generate candidates for:
  /// - Today and the past [daysToProbe] days
  /// - Returns list sorted newest first
  static List<String> generateCandidateVersions({int daysToProbe = 90}) {
    final candidates = <String>[];
    final now = DateTime.now();

    for (int daysBack = 0; daysBack <= daysToProbe; daysBack++) {
      final date = now.subtract(Duration(days: daysBack));
      candidates.add(dateToVersion(date));
    }

    return candidates;
  }

  /// Convert DateTime to YYMMDD version string
  static String dateToVersion(DateTime date) {
    final yy = (date.year % 100).toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    final dd = date.day.toString().padLeft(2, '0');
    return '$yy$mm$dd';
  }

  /// Query the CoMaps metaserver for active servers
  Future<List<String>> queryMetaserver() async {
    try {
      final response = await _client
          .get(Uri.parse(comapsMetaserverUrl))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> servers = jsonDecode(response.body);
        return servers.cast<String>();
      }
    } catch (e) {
      // Silently fail - will use default mirrors
    }
    return [];
  }

  /// Build download URL for CoMaps CDN
  ///
  /// URL structure: `<base>/maps/<snapshot>/<fileName>`
  static String buildDownloadUrl(String baseUrl, String snapshot, String fileName) {
    return '${baseUrl}maps/$snapshot/$fileName';
  }

  /// Check mirror accessibility and measure latency
  Future<MirrorStatus> checkMirror(
    MirrorConfig mirror,
    List<String> candidateSnapshots, {
    bool isFromMetaserver = false,
  }) async {
    bool isAccessible = false;
    int? latencyMs;
    String? latestSnapshot;
    String? error;

    // Check base URL accessibility
    try {
      final stopwatch = Stopwatch()..start();
      final response = await _client
          .head(Uri.parse(mirror.baseUrl))
          .timeout(const Duration(seconds: 10));
      stopwatch.stop();

      isAccessible = response.statusCode == 200 ||
          response.statusCode == 301 ||
          response.statusCode == 302;
      latencyMs = stopwatch.elapsedMilliseconds;
    } catch (e) {
      error = 'Base URL check failed: $e';
      return MirrorStatus(
        mirror: mirror,
        isAccessible: false,
        error: error,
        isFromMetaserver: isFromMetaserver,
      );
    }

    // Probe for latest snapshot
    if (isAccessible) {
      latestSnapshot = await findLatestSnapshot(mirror, candidateSnapshots);
      if (latestSnapshot == null) {
        error = 'No snapshots found';
      }
    }

    return MirrorStatus(
      mirror: mirror,
      isAccessible: isAccessible,
      latencyMs: latencyMs,
      latestSnapshot: latestSnapshot,
      error: error,
      isFromMetaserver: isFromMetaserver,
    );
  }

  /// Find the latest available snapshot on a mirror
  Future<String?> findLatestSnapshot(
    MirrorConfig mirror,
    List<String> candidates,
  ) async {
    for (final snapshot in candidates) {
      final countriesUrl = buildDownloadUrl(mirror.baseUrl, snapshot, 'countries.txt');
      try {
        final response = await _client
            .head(Uri.parse(countriesUrl))
            .timeout(const Duration(seconds: 3));
        if (response.statusCode == 200) {
          return snapshot;
        }
      } catch (_) {
        // Continue to next snapshot
      }
    }
    return null;
  }

  /// Fetch and parse countries.txt from a mirror (JSON format)
  Future<CountriesData?> fetchCountriesData(String baseUrl, String snapshot) async {
    final url = buildDownloadUrl(baseUrl, snapshot, 'countries.txt');
    try {
      final response = await _client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return CountriesData.fromJson(json);
      }
    } catch (e) {
      // Failed to fetch countries data
    }
    return null;
  }

  /// Download a file to disk with progress callback
  ///
  /// Streams data directly to the destination file to avoid holding
  /// the entire file in memory. This is critical for large map files
  /// (100MB+) to prevent iOS memory exhaustion (EXC_RESOURCE).
  Future<bool> downloadFile(
    String url,
    File destination, {
    void Function(int received, int total)? onProgress,
  }) async {
    try {
      final request = http.Request('GET', Uri.parse(url));
      final response = await _client.send(request);

      if (response.statusCode != 200) {
        return false;
      }

      final contentLength = response.contentLength ?? 0;
      int received = 0;

      await destination.parent.create(recursive: true);
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

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Download a file and return bytes written
  ///
  /// Streams data directly to the destination file to avoid holding
  /// the entire file in memory.
  ///
  /// Returns the total number of bytes written.
  /// Throws an exception if download fails.
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

  /// Get the best available mirror
  ///
  /// Queries metaserver, checks all mirrors for availability,
  /// and returns the fastest operational mirror.
  Future<MirrorStatus?> getBestMirror() async {
    final metaserverUrls = await queryMetaserver();
    final metaserverSet = metaserverUrls.toSet();
    final candidateSnapshots = generateCandidateVersions();

    final results = <MirrorStatus>[];

    for (final mirror in mirrors) {
      final isFromMetaserver = metaserverSet.any((url) =>
          mirror.baseUrl.contains(url.replaceAll('https://', '').replaceAll('/', '')) ||
          url.contains(mirror.baseUrl.replaceAll('https://', '').replaceAll('/', '')));

      final status = await checkMirror(
        mirror,
        candidateSnapshots,
        isFromMetaserver: isFromMetaserver,
      );
      results.add(status);
    }

    // Return the fastest operational mirror
    final operational = results.where((r) => r.isOperational).toList();
    if (operational.isEmpty) return null;

    operational.sort((a, b) => (a.latencyMs ?? 999999).compareTo(b.latencyMs ?? 999999));
    return operational.first;
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

  void dispose() {
    _client.close();
  }
}
