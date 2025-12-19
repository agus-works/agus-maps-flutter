# IMPL-02: MWM Metadata Storage

## Overview

Track downloaded MWM files with metadata for version management and future updates.

## Data Model

### MwmMetadata

```dart
class MwmMetadata {
  /// Region/country name (e.g., "Gibraltar", "World")
  final String regionName;
  
  /// Snapshot version from mirror (e.g., "250608" for YYMMDD format)
  final String snapshotVersion;
  
  /// File size in bytes
  final int fileSize;
  
  /// When the file was downloaded
  final DateTime downloadDate;
  
  /// Full path to the MWM file on device
  final String filePath;
  
  /// SHA256 hash of the file (optional, for integrity checking)
  final String? sha256;
  
  /// Whether this is a bundled asset vs downloaded
  final bool isBundled;
}
```

### Storage Format

Use `shared_preferences` with JSON serialization:

```dart
// Key: 'mwm_metadata'
// Value: JSON array of MwmMetadata objects
[
  {
    "regionName": "Gibraltar",
    "snapshotVersion": "250608",
    "fileSize": 1234567,
    "downloadDate": "2025-06-08T12:00:00Z",
    "filePath": "/data/data/app.agus.maps.example/files/Gibraltar.mwm",
    "sha256": null,
    "isBundled": false
  },
  {
    "regionName": "World",
    "snapshotVersion": "bundled",
    "fileSize": 98765432,
    "downloadDate": "2025-06-01T00:00:00Z",
    "filePath": "/data/data/app.agus.maps.example/files/World.mwm",
    "sha256": null,
    "isBundled": true
  }
]
```

## Implementation

### File: `lib/mwm_storage.dart`

```dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class MwmMetadata {
  final String regionName;
  final String snapshotVersion;
  final int fileSize;
  final DateTime downloadDate;
  final String filePath;
  final String? sha256;
  final bool isBundled;
  
  const MwmMetadata({
    required this.regionName,
    required this.snapshotVersion,
    required this.fileSize,
    required this.downloadDate,
    required this.filePath,
    this.sha256,
    this.isBundled = false,
  });
  
  Map<String, dynamic> toJson() => {
    'regionName': regionName,
    'snapshotVersion': snapshotVersion,
    'fileSize': fileSize,
    'downloadDate': downloadDate.toIso8601String(),
    'filePath': filePath,
    'sha256': sha256,
    'isBundled': isBundled,
  };
  
  factory MwmMetadata.fromJson(Map<String, dynamic> json) => MwmMetadata(
    regionName: json['regionName'] as String,
    snapshotVersion: json['snapshotVersion'] as String,
    fileSize: json['fileSize'] as int,
    downloadDate: DateTime.parse(json['downloadDate'] as String),
    filePath: json['filePath'] as String,
    sha256: json['sha256'] as String?,
    isBundled: json['isBundled'] as bool? ?? false,
  );
}

class MwmStorage {
  static const String _key = 'mwm_metadata';
  
  final SharedPreferences _prefs;
  List<MwmMetadata> _cache = [];
  
  MwmStorage._(this._prefs);
  
  static Future<MwmStorage> create() async {
    final prefs = await SharedPreferences.getInstance();
    final storage = MwmStorage._(prefs);
    await storage._load();
    return storage;
  }
  
  Future<void> _load() async {
    final json = _prefs.getString(_key);
    if (json != null) {
      final list = jsonDecode(json) as List;
      _cache = list.map((e) => MwmMetadata.fromJson(e as Map<String, dynamic>)).toList();
    }
  }
  
  Future<void> _save() async {
    final json = jsonEncode(_cache.map((e) => e.toJson()).toList());
    await _prefs.setString(_key, json);
  }
  
  /// Get all stored metadata
  List<MwmMetadata> getAll() => List.unmodifiable(_cache);
  
  /// Get metadata for a specific region
  MwmMetadata? getByRegion(String regionName) {
    return _cache.cast<MwmMetadata?>().firstWhere(
      (m) => m?.regionName == regionName,
      orElse: () => null,
    );
  }
  
  /// Check if a region is downloaded
  bool isDownloaded(String regionName) {
    return _cache.any((m) => m.regionName == regionName);
  }
  
  /// Add or update metadata for a region
  Future<void> upsert(MwmMetadata metadata) async {
    _cache.removeWhere((m) => m.regionName == metadata.regionName);
    _cache.add(metadata);
    await _save();
  }
  
  /// Remove metadata for a region
  Future<void> remove(String regionName) async {
    _cache.removeWhere((m) => m.regionName == regionName);
    await _save();
  }
  
  /// Check if an update is available (compare snapshot versions)
  bool hasUpdate(String regionName, String latestSnapshotVersion) {
    final current = getByRegion(regionName);
    if (current == null) return false;
    if (current.isBundled) return false; // Don't suggest updates for bundled files
    return current.snapshotVersion != latestSnapshotVersion;
  }
}
```

## Usage

### Initialize at App Start

```dart
late MwmStorage _mwmStorage;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _mwmStorage = await MwmStorage.create();
  runApp(const MyApp());
}
```

### Record Bundled Assets

```dart
// After extracting bundled assets
await _mwmStorage.upsert(MwmMetadata(
  regionName: 'World',
  snapshotVersion: 'bundled',
  fileSize: worldFileSize,
  downloadDate: DateTime.now(),
  filePath: worldPath,
  isBundled: true,
));
```

### Record Downloaded MWMs

```dart
// After downloading from mirror
await _mwmStorage.upsert(MwmMetadata(
  regionName: 'Spain',
  snapshotVersion: '250608',
  fileSize: downloadedSize,
  downloadDate: DateTime.now(),
  filePath: downloadPath,
  isBundled: false,
));
```

### Check for Updates

```dart
final hasUpdate = _mwmStorage.hasUpdate('Spain', latestSnapshot);
if (hasUpdate) {
  // Show update icon in UI
}
```

## Dependencies

Add to `pubspec.yaml`:
```yaml
dependencies:
  shared_preferences: ^2.2.0
```

## Notes

- Metadata is stored separately from the MWM files themselves
- If an MWM file is deleted manually, metadata becomes stale (could add integrity check)
- Bundled assets marked with `isBundled: true` are excluded from update suggestions
- Future: Could add SHA256 verification for downloaded files
