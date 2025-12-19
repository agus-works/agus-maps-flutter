import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Metadata for a downloaded or bundled MWM map file.
class MwmMetadata {
  /// Region/country name (e.g., "Gibraltar", "World")
  final String regionName;

  /// Snapshot version from mirror (e.g., "250608" for YYMMDD format)
  /// Use "bundled" for assets included in the app
  final String snapshotVersion;

  /// File size in bytes
  final int fileSize;

  /// When the file was downloaded/extracted
  final DateTime downloadDate;

  /// Full path to the MWM file on device
  final String filePath;

  /// SHA256 hash of the file (optional, for integrity checking)
  final String? sha256;

  /// Whether this is a bundled asset vs downloaded from mirror
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

  @override
  String toString() =>
      'MwmMetadata(region=$regionName, version=$snapshotVersion, size=$fileSize, bundled=$isBundled)';
}

/// Storage service for MWM file metadata.
/// 
/// Tracks downloaded regions with version information for update detection.
class MwmStorage {
  static const String _key = 'mwm_metadata';

  final SharedPreferences _prefs;
  List<MwmMetadata> _cache = [];

  MwmStorage._(this._prefs);

  /// Create and initialize the storage service.
  static Future<MwmStorage> create() async {
    final prefs = await SharedPreferences.getInstance();
    final storage = MwmStorage._(prefs);
    await storage._load();
    return storage;
  }

  Future<void> _load() async {
    final json = _prefs.getString(_key);
    if (json != null) {
      try {
        final list = jsonDecode(json) as List;
        _cache = list
            .map((e) => MwmMetadata.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (e) {
        // If parsing fails, start fresh
        _cache = [];
      }
    }
  }

  Future<void> _save() async {
    final json = jsonEncode(_cache.map((e) => e.toJson()).toList());
    await _prefs.setString(_key, json);
  }

  /// Get all stored metadata.
  List<MwmMetadata> getAll() => List.unmodifiable(_cache);

  /// Get metadata for a specific region.
  MwmMetadata? getByRegion(String regionName) {
    for (final m in _cache) {
      if (m.regionName == regionName) return m;
    }
    return null;
  }

  /// Check if a region is downloaded.
  bool isDownloaded(String regionName) {
    return _cache.any((m) => m.regionName == regionName);
  }

  /// Add or update metadata for a region.
  /// 
  /// If the region already exists, it will be replaced.
  Future<void> upsert(MwmMetadata metadata) async {
    _cache.removeWhere((m) => m.regionName == metadata.regionName);
    _cache.add(metadata);
    await _save();
  }

  /// Remove metadata for a region.
  Future<void> remove(String regionName) async {
    _cache.removeWhere((m) => m.regionName == regionName);
    await _save();
  }

  /// Clear all metadata.
  Future<void> clear() async {
    _cache.clear();
    await _prefs.remove(_key);
  }

  /// Check if an update is available for a region.
  /// 
  /// Compares the stored snapshot version with the latest available version.
  /// Returns false for bundled files (they don't get updated).
  bool hasUpdate(String regionName, String latestSnapshotVersion) {
    final current = getByRegion(regionName);
    if (current == null) return false;
    if (current.isBundled) return false; // Don't suggest updates for bundled files
    return current.snapshotVersion != latestSnapshotVersion;
  }

  /// Get total size of all downloaded maps in bytes.
  int get totalDownloadedSize {
    return _cache.fold(0, (sum, m) => sum + m.fileSize);
  }

  /// Get count of downloaded maps (excluding bundled).
  int get downloadedCount {
    return _cache.where((m) => !m.isBundled).length;
  }

  /// Get count of bundled maps.
  int get bundledCount {
    return _cache.where((m) => m.isBundled).length;
  }
}
