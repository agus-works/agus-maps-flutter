// Cross-platform file operations

import 'dart:io';
import 'package:path/path.dart' as path;
import 'platform_detector.dart' show normalizePath, joinPaths;

/// Copy file or directory recursively
Future<void> copyPath(String source, String dest) async {
  final sourceEntity = FileSystemEntity.typeSync(source);
  
  if (sourceEntity == FileSystemEntityType.directory) {
    final destDir = Directory(dest);
    if (!await destDir.exists()) {
      await destDir.create(recursive: true);
    }
    
    await for (final entity in Directory(source).list(recursive: true)) {
      final relativePath = path.relative(entity.path, from: source);
      final destPath = path.join(dest, relativePath);
      
      if (entity is File) {
        final destFile = File(destPath);
        await destFile.parent.create(recursive: true);
        await entity.copy(destPath);
      } else if (entity is Directory) {
        await Directory(destPath).create(recursive: true);
      }
    }
  } else if (sourceEntity == FileSystemEntityType.file) {
    final destFile = File(dest);
    await destFile.parent.create(recursive: true);
    await File(source).copy(dest);
  } else {
    throw Exception('Source path does not exist: $source');
  }
}

/// Remove file or directory recursively
Future<void> removePath(String target) async {
  final entity = FileSystemEntity.typeSync(target);
  if (entity == FileSystemEntityType.directory) {
    await Directory(target).delete(recursive: true);
  } else if (entity == FileSystemEntityType.file) {
    await File(target).delete();
  }
}

/// Ensure directory exists
Future<void> ensureDir(String dirPath) async {
  final dir = Directory(dirPath);
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
}

/// Check if path exists
bool pathExists(String target) {
  return FileSystemEntity.typeSync(target) != FileSystemEntityType.notFound;
}

/// Check if file exists
bool fileExists(String target) {
  return File(target).existsSync();
}

/// Check if directory exists
bool dirExists(String target) {
  return Directory(target).existsSync();
}
