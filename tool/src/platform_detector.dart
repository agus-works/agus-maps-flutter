// Platform detection and path utilities

import 'dart:io';
import 'package:path/path.dart' as path;

/// Operating system type
enum OSType {
  macos,
  linux,
  windows,
}

/// Detect current operating system
OSType detectOS() {
  if (Platform.isMacOS) return OSType.macos;
  if (Platform.isLinux) return OSType.linux;
  if (Platform.isWindows) return OSType.windows;
  throw UnsupportedError('Unsupported operating system: ${Platform.operatingSystem}');
}

/// Get number of CPU cores for parallel builds
int getCpuCores() {
  return Platform.numberOfProcessors;
}

/// Get repository root directory
String getRepoRoot() {
  // If running from tool/ directory, go up one level
  final currentDir = Directory.current.path;
  if (currentDir.endsWith('tool') || currentDir.endsWith(path.join('tool', 'src'))) {
    return path.dirname(path.dirname(currentDir));
  }
  return currentDir;
}

/// Get script directory (where scripts/ would be)
String getScriptDir() {
  return path.join(getRepoRoot(), 'scripts');
}

/// Get thirdparty directory
String getThirdpartyDir() {
  return path.join(getRepoRoot(), 'thirdparty');
}

/// Get CoMaps directory
String getComapsDir() {
  return path.join(getThirdpartyDir(), 'comaps');
}

/// Get build directory
String getBuildDir() {
  return path.join(getRepoRoot(), 'build');
}

/// Get patches directory
String getPatchesDir() {
  return path.join(getRepoRoot(), 'patches', 'comaps');
}

/// Normalize path for current platform
String normalizePath(String p) {
  return path.normalize(p);
}

/// Join paths for current platform
String joinPaths(String part1, [String? part2, String? part3, String? part4, String? part5]) {
  final parts = [part1];
  if (part2 != null) parts.add(part2);
  if (part3 != null) parts.add(part3);
  if (part4 != null) parts.add(part4);
  if (part5 != null) parts.add(part5);
  return path.joinAll(parts);
}
