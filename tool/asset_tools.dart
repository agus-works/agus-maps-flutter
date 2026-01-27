#!/usr/bin/env dart
// Asset helper tool for contributors
// Usage: dart run tool/asset_tools.dart [options]

import 'dart:io';
import 'package:args/args.dart';

import 'src/assets_updater.dart'
    show syncLocalizedStringsAssets, copyDataFiles, updateFlutterAssetsList;

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addFlag(
      'copy-assets',
      abbr: 'c',
      defaultsTo: false,
      help:
          'Copy assets from thirdparty/comaps into assets/ and example/assets',
    )
    ..addFlag(
      'update-pubspec',
      abbr: 'u',
      defaultsTo: false,
      help: 'Regenerate pubspec.yaml assets list from assets/',
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
      print('Agus Maps Flutter - Asset Tool');
      print('');
      print('Usage: dart run tool/asset_tools.dart [options]');
      print('');
      print('Options:');
      print(parser.usage);
      print('');
      print('Examples:');
      print('  dart run tool/asset_tools.dart --copy-assets');
      print('  dart run tool/asset_tools.dart --update-pubspec');
      print('  dart run tool/asset_tools.dart');
      exit(0);
    }

    final copyAssets = results['copy-assets'] as bool;
    final updatePubspec = results['update-pubspec'] as bool;

    if (!copyAssets && !updatePubspec) {
      await syncLocalizedStringsAssets();
      await copyDataFiles();
      await updateFlutterAssetsList();
      exit(0);
    }

    if (copyAssets) {
      await syncLocalizedStringsAssets();
      await copyDataFiles();
    }

    if (updatePubspec) {
      await updateFlutterAssetsList();
    }

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
