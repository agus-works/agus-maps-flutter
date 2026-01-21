// Git operations (clone, checkout, submodules)

import 'dart:io';
import 'package:path/path.dart' as path;
import 'process_runner.dart' show runProcess, commandExists;
import 'file_operations.dart' show pathExists, dirExists;
import 'platform_detector.dart' show getComapsDir, getThirdpartyDir;

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
  
  print('Checking out CoMaps tag: $tag');
  
  // Fetch tags
  await runProcess('git', ['fetch', '--tags', '--prune'], workingDirectory: dir);
  
  // Checkout tag
  await runProcess('git', ['checkout', '--detach', tag], workingDirectory: dir);
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
  await runProcess(
    'git',
    ['submodule', 'update', '--init', '--recursive'],
    workingDirectory: dir,
  );
  
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
