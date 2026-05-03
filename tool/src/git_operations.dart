// Git operations (clone, checkout, submodules)

import 'dart:io';
import 'package:path/path.dart' as path;
import 'process_runner.dart' show runProcess, commandExists;
import 'platform_detector.dart' show getComapsDir, getThirdpartyDir;

/// Check whether [dir] is a git checkout or initialized git submodule.
Future<bool> isGitCheckout(String dir) async {
  if (!await Directory(dir).exists()) {
    return false;
  }

  return await Directory(path.join(dir, '.git')).exists() ||
      await File(path.join(dir, '.git')).exists();
}

/// Initialize a submodule path from the parent repository.
Future<void> updateSubmodule(String relativePath) async {
  await runProcess(
    'git',
    ['submodule', 'update', '--init', '--recursive', '--', relativePath],
  );
}

/// Clone a managed git dependency when root submodule metadata is unavailable.
Future<void> cloneGitRepository({
  required String url,
  required String targetDir,
  required String dependencyName,
}) async {
  if (await isGitCheckout(targetDir)) {
    print('$dependencyName repository already exists at $targetDir');
    return;
  }

  final targetDirectory = Directory(targetDir);
  if (await targetDirectory.exists()) {
    final entries = await targetDirectory.list().take(1).toList();
    if (entries.isEmpty) {
      await targetDirectory.delete();
    } else {
      throw Exception(
        '$dependencyName target exists but is not a git checkout: $targetDir',
      );
    }
  }

  await Directory(path.dirname(targetDir)).create(recursive: true);

  print('Cloning $dependencyName repository from $url');
  try {
    await runProcess(
      'git',
      ['clone', '--filter=blob:none', url, targetDir],
    );
  } catch (e) {
    print('Partial clone failed for $dependencyName; retrying full clone');
    if (await targetDirectory.exists()) {
      await targetDirectory.delete(recursive: true);
    }
    await runProcess('git', ['clone', url, targetDir]);
  }
}

/// Checkout a tag, branch, or commit in a managed git checkout.
Future<void> checkoutGitRef(
  String ref, {
  required String dir,
  required String dependencyName,
}) async {
  if (!await isGitCheckout(dir)) {
    throw Exception('$dependencyName directory is not a git checkout: $dir');
  }

  print('Checking out $dependencyName ref: $ref');

  final status = await runProcess(
    'git',
    ['status', '--porcelain'],
    workingDirectory: dir,
    throwOnError: false,
  );
  if (status.exitCode == 0 && status.stdout.toString().trim().isNotEmpty) {
    print('$dependencyName working tree has local changes; resetting first');
    await resetGitWorkingTree(dir: dir, dependencyName: dependencyName);
  }

  await runProcess(
    'git',
    ['fetch', '--tags', '--prune', '--no-recurse-submodules'],
    workingDirectory: dir,
  );
  await runProcess('git', ['checkout', '--detach', ref], workingDirectory: dir);
}

/// Reset a managed git checkout to a clean HEAD state.
Future<void> resetGitWorkingTree({
  required String dir,
  required String dependencyName,
}) async {
  if (!await isGitCheckout(dir)) {
    throw Exception('$dependencyName directory is not a git checkout: $dir');
  }

  print('Resetting $dependencyName working tree to HEAD...');
  await runProcess('git', ['reset', '--hard', 'HEAD'], workingDirectory: dir);
  await runProcess('git', ['clean', '-fd'], workingDirectory: dir);

  print('Resetting $dependencyName submodules...');
  try {
    await runProcess(
      'git',
      ['submodule', 'foreach', '--recursive', 'git', 'reset', '--hard', 'HEAD'],
      workingDirectory: dir,
    );
    await runProcess(
      'git',
      ['submodule', 'foreach', '--recursive', 'git', 'clean', '-fd'],
      workingDirectory: dir,
    );
  } catch (e) {
    print('Note: $dependencyName submodule reset had warnings');
  }
}

/// Initialize submodules and LFS recursively for a managed git checkout.
Future<void> initRepositorySubmodules({
  required String dir,
  required String dependencyName,
}) async {
  if (!await isGitCheckout(dir)) {
    throw Exception('$dependencyName directory is not a git checkout: $dir');
  }

  print('Initializing $dependencyName submodules');
  try {
    await runProcess(
      'git',
      ['submodule', 'update', '--init', '--recursive'],
      workingDirectory: dir,
    );
  } catch (e) {
    print('Warning: $dependencyName submodule update failed. Retrying...');
    await runProcess('git', ['submodule', 'sync', '--recursive'],
        workingDirectory: dir);
    await runProcess(
      'git',
      ['submodule', 'update', '--init', '--recursive', '--force'],
      workingDirectory: dir,
    );
  }

  print('Download LFS on $dependencyName');
  await runProcess(
    'git',
    ['lfs', 'pull'],
    workingDirectory: dir,
    throwOnError: false,
  );

  print('Download LFS recursively on $dependencyName');
  await runProcess(
    'git',
    ['submodule', 'foreach', '--recursive', 'git', 'lfs', 'pull'],
    workingDirectory: dir,
    throwOnError: false,
  );
}

/// Clone CoMaps repository
Future<void> cloneComaps(String tag, {String? targetDir}) async {
  final comapsDir = targetDir ?? getComapsDir();
  final thirdpartyDir = getThirdpartyDir();

  // Check if already cloned
  if (await Directory(comapsDir).exists()) {
    final gitDir = Directory(path.join(comapsDir, '.git'));
    if (await gitDir.exists()) {
      print('CoMaps repository already exists at $comapsDir');
      return;
    }
  }

  // Ensure thirdparty directory exists
  await Directory(thirdpartyDir).create(recursive: true);

  // Clone repository
  print('Cloning CoMaps repository...');
  await runProcess(
    'git',
    ['clone', 'https://github.com/comaps/comaps.git', comapsDir],
  );

  // Checkout specific tag
  await checkoutComapsTag(tag, comapsDir: comapsDir);

  // Initialize submodules
  await initSubmodules(comapsDir: comapsDir);
}

/// Checkout specific CoMaps tag
Future<void> checkoutComapsTag(String tag, {String? comapsDir}) async {
  final dir = comapsDir ?? getComapsDir();

  if (!await Directory(dir).exists()) {
    throw Exception('CoMaps directory does not exist: $dir');
  }

  await checkoutGitRef(tag, dir: dir, dependencyName: 'CoMaps');
}

/// Reset the managed CoMaps checkout to a clean HEAD state.
Future<void> resetComapsWorkingTree({String? comapsDir}) async {
  final dir = comapsDir ?? getComapsDir();

  if (!await Directory(dir).exists()) {
    throw Exception('CoMaps directory does not exist: $dir');
  }

  await resetGitWorkingTree(dir: dir, dependencyName: 'CoMaps');
}

/// Initialize submodules recursively
Future<void> initSubmodules({String? comapsDir}) async {
  final dir = comapsDir ?? getComapsDir();

  if (!await Directory(dir).exists()) {
    throw Exception('CoMaps directory does not exist: $dir');
  }

  // Fix Codeberg URLs in .gitmodules if needed (use GitHub mirrors)
  print('Git submodules mirror replacements');
  final gitmodulesFile = File(path.join(dir, '.gitmodules'));
  if (await gitmodulesFile.exists()) {
    var content = await gitmodulesFile.readAsString();
    final originalContent = content;

    // Replace Codeberg URLs with GitHub mirrors
    content = content.replaceAll(
      'https://codeberg.org/comaps/protobuf.git',
      'https://github.com/organicmaps/protobuf.git',
    );
    content = content.replaceAll(
      'https://codeberg.org/comaps/kothic.git',
      'https://github.com/organicmaps/kothic.git',
    );

    if (content != originalContent) {
      await gitmodulesFile.writeAsString(content);
      print('Updated .gitmodules to use GitHub mirrors');
    }
  }

  // Initialize submodules
  print('Initializing submodules');
  try {
    await runProcess(
      'git',
      ['submodule', 'update', '--init', '--recursive'],
      workingDirectory: dir,
    );
  } catch (e) {
    print('Warning: Submodule update failed. Attempting to recover...');
    // Try to recover: sync URLs and force update
    try {
      await runProcess('git', ['submodule', 'sync', '--recursive'],
          workingDirectory: dir);
      await runProcess(
        'git',
        ['submodule', 'update', '--init', '--recursive', '--force'],
        workingDirectory: dir,
      );
      print('Submodule recovery successful');
    } catch (e2) {
      print('Error: Submodule recovery failed: $e2');
      rethrow;
    }
  }

  print('Download LFS on CoMaps');
  await runProcess(
    'git',
    ['lfs', 'pull'],
    workingDirectory: dir,
  );

  print('Download LFS recursively');
  await runProcess(
    'git',
    ['submodule', 'foreach', '--recursive', 'git', 'lfs', 'pull'],
    workingDirectory: dir,
  );
}

/// Get current git commit hash
Future<String> getGitCommitHash({String? workingDirectory}) async {
  final result = await runProcess(
    'git',
    ['rev-parse', 'HEAD'],
    workingDirectory: workingDirectory,
  );
  return result.stdout.toString().trim();
}

/// Check if git is available
Future<bool> isGitAvailable() async {
  return await commandExists('git');
}
