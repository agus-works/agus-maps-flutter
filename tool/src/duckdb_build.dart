// DuckDB build orchestration for embedded persistence and analytics layers

import 'dart:io';
import 'dart:convert';

import 'package:path/path.dart' as path;

import 'cmake_build.dart' show CMakeBuildConfig, buildWithCMake;
import 'config.dart' show BuildConfig;
import 'file_operations.dart' show copyPath, dirExists, ensureDir, fileExists;
import 'platform_detector.dart'
    show getBuildDir, getDuckdbDir, getDuckdbSpatialDir, getRepoRoot;
import 'process_runner.dart' show commandExists, runProcess;

const List<String> _requiredDuckDBExtensions = [
  'core_functions',
  'parquet',
  'json',
  'icu',
  'httpfs',
  'spatial',
];

/// Build DuckDB for macOS as a static XCFramework.
Future<void> buildDuckDBMacOSXCFramework({
  String? duckdbDir,
  String? duckdbSpatialDir,
  String? vcpkgRoot,
}) async {
  if (!Platform.isMacOS) {
    throw UnsupportedError(
        'DuckDB macOS XCFrameworks can only be built on macOS');
  }

  final duckdbSourceDir = duckdbDir ?? getDuckdbDir();
  final spatialSourceDir = duckdbSpatialDir ?? getDuckdbSpatialDir();
  final extensionConfig = _getExtensionConfigPath();
  _validateDuckDBInputs(duckdbSourceDir, spatialSourceDir, extensionConfig);

  final resolvedVcpkgRoot = vcpkgRoot ?? await _detectVcpkgRoot();
  final toolchainFile = path.join(
    resolvedVcpkgRoot,
    'scripts',
    'buildsystems',
    'vcpkg.cmake',
  );
  if (!fileExists(toolchainFile)) {
    throw Exception('vcpkg toolchain not found: $toolchainFile');
  }

  print('=== Build DuckDB macOS XCFramework ===');
  print('DuckDB source: $duckdbSourceDir');
  print('duckdb-spatial source: $spatialSourceDir');
  print('DuckDB extensions: ${_requiredDuckDBExtensions.join(', ')}');
  print('vcpkg root: $resolvedVcpkgRoot');

  final manifestDir = await _generateDuckDBVcpkgManifest(
    duckdbSourceDir: duckdbSourceDir,
    spatialSourceDir: spatialSourceDir,
    extensionConfig: extensionConfig,
  );
  await _ensureVcpkgBaselineAvailable(resolvedVcpkgRoot, manifestDir);

  final sdkPath = await _getMacOSSDKPath();
  final installedDir = path.join(getBuildDir(), 'duckdb-vcpkg-installed');
  final buildRoot = path.join(getBuildDir(), 'duckdb', 'macos');
  final outputDir = path.join(getBuildDir(), 'agus-binaries-macos');

  final arm64Archive = await _buildDuckDBMacOSArch(
    arch: 'arm64',
    triplet: 'arm64-osx',
    duckdbSourceDir: duckdbSourceDir,
    spatialSourceDir: spatialSourceDir,
    extensionConfig: extensionConfig,
    manifestDir: manifestDir,
    installedDir: installedDir,
    toolchainFile: toolchainFile,
    sdkPath: sdkPath,
    buildRoot: buildRoot,
  );

  final x64Archive = await _buildDuckDBMacOSArch(
    arch: 'x86_64',
    triplet: 'x64-osx',
    duckdbSourceDir: duckdbSourceDir,
    spatialSourceDir: spatialSourceDir,
    extensionConfig: extensionConfig,
    manifestDir: manifestDir,
    installedDir: installedDir,
    toolchainFile: toolchainFile,
    sdkPath: sdkPath,
    buildRoot: buildRoot,
  );

  await _createDuckDBMacOSXCFramework(
    arm64Archive: arm64Archive,
    x64Archive: x64Archive,
    outputDir: outputDir,
    duckdbSourceDir: duckdbSourceDir,
  );
}

/// Build DuckDB for iOS as a static XCFramework.
Future<void> buildDuckDBiOSXCFramework({
  String? duckdbDir,
  String? duckdbSpatialDir,
  String? vcpkgRoot,
}) async {
  if (!Platform.isMacOS) {
    throw UnsupportedError(
        'DuckDB iOS XCFrameworks can only be built on macOS');
  }

  final duckdbSourceDir = duckdbDir ?? getDuckdbDir();
  final spatialSourceDir = duckdbSpatialDir ?? getDuckdbSpatialDir();
  final extensionConfig = _getExtensionConfigPath();
  _validateDuckDBInputs(duckdbSourceDir, spatialSourceDir, extensionConfig);

  final resolvedVcpkgRoot = vcpkgRoot ?? await _detectVcpkgRoot();
  final toolchainFile = path.join(
    resolvedVcpkgRoot,
    'scripts',
    'buildsystems',
    'vcpkg.cmake',
  );
  if (!fileExists(toolchainFile)) {
    throw Exception('vcpkg toolchain not found: $toolchainFile');
  }

  print('=== Build DuckDB iOS XCFramework ===');
  print('DuckDB source: $duckdbSourceDir');
  print('duckdb-spatial source: $spatialSourceDir');
  print('DuckDB extensions: ${_requiredDuckDBExtensions.join(', ')}');
  print('vcpkg root: $resolvedVcpkgRoot');

  final manifestDir = await _generateDuckDBVcpkgManifest(
    duckdbSourceDir: duckdbSourceDir,
    spatialSourceDir: spatialSourceDir,
    extensionConfig: extensionConfig,
  );
  await _ensureVcpkgBaselineAvailable(resolvedVcpkgRoot, manifestDir);

  final deviceSdkPath = await _getAppleSDKPath('iphoneos');
  final simulatorSdkPath = await _getAppleSDKPath('iphonesimulator');
  final installedDir = path.join(getBuildDir(), 'duckdb-vcpkg-installed-ios');
  final buildRoot = path.join(getBuildDir(), 'duckdb', 'ios');
  final outputDir = path.join(getBuildDir(), 'agus-binaries-ios');
  final tripletsDir = await _writeDuckDBIOSTriplets(buildRoot);

  final deviceArchive = await _buildDuckDBAppleArch(
    platformLabel: 'iOS device',
    arch: 'arm64',
    triplet: 'arm64-ios-agus',
    archiveName: 'libagus_duckdb_iphoneos_arm64.a',
    duckdbSourceDir: duckdbSourceDir,
    spatialSourceDir: spatialSourceDir,
    extensionConfig: extensionConfig,
    manifestDir: manifestDir,
    installedDir: installedDir,
    toolchainFile: toolchainFile,
    sdkPath: deviceSdkPath,
    deploymentTarget: BuildConfig.iosDeploymentTarget,
    buildDir: path.join(buildRoot, 'iphoneos-arm64'),
    systemName: 'iOS',
    systemProcessor: 'aarch64',
    duckdbPlatform: 'ios_arm64',
    overlayTripletsDir: tripletsDir,
  );

  final simulatorArm64Archive = await _buildDuckDBAppleArch(
    platformLabel: 'iOS simulator',
    arch: 'arm64',
    triplet: 'arm64-ios-simulator-agus',
    archiveName: 'libagus_duckdb_iphonesimulator_arm64.a',
    duckdbSourceDir: duckdbSourceDir,
    spatialSourceDir: spatialSourceDir,
    extensionConfig: extensionConfig,
    manifestDir: manifestDir,
    installedDir: installedDir,
    toolchainFile: toolchainFile,
    sdkPath: simulatorSdkPath,
    deploymentTarget: BuildConfig.iosDeploymentTarget,
    buildDir: path.join(buildRoot, 'iphonesimulator-arm64'),
    systemName: 'iOS',
    systemProcessor: 'aarch64',
    duckdbPlatform: 'ios_simulator_arm64',
    overlayTripletsDir: tripletsDir,
  );

  final simulatorX64Archive = await _buildDuckDBAppleArch(
    platformLabel: 'iOS simulator',
    arch: 'x86_64',
    triplet: 'x64-ios-simulator-agus',
    archiveName: 'libagus_duckdb_iphonesimulator_x86_64.a',
    duckdbSourceDir: duckdbSourceDir,
    spatialSourceDir: spatialSourceDir,
    extensionConfig: extensionConfig,
    manifestDir: manifestDir,
    installedDir: installedDir,
    toolchainFile: toolchainFile,
    sdkPath: simulatorSdkPath,
    deploymentTarget: BuildConfig.iosDeploymentTarget,
    buildDir: path.join(buildRoot, 'iphonesimulator-x86_64'),
    systemName: 'iOS',
    systemProcessor: 'x86_64',
    duckdbPlatform: 'ios_simulator_amd64',
    overlayTripletsDir: tripletsDir,
  );

  await _createDuckDBiOSXCFramework(
    deviceArchive: deviceArchive,
    simulatorArm64Archive: simulatorArm64Archive,
    simulatorX64Archive: simulatorX64Archive,
    outputDir: outputDir,
    duckdbSourceDir: duckdbSourceDir,
  );
}

String _getExtensionConfigPath() {
  return path.join(
      getRepoRoot(), 'tool', 'duckdb', 'agus_duckdb_extensions.cmake');
}

void _validateDuckDBInputs(
  String duckdbSourceDir,
  String spatialSourceDir,
  String extensionConfig,
) {
  if (!dirExists(duckdbSourceDir)) {
    throw Exception('DuckDB source directory not found: $duckdbSourceDir');
  }
  if (!dirExists(spatialSourceDir)) {
    throw Exception(
        'duckdb-spatial source directory not found: $spatialSourceDir');
  }
  if (!fileExists(extensionConfig)) {
    throw Exception('DuckDB extension config not found: $extensionConfig');
  }
}

Future<String> _detectVcpkgRoot() async {
  final envRoot = Platform.environment['VCPKG_ROOT'];
  if (envRoot != null && envRoot.isNotEmpty && dirExists(envRoot)) {
    return envRoot;
  }

  if (await commandExists('vcpkg')) {
    final result = await runProcess(
      Platform.isWindows ? 'where' : 'which',
      ['vcpkg'],
      throwOnError: false,
    );
    if (result.exitCode == 0) {
      final executable =
          result.stdout.toString().split(RegExp(r'\r?\n')).first.trim();
      if (executable.isNotEmpty) {
        return path.dirname(executable);
      }
    }
  }

  final home = Platform.environment['HOME'];
  final candidates = <String>[
    if (home != null) path.join(home, 'vcpkg'),
    '/opt/vcpkg',
    '/usr/local/vcpkg',
  ];
  for (final candidate in candidates) {
    if (dirExists(candidate)) return candidate;
  }

  throw Exception(
    'vcpkg is required to build DuckDB spatial dependencies. '
    'Install vcpkg and set VCPKG_ROOT before building DuckDB.',
  );
}

Future<String> _generateDuckDBVcpkgManifest({
  required String duckdbSourceDir,
  required String spatialSourceDir,
  required String extensionConfig,
}) async {
  print('Generating DuckDB merged vcpkg manifest...');

  final buildDir = path.join(getBuildDir(), 'duckdb-extension-configuration');
  final duckdbManifestDir =
      path.join(duckdbSourceDir, 'build', 'extension_configuration');
  await ensureDir(duckdbManifestDir);

  await buildWithCMake(CMakeBuildConfig(
    sourceDir: duckdbSourceDir,
    buildDir: buildDir,
    variables: {
      'CMAKE_BUILD_TYPE': 'Debug',
      'DUCKDB_EXTENSION_CONFIGS': extensionConfig,
      'AGUS_DUCKDB_SPATIAL_SOURCE_DIR': spatialSourceDir,
      'EXTENSION_CONFIG_BUILD': 'TRUE',
      'VCPKG_BUILD': '1',
      'BUILD_SHELL': 'OFF',
      'BUILD_UNITTESTS': 'OFF',
      'BUILD_BENCHMARKS': 'OFF',
    },
    generator: 'Ninja',
    target: 'duckdb_merge_vcpkg_manifests',
  ));

  final manifestPath = path.join(duckdbManifestDir, 'vcpkg.json');
  if (!fileExists(manifestPath)) {
    throw Exception(
        'DuckDB merged vcpkg manifest was not generated: $manifestPath');
  }

  return duckdbManifestDir;
}

Future<void> _ensureVcpkgBaselineAvailable(
  String vcpkgRoot,
  String manifestDir,
) async {
  final gitDir = path.join(vcpkgRoot, '.git');
  if (!dirExists(gitDir)) return;

  final manifestPath = path.join(manifestDir, 'vcpkg.json');
  final manifest = jsonDecode(await File(manifestPath).readAsString()) as Map;
  final baseline = manifest['builtin-baseline'] as String?;
  if (baseline == null || baseline.isEmpty) return;

  final exists = await runProcess(
    'git',
    ['cat-file', '-e', '$baseline^{commit}'],
    workingDirectory: vcpkgRoot,
    throwOnError: false,
  );
  if (exists.exitCode == 0) return;

  print('Fetching vcpkg baseline required by DuckDB spatial: $baseline');
  await runProcess(
    'git',
    ['fetch', 'origin', baseline, '--depth=1'],
    workingDirectory: vcpkgRoot,
  );
}

Future<String> _getMacOSSDKPath() async {
  return _getAppleSDKPath('macosx');
}

Future<String> _getAppleSDKPath(String sdk) async {
  final result = await runProcess('xcrun', ['--sdk', sdk, '--show-sdk-path']);
  return result.stdout.toString().trim();
}

Future<String> _buildDuckDBMacOSArch({
  required String arch,
  required String triplet,
  required String duckdbSourceDir,
  required String spatialSourceDir,
  required String extensionConfig,
  required String manifestDir,
  required String installedDir,
  required String toolchainFile,
  required String sdkPath,
  required String buildRoot,
}) async {
  return _buildDuckDBAppleArch(
    platformLabel: 'macOS',
    arch: arch,
    triplet: triplet,
    archiveName: 'libagus_duckdb_$arch.a',
    duckdbSourceDir: duckdbSourceDir,
    spatialSourceDir: spatialSourceDir,
    extensionConfig: extensionConfig,
    manifestDir: manifestDir,
    installedDir: installedDir,
    toolchainFile: toolchainFile,
    sdkPath: sdkPath,
    deploymentTarget: BuildConfig.macOSDeploymentTarget,
    buildDir: path.join(buildRoot, arch),
  );
}

Future<String> _buildDuckDBAppleArch({
  required String platformLabel,
  required String arch,
  required String triplet,
  required String archiveName,
  required String duckdbSourceDir,
  required String spatialSourceDir,
  required String extensionConfig,
  required String manifestDir,
  required String installedDir,
  required String toolchainFile,
  required String sdkPath,
  required String deploymentTarget,
  required String buildDir,
  String? systemName,
  String? systemProcessor,
  String? duckdbPlatform,
  String? overlayTripletsDir,
}) async {
  print('Building DuckDB for $platformLabel $arch...');

  final variables = <String, String>{
    'CMAKE_TOOLCHAIN_FILE': toolchainFile,
    'VCPKG_MANIFEST_DIR': manifestDir,
    'VCPKG_INSTALLED_DIR': installedDir,
    'VCPKG_TARGET_TRIPLET': triplet,
    'VCPKG_BUILD': '1',
    'CMAKE_BUILD_TYPE': BuildConfig.buildType,
    'CMAKE_OSX_ARCHITECTURES': arch,
    'CMAKE_OSX_SYSROOT': sdkPath,
    'CMAKE_OSX_DEPLOYMENT_TARGET': deploymentTarget,
    'DUCKDB_EXTENSION_CONFIGS': extensionConfig,
    'AGUS_DUCKDB_SPATIAL_SOURCE_DIR': spatialSourceDir,
    'EXTENSION_STATIC_BUILD': 'TRUE',
    'BUILD_SHELL': 'OFF',
    'BUILD_UNITTESTS': 'OFF',
    'BUILD_BENCHMARKS': 'OFF',
    'ENABLE_EXTENSION_AUTOLOADING': 'OFF',
    'ENABLE_EXTENSION_AUTOINSTALL': 'OFF',
    'OPENSSL_USE_STATIC_LIBS': 'ON',
    'ZLIB_USE_STATIC_LIBS': 'ON',
  };
  if (systemName != null) {
    variables['CMAKE_SYSTEM_NAME'] = systemName;
  }
  if (systemProcessor != null) {
    await _deleteIfExists(buildDir);
    final processorInclude = await _writeAppleProcessorInclude(buildDir);
    variables['CMAKE_SYSTEM_PROCESSOR'] = systemProcessor;
    variables['AGUS_CMAKE_SYSTEM_PROCESSOR'] = systemProcessor;
    variables['CMAKE_PROJECT_TOP_LEVEL_INCLUDES'] = processorInclude;
  }
  if (duckdbPlatform != null) {
    variables['DUCKDB_EXPLICIT_PLATFORM'] = duckdbPlatform;
  }
  if (overlayTripletsDir != null) {
    variables['VCPKG_OVERLAY_TRIPLETS'] = overlayTripletsDir;
  }

  final icuPrefixHeader = await _writeDuckDBICUPrefixHeader(
    duckdbSourceDir: duckdbSourceDir,
    buildDir: buildDir,
  );
  final forceIncludeICUPrefix = '-include $icuPrefixHeader';
  variables['CMAKE_C_FLAGS'] = forceIncludeICUPrefix;
  variables['CMAKE_CXX_FLAGS'] = forceIncludeICUPrefix;

  await buildWithCMake(CMakeBuildConfig(
    sourceDir: duckdbSourceDir,
    buildDir: buildDir,
    variables: variables,
    generator: 'Ninja',
  ));

  final archive = path.join(buildDir, archiveName);
  await _deleteIfExists(archive);
  final libs = <String>[
    ...await _findStaticLibraries(buildDir),
    ...await _findStaticLibraries(path.join(installedDir, triplet, 'lib')),
  ];

  await _mergeStaticLibraries(_dedupePaths(libs), archive);
  return archive;
}

Future<String> _writeDuckDBICUPrefixHeader({
  required String duckdbSourceDir,
  required String buildDir,
}) async {
  final urenamePath = path.join(
    duckdbSourceDir,
    'extension',
    'icu',
    'third_party',
    'icu',
    'common',
    'unicode',
    'urename.h',
  );
  if (!fileExists(urenamePath)) {
    throw Exception('DuckDB ICU rename table not found: $urenamePath');
  }

  final symbols = <String>{};
  final definePattern = RegExp(
    r'^//\s*#define\s+([A-Za-z_][A-Za-z0-9_]*)\s+'
    r'U_ICU_ENTRY_POINT_RENAME\(\1\)\s*$',
  );
  final lines = await File(urenamePath).readAsLines();
  for (final line in lines) {
    final match = definePattern.firstMatch(line);
    if (match != null) {
      symbols.add(match.group(1)!);
    }
  }
  if (symbols.isEmpty) {
    throw Exception(
        'No DuckDB ICU symbols found in rename table: $urenamePath');
  }

  final sortedSymbols = symbols.toList()..sort();
  final headerPath = path.join(buildDir, 'agus_duckdb_icu_prefix.h');
  await ensureDir(buildDir);

  final buffer = StringBuffer()
    ..writeln('#ifndef AGUS_DUCKDB_ICU_PREFIX_H')
    ..writeln('#define AGUS_DUCKDB_ICU_PREFIX_H')
    ..writeln('')
    ..writeln('#ifndef U_DISABLE_RENAMING')
    ..writeln('#define U_DISABLE_RENAMING 0')
    ..writeln('#endif')
    ..writeln('')
    ..writeln('#define AGUS_DUCKDB_ICU_RENAME(symbol) \\')
    ..writeln('  AGUS_DUCKDB_ICU_RENAME_IMPL(symbol)')
    ..writeln('#define AGUS_DUCKDB_ICU_RENAME_IMPL(symbol) \\')
    ..writeln('  agus_duckdb_icu_##symbol')
    ..writeln('')
    ..writeln('#ifdef U_ICU_ENTRY_POINT_RENAME')
    ..writeln('#undef U_ICU_ENTRY_POINT_RENAME')
    ..writeln('#endif')
    ..writeln('#define U_ICU_ENTRY_POINT_RENAME(symbol) \\')
    ..writeln('  AGUS_DUCKDB_ICU_RENAME(symbol)')
    ..writeln('');

  for (final symbol in sortedSymbols) {
    buffer
      ..writeln('#ifndef $symbol')
      ..writeln('#define $symbol U_ICU_ENTRY_POINT_RENAME($symbol)')
      ..writeln('#endif');
  }

  buffer
    ..writeln('')
    ..writeln('#endif')
    ..writeln('');

  await File(headerPath).writeAsString(buffer.toString());
  return headerPath;
}

Future<void> _createDuckDBMacOSXCFramework({
  required String arm64Archive,
  required String x64Archive,
  required String outputDir,
  required String duckdbSourceDir,
}) async {
  await ensureDir(outputDir);

  final universalArchive = path.join(outputDir, 'libagus_duckdb.a');
  await _deleteIfExists(universalArchive);
  await runProcess('lipo', [
    '-create',
    arm64Archive,
    x64Archive,
    '-output',
    universalArchive,
  ]);

  final headersDir = path.join(getBuildDir(), 'duckdb-headers');
  await _deleteIfExists(headersDir);
  await copyPath(path.join(duckdbSourceDir, 'src', 'include'), headersDir);

  final xcframeworkPath = path.join(outputDir, 'DuckDB.xcframework');
  await _deleteIfExists(xcframeworkPath);
  await runProcess('xcodebuild', [
    '-create-xcframework',
    '-library',
    universalArchive,
    '-headers',
    headersDir,
    '-output',
    xcframeworkPath,
  ]);

  print('Created DuckDB XCFramework: $xcframeworkPath');
}

Future<String> _writeAppleProcessorInclude(String buildDir) async {
  await ensureDir(buildDir);
  final includePath = path.join(buildDir, 'agus_apple_processor.cmake');
  await File(includePath).writeAsString('''
if(DEFINED AGUS_CMAKE_SYSTEM_PROCESSOR AND AGUS_CMAKE_SYSTEM_PROCESSOR)
  set(CMAKE_SYSTEM_PROCESSOR "\${AGUS_CMAKE_SYSTEM_PROCESSOR}" CACHE STRING "" FORCE)
endif()
''');
  return includePath;
}

Future<String> _writeDuckDBIOSTriplets(String buildRoot) async {
  final tripletsDir = path.join(buildRoot, 'vcpkg-triplets');
  await _deleteIfExists(tripletsDir);
  await ensureDir(tripletsDir);

  await _writeDuckDBIOSTriplet(
    tripletsDir: tripletsDir,
    name: 'arm64-ios-agus',
    architecture: 'arm64',
    simulator: false,
  );
  await _writeDuckDBIOSTriplet(
    tripletsDir: tripletsDir,
    name: 'arm64-ios-simulator-agus',
    architecture: 'arm64',
    simulator: true,
  );
  await _writeDuckDBIOSTriplet(
    tripletsDir: tripletsDir,
    name: 'x64-ios-simulator-agus',
    architecture: 'x64',
    simulator: true,
  );

  return tripletsDir;
}

Future<void> _writeDuckDBIOSTriplet({
  required String tripletsDir,
  required String name,
  required String architecture,
  required bool simulator,
}) async {
  final buffer = StringBuffer()
    ..writeln('set(VCPKG_TARGET_ARCHITECTURE $architecture)')
    ..writeln('set(VCPKG_CRT_LINKAGE dynamic)')
    ..writeln('set(VCPKG_LIBRARY_LINKAGE static)')
    ..writeln('set(VCPKG_CMAKE_SYSTEM_NAME iOS)');
  if (simulator) {
    buffer.writeln('set(VCPKG_OSX_SYSROOT iphonesimulator)');
  }
  buffer.writeln('set(VCPKG_CMAKE_CONFIGURE_OPTIONS -DHAVE_PIPE2=0)');

  await File(path.join(tripletsDir, '$name.cmake'))
      .writeAsString(buffer.toString());
}

Future<void> _createDuckDBiOSXCFramework({
  required String deviceArchive,
  required String simulatorArm64Archive,
  required String simulatorX64Archive,
  required String outputDir,
  required String duckdbSourceDir,
}) async {
  await ensureDir(outputDir);

  final tempDir = path.join(outputDir, 'duckdb-temp-ios');
  final deviceTempDir = path.join(tempDir, 'iphoneos');
  final simulatorTempDir = path.join(tempDir, 'iphonesimulator');
  await _deleteIfExists(tempDir);
  await ensureDir(deviceTempDir);
  await ensureDir(simulatorTempDir);

  final deviceLibrary = path.join(deviceTempDir, 'libagus_duckdb.a');
  final simulatorLibrary = path.join(simulatorTempDir, 'libagus_duckdb.a');
  await copyPath(deviceArchive, deviceLibrary);
  await _deleteIfExists(simulatorLibrary);
  await runProcess('lipo', [
    '-create',
    simulatorArm64Archive,
    simulatorX64Archive,
    '-output',
    simulatorLibrary,
  ]);

  final headersDir = path.join(getBuildDir(), 'duckdb-headers-ios');
  await _deleteIfExists(headersDir);
  await copyPath(path.join(duckdbSourceDir, 'src', 'include'), headersDir);

  final xcframeworkPath = path.join(outputDir, 'DuckDB.xcframework');
  await _deleteIfExists(xcframeworkPath);
  await runProcess('xcodebuild', [
    '-create-xcframework',
    '-library',
    deviceLibrary,
    '-headers',
    headersDir,
    '-library',
    simulatorLibrary,
    '-headers',
    headersDir,
    '-output',
    xcframeworkPath,
  ]);

  await _deleteIfExists(tempDir);
  print('Created DuckDB XCFramework: $xcframeworkPath');
}

Future<List<String>> _findStaticLibraries(String directory) async {
  final libs = <String>[];
  final dir = Directory(directory);
  if (!await dir.exists()) return libs;

  await for (final entity in dir.list(recursive: true)) {
    if (entity is File && entity.path.endsWith('.a')) {
      if (!entity.path
          .contains('${path.separator}CMakeFiles${path.separator}')) {
        libs.add(entity.path);
      }
    }
  }

  return libs;
}

List<String> _dedupePaths(List<String> paths) {
  final seen = <String>{};
  final deduped = <String>[];
  for (final item in paths) {
    final normalized = path.normalize(item);
    if (seen.add(normalized)) deduped.add(item);
  }
  return deduped;
}

Future<void> _mergeStaticLibraries(List<String> libs, String output) async {
  if (libs.isEmpty) {
    throw Exception('No DuckDB static libraries found to merge into $output');
  }

  await _deleteIfExists(output);
  await ensureDir(path.dirname(output));
  await runProcess('libtool', ['-static', '-o', output, ...libs]);
}

Future<void> _deleteIfExists(String targetPath) async {
  final type = await FileSystemEntity.type(targetPath);
  switch (type) {
    case FileSystemEntityType.file:
    case FileSystemEntityType.link:
      await File(targetPath).delete();
      break;
    case FileSystemEntityType.directory:
      await Directory(targetPath).delete(recursive: true);
      break;
    case FileSystemEntityType.notFound:
      break;
    default:
      throw Exception('Unsupported filesystem entity at $targetPath');
  }
}
