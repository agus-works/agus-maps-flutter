#!/usr/bin/env dart
/// Mirror Availability Diagnostic Tool
///
/// This tool checks all configured CoMaps CDN servers for availability.
///
/// Usage:
///   dart run tool/check_mirrors.dart
///
/// What it does:
///   1. Queries the CoMaps metaserver for the active server list
///   2. Checks each mirror's base URL accessibility
///   3. Dynamically probes for the latest available snapshot
///   4. Attempts to download Gibraltar.mwm from each mirror
///   5. Reports status, latency, and any errors for each mirror
///
/// For programmatic access to mirror utilities, import:
///   import 'package:agus_maps_flutter/tool/src/mirror_utils.dart';

import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../lib/src/mirror_utils.dart';

export '../lib/src/mirror_utils.dart';

/// Result of checking a single mirror (extends MirrorStatus with download test)
class MirrorCheckResult {
  final MirrorConfig mirror;
  final bool baseUrlAccessible;
  final int? baseUrlLatencyMs;
  final String? latestSnapshot;
  final bool snapshotListSuccess;
  final bool gibraltarDownloadSuccess;
  final int? gibraltarSizeBytes;
  final int? gibraltarDownloadMs;
  final String? error;
  final bool isFromMetaserver;

  const MirrorCheckResult({
    required this.mirror,
    required this.baseUrlAccessible,
    this.baseUrlLatencyMs,
    this.latestSnapshot,
    required this.snapshotListSuccess,
    required this.gibraltarDownloadSuccess,
    this.gibraltarSizeBytes,
    this.gibraltarDownloadMs,
    this.error,
    this.isFromMetaserver = false,
  });

  bool get isFullyOperational =>
      baseUrlAccessible && snapshotListSuccess && gibraltarDownloadSuccess;

  String get statusEmoji {
    if (isFullyOperational) return '✅';
    if (baseUrlAccessible && snapshotListSuccess) return '⚠️';
    if (baseUrlAccessible) return '🔶';
    return '❌';
  }

  String get statusText {
    if (isFullyOperational) return 'OPERATIONAL';
    if (baseUrlAccessible && snapshotListSuccess) return 'PARTIAL (download failed)';
    if (baseUrlAccessible) return 'DEGRADED (no snapshots)';
    return 'DOWN';
  }

  Map<String, dynamic> toJson() => {
    'mirror': mirror.toJson(),
    'baseUrlAccessible': baseUrlAccessible,
    'baseUrlLatencyMs': baseUrlLatencyMs,
    'latestSnapshot': latestSnapshot,
    'snapshotListSuccess': snapshotListSuccess,
    'gibraltarDownloadSuccess': gibraltarDownloadSuccess,
    'gibraltarSizeBytes': gibraltarSizeBytes,
    'gibraltarDownloadMs': gibraltarDownloadMs,
    'error': error,
    'isFromMetaserver': isFromMetaserver,
    'isFullyOperational': isFullyOperational,
  };
}

/// HTTP client with reasonable timeouts
final http.Client _client = http.Client();

/// Check a single mirror's availability with full diagnostics
Future<MirrorCheckResult> checkMirrorWithDiagnostics(
  MirrorConfig mirror,
  List<String> candidateSnapshots, {
  bool isFromMetaserver = false,
}) async {
  print('  Checking ${mirror.name}...');
  if (isFromMetaserver) {
    print('    (Listed by metaserver)');
  }

  bool baseUrlAccessible = false;
  int? baseUrlLatencyMs;
  String? latestSnapshot;
  bool snapshotListSuccess = false;
  bool gibraltarDownloadSuccess = false;
  int? gibraltarSizeBytes;
  int? gibraltarDownloadMs;
  String? error;

  // Step 1: Check base URL accessibility
  try {
    final stopwatch = Stopwatch()..start();
    final response = await _client
        .head(Uri.parse(mirror.baseUrl))
        .timeout(const Duration(seconds: 10));
    stopwatch.stop();

    baseUrlAccessible = response.statusCode == 200 ||
        response.statusCode == 301 ||
        response.statusCode == 302;
    baseUrlLatencyMs = stopwatch.elapsedMilliseconds;
    print('    Base URL: ${baseUrlAccessible ? "OK" : "FAILED"} (${baseUrlLatencyMs}ms)');
  } catch (e) {
    error = 'Base URL check failed: $e';
    print('    Base URL: FAILED - $e');
    return MirrorCheckResult(
      mirror: mirror,
      baseUrlAccessible: false,
      snapshotListSuccess: false,
      gibraltarDownloadSuccess: false,
      error: error,
      isFromMetaserver: isFromMetaserver,
    );
  }

  // Step 2: Probe for latest snapshot dynamically
  print('    Snapshots: Probing for latest version...');
  latestSnapshot = await _findLatestSnapshot(mirror, candidateSnapshots);
  if (latestSnapshot != null) {
    snapshotListSuccess = true;
    print('    Snapshots: Found version $latestSnapshot');
  } else {
    error = 'No snapshots found in last 90 days';
    print('    Snapshots: FAILED - No snapshots found');
  }

  // Step 3: Try to download Gibraltar.mwm
  if (latestSnapshot != null) {
    final gibraltarUrl = MirrorService.buildDownloadUrl(mirror.baseUrl, latestSnapshot, 'Gibraltar.mwm');

    try {
      final headResponse = await _client
          .head(Uri.parse(gibraltarUrl))
          .timeout(const Duration(seconds: 10));

      if (headResponse.statusCode == 200) {
        gibraltarSizeBytes = int.tryParse(
          headResponse.headers['content-length'] ?? '',
        );

        final stopwatch = Stopwatch()..start();
        final request = http.Request('GET', Uri.parse(gibraltarUrl));
        request.headers['Range'] = 'bytes=0-1023';

        final streamedResponse = await _client.send(request).timeout(
          const Duration(seconds: 15),
        );

        if (streamedResponse.statusCode == 200 ||
            streamedResponse.statusCode == 206) {
          await streamedResponse.stream.drain();
          stopwatch.stop();
          gibraltarDownloadMs = stopwatch.elapsedMilliseconds;
          gibraltarDownloadSuccess = true;

          final sizeMb = gibraltarSizeBytes != null
              ? (gibraltarSizeBytes / (1024 * 1024)).toStringAsFixed(2)
              : '?';
          print(
            '    Gibraltar.mwm: OK ($sizeMb MB, partial download in ${gibraltarDownloadMs}ms)',
          );
        } else {
          error = 'Gibraltar download HTTP ${streamedResponse.statusCode}';
          print('    Gibraltar.mwm: FAILED - HTTP ${streamedResponse.statusCode}');
        }
      } else {
        error = 'Gibraltar HEAD HTTP ${headResponse.statusCode}';
        print('    Gibraltar.mwm: FAILED - HTTP ${headResponse.statusCode}');
      }
    } catch (e) {
      error = 'Gibraltar download failed: $e';
      print('    Gibraltar.mwm: FAILED - $e');
    }
  }

  return MirrorCheckResult(
    mirror: mirror,
    baseUrlAccessible: baseUrlAccessible,
    baseUrlLatencyMs: baseUrlLatencyMs,
    latestSnapshot: latestSnapshot,
    snapshotListSuccess: snapshotListSuccess,
    gibraltarDownloadSuccess: gibraltarDownloadSuccess,
    gibraltarSizeBytes: gibraltarSizeBytes,
    gibraltarDownloadMs: gibraltarDownloadMs,
    error: error,
    isFromMetaserver: isFromMetaserver,
  );
}

/// Find the latest available snapshot on a CoMaps server.
Future<String?> _findLatestSnapshot(MirrorConfig mirror, List<String> candidates) async {
  for (final snapshot in candidates) {
    // Try to fetch countries.txt which contains version info
    final countriesUrl = '${mirror.baseUrl}maps/$snapshot/countries.txt';
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

    // Fallback: try Gibraltar.mwm directly
    final gibraltarUrl = MirrorService.buildDownloadUrl(mirror.baseUrl, snapshot, 'Gibraltar.mwm');
    try {
      final response = await _client
          .head(Uri.parse(gibraltarUrl))
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

/// Query the CoMaps metaserver for active servers
Future<List<String>> _queryMetaserver() async {
  print('📡 Querying CoMaps metaserver...');
  print('   URL: $comapsMetaserverUrl');

  try {
    final response = await _client
        .get(Uri.parse(comapsMetaserverUrl))
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final List<dynamic> servers = jsonDecode(response.body);
      final serverList = servers.cast<String>();
      print('   Response: ${serverList.length} server(s) returned');
      for (final server in serverList) {
        print('     - $server');
      }
      return serverList;
    } else {
      print('   Error: HTTP ${response.statusCode}');
      return [];
    }
  } catch (e) {
    print('   Error: $e');
    return [];
  }
}

/// Print a formatted report of all results
void printReport(List<MirrorCheckResult> results, List<String> metaserverUrls) {
  print('');
  print('=' * 80);
  print('COMAPS CDN MIRROR AVAILABILITY REPORT');
  print('=' * 80);
  print('');

  // Metaserver info
  print('📡 COMAPS METASERVER');
  print('-' * 40);
  print('URL: $comapsMetaserverUrl');
  if (metaserverUrls.isNotEmpty) {
    print('Status: ✅ ONLINE');
    print('Active servers:');
    for (final url in metaserverUrls) {
      print('  - $url');
    }
  } else {
    print('Status: ❌ OFFLINE or empty response');
  }
  print('');

  // Summary counts
  final totalOperational = results.where((r) => r.isFullyOperational).length;

  print('📊 SUMMARY');
  print('-' * 40);
  print('Total mirrors checked: ${results.length}');
  print('Fully operational: $totalOperational / ${results.length}');
  print('');

  // CoMaps CDN section
  print('🗺️  COMAPS CDN SERVERS');
  print('-' * 40);
  print('URL pattern: <base>/maps/<version>/<file>');
  print('');
  for (final result in results) {
    _printMirrorResult(result);
  }
  print('');

  // Detailed error report
  final failedResults = results.where((r) => !r.isFullyOperational).toList();
  if (failedResults.isNotEmpty) {
    print('⚠️  ISSUES DETECTED');
    print('-' * 40);
    for (final result in failedResults) {
      print('${result.mirror.name}:');
      print('  Status: ${result.statusText}');
      if (result.error != null) {
        print('  Error: ${result.error}');
      }
      print('');
    }
  }

  // Recommendations
  print('📋 RECOMMENDATIONS');
  print('-' * 40);

  final operational = results
      .where((r) => r.isFullyOperational && r.baseUrlLatencyMs != null)
      .toList()
    ..sort((a, b) => a.baseUrlLatencyMs!.compareTo(b.baseUrlLatencyMs!));

  if (operational.isNotEmpty) {
    final best = operational.first;
    print('Best CoMaps CDN: ${best.mirror.name} (${best.baseUrlLatencyMs}ms latency)');
    print('  URL: ${best.mirror.baseUrl}');
    print('  Latest snapshot: ${best.latestSnapshot}');
    print('  Download URL pattern: ${best.mirror.baseUrl}maps/<version>/<file>');
    if (best.isFromMetaserver) {
      print('  📡 Listed by metaserver');
    }
  } else {
    print('❌ No CoMaps CDN servers with map data available!');
  }

  print('');
  print('=' * 80);
  print('ℹ️  NOTES');
  print('=' * 80);
  print('');
  print('Version discovery uses dynamic date probing (no hardcoded dates).');
  print('Snapshots are probed from today going back 90 days.');
  print('');
  print('CoMaps CDN servers provide MWM files with enhanced features:');
  print('  - Improved routing engine with conditional restrictions');
  print('  - More dense altitude contour lines');
  print('  - Additional POIs (EV charging, vending machines, etc.)');
  print('  - Enhanced map colors for light/dark modes');
  print('');
  print('The CoMaps metaserver at $comapsMetaserverUrl');
  print('returns the currently active download servers used by the CoMaps app.');
  print('');
  print('=' * 80);
}

void _printMirrorResult(MirrorCheckResult result) {
  final latency = result.baseUrlLatencyMs != null
      ? '${result.baseUrlLatencyMs}ms'
      : 'N/A';
  final snapshot = result.latestSnapshot ?? 'N/A';
  final size = result.gibraltarSizeBytes != null
      ? '${(result.gibraltarSizeBytes! / (1024 * 1024)).toStringAsFixed(2)} MB'
      : 'N/A';
  final metaTag = result.isFromMetaserver ? ' 📡' : '';

  print('${result.statusEmoji} ${result.mirror.name}$metaTag');
  print('   URL: ${result.mirror.baseUrl}');
  print('   Status: ${result.statusText}');
  print('   Latency: $latency | Snapshot: $snapshot | Gibraltar: $size');
  print('');
}

Future<void> main() async {
  print('');
  print('🔍 CoMaps CDN Mirror Availability Diagnostic Tool');
  print('=' * 50);
  print('');

  // Generate candidate snapshots dynamically from current date
  final candidateSnapshots = MirrorService.generateCandidateVersions();
  print('📅 Generated ${candidateSnapshots.length} candidate versions');
  print('   Range: ${candidateSnapshots.last} to ${candidateSnapshots.first}');
  print('');

  // Query the metaserver
  final metaserverUrls = await _queryMetaserver();
  print('');

  // Build mirror list using shared constants from mirror_utils
  final mirrors = <MirrorConfig>[];
  final metaserverSet = metaserverUrls.toSet();

  for (final mirror in defaultMirrors) {
    mirrors.add(mirror);
  }

  // Add any metaserver URLs not already in static list
  for (final url in metaserverUrls) {
    final normalizedUrl = url.endsWith('/') ? url : '$url/';
    final alreadyExists = mirrors.any((m) =>
        m.baseUrl == normalizedUrl ||
        m.baseUrl == url ||
        normalizedUrl.contains(m.baseUrl.replaceAll('https://', '').replaceAll('/', '')));

    if (!alreadyExists) {
      mirrors.add(MirrorConfig(
        name: 'CoMaps (from metaserver)',
        baseUrl: normalizedUrl,
      ));
    }
  }

  print('Checking ${mirrors.length} CoMaps CDN servers...');
  print('');

  final results = <MirrorCheckResult>[];

  for (final mirror in mirrors) {
    final isFromMetaserver = metaserverSet.any((url) =>
        mirror.baseUrl.contains(url.replaceAll('https://', '').replaceAll('/', '')) ||
        url.contains(mirror.baseUrl.replaceAll('https://', '').replaceAll('/', '')));

    final result = await checkMirrorWithDiagnostics(mirror, candidateSnapshots, isFromMetaserver: isFromMetaserver);
    results.add(result);
    print('');
  }

  _client.close();

  printReport(results, metaserverUrls);

  final operationalCount = results.where((r) => r.isFullyOperational).length;
  if (operationalCount == 0) {
    print('');
    print('❌ CRITICAL: No CoMaps CDN mirrors are operational!');
    exit(1);
  }
}
