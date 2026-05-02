// Patch application logic

import 'dart:io';
import 'package:path/path.dart' as path;
import 'process_runner.dart' show runProcess;
import 'platform_detector.dart' show getPatchesDir, getComapsDir;
import 'git_operations.dart' show resetComapsWorkingTree, resetGitWorkingTree;

/// Apply all patches from a dependency-specific patch directory.
Future<void> applyDependencyPatches({
  required String dependencyName,
  required String sourceDir,
  required String patchesDir,
  Future<void> Function()? resetWorkingTree,
}) async {
  if (!await Directory(patchesDir).exists()) {
    print('Patches directory not found for $dependencyName: $patchesDir');
    return;
  }

  final patchFiles = <File>[];
  await for (final entity in Directory(patchesDir).list()) {
    if (entity is File && entity.path.endsWith('.patch')) {
      patchFiles.add(entity);
    }
  }
  patchFiles
      .sort((a, b) => path.basename(a.path).compareTo(path.basename(b.path)));

  if (patchFiles.isEmpty) {
    print('No patches found for $dependencyName in $patchesDir');
    return;
  }

  print('Found ${patchFiles.length} $dependencyName patches to apply');

  if (resetWorkingTree != null) {
    await resetWorkingTree();
  } else {
    await resetGitWorkingTree(
      dir: sourceDir,
      dependencyName: dependencyName,
    );
  }

  int applied = 0;
  int skipped = 0;
  int failed = 0;

  for (final patchFile in patchFiles) {
    final patchName = path.basename(patchFile.path);
    print('Processing $dependencyName patch: $patchName');

    bool success = false;

    try {
      final result = await runProcess(
        'git',
        ['apply', '--whitespace=nowarn', patchFile.path],
        workingDirectory: sourceDir,
        throwOnError: false,
      );
      if (result.exitCode == 0) {
        print('  Applied: $patchName');
        applied++;
        success = true;
      }
    } catch (e) {
      // Try next method.
    }

    if (!success) {
      try {
        final result = await runProcess(
          'git',
          ['apply', '--3way', '--whitespace=nowarn', patchFile.path],
          workingDirectory: sourceDir,
          throwOnError: false,
        );
        if (result.exitCode == 0) {
          print('  Applied (3-way): $patchName');
          applied++;
          success = true;
        }
      } catch (e) {
        // Try next method.
      }
    }

    if (!success) {
      try {
        final result = await runProcess(
          'git',
          ['apply', '--check', '--reverse', patchFile.path],
          workingDirectory: sourceDir,
          throwOnError: false,
        );
        if (result.exitCode == 0) {
          print('  Already applied: $patchName');
          skipped++;
          success = true;
        }
      } catch (e) {
        // Not already applied.
      }
    }

    if (!success) {
      try {
        final result = await runProcess(
          'patch',
          ['-p1', '--batch', '--forward', patchFile.path],
          workingDirectory: sourceDir,
          throwOnError: false,
        );
        if (result.exitCode == 0) {
          print('  Applied (patch): $patchName');
          applied++;
          success = true;
        }
      } catch (e) {
        // Failed.
      }
    }

    if (!success) {
      print('  Failed: $patchName');
      failed++;
    }
  }

  print(
      '$dependencyName patch summary: Applied=$applied, Skipped=$skipped, Failed=$failed');

  if (failed > 0) {
    print(
        'Warning: Some $dependencyName patches failed - build may still succeed');
  }
}

/// Apply all patches from patches/comaps/ directory
Future<void> applyPatches({String? comapsDir, String? patchesDir}) async {
  final comaps = comapsDir ?? getComapsDir();
  final patches = patchesDir ?? getPatchesDir();
  await applyDependencyPatches(
    dependencyName: 'CoMaps',
    sourceDir: comaps,
    patchesDir: patches,
    resetWorkingTree: () => resetComapsWorkingTree(comapsDir: comaps),
  );
}
