// Asset synchronization and pubspec update utilities

import 'dart:io';
import 'package:path/path.dart' as path;
import 'file_operations.dart' show ensureDir, copyPath;
import 'platform_detector.dart' show getRepoRoot;
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

Future<void> syncLocalizedStringsAssets() async {
  final repoRoot = getRepoRoot();
  final sourceDir = path.join(
    repoRoot,
    'thirdparty',
    'comaps',
    'iphone',
    'Maps',
    'LocalizedStrings',
  );
  final destDir = path.join(repoRoot, 'assets', 'localized_types');

  if (!await Directory(sourceDir).exists()) {
    print('Localized strings source not found: $sourceDir');
    return;
  }

  if (await Directory(destDir).exists()) {
    await Directory(destDir).delete(recursive: true);
  }
  await ensureDir(destDir);

  await copyPath(sourceDir, destDir);
  print('Synced localized strings to assets/localized_types/');
}

Future<void> copyDataFiles() async {
  final repoRoot = getRepoRoot();
  final comapsDataDir = path.join(repoRoot, 'thirdparty', 'comaps', 'data');
  final destDataDir = path.join(repoRoot, 'example', 'assets', 'comaps_data');

  print('=== Copy Data Files ===');

  if (!await Directory(comapsDataDir).exists()) {
    print('CoMaps data directory not found: $comapsDataDir');
    return;
  }

  await ensureDir(destDataDir);

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

  final dirsToCopy = [
    'categories-strings',
    'countries-strings',
    'fonts',
    'symbols',
    'styles',
  ];
  for (final dir in dirsToCopy) {
    final srcDir = path.join(comapsDataDir, dir);
    if (await Directory(srcDir).exists()) {
      final destDir = path.join(destDataDir, dir);
      await copyPath(srcDir, destDir);
      print('  Copied: $dir/');
    }
  }

  final localizedTypesSrc = path.join(repoRoot, 'assets', 'localized_types');
  if (await Directory(localizedTypesSrc).exists()) {
    final localizedTypesDest = path.join(destDataDir, 'localized_types');
    await copyPath(localizedTypesSrc, localizedTypesDest);
    print('  Copied: localized_types/');
  }

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

Future<void> updateFlutterAssetsList() async {
  final repoRoot = getRepoRoot();
  final assetsDir = path.join(repoRoot, 'assets');
  final pubspecPath = path.join(repoRoot, 'pubspec.yaml');

  if (!await Directory(assetsDir).exists()) {
    print('Assets directory not found: $assetsDir');
    return;
  }

  final pubspecFile = File(pubspecPath);
  if (!await pubspecFile.exists()) {
    print('pubspec.yaml not found at: $pubspecPath');
    return;
  }

  final assets = await _collectAssetDirectories(assetsDir, repoRoot);
  if (assets.isEmpty) {
    print('No asset files found under: $assetsDir');
    return;
  }

  final content = await pubspecFile.readAsString();
  final updated = _updatePubspecAssetsYaml(content, assets);

  if (updated == content) {
    print('pubspec.yaml assets list already up to date');
    return;
  }

  await pubspecFile.writeAsString(updated);
  print('Updated pubspec.yaml assets list (${assets.length} directories)');
}

Future<List<String>> _collectAssetDirectories(
  String assetsDir,
  String repoRoot,
) async {
  final directories = <String>{};
  await for (final entity in Directory(assetsDir).list(recursive: true)) {
    if (entity is! File) {
      continue;
    }
    final fileName = path.basename(entity.path);
    if (fileName.startsWith('.')) {
      continue;
    }
    final relative = path.relative(entity.path, from: repoRoot);
    final normalized = relative.split(path.separator).join('/');
    if (!normalized.startsWith('assets/')) {
      continue;
    }
    final dir = path.dirname(normalized);
    final withSlash = dir.endsWith('/') ? dir : '$dir/';
    directories.add(withSlash);
  }
  final result = directories.toList()..sort();
  return result;
}

String _updatePubspecAssetsYaml(String content, List<String> assets) {
  final editor = YamlEditor(content);
  final doc = loadYaml(content);

  if (doc is! YamlMap) {
    print('pubspec.yaml root is not a map');
    return content;
  }

  if (!doc.containsKey('flutter') || doc['flutter'] is! YamlMap) {
    editor.update(['flutter'], <String, dynamic>{});
  }

  editor.update(['flutter', 'assets'], assets);
  return editor.toString();
}
