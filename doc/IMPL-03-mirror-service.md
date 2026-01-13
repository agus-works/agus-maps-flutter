# IMPL-03: Mirror Service for MWM Downloads

## Overview

Service to discover available MWM files from CoMaps CDN servers, probe for available snapshots, and measure latency for mirror selection.

## CoMaps CDN Servers

The official CoMaps CDN servers host MWM files with enhanced features:
- Improved routing engine with conditional restrictions
- More dense/detailed altitude contour lines
- Additional Points of Interest (EV charging stations, vending machines, etc.)
- Enhanced map colors for light/dark modes
- Better search functionality

| Server | URL | Notes |
|--------|-----|-------|
| **CoMaps MapGen Finland** | `https://mapgen-fi-1.comaps.app/` | Primary (listed by metaserver) |
| **CoMaps CDN US** | `https://cdn-us-2.comaps.tech/` | |
| **CoMaps CDN Germany** | `https://comaps.firewall-gateway.de/` | |

### Metaserver

The CoMaps metaserver at `https://cdn-us-1.comaps.app/servers` returns the currently active download servers used by the CoMaps app.

## URL Structure

CoMaps CDN uses the following URL pattern:

```
https://mapgen-fi-1.comaps.app/
└── maps/
    └── 260101/                         ← Snapshot folder (YYMMDD)
        ├── Afghanistan.mwm
        ├── Gibraltar.mwm
        ├── Spain.mwm
        └── ...
```

Direct download URL example:
```
https://mapgen-fi-1.comaps.app/maps/260101/Gibraltar.mwm
```

> **Note:** CoMaps CDN servers do not provide directory listings. The service probes known snapshot versions to discover available data.

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
  final String version;  // e.g., "260101"
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
class MirrorService {
  /// CoMaps CDN servers (official, verified working)
  static final List<Mirror> defaultMirrors = [
    Mirror(name: 'CoMaps MapGen Finland', baseUrl: 'https://mapgen-fi-1.comaps.app/'),
    Mirror(name: 'CoMaps CDN US', baseUrl: 'https://cdn-us-2.comaps.tech/'),
    Mirror(name: 'CoMaps CDN Germany', baseUrl: 'https://comaps.firewall-gateway.de/'),
  ];
  
  final http.Client _client;
  final List<Mirror> mirrors;
  
  MirrorService({http.Client? client, List<Mirror>? customMirrors})
      : _client = client ?? http.Client(),
        mirrors = customMirrors ?? List.from(defaultMirrors);
  
  /// Generate candidate snapshot versions dynamically based on current date.
  /// No hardcoded dates - versions are calculated from today going back 60 days.
  static List<String> _generateCandidateVersions({int daysToProbe = 60}) {
    final candidates = <String>[];
    final now = DateTime.now();

    for (int daysBack = 0; daysBack <= daysToProbe; daysBack++) {
      final date = now.subtract(Duration(days: daysBack));
      final yy = (date.year % 100).toString().padLeft(2, '0');
      final mm = date.month.toString().padLeft(2, '0');
      final dd = date.day.toString().padLeft(2, '0');
      candidates.add('$yy$mm$dd');
    }

    return candidates;
  }
  
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
  
  /// Get list of available snapshots from a mirror.
  /// Uses dynamic date generation - no hardcoded dates.
  Future<List<Snapshot>> getSnapshots(Mirror mirror) async {
    final snapshots = <Snapshot>[];
    final candidates = _generateCandidateVersions();
    
    for (final version in candidates) {
      final testUrl = '${mirror.baseUrl}maps/$version/countries.txt';
      try {
        final response = await _client.head(Uri.parse(testUrl))
            .timeout(const Duration(seconds: 3));
        if (response.statusCode == 200) {
          snapshots.add(Snapshot(version: version));
          break; // Found latest, stop probing
        }
      } catch (e) {
        // Skip unavailable snapshots
      }
    }
    
    // Sort by date, newest first
    snapshots.sort((a, b) => b.date.compareTo(a.date));
    return snapshots;
  }
  
  /// Build download URL for a region
  /// URL pattern: <base>/maps/<version>/<file>
  String getDownloadUrl(Mirror mirror, Snapshot snapshot, MwmRegion region) {
    return '${mirror.baseUrl}maps/${snapshot.version}/${region.fileName}';
  }
  
  /// Get file size via HEAD request
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

// 3. Get available snapshots (probes known versions)
final snapshots = await mirrorService.getSnapshots(activeMirror);
print('Latest snapshot: ${snapshots.first.version}');

// 4. Get download URL
final gibraltarRegion = MwmRegion(name: 'Gibraltar', fileName: 'Gibraltar.mwm');
final url = mirrorService.getDownloadUrl(activeMirror, snapshots.first, gibraltarRegion);
print('Download URL: $url');
// Output: https://mapgen-fi-1.comaps.app/maps/260101/Gibraltar.mwm
```

## Diagnostic Tool

Run the mirror availability diagnostic tool:

```bash
dart run tool/check_mirrors.dart
```

This tool:
1. Queries the CoMaps metaserver
2. Tests each CoMaps CDN server for availability
3. Probes known snapshot versions
4. Attempts to download Gibraltar.mwm from each server
5. Reports status, latency, and any errors

## Dependencies

Add to `pubspec.yaml`:
```yaml
dependencies:
  http: ^1.1.0
```

## Error Handling

- Network timeouts: 10 seconds for latency checks, 5 seconds for snapshot probing
- Parse errors: Skip invalid entries, don't fail entire operation
- Unavailable mirrors: Mark as unavailable, don't throw

## Notes

- CoMaps CDN servers do not provide directory listings
- Snapshot discovery requires probing known versions
- File sizes can be obtained via HEAD requests
- Consider caching snapshot lists to reduce network requests
- Future: Add retry logic with exponential backoff
