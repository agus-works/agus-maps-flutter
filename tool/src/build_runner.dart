// Build orchestration - coordinates all build steps

import 'dart:io';
import 'package:path/path.dart' as path;
import 'config.dart' show BuildConfig, BuildMode, getComapsTag;
import 'platform_detector.dart' show getRepoRoot, getComapsDir, getBuildDir, detectOS, OSType;
import 'git_operations.dart' show cloneComaps, checkoutComapsTag, initSubmodules;
import 'patch_applicator.dart' show applyPatches;
import 'file_operations.dart' show ensureDir, copyPath;
import 'process_runner.dart' show runProcess, commandExists;
import 'cmake_build.dart' show buildAndroidAbi, buildiOSXCFramework, buildMacOSXCFramework, buildWindowsLibrary, buildLinuxLibrary;

/// Build runner configuration
class BuildRunnerConfig {
  final BuildMode mode;
  final List<String>? platforms;
  final bool buildBinaries;
  final bool skipPatches;
  final bool noCache;

  BuildRunnerConfig({
    required this.mode,
    this.platforms,
    this.buildBinaries = false,
    this.skipPatches = false,
    this.noCache = false,
  });
}

/// Main build runner entry point
Future<void> runBuild(BuildRunnerConfig config) async {
  print('=== Agus Maps Flutter Build Runner ===');
  print('Mode: ${config.mode}');
  final repoRoot = getRepoRoot();
  print('Repository: $repoRoot');
  print('');

  if (config.mode == BuildMode.contributor) {
    await _runContributorBuild(config);
  } else {
    print('Consumer mode: SDK should be downloaded via hook/build.dart');
    print('Set AGUS_MAPS_BUILD_MODE=contributor to build from source');
  }
}

/// Contributor build workflow (build from source)
Future<void> _runContributorBuild(BuildRunnerConfig config) async {
  final tag = getComapsTag();

  print('=== Contributor Build (from source) ===');
  print('CoMaps tag: $tag');
  print('');

  // Step 1: Bootstrap CoMaps
  await _bootstrapComaps(tag, skipPatches: config.skipPatches);

  // Step 2: Build Boost headers
  await _buildBoostHeaders();

  // Step 3: Generate CoMaps data files
  await _generateComapsData();

  // Step 4: Copy data files to example/assets
  await _copyDataFiles();

  // Step 5: Build native binaries (if requested)
  bool builtIOS = false;
  bool builtMacOS = false;
  
  if (config.buildBinaries) {
    final platforms = config.platforms ?? _getDefaultPlatforms();
    for (final platform in platforms) {
      await _buildPlatform(platform);
      
      // Track iOS/macOS builds for Metal shaders and CocoaPods
      if (platform == 'ios') builtIOS = true;
      if (platform == 'macos') builtMacOS = true;
      
      // Setup CocoaPods after iOS/macOS builds
      if (platform == 'ios' || platform == 'macos') {
        await _setupCocoaPods(platform);
      }
    }
    
    // Build Metal shaders if iOS or macOS was built (macOS only)
    if (Platform.isMacOS && (builtIOS || builtMacOS)) {
      await _buildMetalShaders();
    }
  } else {
    print('');
    print('Build binaries: false (use --build-binaries to build native libraries)');
  }

  print('');
  print('=== Build Complete ===');
}

/// Bootstrap CoMaps (clone, checkout, submodules, patches)
Future<void> _bootstrapComaps(String tag, {bool skipPatches = false}) async {
  final comapsDir = getComapsDir();

  print('=== Bootstrap CoMaps ===');

  // Check if already cloned
  if (await Directory(comapsDir).exists()) {
    final gitDir = Directory(path.join(comapsDir, '.git'));
    if (await gitDir.exists()) {
      print('CoMaps repository already exists');
      // Still checkout correct tag and update submodules
      await checkoutComapsTag(tag);
      await initSubmodules();
    } else {
      // Clone fresh
      await cloneComaps(tag);
    }
  } else {
    // Clone fresh
    await cloneComaps(tag);
  }

  // Apply patches
  if (!skipPatches) {
    print('');
    print('=== Apply Patches ===');
    await applyPatches();
  } else {
    print('Skipping patches (--skip-patches)');
  }

  print('');
}

/// Build Boost headers
Future<void> _buildBoostHeaders() async {
  final comapsDir = getComapsDir();
  final boostDir = path.join(comapsDir, '3party', 'boost');
  final configFile = path.join(boostDir, 'boost', 'config.hpp');

  print('=== Build Boost Headers ===');

  if (await File(configFile).exists()) {
    print('Boost headers already built');
    return;
  }

  if (!await Directory(boostDir).exists()) {
    throw Exception('Boost directory not found: $boostDir');
  }

  // Build bootstrap.sh
  print('Running bootstrap.sh...');
  if (Platform.isWindows) {
    // On Windows, try bootstrap.bat first
    final bootstrapBat = path.join(boostDir, 'bootstrap.bat');
    if (await File(bootstrapBat).exists()) {
      await runProcess('bootstrap.bat', [], workingDirectory: boostDir);
    } else {
      // Try bash bootstrap.sh (Git Bash, WSL)
      await runProcess('bash', ['bootstrap.sh'], workingDirectory: boostDir);
    }
  } else {
    await runProcess('bash', ['bootstrap.sh'], workingDirectory: boostDir);
  }

  // Build headers with b2
  print('Building headers with b2...');
  if (Platform.isWindows) {
    await runProcess('b2', ['headers'], workingDirectory: boostDir);
  } else {
    await runProcess('./b2', ['headers'], workingDirectory: boostDir);
  }

  print('Boost headers built');
  print('');
}

/// Generate CoMaps data files
Future<void> _generateComapsData() async {
  final comapsDir = getComapsDir();
  final dataDir = path.join(comapsDir, 'data');

  print('=== Generate CoMaps Data Files ===');

  // Check if already generated
  final classificatorFile = path.join(dataDir, 'classificator.txt');
  final typesFile = path.join(dataDir, 'types.txt');
  final visibilityFile = path.join(dataDir, 'visibility.txt');
  final categoriesFile = path.join(dataDir, 'categories.txt');

  if (await File(classificatorFile).exists() &&
      await File(typesFile).exists() &&
      await File(visibilityFile).exists() &&
      await File(categoriesFile).exists()) {
    print('Data files already generated');
    print('');
    return;
  }

  // Set protobuf compatibility mode
  final env = Map<String, String>.from(Platform.environment);
  env['PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION'] = 'python';
  env['OMIM_PATH'] = comapsDir;
  env['DATA_PATH'] = dataDir;

  if (Platform.isWindows) {
    // On Windows, match the old PowerShell implementation:
    // Only run generate_desktop_ui_strings.py directly (skip bash scripts)
    final generateDesktopUIPython = path.join(comapsDir, 'tools', 'python', 'generate_desktop_ui_strings.py');
    if (await File(generateDesktopUIPython).exists()) {
      print('Generating desktop UI strings...');
      await runProcess(
        'python',
        [generateDesktopUIPython],
        workingDirectory: comapsDir,
        environment: env,
      );
    } else {
      print('Warning: generate_desktop_ui_strings.py not found at $generateDesktopUIPython');
    }
    
    // Note: On Windows, generate_drules.sh and generate_categories.sh are skipped
    // These are typically generated during native builds or are provided in the SDK
    print('Note: Skipping generate_drules.sh and generate_categories.sh on Windows (matches old PowerShell behavior)');
  } else {
    // On Unix systems, run all bash scripts
    // Generate drawing rules
    final generateDrulesScript = path.join(comapsDir, 'tools', 'unix', 'generate_drules.sh');
    if (await File(generateDrulesScript).exists()) {
      print('Generating drawing rules...');
      await runProcess(
        'bash',
        [generateDrulesScript],
        workingDirectory: comapsDir,
        environment: env,
      );
    }

    // Generate categories
    final generateCategoriesScript = path.join(comapsDir, 'tools', 'unix', 'generate_categories.sh');
    if (await File(generateCategoriesScript).exists()) {
      print('Generating categories...');
      await runProcess(
        'bash',
        [generateCategoriesScript],
        workingDirectory: comapsDir,
        environment: env,
      );
    }

    // Generate desktop UI strings
    final generateDesktopUIScript = path.join(comapsDir, 'tools', 'unix', 'generate_desktop_ui_strings.sh');
    if (await File(generateDesktopUIScript).exists()) {
      print('Generating desktop UI strings...');
      try {
        await runProcess(
          'bash',
          [generateDesktopUIScript],
          workingDirectory: comapsDir,
          environment: env,
          throwOnError: false,
        );
      } catch (e) {
        print('Warning: generate_desktop_ui_strings.sh had warnings (may be expected)');
      }
    }
  }

  // Download symbol textures from Organic Maps
  // These are generated by skin_generator_tool which requires building desktop tools
  print('Downloading symbol textures...');
  final resolutions = ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi', '6plus'];
  final themes = ['light', 'dark'];
  final baseUrl = 'https://raw.githubusercontent.com/organicmaps/organicmaps/master/data/symbols';
  
  for (final res in resolutions) {
    for (final theme in themes) {
      final symbolDir = path.join(dataDir, 'symbols', res, theme);
      await ensureDir(symbolDir);
      
      final sdfFile = path.join(symbolDir, 'symbols.sdf');
      final pngFile = path.join(symbolDir, 'symbols.png');
      
      // Download symbols.sdf if it doesn't exist
      if (!await File(sdfFile).exists()) {
        try {
          print('  Downloading $res/$theme symbols.sdf...');
          final sdfUrl = '$baseUrl/$res/$theme/symbols.sdf';
          await runProcess(
            'curl',
            ['-sL', sdfUrl, '-o', sdfFile],
            throwOnError: false,
          );
          if (!await File(sdfFile).exists()) {
            print('Warning: Failed to download $res/$theme/symbols.sdf');
          }
        } catch (e) {
          print('Warning: Failed to download $res/$theme/symbols.sdf: $e');
        }
      }
      
      // Download symbols.png if it doesn't exist
      if (!await File(pngFile).exists()) {
        try {
          print('  Downloading $res/$theme symbols.png...');
          final pngUrl = '$baseUrl/$res/$theme/symbols.png';
          await runProcess(
            'curl',
            ['-sL', pngUrl, '-o', pngFile],
            throwOnError: false,
          );
          if (!await File(pngFile).exists()) {
            print('Warning: Failed to download $res/$theme/symbols.png');
          }
        } catch (e) {
          print('Warning: Failed to download $res/$theme/symbols.png: $e');
        }
      }
    }
  }

  print('Data files generated');
  print('');
}

/// Copy data files to example/assets
Future<void> _copyDataFiles() async {
  final repoRoot = getRepoRoot();
  final comapsDataDir = path.join(repoRoot, 'thirdparty', 'comaps', 'data');
  final destDataDir = path.join(repoRoot, 'example', 'assets', 'comaps_data');

  print('=== Copy Data Files ===');

  if (!await Directory(comapsDataDir).exists()) {
    print('CoMaps data directory not found: $comapsDataDir');
    return;
  }

  await ensureDir(destDataDir);

  // Essential files
  final essentialFiles = [
    'classificator.txt',
    'types.txt',
    'categories.txt',
    'visibility.txt',
    'countries.txt',
    'countries_meta.txt',
    'packed_polygons.bin',
    'drules_proto.bin',
    'drules_proto_default_light.bin',
    'drules_proto_default_dark.bin',
    'drules_proto_outdoors_light.bin',
    'drules_proto_outdoors_dark.bin',
    'drules_proto_vehicle_light.bin',
    'drules_proto_vehicle_dark.bin',
    'drules_hash',
    'transit_colors.txt',
    'colors.txt',
    'patterns.txt',
    'editor.config',
  ];

  for (final file in essentialFiles) {
    final src = path.join(comapsDataDir, file);
    if (await File(src).exists()) {
      final dest = path.join(destDataDir, file);
      await File(src).copy(dest);
      print('  Copied: $file');
    }
  }

  // Copy directories
  final dirsToCopy = ['categories-strings', 'countries-strings', 'fonts', 'symbols', 'styles'];
  for (final dir in dirsToCopy) {
    final srcDir = path.join(comapsDataDir, dir);
    if (await Directory(srcDir).exists()) {
      final destDir = path.join(destDataDir, dir);
      await copyPath(srcDir, destDir);
      print('  Copied: $dir/');
    }
  }

  // Copy ICU data
  final icuSource = path.join(comapsDataDir, 'icudt75l.dat');
  final mapsDir = path.join(repoRoot, 'example', 'assets', 'maps');
  await ensureDir(mapsDir);
  if (await File(icuSource).exists()) {
    final icuDest = path.join(mapsDir, 'icudt75l.dat');
    await File(icuSource).copy(icuDest);
    print('  Copied: icudt75l.dat to assets/maps/');
  }

  print('Data files copied');
  print('');
}

/// Build native binaries for a specific platform
Future<void> _buildPlatform(String platform) async {
  print('=== Build $platform ===');

  try {
    switch (platform.toLowerCase()) {
      case 'android':
        await _buildAndroid();
        break;
      case 'ios':
        await _buildiOS();
        break;
      case 'macos':
        await _buildMacOS();
        break;
      case 'windows':
        await _buildWindows();
        break;
      case 'linux':
        await _buildLinux();
        break;
      default:
        print('Unknown platform: $platform');
        return;
    }

    print('$platform build complete');
    print('');
  } catch (e) {
    print('Error building $platform: $e');
    rethrow;
  }
}

/// Build Android binaries
Future<void> _buildAndroid() async {
  final outputDir = path.join(getBuildDir(), 'agus-binaries-android');
  await ensureDir(outputDir);

  for (final abi in BuildConfig.androidAbis) {
    print('Building Android $abi...');
    await buildAndroidAbi(abi);
  }

  // Copy to android/prebuilt
  final prebuiltDir = path.join(getRepoRoot(), 'android', 'prebuilt');
  await ensureDir(prebuiltDir);
  await copyPath(outputDir, prebuiltDir);
}

/// Build iOS XCFramework
Future<void> _buildiOS() async {
  await buildiOSXCFramework();

  // Copy to ios/Frameworks
  final outputDir = path.join(getBuildDir(), 'agus-binaries-ios');
  final frameworksDir = path.join(getRepoRoot(), 'ios', 'Frameworks');
  await ensureDir(frameworksDir);

  final xcframeworkPath = path.join(outputDir, 'CoMaps.xcframework');
  if (await Directory(xcframeworkPath).exists()) {
    await copyPath(xcframeworkPath, path.join(frameworksDir, 'CoMaps.xcframework'));
  }
}

/// Build macOS XCFramework
Future<void> _buildMacOS() async {
  await buildMacOSXCFramework();

  // Copy to macos/Frameworks
  final outputDir = path.join(getBuildDir(), 'agus-binaries-macos');
  final frameworksDir = path.join(getRepoRoot(), 'macos', 'Frameworks');
  await ensureDir(frameworksDir);

  final xcframeworkPath = path.join(outputDir, 'CoMaps.xcframework');
  if (await Directory(xcframeworkPath).exists()) {
    await copyPath(xcframeworkPath, path.join(frameworksDir, 'CoMaps.xcframework'));
  }
}

/// Build Windows library
Future<void> _buildWindows() async {
  await buildWindowsLibrary();

  // Copy to windows/prebuilt/x64
  final outputDir = path.join(getBuildDir(), 'agus-binaries-windows', 'x64');
  final prebuiltDir = path.join(getRepoRoot(), 'windows', 'prebuilt', 'x64');
  await ensureDir(prebuiltDir);

  if (await Directory(outputDir).exists()) {
    await copyPath(outputDir, prebuiltDir);
  }
}

/// Build Linux library
Future<void> _buildLinux() async {
  await buildLinuxLibrary();

  // Copy to linux/prebuilt/x64
  final outputDir = path.join(getBuildDir(), 'agus-binaries-linux', 'x64');
  final prebuiltDir = path.join(getRepoRoot(), 'linux', 'prebuilt', 'x64');
  await ensureDir(prebuiltDir);

  if (await Directory(outputDir).exists()) {
    await copyPath(outputDir, prebuiltDir);
  }
}

/// Build Metal shaders for iOS/macOS
Future<void> _buildMetalShaders() async {
  if (!Platform.isMacOS) {
    print('Skipping Metal shaders (macOS/iOS only)');
    return;
  }

  print('=== Build Metal Shaders ===');

  final comapsDir = getComapsDir();
  final repoRoot = getRepoRoot();
  
  // Find shader directory (try multiple locations)
  var shadersDir = path.join(comapsDir, 'libs', 'shaders', 'Metal');
  if (!await Directory(shadersDir).exists()) {
    // Try alternative location: thirdparty/comaps/shaders/Metal
    shadersDir = path.join(comapsDir, 'shaders', 'Metal');
  }
  
  if (!await Directory(shadersDir).exists()) {
    // Search recursively for shaders/Metal directory
    await for (final entity in Directory(comapsDir).list(recursive: true)) {
      if (entity is Directory && 
          entity.path.contains('shaders') && 
          entity.path.contains('Metal') &&
          path.basename(entity.path) == 'Metal') {
        shadersDir = entity.path;
        break;
      }
    }
  }
  
  // Try to find .metal files if directory still doesn't exist
  if (!await Directory(shadersDir).exists()) {
    await for (final entity in Directory(comapsDir).list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.metal')) {
        shadersDir = path.dirname(entity.path);
        break;
      }
    }
  }

  if (!await Directory(shadersDir).exists()) {
    print('Warning: Metal shader directory not found, skipping Metal shader compilation');
    print('The app may fall back to OpenGL rendering');
    return;
  }

  final tempDir = path.join(getBuildDir(), 'metal_temp');
  final outputLib = path.join(getBuildDir(), 'metal_shaders', 'shaders_metal.metallib');
  await ensureDir(tempDir);
  await ensureDir(path.dirname(outputLib));

  print('Compiling Metal shaders from $shadersDir...');

  // Find all .metal files
  final metalFiles = <String>[];
  await for (final entity in Directory(shadersDir).list(recursive: false)) {
    if (entity is File && entity.path.endsWith('.metal')) {
      metalFiles.add(entity.path);
    }
  }

  if (metalFiles.isEmpty) {
    print('Warning: No Metal shader files found, skipping Metal shader compilation');
    return;
  }

  // Compile each .metal file to .air
  final airFiles = <String>[];
  for (final metalFile in metalFiles) {
    final filename = path.basename(metalFile);
    final name = path.basenameWithoutExtension(metalFile);
    final airFile = path.join(tempDir, '$name.air');

    try {
      // Try with macosx SDK first (works for both macOS and iOS with Metal 2.0)
      await runProcess(
        'xcrun',
        ['-sdk', 'macosx', 'metal', '-c', '-std=osx-metal2.0', '-I', shadersDir, '-o', airFile, metalFile],
        throwOnError: false,
      );
      
      if (await File(airFile).exists()) {
        airFiles.add(airFile);
        print('  Compiled: $filename');
      }
    } catch (e) {
      print('Warning: Failed to compile $filename: $e');
    }
  }

  if (airFiles.isEmpty) {
    print('Warning: No Metal shaders compiled successfully');
    return;
  }

  // Link .air files to .metallib
  print('Linking ${airFiles.length} shaders...');
  try {
    await runProcess(
      'xcrun',
      ['-sdk', 'macosx', 'metallib', '-o', outputLib, ...airFiles],
      throwOnError: false,
    );

    if (!await File(outputLib).exists()) {
      print('Warning: Failed to link Metal library');
      return;
    }

    print('Created: ${path.basename(outputLib)}');

    // Copy to platform resource directories
    final iosResources = path.join(repoRoot, 'ios', 'Resources');
    final macosResources = path.join(repoRoot, 'macos', 'Resources');
    
    await ensureDir(iosResources);
    await ensureDir(macosResources);
    
    final iosDest = path.join(iosResources, 'shaders_metal.metallib');
    final macosDest = path.join(macosResources, 'shaders_metal.metallib');
    
    await File(outputLib).copy(iosDest);
    await File(outputLib).copy(macosDest);
    
    print('Copied to ios/Resources/');
    print('Copied to macos/Resources/');
  } catch (e) {
    print('Warning: Failed to link Metal library: $e');
  }
}

/// Setup CocoaPods for iOS or macOS
Future<void> _setupCocoaPods(String platform) async {
  if (!Platform.isMacOS) {
    print('Skipping CocoaPods setup (macOS/iOS only)');
    return;
  }

  if (platform != 'ios' && platform != 'macos') {
    return;
  }

  print('=== Setup CocoaPods ($platform) ===');

  // Check if pod command exists
  if (!await commandExists('pod')) {
    print('Warning: CocoaPods not found, skipping pod install');
    print('Install CocoaPods: sudo gem install cocoapods');
    return;
  }

  final repoRoot = getRepoRoot();
  final podDir = path.join(repoRoot, 'example', platform);

  if (!await Directory(podDir).exists()) {
    print('Warning: $platform example directory not found, skipping CocoaPods setup');
    return;
  }

  try {
    print('Running pod install in example/$platform...');
    await runProcess('pod', ['install'], workingDirectory: podDir);
    print('CocoaPods setup complete for $platform');
  } catch (e) {
    print('Warning: CocoaPods setup failed for $platform: $e');
    // Don't fail the build if CocoaPods fails
  }
}

/// Get default platforms based on OS
List<String> _getDefaultPlatforms() {
  final os = detectOS();
  switch (os) {
    case OSType.macos:
      return ['android', 'ios', 'macos'];
    case OSType.linux:
      return ['android', 'linux'];
    case OSType.windows:
      return ['android', 'windows'];
  }
}
