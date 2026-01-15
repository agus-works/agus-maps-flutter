// CMake build orchestration for all platforms

import 'dart:io';
import 'package:path/path.dart' as path;
import 'process_runner.dart' show runProcess, runProcessStreaming, commandExists;
import 'file_operations.dart' show ensureDir, copyPath, dirExists, fileExists;
import 'platform_detector.dart' show getRepoRoot, getBuildDir, getComapsDir, getCpuCores, detectOS, OSType;
import 'config.dart' show BuildConfig;
import 'utils.dart' show compareVersions;

// Cached CMake path
String? _cmakePath;

/// Get CMake executable path (may be in PATH or from Android SDK)
String _getCMakePath() {
  if (_cmakePath != null) return _cmakePath!;
  
  // Check if cmake is in PATH
  final result = Process.runSync(Platform.isWindows ? 'where' : 'which', ['cmake'], runInShell: true);
  if (result.exitCode == 0) {
    _cmakePath = 'cmake';
    return _cmakePath!;
  }
  
  // On Windows, try to find cmake from Android SDK
  if (Platform.isWindows) {
    final androidHome = Platform.environment['ANDROID_HOME'] ??
        Platform.environment['ANDROID_SDK_ROOT'] ??
        path.join(Platform.environment['LOCALAPPDATA'] ?? '', 'Android', 'Sdk');
    
    if (androidHome.isNotEmpty && dirExists(androidHome)) {
      final cmakeDir = path.join(androidHome, 'cmake');
      if (dirExists(cmakeDir)) {
        // Find newest CMake version
        final cmakeDirectory = Directory(cmakeDir);
        final cmakeVersions = cmakeDirectory
            .listSync()
            .whereType<Directory>()
            .map((d) => path.basename(d.path))
            .where((name) => RegExp(r'^\d+\.\d+').hasMatch(name))
            .toList()
          ..sort((a, b) => compareVersions(b, a)); // Sort descending
        
        if (cmakeVersions.isNotEmpty) {
          final cmakeExe = path.join(cmakeDir, cmakeVersions.first, 'bin', 'cmake.exe');
          if (fileExists(cmakeExe)) {
            _cmakePath = cmakeExe;
            print('Using CMake from Android SDK: $_cmakePath');
            return _cmakePath!;
          }
        }
      }
    }
  }
  
  throw Exception('CMake not found. Install CMake and add to PATH, or install via Android Studio SDK Manager.');
}

/// Build configuration for CMake
class CMakeBuildConfig {
  final String sourceDir;
  final String buildDir;
  final Map<String, String> variables;
  final String? generator;
  final String? target;
  final int? parallelJobs;

  CMakeBuildConfig({
    required this.sourceDir,
    required this.buildDir,
    required this.variables,
    this.generator,
    this.target,
    this.parallelJobs,
  });
}

/// Configure and build with CMake
Future<void> buildWithCMake(CMakeBuildConfig config) async {
  await ensureDir(config.buildDir);

  // CMake configure arguments
  final cmakeArgs = <String>[
    '-S', config.sourceDir,
    '-B', config.buildDir,
  ];

  // Add generator if specified
  if (config.generator != null) {
    cmakeArgs.addAll(['-G', config.generator!]);
  }

  // Add CMake variables
  for (final entry in config.variables.entries) {
    cmakeArgs.addAll(['-D', '${entry.key}=${entry.value}']);
  }

  final cmake = _getCMakePath();
  
  print('Configuring CMake...');
  print('  Source: ${config.sourceDir}');
  print('  Build: ${config.buildDir}');
  if (config.generator != null) {
    print('  Generator: ${config.generator}');
  }

  // Configure
  await runProcessStreaming(
    cmake,
    cmakeArgs,
    onStdout: (line) => stdout.write(line),
    onStderr: (line) => stderr.write(line),
  );

  // Build
  print('Building with CMake...');
  final buildArgs = <String>[
    '--build',
    config.buildDir,
  ];

  // Visual Studio generator uses multi-config builds, so --config is required
  // For single-config generators (Ninja, Unix Makefiles), CMAKE_BUILD_TYPE is used instead
  final isMultiConfig = config.generator != null && 
      (config.generator!.contains('Visual Studio') || 
       config.generator!.contains('Xcode'));
  
  if (isMultiConfig) {
    // For multi-config generators, use --config flag
    // Extract build type from variables if CMAKE_BUILD_TYPE is set
    final buildType = config.variables['CMAKE_BUILD_TYPE'] ?? BuildConfig.buildType;
    buildArgs.addAll(['--config', buildType]);
  }

  if (config.target != null) {
    buildArgs.addAll(['--target', config.target!]);
  }

  final jobs = config.parallelJobs ?? getCpuCores();
  buildArgs.addAll(['--parallel', jobs.toString()]);

  await runProcessStreaming(
    cmake,
    buildArgs,
    onStdout: (line) => stdout.write(line),
    onStderr: (line) => stderr.write(line),
  );

  print('CMake build complete!');
}

/// Build Android native library for a specific ABI
Future<void> buildAndroidAbi(String abi, {
  String? ndkPath,
  String? sourceDir,
}) async {
  final buildDir = path.join(getBuildDir(), 'android-$abi');
  final source = sourceDir ?? path.join(getRepoRoot(), 'src');
  final ndk = ndkPath ?? _detectAndroidNDK();

  // Find NDK toolchain
  final toolchainFile = path.join(ndk, 'build', 'cmake', 'android.toolchain.cmake');
  if (!fileExists(toolchainFile)) {
    throw Exception('Android NDK toolchain not found: $toolchainFile');
  }

  final variables = <String, String>{
    'CMAKE_TOOLCHAIN_FILE': toolchainFile,
    'ANDROID_ABI': abi,
    'ANDROID_PLATFORM': 'android-${BuildConfig.androidMinSdk}',
    'ANDROID_NDK': ndk,
    'CMAKE_BUILD_TYPE': BuildConfig.buildType,
    'ANDROID': 'ON',
  };

  await buildWithCMake(CMakeBuildConfig(
    sourceDir: source,
    buildDir: buildDir,
    variables: variables,
    generator: 'Ninja',
  ));

  // Copy output library
  final outputDir = path.join(getBuildDir(), 'agus-binaries-android', abi);
  await ensureDir(outputDir);

  final libPath = path.join(buildDir, 'libagus_maps_flutter.so');
  if (fileExists(libPath)) {
    await copyPath(libPath, path.join(outputDir, 'libagus_maps_flutter.so'));
    print('Copied library to $outputDir');
  } else {
    throw Exception('Build output not found: $libPath');
  }
}

/// Build iOS XCFramework (device + simulator)
Future<void> buildiOSXCFramework({
  String? sourceDir,
}) async {
  final comapsDir = sourceDir ?? getComapsDir();
  final buildDir = path.join(getBuildDir(), 'ios');
  final outputDir = path.join(getBuildDir(), 'agus-binaries-ios');

  // Get SDK paths
  final deviceSdkResult = await Process.run('xcrun', ['--sdk', 'iphoneos', '--show-sdk-path']);
  final simSdkResult = await Process.run('xcrun', ['--sdk', 'iphonesimulator', '--show-sdk-path']);

  if (deviceSdkResult.exitCode != 0 || simSdkResult.exitCode != 0) {
    throw Exception('Failed to get iOS SDK paths');
  }

  final deviceSdk = deviceSdkResult.stdout.toString().trim();
  final simSdk = simSdkResult.stdout.toString().trim();

  // Build for device (arm64)
  final deviceBuildDir = path.join(buildDir, 'iphoneos');
  print('Building for iOS device (arm64)...');
  await buildWithCMake(CMakeBuildConfig(
    sourceDir: comapsDir,
    buildDir: deviceBuildDir,
    variables: {
      'CMAKE_BUILD_TYPE': BuildConfig.buildType,
      'CMAKE_SYSTEM_NAME': 'iOS',
      'CMAKE_OSX_ARCHITECTURES': 'arm64',
      'CMAKE_OSX_SYSROOT': deviceSdk,
      'CMAKE_OSX_DEPLOYMENT_TARGET': BuildConfig.iosDeploymentTarget,
      'PLATFORM_IPHONE': 'ON',
      'PLATFORM_DESKTOP': 'OFF',
      'SKIP_TESTS': 'ON',
      'SKIP_QT': 'ON',
      'SKIP_QT_GUI': 'ON',
      'SKIP_TOOLS': 'ON',
      'SKIP_PROTOBUF_CHECK': 'ON',
      'WITH_SYSTEM_PROVIDED_3PARTY': 'OFF',
    },
    generator: 'Ninja',
  ));

  // Build for simulator (arm64 + x86_64)
  final simBuildDir = path.join(buildDir, 'iphonesimulator');
  print('Building for iOS simulator (arm64, x86_64)...');
  await buildWithCMake(CMakeBuildConfig(
    sourceDir: comapsDir,
    buildDir: simBuildDir,
    variables: {
      'CMAKE_BUILD_TYPE': BuildConfig.buildType,
      'CMAKE_SYSTEM_NAME': 'iOS',
      'CMAKE_OSX_ARCHITECTURES': 'arm64;x86_64',
      'CMAKE_OSX_SYSROOT': simSdk,
      'CMAKE_OSX_DEPLOYMENT_TARGET': BuildConfig.iosDeploymentTarget,
      'PLATFORM_IPHONE': 'ON',
      'PLATFORM_DESKTOP': 'OFF',
      'SKIP_TESTS': 'ON',
      'SKIP_QT': 'ON',
      'SKIP_QT_GUI': 'ON',
      'SKIP_TOOLS': 'ON',
      'SKIP_PROTOBUF_CHECK': 'ON',
      'WITH_SYSTEM_PROVIDED_3PARTY': 'OFF',
    },
    generator: 'Ninja',
  ));

  // Merge static libraries and create XCFramework
  await _createiOSXCFramework(deviceBuildDir, simBuildDir, outputDir);
}

/// Create iOS XCFramework from device and simulator builds
Future<void> _createiOSXCFramework(String deviceBuildDir, String simBuildDir, String outputDir) async {
  // Create temporary directories for merged libraries (separate to avoid overwriting)
  final tempDir = path.join(outputDir, 'temp');
  final deviceTempDir = path.join(tempDir, 'iphoneos');
  final simTempDir = path.join(tempDir, 'iphonesimulator');
  await ensureDir(deviceTempDir);
  await ensureDir(simTempDir);

  // Merge static libraries for device (same filename but different directory)
  final deviceLibs = await _findStaticLibraries(deviceBuildDir);
  final deviceMerged = path.join(deviceTempDir, 'libcomaps.a');
  await _mergeStaticLibraries(deviceLibs, deviceMerged);

  // Merge static libraries for simulator (same filename but different directory)
  final simLibs = await _findStaticLibraries(simBuildDir);
  final simMerged = path.join(simTempDir, 'libcomaps.a');
  await _mergeStaticLibraries(simLibs, simMerged);

  // Create XCFramework with the same library name (CocoaPods requirement)
  // Both libraries must have the same name 'libcomaps.a' but in different directories
  final xcframeworkPath = path.join(outputDir, 'CoMaps.xcframework');
  await runProcess('xcodebuild', [
    '-create-xcframework',
    '-library', deviceMerged,
    '-library', simMerged,
    '-output', xcframeworkPath,
  ]);

  // Clean up temp directory
  final tempDirObj = Directory(tempDir);
  if (await tempDirObj.exists()) {
    await tempDirObj.delete(recursive: true);
  }

  print('Created XCFramework: $xcframeworkPath');
}

/// Build macOS XCFramework (arm64 + x86_64 universal)
Future<void> buildMacOSXCFramework({
  String? sourceDir,
}) async {
  final comapsDir = sourceDir ?? getComapsDir();
  final buildDir = path.join(getBuildDir(), 'macos');
  final outputDir = path.join(getBuildDir(), 'agus-binaries-macos');

  // Get macOS SDK path
  final sdkResult = await Process.run('xcrun', ['--sdk', 'macosx', '--show-sdk-path']);
  if (sdkResult.exitCode != 0) {
    throw Exception('Failed to get macOS SDK path');
  }
  final sdkPath = sdkResult.stdout.toString().trim();

  // Build for arm64
  final arm64BuildDir = path.join(buildDir, 'arm64');
  print('Building for macOS arm64...');
  await buildWithCMake(CMakeBuildConfig(
    sourceDir: comapsDir,
    buildDir: arm64BuildDir,
    variables: {
      'CMAKE_BUILD_TYPE': BuildConfig.buildType,
      'CMAKE_SYSTEM_NAME': 'Darwin',
      'CMAKE_OSX_ARCHITECTURES': 'arm64',
      'CMAKE_OSX_SYSROOT': sdkPath,
      'CMAKE_OSX_DEPLOYMENT_TARGET': BuildConfig.macOSDeploymentTarget,
      'PLATFORM_IPHONE': 'OFF',
      'PLATFORM_DESKTOP': 'ON',
      'SKIP_TESTS': 'ON',
      'SKIP_QT': 'ON',
      'SKIP_QT_GUI': 'ON',
      'SKIP_TOOLS': 'ON',
      'SKIP_PROTOBUF_CHECK': 'ON',
      'WITH_SYSTEM_PROVIDED_3PARTY': 'OFF',
    },
    generator: 'Ninja',
    target: 'map',
  ));

  // Build for x86_64
  final x64BuildDir = path.join(buildDir, 'x86_64');
  print('Building for macOS x86_64...');
  await buildWithCMake(CMakeBuildConfig(
    sourceDir: comapsDir,
    buildDir: x64BuildDir,
    variables: {
      'CMAKE_BUILD_TYPE': BuildConfig.buildType,
      'CMAKE_SYSTEM_NAME': 'Darwin',
      'CMAKE_OSX_ARCHITECTURES': 'x86_64',
      'CMAKE_OSX_SYSROOT': sdkPath,
      'CMAKE_OSX_DEPLOYMENT_TARGET': BuildConfig.macOSDeploymentTarget,
      'PLATFORM_IPHONE': 'OFF',
      'PLATFORM_DESKTOP': 'ON',
      'SKIP_TESTS': 'ON',
      'SKIP_QT': 'ON',
      'SKIP_QT_GUI': 'ON',
      'SKIP_TOOLS': 'ON',
      'SKIP_PROTOBUF_CHECK': 'ON',
      'WITH_SYSTEM_PROVIDED_3PARTY': 'OFF',
    },
    generator: 'Ninja',
    target: 'map',
  ));

  // Merge static libraries and create universal binary
  await _createMacOSXCFramework(arm64BuildDir, x64BuildDir, outputDir);
}

/// Create macOS XCFramework from arm64 and x86_64 builds
Future<void> _createMacOSXCFramework(String arm64BuildDir, String x64BuildDir, String outputDir) async {
  await ensureDir(outputDir);

  // Merge static libraries for arm64
  final arm64Libs = await _findStaticLibraries(arm64BuildDir);
  final arm64Merged = path.join(outputDir, 'libcomaps-arm64.a');
  await _mergeStaticLibraries(arm64Libs, arm64Merged);

  // Merge static libraries for x86_64
  final x64Libs = await _findStaticLibraries(x64BuildDir);
  final x64Merged = path.join(outputDir, 'libcomaps-x86_64.a');
  await _mergeStaticLibraries(x64Libs, x64Merged);

  // Create universal binary
  final universalLib = path.join(outputDir, 'libcomaps.a');
  await runProcess('lipo', [
    '-create',
    arm64Merged,
    x64Merged,
    '-output',
    universalLib,
  ]);

  // Create XCFramework
  final xcframeworkPath = path.join(outputDir, 'CoMaps.xcframework');
  await runProcess('xcodebuild', [
    '-create-xcframework',
    '-library', universalLib,
    '-output', xcframeworkPath,
  ]);

  print('Created XCFramework: $xcframeworkPath');
}

/// Build Windows native library
Future<void> buildWindowsLibrary({
  String? sourceDir,
  String? vcpkgRoot,
}) async {
  final source = sourceDir ?? path.join(getRepoRoot(), 'src');
  final buildDir = path.join(getBuildDir(), 'windows-x64');
  final outputDir = path.join(getBuildDir(), 'agus-binaries-windows', 'x64');
  final vcpkg = vcpkgRoot ?? _detectVcpkg();

  final toolchainFile = path.join(vcpkg, 'scripts', 'buildsystems', 'vcpkg.cmake');
  if (!fileExists(toolchainFile)) {
    throw Exception('vcpkg toolchain not found: $toolchainFile');
  }

  // On Windows, prefer Visual Studio generator to avoid GCC/MinGW compatibility issues
  // (ICU has known issues with newer GCC versions like 15.2.0)
  String? generator;
  if (Platform.isWindows) {
    // Use Visual Studio generator on Windows to avoid GCC/MinGW issues
    generator = 'Visual Studio 17 2022';
  } else {
    // On other platforms, use Ninja if available
    if (await commandExists('ninja')) {
      generator = 'Ninja';
    } else {
      generator = 'Unix Makefiles';
    }
  }

  final repoRoot = getRepoRoot();
  final vcpkgInstalledDir = path.join(repoRoot, 'vcpkg_installed');
  final variables = <String, String>{
    'CMAKE_TOOLCHAIN_FILE': toolchainFile,
    'VCPKG_TARGET_TRIPLET': 'x64-windows',
    // Use project-local vcpkg manifest and installed packages
    // This ensures vcpkg uses vcpkg.json from repo root and installs to vcpkg_installed/
    'VCPKG_MANIFEST_DIR': repoRoot,
    'VCPKG_INSTALLED_DIR': vcpkgInstalledDir,
    'CMAKE_BUILD_TYPE': BuildConfig.buildType,
    // Disable ccache on Windows
    'CMAKE_C_COMPILER_LAUNCHER': '',
    'CMAKE_CXX_COMPILER_LAUNCHER': '',
  };

  await buildWithCMake(CMakeBuildConfig(
    sourceDir: source,
    buildDir: buildDir,
    variables: variables,
    generator: generator,
  ));

  // Copy output DLL
  await ensureDir(outputDir);
  final dllName = 'agus_maps_flutter.dll';
  // Visual Studio generator uses multi-config, so DLL is in buildDir/Release/ or buildDir/Debug/
  // Ninja generator uses single-config, so DLL is in buildDir/ (CMAKE_BUILD_TYPE sets the location)
  final buildType = BuildConfig.buildType; // Release or Debug
  final dllPaths = [
    path.join(buildDir, buildType, dllName), // Visual Studio: buildDir/Release/ or buildDir/Debug/
    path.join(buildDir, dllName), // Ninja/single-config: buildDir/
  ];

  var dllCopied = false;
  for (final dllPath in dllPaths) {
    if (fileExists(dllPath)) {
      await copyPath(dllPath, path.join(outputDir, dllName));
      print('Copied DLL to $outputDir');
      dllCopied = true;
      break;
    }
  }

  if (!dllCopied) {
    throw Exception('Build output not found: $dllName');
  }

  // Copy zlib1.dll runtime dependency from vcpkg
  // This DLL is required at runtime by agus_maps_flutter.dll
  final zlibDllPaths = [
    // Manifest mode: vcpkg_installed/x64-windows/bin/zlib1.dll
    path.join(vcpkgInstalledDir, 'x64-windows', 'bin', 'zlib1.dll'),
    // Classic mode: vcpkg/installed/x64-windows/bin/zlib1.dll
    path.join(vcpkg, 'installed', 'x64-windows', 'bin', 'zlib1.dll'),
  ];

  var zlibCopied = false;
  for (final zlibPath in zlibDllPaths) {
    if (fileExists(zlibPath)) {
      await copyPath(zlibPath, path.join(outputDir, 'zlib1.dll'));
      print('Copied zlib1.dll to $outputDir');
      zlibCopied = true;
      break;
    }
  }

  if (!zlibCopied) {
    print('Warning: zlib1.dll not found - app may fail at runtime');
    print('Searched locations:');
    for (final p in zlibDllPaths) {
      print('  - $p');
    }
  }
}

/// Build Linux native library
Future<void> buildLinuxLibrary({
  String? sourceDir,
}) async {
  final repoRoot = getRepoRoot();
  final source = sourceDir ?? path.join(repoRoot, 'src');
  final buildDir = path.join(getBuildDir(), 'linux');
  final outputDir = path.join(getBuildDir(), 'agus-binaries-linux', 'x64');

  final variables = <String, String>{
    'CMAKE_BUILD_TYPE': BuildConfig.buildType,
  };

  await buildWithCMake(CMakeBuildConfig(
    sourceDir: source,
    buildDir: buildDir,
    variables: variables,
    generator: 'Ninja',
  ));

  // Copy output library
  await ensureDir(outputDir);
  final libPath = path.join(buildDir, 'libagus_maps_flutter.so');
  if (fileExists(libPath)) {
    await copyPath(libPath, path.join(outputDir, 'libagus_maps_flutter.so'));
    print('Copied library to $outputDir');
  } else {
    throw Exception('Build output not found: $libPath');
  }
}

/// Find all static libraries in a build directory
Future<List<String>> _findStaticLibraries(String buildDir) async {
  final libs = <String>[];
  final dir = Directory(buildDir);

  if (!await dir.exists()) {
    return libs;
  }

  await for (final entity in dir.list(recursive: true)) {
    if (entity is File && entity.path.endsWith('.a')) {
      // Skip CMakeFiles directories
      if (!entity.path.contains('CMakeFiles')) {
        libs.add(entity.path);
      }
    }
  }

  return libs;
}

/// Merge static libraries using libtool (macOS/iOS) or ar (Linux)
Future<void> _mergeStaticLibraries(List<String> libs, String output) async {
  if (libs.isEmpty) {
    throw Exception('No static libraries found to merge');
  }

  final os = detectOS();
  if (os == OSType.macos || os == OSType.linux) {
    // Use libtool on macOS/iOS, ar on Linux
    final tool = os == OSType.macos ? 'libtool' : 'ar';
    final args = os == OSType.macos
        ? ['-static', '-o', output, ...libs]
        : ['cr', output, ...libs];

    await runProcess(tool, args);
  } else {
    throw UnsupportedError('Merging static libraries not supported on Windows');
  }
}

/// Detect Android NDK path
String _detectAndroidNDK() {
  // Check environment variable first
  final envNdkPath = Platform.environment['ANDROID_NDK_HOME'] ?? 
      Platform.environment['ANDROID_NDK'];
  if (envNdkPath != null && envNdkPath.isNotEmpty && dirExists(envNdkPath)) {
    print('Using NDK from environment: $envNdkPath');
    return envNdkPath;
  }
  
  final androidHome = Platform.environment['ANDROID_HOME'] ??
      Platform.environment['ANDROID_SDK_ROOT'] ??
      (Platform.isMacOS ? path.join(Platform.environment['HOME']!, 'Library', 'Android', 'sdk') : 
       Platform.isLinux ? path.join(Platform.environment['HOME']!, 'Android', 'Sdk') :
       Platform.isWindows ? path.join(Platform.environment['LOCALAPPDATA'] ?? '', 'Android', 'Sdk') : '');
  
  if (androidHome.isEmpty || !dirExists(androidHome)) {
    throw Exception('ANDROID_HOME not set or not found. Set ANDROID_HOME or ANDROID_SDK_ROOT environment variable.');
  }

  final ndkDir = path.join(androidHome, 'ndk');
  
  // First try the configured version
  final preferredNdk = path.join(ndkDir, BuildConfig.ndkVersion);
  if (dirExists(preferredNdk)) {
    return preferredNdk;
  }

  // Auto-detect installed NDK versions
  final ndkDirectory = Directory(ndkDir);
  if (!ndkDirectory.existsSync()) {
    throw Exception('Android NDK directory not found: $ndkDir\nInstall NDK via Android Studio SDK Manager.');
  }

  final installedNdks = ndkDirectory
      .listSync()
      .whereType<Directory>()
      .map((d) => path.basename(d.path))
      .where((name) => RegExp(r'^\d+\.\d+\.\d+$').hasMatch(name))
      .toList()
    ..sort((a, b) => compareVersions(b, a)); // Sort descending (newest first)

  if (installedNdks.isEmpty) {
    throw Exception('No Android NDK versions found in: $ndkDir\n'
        'Install NDK via Android Studio SDK Manager.\n'
        'Preferred version: ${BuildConfig.ndkVersion}');
  }

  // Use the newest available NDK
  final selectedNdk = installedNdks.first;
  final selectedPath = path.join(ndkDir, selectedNdk);
  
  if (selectedNdk != BuildConfig.ndkVersion) {
    print('Note: Using NDK $selectedNdk (configured: ${BuildConfig.ndkVersion})');
  }
  
  return selectedPath;
}

/// Detect vcpkg path
String _detectVcpkg() {
  final vcpkgRoot = Platform.environment['VCPKG_ROOT'] ?? 
      (Platform.isWindows ? 'C:\\vcpkg' : '/usr/local/vcpkg');
  if (!dirExists(vcpkgRoot)) {
    throw Exception('vcpkg not found at: $vcpkgRoot');
  }
  return vcpkgRoot;
}
