// Build orchestration - coordinates all build steps

import 'dart:io';
import 'package:path/path.dart' as path;
import 'config.dart' show BuildConfig, BuildMode, getComapsTag;
import 'platform_detector.dart' show getRepoRoot, getComapsDir, getBuildDir, detectOS, OSType;
import 'git_operations.dart' show cloneComaps, checkoutComapsTag, initSubmodules;
import 'patch_applicator.dart' show applyPatches;
import 'file_operations.dart' show ensureDir, copyPath;
import 'process_runner.dart' show runProcess;
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
  if (config.buildBinaries) {
    final platforms = config.platforms ?? _getDefaultPlatforms();
    for (final platform in platforms) {
      await _buildPlatform(platform);
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

  // Generate drawing rules
  final generateDrulesScript = path.join(comapsDir, 'tools', 'unix', 'generate_drules.sh');
  if (await File(generateDrulesScript).exists()) {
    print('Generating drawing rules...');
    // On Windows, convert paths to Unix format for bash
    final scriptPath = Platform.isWindows 
        ? generateDrulesScript.replaceAll('\\', '/')
        : generateDrulesScript;
    final workingDir = Platform.isWindows
        ? comapsDir.replaceAll('\\', '/')
        : comapsDir;
    // Convert environment paths to Unix format on Windows
    final bashEnv = Map<String, String>.from(env);
    if (Platform.isWindows) {
      if (bashEnv.containsKey('OMIM_PATH')) {
        bashEnv['OMIM_PATH'] = bashEnv['OMIM_PATH']!.replaceAll('\\', '/');
      }
      if (bashEnv.containsKey('DATA_PATH')) {
        bashEnv['DATA_PATH'] = bashEnv['DATA_PATH']!.replaceAll('\\', '/');
      }
    }
    await runProcess(
      'bash',
      [scriptPath],
      workingDirectory: workingDir,
      environment: bashEnv,
    );
  }

  // Generate categories
  final generateCategoriesScript = path.join(comapsDir, 'tools', 'unix', 'generate_categories.sh');
  if (await File(generateCategoriesScript).exists()) {
    print('Generating categories...');
    // On Windows, convert paths to Unix format for bash
    final scriptPath = Platform.isWindows 
        ? generateCategoriesScript.replaceAll('\\', '/')
        : generateCategoriesScript;
    final workingDir = Platform.isWindows
        ? comapsDir.replaceAll('\\', '/')
        : comapsDir;
    // Convert environment paths to Unix format on Windows (for consistency)
    final bashEnv = Map<String, String>.from(env);
    if (Platform.isWindows) {
      if (bashEnv.containsKey('OMIM_PATH')) {
        bashEnv['OMIM_PATH'] = bashEnv['OMIM_PATH']!.replaceAll('\\', '/');
      }
      if (bashEnv.containsKey('DATA_PATH')) {
        bashEnv['DATA_PATH'] = bashEnv['DATA_PATH']!.replaceAll('\\', '/');
      }
    }
    await runProcess(
      'bash',
      [scriptPath],
      workingDirectory: workingDir,
      environment: bashEnv,
    );
  }

  // Generate desktop UI strings
  final generateDesktopUIScript = path.join(comapsDir, 'tools', 'unix', 'generate_desktop_ui_strings.sh');
  if (await File(generateDesktopUIScript).exists()) {
    print('Generating desktop UI strings...');
    // On Windows, convert paths to Unix format for bash
    final scriptPath = Platform.isWindows 
        ? generateDesktopUIScript.replaceAll('\\', '/')
        : generateDesktopUIScript;
    final workingDir = Platform.isWindows
        ? comapsDir.replaceAll('\\', '/')
        : comapsDir;
    try {
      await runProcess(
        'bash',
        [scriptPath],
        workingDirectory: workingDir,
        environment: env,
        throwOnError: false,
      );
    } catch (e) {
      print('Warning: generate_desktop_ui_strings.sh had warnings (may be expected)');
    }
  }

  // Download symbol textures (simplified - just note it's needed)
  print('Note: Symbol textures should be downloaded separately if needed');

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
