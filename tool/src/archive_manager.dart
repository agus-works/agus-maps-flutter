// Archive operations (compress/extract)

import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;
import 'process_runner.dart' show runProcess;
import 'platform_detector.dart' show detectOS, OSType;

/// Extract ZIP archive
Future<void> extractZip(String zipPath, String destDir) async {
  final zipFile = File(zipPath);
  if (!await zipFile.exists()) {
    throw Exception('ZIP file does not exist: $zipPath');
  }
  
  final bytes = await zipFile.readAsBytes();
  final archive = ZipDecoder().decodeBytes(bytes);
  
  final dest = Directory(destDir);
  if (!await dest.exists()) {
    await dest.create(recursive: true);
  }
  
  for (final file in archive) {
    final filename = file.name;
    if (file.isFile) {
      final data = file.content as List<int>;
      final outFile = File(path.join(destDir, filename));
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(data);
    } else {
      final dir = Directory(path.join(destDir, filename));
      await dir.create(recursive: true);
    }
  }
}

/// Extract TAR.BZ2 archive (using external tools)
Future<void> extractTarBz2(String tarPath, String destDir) async {
  final os = detectOS();
  
  if (os == OSType.windows) {
    // Windows: try 7z or tar (Windows 10+ has tar)
    if (await _commandExists('7z')) {
      await runProcess('7z', ['x', tarPath, '-o$destDir', '-y']);
    } else if (await _commandExists('tar')) {
      await runProcess('tar', ['-xjf', tarPath, '-C', destDir]);
    } else {
      throw Exception('Neither 7z nor tar found. Cannot extract TAR.BZ2 on Windows.');
    }
  } else {
    // Unix: use tar
    await runProcess('tar', ['-xjf', tarPath, '-C', destDir]);
  }
}

/// Create TAR.BZ2 archive (using external tools)
Future<void> createTarBz2(String sourceDir, String archivePath) async {
  final os = detectOS();
  
  if (os == OSType.windows) {
    // Windows: try 7z
    if (await _commandExists('7z')) {
      await runProcess('7z', ['a', '-tbzip2', archivePath, path.join(sourceDir, '*')]);
    } else {
      throw Exception('7z not found. Cannot create TAR.BZ2 on Windows without 7z.');
    }
  } else {
    // Unix: use tar
    await runProcess('tar', ['-cjf', archivePath, '-C', path.dirname(sourceDir), path.basename(sourceDir)]);
  }
}

/// Create ZIP archive
Future<void> createZip(String sourceDir, String zipPath) async {
  final archive = Archive();
  final source = Directory(sourceDir);
  
  await for (final entity in source.list(recursive: true)) {
    if (entity is File) {
      final relativePath = path.relative(entity.path, from: sourceDir);
      final bytes = await entity.readAsBytes();
      archive.addFile(ArchiveFile(relativePath, bytes.length, bytes));
    }
  }
  
  final zipEncoder = ZipEncoder();
  final zipData = zipEncoder.encode(archive);
  
  if (zipData != null) {
    await File(zipPath).writeAsBytes(zipData);
  }
}

/// Check if command exists (helper)
Future<bool> _commandExists(String command) async {
  try {
    if (Platform.isWindows) {
      final result = await Process.run('where', [command]);
      return result.exitCode == 0;
    } else {
      final result = await Process.run('which', [command]);
      return result.exitCode == 0;
    }
  } catch (e) {
    return false;
  }
}
