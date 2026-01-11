#!/usr/bin/env dart
// Main build tool entry point for contributors
// Usage: dart run tool/build.dart [options]

import 'dart:io';
import 'package:args/args.dart';

import 'src/build_runner.dart' show runBuild, BuildRunnerConfig;
import 'src/config.dart' show detectBuildMode;

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addFlag(
      'build-binaries',
      abbr: 'b',
      defaultsTo: false,
      help: 'Build native binaries for all platforms',
    )
    ..addFlag(
      'skip-patches',
      defaultsTo: false,
      help: 'Skip applying patches',
    )
    ..addFlag(
      'no-cache',
      defaultsTo: false,
      help: 'Disable caching',
    )
    ..addMultiOption(
      'platform',
      abbr: 'p',
      allowed: ['android', 'ios', 'macos', 'windows', 'linux'],
      help: 'Build specific platforms (can specify multiple)',
    )
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Show this help message',
    );

  try {
    final results = parser.parse(args);

    if (results['help'] as bool) {
      print('Agus Maps Flutter - Build Tool');
      print('');
      print('Usage: dart run tool/build.dart [options]');
      print('');
      print('Options:');
      print(parser.usage);
      print('');
      print('Examples:');
      print('  dart run tool/build.dart');
      print('    Bootstrap CoMaps and prepare for building');
      print('');
      print('  dart run tool/build.dart --build-binaries');
      print('    Bootstrap and build native binaries for all platforms');
      print('');
      print('  dart run tool/build.dart --build-binaries --platform android --platform ios');
      print('    Build only Android and iOS binaries');
      exit(0);
    }

    // Detect build mode
    final buildMode = detectBuildMode();

    // Create build configuration
    final config = BuildRunnerConfig(
      mode: buildMode,
      buildBinaries: results['build-binaries'] as bool,
      skipPatches: results['skip-patches'] as bool,
      noCache: results['no-cache'] as bool,
      platforms: results['platform'] as List<String>?,
    );

    // Run build
    await runBuild(config);

    exit(0);
  } on FormatException catch (e) {
    stderr.writeln('Error: ${e.message}');
    stderr.writeln('');
    stderr.writeln('Run with --help for usage information');
    exit(1);
  } catch (e, stackTrace) {
    stderr.writeln('Error: $e');
    if (Platform.environment['DEBUG'] == 'true') {
      stderr.writeln('Stack trace:');
      stderr.writeln(stackTrace);
    }
    exit(1);
  }
}
