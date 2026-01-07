# IMPL-03: Mirror Service for MWM Downloads

## Overview

Service to discover available MWM files from mirror sites, parse directory listings, and measure latency for mirror selection.

## Mirror Sites

- **Primary**: `https://omaps.wfr.software/maps/`
- **Secondary**: `https://omaps.webfreak.org/maps/`

## URL Structure

```
https://omaps.wfr.software/maps/
├── 250608/                         ← Snapshot folder (YYMMDD)
│   ├── Afghanistan.mwm
│   ├── Gibraltar.mwm
│   ├── Spain.mwm
│   └── ...
├── 250601/                         ← Older snapshot
│   └── ...
└── ...
```

Direct download URL example:
```
https://omaps.wfr.software/maps/250608/Gibraltar.mwm
```

## Data Models

### Mirror

```dart
class Mirror {
  final String name;
  final String baseUrl;
  int? latencyMs;  // null = not tested
  bool isAvailable;
  
  Mirror({
    required this.name,
    required this.baseUrl,
    this.latencyMs,
    this.isAvailable = true,
  });
}
```

### Snapshot

```dart
class Snapshot {
  final String version;  // e.g., "250608"
  final DateTime date;   // Parsed from version
  
  Snapshot({required this.version})
      : date = _parseDate(version);
  
  static DateTime _parseDate(String v) {
    // Parse YYMMDD format
    final year = 2000 + int.parse(v.substring(0, 2));
    final month = int.parse(v.substring(2, 4));
    final day = int.parse(v.substring(4, 6));
    return DateTime(year, month, day);
  }
}
```

### MwmRegion

```dart
class MwmRegion {
  final String name;       // e.g., "Gibraltar"
  final String fileName;   // e.g., "Gibraltar.mwm"
  final int? sizeBytes;    // File size if available
  
  MwmRegion({
    required this.name,
    required this.fileName,
    this.sizeBytes,
  });
}
```

## Implementation

### File: `lib/mirror_service.dart`

```dart
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

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
}

class Snapshot {
  final String version;
  final DateTime date;
  
  Snapshot({required this.version})
      : date = _parseDate(version);
  
  static DateTime _parseDate(String v) {
    if (v.length != 6) throw FormatException('Invalid snapshot version: $v');
    final year = 2000 + int.parse(v.substring(0, 2));
    final month = int.parse(v.substring(2, 4));
    final day = int.parse(v.substring(4, 6));
    return DateTime(year, month, day);
  }
}

class MwmRegion {
  final String name;
  final String fileName;
  final int? sizeBytes;
  
  MwmRegion({
    required this.name,
    required this.fileName,
    this.sizeBytes,
  });
}

class MirrorService {
  static const List<Mirror> defaultMirrors = [
    Mirror(name: 'WFR Software', baseUrl: 'https://omaps.wfr.software/maps/'),
    Mirror(name: 'WebFreak', baseUrl: 'https://omaps.webfreak.org/maps/'),
  ];
  
  final http.Client _client;
  final List<Mirror> mirrors;
  
  MirrorService({http.Client? client, List<Mirror>? customMirrors})
      : _client = client ?? http.Client(),
        mirrors = customMirrors ?? List.from(defaultMirrors);
  
  /// Measure latency to each mirror (HEAD request to base URL)
  Future<void> measureLatencies() async {
    await Future.wait(mirrors.map((m) async {
      try {
        final stopwatch = Stopwatch()..start();
        final response = await _client.head(Uri.parse(m.baseUrl))
            .timeout(const Duration(seconds: 10));
        stopwatch.stop();
        
        m.latencyMs = stopwatch.elapsedMilliseconds;
        m.isAvailable = response.statusCode == 200;
      } catch (e) {
        m.latencyMs = null;
        m.isAvailable = false;
      }
    }));
  }
  
  /// Get list of available snapshots from a mirror
  Future<List<Snapshot>> getSnapshots(Mirror mirror) async {
    final uri = Uri.parse(mirror.baseUrl);
    final response = await _client.get(uri);
    
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch snapshots: ${response.statusCode}');
    }
    
    // Parse HTML directory listing
    // Most servers return Apache-style directory listing
    final snapshots = <Snapshot>[];
    final regex = RegExp(r'href="(\d{6})/"');
    
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
  
  /// Get list of available regions in a snapshot
  Future<List<MwmRegion>> getRegions(Mirror mirror, Snapshot snapshot) async {
    final uri = Uri.parse('${mirror.baseUrl}${snapshot.version}/');
    final response = await _client.get(uri);
    
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch regions: ${response.statusCode}');
    }
    
    // Parse HTML directory listing for .mwm files
    final regions = <MwmRegion>[];
    
    // Pattern: href="Gibraltar.mwm" or href="Gibraltar.mwm">Gibraltar.mwm</a> 123M
    final regex = RegExp(r'href="([^"]+\.mwm)"');
    
    for (final match in regex.allMatches(response.body)) {
      final fileName = match.group(1)!;
      final name = fileName.replaceAll('.mwm', '');
      
      // Try to extract size from the listing (varies by server)
      int? size;
      final sizeMatch = RegExp('$fileName[^0-9]*([0-9.]+)([KMG])')
          .firstMatch(response.body);
      if (sizeMatch != null) {
        final num = double.parse(sizeMatch.group(1)!);
        final unit = sizeMatch.group(2)!;
        size = switch (unit) {
          'K' => (num * 1024).toInt(),
          'M' => (num * 1024 * 1024).toInt(),
          'G' => (num * 1024 * 1024 * 1024).toInt(),
          _ => null,
        };
      }
      
      regions.add(MwmRegion(name: name, fileName: fileName, sizeBytes: size));
    }
    
    // Sort alphabetically
    regions.sort((a, b) => a.name.compareTo(b.name));
    return regions;
  }
  
  /// Build download URL for a region
  String getDownloadUrl(Mirror mirror, Snapshot snapshot, MwmRegion region) {
    return '${mirror.baseUrl}${snapshot.version}/${region.fileName}';
  }
  
  /// Get file size via HEAD request (if not available from listing)
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
```

## Usage

```dart
final mirrorService = MirrorService();

// 1. Measure latencies for UI display
await mirrorService.measureLatencies();
for (final mirror in mirrorService.mirrors) {
  print('${mirror.name}: ${mirror.latencyMs}ms, available=${mirror.isAvailable}');
}

// 2. Select fastest available mirror
final activeMirror = mirrorService.mirrors
    .where((m) => m.isAvailable)
    .reduce((a, b) => (a.latencyMs ?? 999999) < (b.latencyMs ?? 999999) ? a : b);

// 3. Get available snapshots
final snapshots = await mirrorService.getSnapshots(activeMirror);
print('Latest snapshot: ${snapshots.first.version}');

// 4. Get regions in snapshot
final regions = await mirrorService.getRegions(activeMirror, snapshots.first);
print('Available regions: ${regions.length}');

// 5. Get download URL
final gibraltarRegion = regions.firstWhere((r) => r.name == 'Gibraltar');
final url = mirrorService.getDownloadUrl(activeMirror, snapshots.first, gibraltarRegion);
print('Download URL: $url');
```

## Dependencies

Add to `pubspec.yaml`:
```yaml
dependencies:
  http: ^1.1.0
```

## Error Handling

- Network timeouts: 10 seconds for latency checks
- Parse errors: Skip invalid entries, don't fail entire operation
- Unavailable mirrors: Mark as unavailable, don't throw

## Notes

- Directory listing format may vary between servers (Apache vs nginx)
- File sizes from listings are approximate (may need HEAD request for exact)
- Consider caching snapshot/region lists to reduce network requests
- Future: Add retry logic with exponential backoff
