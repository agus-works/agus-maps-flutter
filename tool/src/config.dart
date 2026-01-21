// Configuration parsing and constants for build system

import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

/// Build mode detection
enum BuildMode {
  consumer,   // Download SDK from releases
  contributor, // Build from source
}

/// Configuration constants
class BuildConfig {
  static const String defaultComapsTag = 'v2026.01.08-11';
  static const String flutterVersion = '3.38.7';
  static const String cmakeVersion = '4.2.1';
  static const String ndkVersion = '27.3.13750724';
  static const String buildType = 'Release';
  
  // Android configuration
  static const String androidMinSdk = '24';
  static const List<String> androidAbis = ['arm64-v8a', 'armeabi-v7a', 'x86_64'];
  
  // iOS configuration
  static const String iosDeploymentTarget = '15.6';
  
  // macOS configuration
  static const String macOSDeploymentTarget = '12.0';
}

/// Parse package version from pubspec.yaml
Future<String> getPackageVersion() async {
  final pubspecFile = File('pubspec.yaml');
  if (!await pubspecFile.exists()) {
    throw Exception('pubspec.yaml not found');
  }
  
  final content = await pubspecFile.readAsString();
  final doc = loadYaml(content) as Map;
  final version = doc['version'] as String?;
  
  if (version == null) {
    throw Exception('version not found in pubspec.yaml');
  }
  
  // Remove build number if present (e.g., "0.1.12+1" -> "0.1.12")
  return version.split('+').first;
}

/// Detect build mode
BuildMode detectBuildMode() {
  // Check environment variable
  final mode = Platform.environment['AGUS_MAPS_BUILD_MODE'];
  if (mode == 'consumer') return BuildMode.consumer;
  if (mode == 'contributor') return BuildMode.contributor;
  
  // Check if AGUS_MAPS_HOME is set (consumer workflow)
  if (Platform.environment.containsKey('AGUS_MAPS_HOME')) {
    return BuildMode.consumer;
  }
  
  // Check if we're in the plugin repo (contributor workflow)
  final pubspecFile = File('pubspec.yaml');
  final patchesDir = Directory('patches/comaps');
  if (pubspecFile.existsSync() && patchesDir.existsSync()) {
    return BuildMode.contributor;
  }
  
  // Default: consumer (most users)
  return BuildMode.consumer;
}

/// Get CoMaps tag from environment or use default
String getComapsTag() {
  return Platform.environment['COMAPS_TAG'] ?? BuildConfig.defaultComapsTag;
}
