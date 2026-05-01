// Patch application logic

import 'dart:io';
import 'package:path/path.dart' as path;
import 'process_runner.dart' show runProcess;
import 'platform_detector.dart' show getPatchesDir, getComapsDir;
import 'git_operations.dart' show resetComapsWorkingTree;

/// Apply all patches from patches/comaps/ directory
Future<void> applyPatches({String? comapsDir, String? patchesDir}) async {
  final comaps = comapsDir ?? getComapsDir();
  final patches = patchesDir ?? getPatchesDir();

  if (!await Directory(patches).exists()) {
    print('Patches directory not found: $patches');
    return;
  }

  final patchFiles = <File>[];
  await for (final entity in Directory(patches).list()) {
    if (entity is File && entity.path.endsWith('.patch')) {
      patchFiles.add(entity);
    }
  }
  patchFiles
      .sort((a, b) => path.basename(a.path).compareTo(path.basename(b.path)));

  if (patchFiles.isEmpty) {
    print('No patches found in $patches');
    return;
  }

  print('Found ${patchFiles.length} patches to apply');

  await resetComapsWorkingTree(comapsDir: comaps);

  int applied = 0;
  int skipped = 0;
  int failed = 0;

  for (final patchFile in patchFiles) {
    final patchName = path.basename(patchFile.path);
    print('Processing patch: $patchName');

    // Try different application methods
    bool success = false;

    // Method 1: git apply (preferred)
    try {
      final result = await runProcess(
        'git',
        ['apply', '--whitespace=nowarn', patchFile.path],
        workingDirectory: comaps,
        throwOnError: false,
      );
      if (result.exitCode == 0) {
        print('  Applied: $patchName');
        applied++;
        success = true;
      }
    } catch (e) {
      // Try next method
    }

    if (!success) {
      // Method 2: git apply with 3-way merge
      try {
        final result = await runProcess(
          'git',
          ['apply', '--3way', '--whitespace=nowarn', patchFile.path],
          workingDirectory: comaps,
          throwOnError: false,
        );
        if (result.exitCode == 0) {
          print('  Applied (3-way): $patchName');
          applied++;
          success = true;
        }
      } catch (e) {
        // Try next method
      }
    }

    if (!success) {
      // Method 3: Check if already applied
      try {
        final result = await runProcess(
          'git',
          ['apply', '--check', '--reverse', patchFile.path],
          workingDirectory: comaps,
          throwOnError: false,
        );
        if (result.exitCode == 0) {
          print('  Already applied: $patchName');
          skipped++;
          success = true;
        }
      } catch (e) {
        // Not already applied
      }
    }

    if (!success) {
      // Method 4: patch command (fallback)
      try {
        final result = await runProcess(
          'patch',
          ['-p1', '--batch', '--forward', patchFile.path],
          workingDirectory: comaps,
          throwOnError: false,
        );
        if (result.exitCode == 0) {
          print('  Applied (patch): $patchName');
          applied++;
          success = true;
        }
      } catch (e) {
        // Failed
      }
    }

    if (!success) {
      print('  Failed: $patchName');
      failed++;
    }
  }

  print('Patch summary: Applied=$applied, Skipped=$skipped, Failed=$failed');

  if (failed > 0) {
    print('Warning: Some patches failed - build may still succeed');
  }
}
