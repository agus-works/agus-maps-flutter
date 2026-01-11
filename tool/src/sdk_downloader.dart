// SDK download logic for consumer workflow

import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'archive_manager.dart' show extractZip;
import 'file_operations.dart' show ensureDir, copyPath, pathExists;
import 'platform_detector.dart' show getRepoRoot;
import 'config.dart' show getPackageVersion;

/// Download SDK from GitHub Releases
Future<void> downloadSDK(String version) async {
  final repoRoot = getRepoRoot();
  final sdkUrl = 'https://github.com/agus-works/agus-maps-flutter/releases/download/v$version/agus-maps-sdk-v$version.zip';
  final cacheDir = path.join(repoRoot, '.dart_tool', 'agus-maps-sdk');
  final cacheFile = path.join(cacheDir, 'agus-maps-sdk-v$version.zip');
  final extractDir = path.join(cacheDir, 'extracted');
  
  print('Downloading SDK v$version from GitHub Releases...');
  print('URL: $sdkUrl');
  
  // Check cache first
  if (await File(cacheFile).exists()) {
    print('Using cached SDK: $cacheFile');
  } else {
    // Download SDK
    await ensureDir(cacheDir);
    print('Downloading...');
    
    final response = await http.get(Uri.parse(sdkUrl));
    if (response.statusCode != 200) {
      throw Exception('Failed to download SDK: HTTP ${response.statusCode}');
    }
    
    await File(cacheFile).writeAsBytes(response.bodyBytes);
    print('Downloaded SDK: ${(response.bodyBytes.length / 1024 / 1024).toStringAsFixed(2)} MB');
  }
  
  // Extract SDK
  print('Extracting SDK...');
  await ensureDir(extractDir);
  await extractZip(cacheFile, extractDir);
  
  // Copy extracted files to plugin directories
  print('Installing SDK to plugin directories...');
  await _installSDK(extractDir, repoRoot);
  
  print('SDK installation complete!');
}

/// Install SDK files to plugin directories
Future<void> _installSDK(String extractDir, String repoRoot) async {
  // Android binaries
  final androidSrc = path.join(extractDir, 'android', 'prebuilt');
  final androidDest = path.join(repoRoot, 'android', 'prebuilt');
  if (await Directory(androidSrc).exists()) {
    await ensureDir(androidDest);
    await copyPath(androidSrc, androidDest);
    print('  Installed Android binaries');
  }
  
  // iOS framework
  final iosSrc = path.join(extractDir, 'ios', 'Frameworks');
  final iosDest = path.join(repoRoot, 'ios', 'Frameworks');
  if (await Directory(iosSrc).exists()) {
    await ensureDir(iosDest);
    await copyPath(iosSrc, iosDest);
    print('  Installed iOS framework');
  }
  
  // macOS framework
  final macosSrc = path.join(extractDir, 'macos', 'Frameworks');
  final macosDest = path.join(repoRoot, 'macos', 'Frameworks');
  if (await Directory(macosSrc).exists()) {
    await ensureDir(macosDest);
    await copyPath(macosSrc, macosDest);
    print('  Installed macOS framework');
  }
  
  // Windows binaries
  final windowsSrc = path.join(extractDir, 'windows', 'prebuilt');
  final windowsDest = path.join(repoRoot, 'windows', 'prebuilt');
  if (await Directory(windowsSrc).exists()) {
    await ensureDir(windowsDest);
    await copyPath(windowsSrc, windowsDest);
    print('  Installed Windows binaries');
  }
  
  // Linux binaries
  final linuxSrc = path.join(extractDir, 'linux', 'prebuilt');
  final linuxDest = path.join(repoRoot, 'linux', 'prebuilt');
  if (await Directory(linuxSrc).exists()) {
    await ensureDir(linuxDest);
    await copyPath(linuxSrc, linuxDest);
    print('  Installed Linux binaries');
  }
  
  // Assets (optional - typically copied to app)
  final assetsSrc = path.join(extractDir, 'assets');
  if (await Directory(assetsSrc).exists()) {
    // Assets are typically copied to the app, not the plugin
    // But we can note they're available
    print('  Assets available in SDK (copy to your app)');
  }
}
