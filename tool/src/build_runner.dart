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
import 'archive_manager.dart' show createTarGz, extractTarGz;

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
  await _bootstrapComaps(tag, skipPatches: config.skipPatches, noCache: config.noCache);

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
/// 
/// Implements local caching for faster iteration on patches:
/// - Cache file: .thirdparty-{tag}.tar.gz (in repo root)
/// - Cache is created AFTER clone, BEFORE patches
/// - If thirdparty/ is deleted and cache exists, extract from cache
/// - Use --no-cache to disable caching behavior
Future<void> _bootstrapComaps(String tag, {bool skipPatches = false, bool noCache = false}) async {
  final repoRoot = getRepoRoot();
  final thirdpartyDir = path.join(repoRoot, 'thirdparty');
  final comapsDir = getComapsDir();
  
  // Sanitize tag for filename (replace slashes and special chars)
  final safeTag = tag.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
  final cacheFile = path.join(repoRoot, '.thirdparty-$safeTag.tar.gz');
  
  print('=== Bootstrap CoMaps ===');
  
  // Show cache status
  final cacheExists = await File(cacheFile).exists();
  if (noCache) {
    print('Cache: disabled (--no-cache)');
  } else if (cacheExists) {
    final cacheSize = await File(cacheFile).length();
    final cacheSizeMB = (cacheSize / 1024 / 1024).toStringAsFixed(1);
    print('Cache: found .thirdparty-$safeTag.tar.gz ($cacheSizeMB MB)');
  } else {
    print('Cache: not found (will create after fresh clone)');
  }
  
  // Track if this was a fresh clone (for cache creation)
  var freshClone = false;
  var usedCache = false;
  
  // Try to restore from cache if thirdparty doesn't exist
  if (!noCache && !await Directory(comapsDir).exists() && cacheExists) {
    print('');
    print('=== Restoring from Cache ===');
    print('Extracting .thirdparty-$safeTag.tar.gz...');
    final stopwatch = Stopwatch()..start();
    
    try {
      await extractTarGz(cacheFile, repoRoot);
      stopwatch.stop();
      print('Extracted in ${stopwatch.elapsed.inSeconds} seconds');
      usedCache = true;
    } catch (e) {
      print('Warning: Cache extraction failed: $e');
      print('Falling back to git clone...');
      // Clean up any partial extraction
      if (await Directory(thirdpartyDir).exists()) {
        await Directory(thirdpartyDir).delete(recursive: true);
      }
    }
  }

  // Check if already cloned (either from cache or existing)
  if (await Directory(comapsDir).exists()) {
    final gitDir = Directory(path.join(comapsDir, '.git'));
    if (await gitDir.exists()) {
      if (usedCache) {
        print('CoMaps restored from cache');
      } else {
        print('CoMaps repository already exists');
      }
      // Still checkout correct tag and update submodules
      await checkoutComapsTag(tag);
      await initSubmodules();
    } else {
      // Clone fresh
      await cloneComaps(tag);
      freshClone = true;
    }
  } else {
    // Clone fresh
    await cloneComaps(tag);
    freshClone = true;
  }
  
  // Create cache after fresh clone (BEFORE patches)
  // This allows iterating on patches without re-cloning
  if (!noCache && freshClone && !usedCache) {
    print('');
    print('=== Creating Cache ===');
    print('Compressing thirdparty to .thirdparty-$safeTag.tar.gz...');
    print('This may take a few minutes (using fastest compression)...');
    final stopwatch = Stopwatch()..start();
    
    try {
      await createTarGz(thirdpartyDir, cacheFile);
      stopwatch.stop();
      
      final cacheSize = await File(cacheFile).length();
      final cacheSizeMB = (cacheSize / 1024 / 1024).toStringAsFixed(1);
      print('Cache created: $cacheSizeMB MB in ${stopwatch.elapsed.inSeconds} seconds');
      print('Tip: Delete thirdparty/ and re-run to use cache');
    } catch (e) {
      print('Warning: Failed to create cache: $e');
      // Don't fail the build if cache creation fails
    }
  }

  // Apply patches (always after cache operations)
  if (!skipPatches) {
    print('');
    print('=== Apply Patches ===');
    await applyPatches();
  } else {
    print('Skipping patches (--skip-patches)');
  }

  // Fallback: ensure Windows multiprocessing is disabled for libkomwm.py
  if (Platform.isWindows) {
    await _disableLibkomwmMultiprocessingOnWindows(comapsDir);
  }

  print('');
}

Future<void> _disableLibkomwmMultiprocessingOnWindows(String comapsDir) async {
  final targetPath = path.join(comapsDir, 'tools', 'kothic', 'src', 'libkomwm.py');
  final file = File(targetPath);
  if (!await file.exists()) {
    return;
  }

  final content = await file.readAsString();
  if (content.contains('MULTIPROCESSING = False')) {
    return;
  }

  final updated = content.replaceFirst('MULTIPROCESSING = True', 'MULTIPROCESSING = False');
  if (updated != content) {
    await file.writeAsString(updated);
    print('Applied Windows fallback: MULTIPROCESSING = False in tools/kothic/src/libkomwm.py');
  }
}

/// Build Boost headers
Future<void> _buildBoostHeaders() async {
  final comapsDir = getComapsDir();
  final boostDir = path.join(comapsDir, '3party', 'boost');
  
  // Check for flat boost/ directory (created by b2 headers)
  final flatConfigFile = path.join(boostDir, 'boost', 'config.hpp');
  
  // Check for modular structure (libs/config/include/boost/config.hpp)
  // CoMaps CMake directly includes from modular paths, so we don't need b2 headers
  final modularConfigFile = path.join(boostDir, 'libs', 'config', 'include', 'boost', 'config.hpp');

  print('=== Build Boost Headers ===');

  // First, check if modular structure exists (preferred - no build needed)
  if (await File(modularConfigFile).exists()) {
    print('Boost modular headers found (libs/*/include structure)');
    print('CMake will use modular include paths directly - no b2 headers needed');
    
    // Verify a few more essential modules exist
    final essentialModules = ['regex', 'container', 'iterator', 'range'];
    var allFound = true;
    for (final module in essentialModules) {
      final modulePath = path.join(boostDir, 'libs', module, 'include');
      if (!await Directory(modulePath).exists()) {
        print('Warning: Boost module "$module" not found at $modulePath');
        allFound = false;
      }
    }
    
    if (allFound) {
      print('All essential Boost modules verified');
      print('');
      return;
    } else {
      print('Some Boost modules missing, will try to build headers...');
    }
  }

  // Check if flat structure already exists (from previous b2 headers run)
  if (await File(flatConfigFile).exists()) {
    print('Boost flat headers already built (boost/config.hpp exists)');
    print('');
    return;
  }

  if (!await Directory(boostDir).exists()) {
    throw Exception('Boost directory not found: $boostDir');
  }

  // If we get here, we need to run b2 headers to create the flat structure
  // This is a fallback path - normally the modular structure should be sufficient
  print('Building flat Boost headers with b2...');
  
  final b2Exe = Platform.isWindows ? path.join(boostDir, 'b2.exe') : path.join(boostDir, 'b2');

  // Check if b2 already exists (bootstrap already done)
  final b2Exists = await File(b2Exe).exists();
  
  if (!b2Exists) {
    // Need to run bootstrap first
    print('Running bootstrap...');
    
    if (Platform.isWindows) {
      // On Windows, check for available compilers first
      final hasVsDevCmd = await _findVsDevCmd();
      
      final bootstrapBat = path.join(boostDir, 'bootstrap.bat');
      if (await File(bootstrapBat).exists()) {
        if (hasVsDevCmd != null) {
          // Run through VS Developer Command Prompt
          print('Using Visual Studio: $hasVsDevCmd');
          try {
            // Create a temporary batch file that calls VsDevCmd and then bootstrap
            final tempBat = path.join(boostDir, '_bootstrap_with_vs.bat');
            await File(tempBat).writeAsString('''
@echo off
call "${hasVsDevCmd}"
cd /d "${boostDir}"
call bootstrap.bat
''');
            await runProcess('cmd', ['/c', tempBat], workingDirectory: boostDir, verbose: true);
            // Clean up temp file
            try {
              await File(tempBat).delete();
            } catch (_) {}
          } catch (e) {
            // Fallback: try direct execution
            print('VS Dev Cmd method failed, trying direct execution...');
            await runProcess('cmd', ['/c', 'bootstrap.bat'], workingDirectory: boostDir, verbose: true);
          }
        } else {
          // Try direct execution - let bootstrap.bat find the compiler
          print('Running bootstrap.bat directly...');
          try {
            await runProcess('cmd', ['/c', 'bootstrap.bat'], workingDirectory: boostDir, verbose: true);
          } catch (e) {
            print('');
            print('ERROR: Failed to build Boost b2 tool.');
            print('');
            print('This requires a C++ compiler. Please ensure one of the following:');
            print('  1. Visual Studio 2019/2022 with "Desktop development with C++" workload');
            print('  2. Run from "Developer Command Prompt for VS"');
            print('  3. MinGW-w64 (gcc) in PATH');
            print('');
            print('After installing, restart your terminal and try again.');
            rethrow;
          }
        }
      } else {
        // Try bash bootstrap.sh (Git Bash, WSL, MSYS2)
        print('bootstrap.bat not found, trying bash bootstrap.sh...');
        await runProcess('bash', ['bootstrap.sh'], workingDirectory: boostDir, verbose: true);
      }
    } else {
      // Unix systems
      await runProcess('bash', ['bootstrap.sh'], workingDirectory: boostDir, verbose: true);
    }
  } else {
    print('b2 already exists, skipping bootstrap');
  }

  // Verify b2 exists after bootstrap
  if (!await File(b2Exe).exists()) {
    throw Exception('Bootstrap completed but b2 executable not found at: $b2Exe');
  }

  // Build headers with b2
  print('Building headers with b2...');
  if (Platform.isWindows) {
    await runProcess('cmd', ['/c', 'b2.exe', 'headers'], workingDirectory: boostDir, verbose: true);
  } else {
    await runProcess('./b2', ['headers'], workingDirectory: boostDir, verbose: true);
  }

  // Verify headers were generated
  if (!await File(flatConfigFile).exists()) {
    throw Exception('b2 headers completed but config.hpp not found at: $flatConfigFile');
  }

  print('Boost headers built');
  print('');
}

/// Find Visual Studio Developer Command Prompt
Future<String?> _findVsDevCmd() async {
  if (!Platform.isWindows) return null;
  
  // Common VS installation paths
  final programFiles = Platform.environment['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)';
  final programFilesNormal = Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
  
  final vsYears = ['2022', '2019', '2017'];
  final vsEditions = ['Enterprise', 'Professional', 'Community', 'BuildTools'];
  
  for (final year in vsYears) {
    for (final edition in vsEditions) {
      // VS 2022 is typically in Program Files (not x86)
      final basePath = year == '2022' ? programFilesNormal : programFiles;
      final devCmdPath = path.join(
        basePath,
        'Microsoft Visual Studio',
        year,
        edition,
        'Common7',
        'Tools',
        'VsDevCmd.bat',
      );
      if (await File(devCmdPath).exists()) {
        return devCmdPath;
      }
    }
  }
  
  return null;
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
  env['PYTHONUTF8'] = '1';
  env['PYTHONIOENCODING'] = 'utf-8';

  String toBashPath(String windowsPath) {
    var p = windowsPath.replaceAll('\\', '/');
    if (RegExp(r'^[A-Za-z]:/').hasMatch(p)) {
      final drive = p.substring(0, 1).toLowerCase();
      p = '/$drive${p.substring(2)}';
    }
    return p;
  }

  Future<void> runUnixDataScripts() async {
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

  if (Platform.isWindows) {
    final gitBashPath = r'C:\Program Files\Git\bin\bash.exe';
    if (await File(gitBashPath).exists()) {
      final gitBashDir = path.dirname(gitBashPath);
      env['PATH'] = '$gitBashDir;${env['PATH'] ?? ''}';
      print('Bash detected on Windows; using Git Bash at $gitBashPath');
    } else {
      print('Bash detected on Windows; running Unix data generation scripts...');
    }
    await runUnixDataScripts();
  } else {
    // On Unix systems, run all bash scripts
    await runUnixDataScripts();
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
