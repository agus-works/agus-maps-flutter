import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Normalize file path separators for the current platform.
/// On Windows, converts forward slashes to backslashes.
/// On other platforms, converts backslashes to forward slashes.
String _normalizePath(String path) {
  if (Platform.isWindows) {
    return path.replaceAll('/', '\\');
  } else {
    return path.replaceAll('\\', '/');
  }
}

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

  /// Full path to the MWM file on device (normalized for platform)
  final String filePath;

  /// SHA256 hash of the file (optional, for integrity checking)
  final String? sha256;

  /// Whether this is a bundled asset vs downloaded from mirror
  final bool isBundled;

  /// Creates MwmMetadata with normalized file path.
  MwmMetadata({
    required this.regionName,
    required this.snapshotVersion,
    required this.fileSize,
    required this.downloadDate,
    required String filePath,
    this.sha256,
    this.isBundled = false,
  }) : filePath = _normalizePath(filePath);

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
    filePath: json['filePath'] as String,  // Will be normalized in constructor
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
    if (current.isBundled)
      return false; // Don't suggest updates for bundled files
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

  /// Check if a specific region's MWM file actually exists on disk.
  ///
  /// This performs an async file existence check to verify the cached
  /// metadata matches reality. Useful after app reinstalls where
  /// SharedPreferences may persist but files are deleted.
  Future<bool> fileExists(String regionName) async {
    final metadata = getByRegion(regionName);
    if (metadata == null) return false;
    return File(metadata.filePath).exists();
  }

  /// Validate that a region's file exists and optionally check its size.
  ///
  /// Returns a [FileValidationResult] with details about the file state.
  Future<FileValidationResult> validateFile(String regionName) async {
    final metadata = getByRegion(regionName);
    if (metadata == null) {
      return FileValidationResult(
        regionName: regionName,
        exists: false,
        hasMetadata: false,
      );
    }

    final file = File(metadata.filePath);
    final exists = await file.exists();

    if (!exists) {
      return FileValidationResult(
        regionName: regionName,
        exists: false,
        hasMetadata: true,
        expectedPath: metadata.filePath,
      );
    }

    final actualSize = await file.length();
    final sizeMatches = actualSize == metadata.fileSize;

    return FileValidationResult(
      regionName: regionName,
      exists: true,
      hasMetadata: true,
      expectedPath: metadata.filePath,
      actualSize: actualSize,
      expectedSize: metadata.fileSize,
      sizeMatches: sizeMatches,
    );
  }

  /// Validate all stored metadata against actual files on disk.
  ///
  /// Runs validation checks in parallel using [Isolate.run] for large
  /// collections to avoid blocking the UI thread.
  ///
  /// Returns a list of [FileValidationResult] for each stored region.
  /// Use [pruneOrphaned] parameter to automatically remove metadata
  /// for files that no longer exist.
  Future<List<FileValidationResult>> validateAll({
    bool pruneOrphaned = false,
    void Function(int current, int total)? onProgress,
  }) async {
    final regions = List<MwmMetadata>.from(_cache);
    final results = <FileValidationResult>[];
    final orphanedRegions = <String>[];

    for (var i = 0; i < regions.length; i++) {
      final metadata = regions[i];
      final result = await validateFile(metadata.regionName);
      results.add(result);

      if (!result.exists && result.hasMetadata) {
        orphanedRegions.add(metadata.regionName);
      }

      onProgress?.call(i + 1, regions.length);
    }

    // Prune orphaned metadata if requested
    if (pruneOrphaned && orphanedRegions.isNotEmpty) {
      for (final region in orphanedRegions) {
        await remove(region);
        debugPrint('[MwmStorage] Pruned orphaned metadata for: $region');
      }
    }

    return results;
  }

  /// Stream-based validation for reactive UI updates.
  ///
  /// Yields [FileValidationResult] one at a time, allowing the UI to
  /// update progressively as each file is checked.
  Stream<FileValidationResult> validateAllStream() async* {
    for (final metadata in _cache) {
      yield await validateFile(metadata.regionName);
    }
  }

  /// Check if metadata is orphaned (file doesn't exist on disk).
  ///
  /// Quick check useful for determining if storage needs cleanup.
  Future<bool> hasOrphanedMetadata() async {
    for (final metadata in _cache) {
      if (!await File(metadata.filePath).exists()) {
        return true;
      }
    }
    return false;
  }

  /// Get list of regions with orphaned metadata (missing files).
  Future<List<String>> getOrphanedRegions() async {
    final orphaned = <String>[];
    for (final metadata in _cache) {
      if (!await File(metadata.filePath).exists()) {
        orphaned.add(metadata.regionName);
      }
    }
    return orphaned;
  }

  /// Remove all metadata for files that no longer exist.
  ///
  /// Returns the list of region names that were pruned.
  Future<List<String>> pruneOrphaned() async {
    final orphaned = await getOrphanedRegions();
    for (final region in orphaned) {
      await remove(region);
      debugPrint('[MwmStorage] Pruned orphaned metadata for: $region');
    }
    return orphaned;
  }
}

/// Result of validating a single MWM file against its metadata.
class FileValidationResult {
  /// Region name being validated.
  final String regionName;

  /// Whether the file exists on disk.
  final bool exists;

  /// Whether metadata exists in storage.
  final bool hasMetadata;

  /// Expected file path from metadata.
  final String? expectedPath;

  /// Actual file size on disk (if file exists).
  final int? actualSize;

  /// Expected file size from metadata.
  final int? expectedSize;

  /// Whether actual size matches expected (null if file doesn't exist).
  final bool? sizeMatches;

  const FileValidationResult({
    required this.regionName,
    required this.exists,
    required this.hasMetadata,
    this.expectedPath,
    this.actualSize,
    this.expectedSize,
    this.sizeMatches,
  });

  /// True if the file is valid (exists and size matches).
  bool get isValid => exists && (sizeMatches ?? false);

  /// True if metadata exists but file is missing (orphaned).
  bool get isOrphaned => hasMetadata && !exists;

  /// True if file exists but size doesn't match (possibly corrupted).
  bool get isSizeMismatch => exists && !(sizeMatches ?? true);

  @override
  String toString() {
    if (!hasMetadata) return 'FileValidationResult($regionName: no metadata)';
    if (!exists) return 'FileValidationResult($regionName: MISSING)';
    if (!isValid) {
      return 'FileValidationResult($regionName: size mismatch '
          '$actualSize != $expectedSize)';
    }
    return 'FileValidationResult($regionName: valid)';
  }
}
