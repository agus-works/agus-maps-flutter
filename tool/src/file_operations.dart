// Cross-platform file operations

import 'dart:io';
import 'package:path/path.dart' as path;

/// Copy file or directory recursively
Future<void> copyPath(String source, String dest) async {
  final sourceEntity = FileSystemEntity.typeSync(source);
  
  if (sourceEntity == FileSystemEntityType.directory) {
    final destDir = Directory(dest);
    if (!await destDir.exists()) {
      await destDir.create(recursive: true);
    }
    
    // Normalize paths to handle Windows path issues
    final normalizedSource = path.normalize(path.absolute(source));
    final normalizedDest = path.normalize(path.absolute(dest));
    
    await for (final entity in Directory(normalizedSource).list(recursive: true)) {
      // Use absolute path and compute relative path more carefully
      final entityAbsolute = path.normalize(path.absolute(entity.path));
      final relativePath = path.relative(entityAbsolute, from: normalizedSource);
      final destPath = path.join(normalizedDest, relativePath);
      
      if (entity is File) {
        final destFile = File(destPath);
        final parentDir = destFile.parent;
        if (!await parentDir.exists()) {
          await parentDir.create(recursive: true);
        }
        // Check if source file exists before copying (handle race conditions and symlinks)
        try {
          if (await entity.exists()) {
            await entity.copy(destPath);
          }
        } catch (e) {
          // Skip files that can't be copied (might be symlinks, missing files, etc.)
          // This is especially important on Windows where path handling can be tricky
          print('Warning: Skipping file ${entity.path}: $e');
        }
      } else if (entity is Directory) {
        final destDir = Directory(destPath);
        if (!await destDir.exists()) {
          await destDir.create(recursive: true);
        }
      }
    }
  } else if (sourceEntity == FileSystemEntityType.file) {
    final destFile = File(dest);
    final parentDir = destFile.parent;
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }
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
