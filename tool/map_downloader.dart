#!/usr/bin/env dart
/// Cross-platform MWM map file downloader for CoMaps CDN.
///
/// This tool discovers available mirrors, probes for the latest snapshot,
/// fetches region metadata, and downloads specified MWM files.
///
/// Usage:
///   dart run tool/map_downloader.dart [options]
///
/// Options:
///   --output-dir, -o   Output directory for downloaded files (default: example/assets/maps)
///   --files, -f        Comma-separated list of MWM files to download
///                      (default: World.mwm,WorldCoasts.mwm,Gibraltar.mwm)
///   --report, -r       Generate JSON report file (optional path, default: map_download_report.json)
///   --list-regions     List all available regions and exit
///   --list-mirrors     List all mirrors and their status
///   --snapshot, -s     Use specific snapshot version (default: auto-detect latest)
///   --mirror, -m       Use specific mirror URL (default: auto-select best)
///   --verbose, -v      Enable verbose output
///   --help, -h         Show this help message
///
/// Examples:
///   # Download default maps
///   dart run tool/map_downloader.dart
///
///   # Download specific maps
///   dart run tool/map_downloader.dart -f "World.mwm,Germany_Berlin.mwm" -o ./maps
///
///   # Generate report without downloading
///   dart run tool/map_downloader.dart --list-regions --report regions.json
///
///   # Check mirror status
///   dart run tool/map_downloader.dart --list-mirrors

import 'dart:convert';
import 'dart:io';
import 'package:args/args.dart';
import '../lib/src/mirror_utils.dart';

/// ANSI color codes for terminal output
class Colors {
  static bool enabled = stdout.hasTerminal;

  static String green(String s) => enabled ? '\x1B[32m$s\x1B[0m' : s;
  static String red(String s) => enabled ? '\x1B[31m$s\x1B[0m' : s;
  static String yellow(String s) => enabled ? '\x1B[33m$s\x1B[0m' : s;
  static String cyan(String s) => enabled ? '\x1B[36m$s\x1B[0m' : s;
  static String blue(String s) => enabled ? '\x1B[34m$s\x1B[0m' : s;
  static String bold(String s) => enabled ? '\x1B[1m$s\x1B[0m' : s;
  static String dim(String s) => enabled ? '\x1B[2m$s\x1B[0m' : s;
}

/// Progress bar for downloads
class ProgressBar {
  final int total;
  final int width;
  int _current = 0;
  int _lastPrintedPercent = -1;

  ProgressBar(this.total, {this.width = 40});

  void update(int current) {
    _current = current;
    final percent = total > 0 ? (_current * 100 ~/ total) : 0;

    // Only update display every 5%
    if (percent != _lastPrintedPercent && percent % 5 == 0) {
      _lastPrintedPercent = percent;
      _printBar(percent);
    }
  }

  void _printBar(int percent) {
    final filled = (width * percent ~/ 100);
    final empty = width - filled;
    final bar = '█' * filled + '░' * empty;
    final sizeStr = _formatSize(_current);
    final totalStr = total > 0 ? _formatSize(total) : '?';

    stdout.write('\r  [$bar] $percent% ($sizeStr / $totalStr)');
  }

  void complete() {
    _printBar(100);
    stdout.writeln();
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

/// Download report data structure
class DownloadReport {
  final DateTime timestamp;
  final MirrorStatus? selectedMirror;
  final Snapshot? snapshot;
  final CountriesData? countriesData;
  final List<DownloadResult> downloads;
  final Duration duration;

  DownloadReport({
    required this.timestamp,
    this.selectedMirror,
    this.snapshot,
    this.countriesData,
    required this.downloads,
    required this.duration,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'durationSeconds': duration.inSeconds,
    'mirror': selectedMirror?.toJson(),
    'snapshot': snapshot?.toJson(),
    'countriesMetadata': {
      'version': countriesData?.version,
      'totalRegions': countriesData?.allRegions.length,
      'totalSizeMB': countriesData != null
          ? (countriesData!.totalSizeBytes / (1024 * 1024)).toStringAsFixed(2)
          : null,
    },
    'downloads': downloads.map((d) => d.toJson()).toList(),
    'summary': {
      'total': downloads.length,
      'successful': downloads.where((d) => d.success).length,
      'failed': downloads.where((d) => !d.success).length,
      'totalDownloadedBytes': downloads.fold<int>(0, (sum, d) => sum + (d.bytesDownloaded ?? 0)),
    },
  };
}

/// Result of a single file download
class DownloadResult {
  final String fileName;
  final String url;
  final bool success;
  final bool cached;
  final int? bytesDownloaded;
  final Duration? duration;
  final String? error;
  final String? localPath;

  DownloadResult({
    required this.fileName,
    required this.url,
    required this.success,
    required this.cached,
    this.bytesDownloaded,
    this.duration,
    this.error,
    this.localPath,
  });

  Map<String, dynamic> toJson() => {
    'fileName': fileName,
    'url': url,
    'success': success,
    'cached': cached,
    'bytesDownloaded': bytesDownloaded,
    'sizeMB': bytesDownloaded != null
        ? (bytesDownloaded! / (1024 * 1024)).toStringAsFixed(2)
        : null,
    'durationMs': duration?.inMilliseconds,
    'localPath': localPath,
    if (error != null) 'error': error,
  };
}

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('output-dir',
        abbr: 'o',
        defaultsTo: 'example/assets/maps',
        help: 'Output directory for downloaded files')
    ..addOption('files',
        abbr: 'f',
        defaultsTo: 'World.mwm,WorldCoasts.mwm,Gibraltar.mwm',
        help: 'Comma-separated list of MWM files to download')
    ..addOption('report',
        abbr: 'r',
        help: 'Generate JSON report file (optional path)')
    ..addFlag('list-regions',
        negatable: false, help: 'List all available regions and exit')
    ..addFlag('list-mirrors',
        negatable: false, help: 'List all mirrors and their status')
    ..addOption('snapshot',
        abbr: 's', help: 'Use specific snapshot version (YYMMDD)')
    ..addOption('mirror', abbr: 'm', help: 'Use specific mirror URL')
    ..addFlag('verbose', abbr: 'v', negatable: false, help: 'Enable verbose output')
    ..addFlag('force', negatable: false, help: 'Force re-download even if file exists')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show help message');

  ArgResults options;
  try {
    options = parser.parse(args);
  } catch (e) {
    stderr.writeln('${Colors.red('Error:')} $e');
    stderr.writeln('Use --help for usage information.');
    exit(1);
  }

  if (options['help'] as bool) {
    printUsage(parser);
    exit(0);
  }

  final verbose = options['verbose'] as bool;
  final startTime = DateTime.now();

  print(Colors.bold('\n╔════════════════════════════════════════════════════════════╗'));
  print(Colors.bold('║         CoMaps MWM Map Downloader                          ║'));
  print(Colors.bold('╚════════════════════════════════════════════════════════════╝\n'));

  final service = MirrorService();

  try {
    // Handle list-mirrors mode
    if (options['list-mirrors'] as bool) {
      await listMirrors(service, verbose);
      exit(0);
    }

    // Find best mirror or use specified one
    print(Colors.cyan('🔍 Discovering mirrors...'));
    MirrorStatus? selectedMirror;
    String mirrorBaseUrl;
    String snapshot;

    if (options['mirror'] != null) {
      mirrorBaseUrl = options['mirror'] as String;
      if (!mirrorBaseUrl.endsWith('/')) mirrorBaseUrl += '/';
      print('  Using specified mirror: $mirrorBaseUrl');

      // Still need to find snapshot
      final candidates = MirrorService.generateCandidateVersions();
      if (options['snapshot'] != null) {
        snapshot = options['snapshot'] as String;
      } else {
        final mirror = MirrorConfig(name: 'Custom', baseUrl: mirrorBaseUrl);
        final found = await service.findLatestSnapshot(mirror, candidates);
        if (found == null) {
          stderr.writeln(Colors.red('Error: No valid snapshot found on mirror'));
          exit(1);
        }
        snapshot = found;
      }
    } else {
      selectedMirror = await service.getBestMirror();
      if (selectedMirror == null || !selectedMirror.isOperational) {
        stderr.writeln(Colors.red('Error: No operational mirrors found'));
        exit(1);
      }
      mirrorBaseUrl = selectedMirror.mirror.baseUrl;
      snapshot = options['snapshot'] as String? ?? selectedMirror.latestSnapshot!;
      print('  ${Colors.green('✓')} Selected: ${selectedMirror.mirror.name}');
      print('    URL: $mirrorBaseUrl');
      print('    Latency: ${selectedMirror.latencyMs}ms');
    }

    final snapshotObj = Snapshot(version: snapshot);
    print('  ${Colors.green('✓')} Snapshot: $snapshot (${snapshotObj.formattedDate})');

    // Fetch countries data
    print(Colors.cyan('\n📋 Fetching region metadata...'));
    final countriesData = await service.fetchCountriesData(mirrorBaseUrl, snapshot);
    if (countriesData != null) {
      print('  ${Colors.green('✓')} Found ${countriesData.allRegions.length} regions');
      print('  Total size: ${(countriesData.totalSizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB');
    } else {
      print('  ${Colors.yellow('⚠')} Could not fetch countries.txt');
    }

    // Handle list-regions mode
    if (options['list-regions'] as bool) {
      if (countriesData != null) {
        print(Colors.cyan('\n📄 Available regions:'));
        listRegions(countriesData);
      }

      // Generate report if requested
      final reportPath = options['report'] as String?;
      if (reportPath != null) {
        final report = DownloadReport(
          timestamp: startTime,
          selectedMirror: selectedMirror,
          snapshot: snapshotObj,
          countriesData: countriesData,
          downloads: [],
          duration: DateTime.now().difference(startTime),
        );
        await saveReport(report, reportPath, countriesData);
      }
      exit(0);
    }

    // Parse files to download
    final fileList = (options['files'] as String)
        .split(',')
        .map((f) => f.trim())
        .where((f) => f.isNotEmpty)
        .toList();

    print(Colors.cyan('\n📥 Downloading ${fileList.length} files...'));

    final outputDir = Directory(options['output-dir'] as String);
    await outputDir.create(recursive: true);
    print('  Output directory: ${outputDir.path}');

    final downloads = <DownloadResult>[];
    final forceDownload = options['force'] as bool;

    for (final fileName in fileList) {
      final url = MirrorService.buildDownloadUrl(mirrorBaseUrl, snapshot, fileName);
      final destFile = File('${outputDir.path}/$fileName');

      print('\n  ${Colors.blue('→')} $fileName');
      if (verbose) print('    URL: $url');

      if (!forceDownload && await destFile.exists()) {
        final cachedSize = await destFile.length();
        print('    ${Colors.green('✓')} Using cached file (${(cachedSize / (1024 * 1024)).toStringAsFixed(2)} MB)');
        downloads.add(DownloadResult(
          fileName: fileName,
          url: url,
          success: true,
          cached: true,
          bytesDownloaded: cachedSize,
          duration: Duration.zero,
          localPath: destFile.path,
        ));
        continue;
      }

      final downloadStart = DateTime.now();

      // Get file size first
      int? expectedSize;
      if (countriesData != null) {
        final regionId = fileName.replaceAll('.mwm', '');
        final region = countriesData.findRegion(regionId);
        expectedSize = region?.sizeBytes;
      }

      final progressBar = ProgressBar(expectedSize ?? 0);

      final success = await service.downloadFile(
        url,
        destFile,
        onProgress: (received, total) {
          progressBar.update(received);
        },
      );

      final downloadDuration = DateTime.now().difference(downloadStart);
      int? actualSize;

      if (success) {
        progressBar.complete();
        actualSize = await destFile.length();
        print('    ${Colors.green('✓')} Downloaded (${(actualSize / (1024 * 1024)).toStringAsFixed(2)} MB in ${downloadDuration.inSeconds}s)');
      } else {
        print('    ${Colors.red('✗')} Failed to download');
      }

      downloads.add(DownloadResult(
        fileName: fileName,
        url: url,
        success: success,
        cached: false,
        bytesDownloaded: actualSize,
        duration: downloadDuration,
        localPath: success ? destFile.path : null,
        error: success ? null : 'Download failed',
      ));
    }

    // Summary
    final successful = downloads.where((d) => d.success).length;
    final failed = downloads.where((d) => !d.success).length;

    print(Colors.cyan('\n📊 Summary:'));
    print('  ${Colors.green('✓')} Successful: $successful');
    if (failed > 0) {
      print('  ${Colors.red('✗')} Failed: $failed');
    }

    final totalBytes = downloads
      .where((d) => !d.cached)
      .fold<int>(0, (sum, d) => sum + (d.bytesDownloaded ?? 0));
    print('  Total downloaded: ${(totalBytes / (1024 * 1024)).toStringAsFixed(2)} MB');

    // Generate report if requested
    final reportPath = options['report'] as String?;
    if (reportPath != null || reportPath == '') {
      final actualPath = (reportPath?.isEmpty ?? true) ? 'map_download_report.json' : reportPath!;
      final report = DownloadReport(
        timestamp: startTime,
        selectedMirror: selectedMirror,
        snapshot: snapshotObj,
        countriesData: countriesData,
        downloads: downloads,
        duration: DateTime.now().difference(startTime),
      );
      await saveReport(report, actualPath, countriesData);
    }

    final endTime = DateTime.now();
    print(Colors.dim('\nCompleted in ${endTime.difference(startTime).inSeconds}s'));

    exit(failed > 0 ? 1 : 0);
  } finally {
    service.dispose();
  }
}

void printUsage(ArgParser parser) {
  print('''
${Colors.bold('CoMaps MWM Map Downloader')}

Cross-platform tool for downloading MWM map files from CoMaps CDN servers.

${Colors.cyan('Usage:')}
  dart run tool/map_downloader.dart [options]

${Colors.cyan('Options:')}
${parser.usage}

${Colors.cyan('Examples:')}
  # Download default base maps (World, WorldCoasts, Gibraltar)
  dart run tool/map_downloader.dart

  # Download specific maps to custom directory
  dart run tool/map_downloader.dart -f "World.mwm,Germany_Berlin.mwm" -o ./maps

  # List all available regions
  dart run tool/map_downloader.dart --list-regions

  # Generate JSON report with region metadata
  dart run tool/map_downloader.dart --list-regions --report regions.json

  # Check mirror status
  dart run tool/map_downloader.dart --list-mirrors

  # Use specific snapshot version
  dart run tool/map_downloader.dart --snapshot 260113

${Colors.cyan('Notes:')}
  - CoMaps CDN URL structure: <base>/maps/<snapshot>/<file>
  - Snapshot versions use YYMMDD format (e.g., 260113 = 2026-01-13)
  - The tool automatically discovers the latest available snapshot
''');
}

Future<void> listMirrors(MirrorService service, bool verbose) async {
  print(Colors.cyan('Checking mirrors...\n'));

  final candidateSnapshots = MirrorService.generateCandidateVersions();
  final metaserverUrls = await service.queryMetaserver();

  if (metaserverUrls.isNotEmpty) {
    print('${Colors.green('✓')} Metaserver returned ${metaserverUrls.length} servers');
    if (verbose) {
      for (final url in metaserverUrls) {
        print('    - $url');
      }
    }
    print('');
  }

  final results = <MirrorStatus>[];
  for (final mirror in service.mirrors) {
    final status = await service.checkMirror(mirror, candidateSnapshots);
    results.add(status);

    final icon = status.isOperational
        ? Colors.green('✓')
        : (status.isAccessible ? Colors.yellow('⚠') : Colors.red('✗'));

    print('$icon ${mirror.name}');
    print('  URL: ${mirror.baseUrl}');
    print('  Accessible: ${status.isAccessible ? 'Yes' : 'No'}');
    if (status.latencyMs != null) {
      print('  Latency: ${status.latencyMs}ms');
    }
    if (status.latestSnapshot != null) {
      final snap = Snapshot(version: status.latestSnapshot!);
      print('  Latest snapshot: ${status.latestSnapshot} (${snap.formattedDate})');
    }
    if (status.error != null) {
      print('  ${Colors.red('Error:')} ${status.error}');
    }
    print('');
  }

  final operational = results.where((r) => r.isOperational).length;
  print('${Colors.cyan('Summary:')} $operational/${results.length} mirrors operational');
}

void listRegions(CountriesData data) {
  final allRegions = data.allRegions;
  allRegions.sort((a, b) => a.id.compareTo(b.id));

  print('');
  print('  ${'ID'.padRight(45)} ${'Size'.padLeft(10)}');
  print('  ${'-' * 45} ${'-' * 10}');

  for (final region in allRegions) {
    print('  ${region.id.padRight(45)} ${region.sizeMB.padLeft(7)} MB');
  }

  print('');
  print('  Total: ${allRegions.length} regions');
}

Future<void> saveReport(DownloadReport report, String path, CountriesData? countriesData) async {
  final file = File(path);

  // Build comprehensive report with all regions if available
  final reportJson = report.toJson();
  if (countriesData != null) {
    reportJson['allRegions'] = countriesData.allRegions.map((r) => {
      'id': r.id,
      'fileName': r.fileName,
      'sizeBytes': r.sizeBytes,
      'sizeMB': r.sizeMB,
    }).toList();
  }

  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(reportJson),
  );

  print('\n${Colors.green('✓')} Report saved to: $path');
}
