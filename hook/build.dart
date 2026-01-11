// Hook entry point for Dart build system
// This hook runs during flutter pub get / flutter build to handle SDK download

import 'dart:io';
import 'package:hooks/hooks.dart';
import 'package:path/path.dart' as path;

// Import build utilities
import '../tool/src/config.dart' show detectBuildMode, BuildMode, getPackageVersion;
import '../tool/src/sdk_downloader.dart' show downloadSDK;

void main(List<String> args) async {
  await build(args, (input, output) async {
    // Detect build mode (consumer vs contributor)
    final buildMode = detectBuildMode();
    
    if (buildMode == BuildMode.consumer) {
      // Consumer workflow: Download SDK from GitHub Releases
      try {
        final version = await getPackageVersion();
        print('[Agus Maps] Consumer mode: Downloading SDK v$version...');
        
        await downloadSDK(version);
        
        print('[Agus Maps] SDK download complete!');
      } catch (e) {
        // Don't fail the build if SDK download fails
        // User can still use AGUS_MAPS_HOME environment variable
        print('[Agus Maps] Warning: SDK download failed: $e');
        print('[Agus Maps] You can set AGUS_MAPS_HOME environment variable to use a local SDK');
      }
    } else {
      // Contributor workflow: Build from source
      // For contributors, we don't use the hook - they should use tool/build.dart instead
      // The hook will just skip in this case
      print('[Agus Maps] Contributor mode detected. Use "dart run tool/build.dart" to build from source.');
    }
  });
}
