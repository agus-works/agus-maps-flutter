// Process execution utilities for cross-platform command running

import 'dart:io';

/// Run a process and return the result
Future<ProcessResult> runProcess(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
  String? workingDirectory,
  bool throwOnError = true,
  bool verbose = false,
}) async {
  final env = Map<String, String>.from(Platform.environment);
  if (environment != null) {
    env.addAll(environment);
  }
  
  if (verbose) {
    print('Running: $executable ${arguments.join(' ')}');
    if (workingDirectory != null) {
      print('  Working directory: $workingDirectory');
    }
  }
  
  final result = await Process.run(
    executable,
    arguments,
    environment: env,
    workingDirectory: workingDirectory,
    runInShell: Platform.isWindows,
  );
  
  if (throwOnError && result.exitCode != 0) {
    final stdoutStr = result.stdout?.toString().trim() ?? '';
    final stderrStr = result.stderr?.toString().trim() ?? '';
    
    // Print captured output for debugging
    if (stdoutStr.isNotEmpty) {
      print('stdout: $stdoutStr');
    }
    if (stderrStr.isNotEmpty) {
      print('stderr: $stderrStr');
    }
    
    throw ProcessException(
      executable,
      arguments,
      'Process failed with exit code ${result.exitCode}',
      result.exitCode,
    );
  }
  
  return result;
}

/// Run a process and stream output
Future<int> runProcessStreaming(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
  String? workingDirectory,
  void Function(String)? onStdout,
  void Function(String)? onStderr,
}) async {
  final env = Map<String, String>.from(Platform.environment);
  if (environment != null) {
    env.addAll(environment);
  }
  
  final process = await Process.start(
    executable,
    arguments,
    environment: env,
    workingDirectory: workingDirectory,
    runInShell: Platform.isWindows,
    mode: ProcessStartMode.normal,
  );
  
  process.stdout.transform(const SystemEncoding().decoder).listen((data) {
    onStdout?.call(data);
    stdout.write(data);
  });
  
  process.stderr.transform(const SystemEncoding().decoder).listen((data) {
    onStderr?.call(data);
    stderr.write(data);
  });
  
  return await process.exitCode;
}

/// Check if command is available
Future<bool> commandExists(String command) async {
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
