import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Represents a mirror server hosting MWM files.
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

  @override
  String toString() => 'Mirror($name, ${latencyMs}ms, available=$isAvailable)';
}

/// Represents a snapshot (version) of MWM files.
///
/// Snapshot versions use YYMMDD format (e.g., "250608" for June 8, 2025).
class Snapshot {
  final String version;
  final DateTime date;

  Snapshot({required this.version}) : date = _parseDate(version);

  static DateTime _parseDate(String v) {
    if (v.length != 6) {
      throw FormatException(
        'Invalid snapshot version: $v (expected YYMMDD format)',
      );
    }
    final year = 2000 + int.parse(v.substring(0, 2));
    final month = int.parse(v.substring(2, 4));
    final day = int.parse(v.substring(4, 6));
    return DateTime(year, month, day);
  }

  String get formattedDate {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

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

/// Represents a downloadable MWM region/country.
class MwmRegion {
  final String name;
  final String fileName;
  final int? sizeBytes;

  MwmRegion({required this.name, required this.fileName, this.sizeBytes});

  /// Human-readable display name with underscores replaced by spaces
  /// and URL encoding decoded.
  String get displayName {
    return Uri.decodeComponent(name).replaceAll('_', ' ');
  }

  String get sizeMB {
    if (sizeBytes == null) return '?';
    return (sizeBytes! / (1024 * 1024)).toStringAsFixed(1);
  }

  /// Convert to JSON for caching.
  Map<String, dynamic> toJson() => {
    'name': name,
    'fileName': fileName,
    'sizeBytes': sizeBytes,
  };

  /// Create from JSON for cache loading.
  factory MwmRegion.fromJson(Map<String, dynamic> json) => MwmRegion(
    name: json['name'] as String,
    fileName: json['fileName'] as String,
    sizeBytes: json['sizeBytes'] as int?,
  );

  @override
  String toString() => 'MwmRegion($name, $sizeMB MB)';
}

/// Top-level function to parse regions from HTML (for compute() isolate).
///
/// This must be a top-level function because compute() requires it.
List<MwmRegion> _parseRegionsFromHtml(String html) {
  final regions = <MwmRegion>[];
  // Handles both href="file.mwm" and href="./file.mwm" formats
  // Also captures the following <td> for size extraction
  final regex = RegExp(
    r'href="\.?/?([^"]+\.mwm)"[^>]*>[^<]*</a></td>\s*<td[^>]*title="(\d+)\s*B"',
    caseSensitive: false,
  );

  for (final match in regex.allMatches(html)) {
    final fileName = match.group(1)!;
    final name = fileName.replaceAll('.mwm', '');
    final sizeStr = match.group(2);
    final size = sizeStr != null ? int.tryParse(sizeStr) : null;

    regions.add(MwmRegion(name: name, fileName: fileName, sizeBytes: size));
  }

  // Fallback: if no matches with size, try simpler pattern
  if (regions.isEmpty) {
    final simpleRegex = RegExp(r'href="\.?/?([^"]+\.mwm)"');
    for (final match in simpleRegex.allMatches(html)) {
      final fileName = match.group(1)!;
      final name = fileName.replaceAll('.mwm', '');
      regions.add(MwmRegion(name: name, fileName: fileName));
    }
  }

  // Sort alphabetically
  regions.sort((a, b) => a.name.compareTo(b.name));
  return regions;
}

/// Service for discovering and downloading MWM files from mirror servers.
class MirrorService {
  /// Default mirror servers.
  static final List<Mirror> defaultMirrors = [
    Mirror(name: 'WFR Software', baseUrl: 'https://omaps.wfr.software/maps/'),
    Mirror(name: 'WebFreak', baseUrl: 'https://omaps.webfreak.org/maps/'),
  ];

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
          m.isAvailable = response.statusCode == 200;
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

  /// Get list of available snapshots from a mirror.
  ///
  /// Parses the HTML directory listing and extracts snapshot folder names.
  /// Results are sorted by date, newest first.
  Future<List<Snapshot>> getSnapshots(Mirror mirror) async {
    final uri = Uri.parse(mirror.baseUrl);
    final response = await _client.get(uri);

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch snapshots: HTTP ${response.statusCode}');
    }

    // Parse HTML directory listing for 6-digit folder names (YYMMDD)
    // Handles both href="250608/" and href="./250608/" formats
    final snapshots = <Snapshot>[];
    final regex = RegExp(r'href="\.?/?(\d{6})/"');

    for (final match in regex.allMatches(response.body)) {
      final version = match.group(1)!;
      try {
        snapshots.add(Snapshot(version: version));
      } catch (e) {
        // Skip invalid versions
      }
    }

    // Sort by date, newest first
    snapshots.sort((a, b) => b.date.compareTo(a.date));
    return snapshots;
  }

  /// Get list of available regions in a snapshot.
  ///
  /// Parses the HTML directory listing for .mwm files.
  /// Uses compute() to offload heavy parsing to an isolate.
  Future<List<MwmRegion>> getRegions(Mirror mirror, Snapshot snapshot) async {
    final uri = Uri.parse('${mirror.baseUrl}${snapshot.version}/');
    final response = await _client.get(uri);

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch regions: HTTP ${response.statusCode}');
    }

    // Offload heavy regex parsing to isolate to avoid blocking main thread
    return compute(_parseRegionsFromHtml, response.body);
  }

  /// Build the full download URL for a region.
  String getDownloadUrl(Mirror mirror, Snapshot snapshot, MwmRegion region) {
    return '${mirror.baseUrl}${snapshot.version}/${region.fileName}';
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
