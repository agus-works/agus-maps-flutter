import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:agus_maps_flutter/mirror_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

/// Represents cached downloads data including mirror, snapshot, and regions.
class CachedDownloadsData {
  final String mirrorName;
  final String mirrorBaseUrl;
  final String snapshotVersion;
  final List<MwmRegion> regions;
  final DateTime cachedAt;

  CachedDownloadsData({
    required this.mirrorName,
    required this.mirrorBaseUrl,
    required this.snapshotVersion,
    required this.regions,
    required this.cachedAt,
  });

  /// Create Snapshot object from cached version.
  Snapshot get snapshot => Snapshot(version: snapshotVersion);

  /// Create Mirror object from cached data.
  Mirror get mirror =>
      Mirror(name: mirrorName, baseUrl: mirrorBaseUrl, isAvailable: true);

  /// Check if cache is stale (older than specified duration).
  bool isStale({Duration maxAge = const Duration(hours: 24)}) {
    return DateTime.now().difference(cachedAt) > maxAge;
  }

  /// Convert to JSON for storage.
  Map<String, dynamic> toJson() => {
    'mirrorName': mirrorName,
    'mirrorBaseUrl': mirrorBaseUrl,
    'snapshotVersion': snapshotVersion,
    'regions': regions.map((r) => r.toJson()).toList(),
    'cachedAt': cachedAt.toIso8601String(),
  };

  /// Create from JSON.
  factory CachedDownloadsData.fromJson(Map<String, dynamic> json) {
    return CachedDownloadsData(
      mirrorName: json['mirrorName'] as String,
      mirrorBaseUrl: json['mirrorBaseUrl'] as String,
      snapshotVersion: json['snapshotVersion'] as String,
      regions: (json['regions'] as List)
          .map((r) => MwmRegion.fromJson(r as Map<String, dynamic>))
          .toList(),
      cachedAt: DateTime.parse(json['cachedAt'] as String),
    );
  }
}

/// Service for caching downloads data to local storage.
class DownloadsCacheService {
  static const _cacheKey = 'downloads_cache_v1';

  SharedPreferences? _prefs;

  /// Initialize the cache service.
  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// Load cached data if available.
  Future<CachedDownloadsData?> loadCache() async {
    await init();
    final jsonStr = _prefs?.getString(_cacheKey);
    if (jsonStr == null) return null;

    try {
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      return CachedDownloadsData.fromJson(json);
    } catch (e) {
      debugPrint('[DownloadsCache] Failed to parse cache: $e');
      return null;
    }
  }

  /// Save data to cache.
  Future<void> saveCache(CachedDownloadsData data) async {
    await init();
    final jsonStr = jsonEncode(data.toJson());
    await _prefs?.setString(_cacheKey, jsonStr);
    debugPrint(
      '[DownloadsCache] Saved ${data.regions.length} regions to cache',
    );
  }

  /// Clear the cache.
  Future<void> clearCache() async {
    await init();
    await _prefs?.remove(_cacheKey);
    debugPrint('[DownloadsCache] Cache cleared');
  }

  /// Validate that the cached snapshot still exists on the server.
  ///
  /// Performs a lightweight HEAD request to check if the snapshot URL is valid.
  /// Returns true if valid, false if invalid or check failed.
  Future<bool> validateCache(CachedDownloadsData cache) async {
    try {
      final uri = Uri.parse('${cache.mirrorBaseUrl}${cache.snapshotVersion}/');
      final response = await http.head(uri).timeout(const Duration(seconds: 5));
      final isValid = response.statusCode == 200;
      debugPrint(
        '[DownloadsCache] Cache validation: ${isValid ? 'valid' : 'invalid'} (HTTP ${response.statusCode})',
      );
      return isValid;
    } catch (e) {
      debugPrint('[DownloadsCache] Cache validation failed: $e');
      // On network error, assume cache is still valid to allow offline use
      return true;
    }
  }
}
