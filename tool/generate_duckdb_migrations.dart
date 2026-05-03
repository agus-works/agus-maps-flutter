#!/usr/bin/env dart

import 'dart:io';

import 'src/duckdb_migration_generator.dart';

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(
        'Usage: dart run tool/generate_duckdb_migrations.dart [--check]');
    stdout.writeln('');
    stdout.writeln(
        'Generates src/agus_duckdb_migrations.inc from doc/schemas/migrations/*.sql.');
    exit(0);
  }

  final unknownArgs = args.where((arg) => arg != '--check').toList();
  if (unknownArgs.isNotEmpty) {
    stderr.writeln('Unknown argument(s): ${unknownArgs.join(', ')}');
    stderr.writeln('Run with --help for usage information.');
    exit(64);
  }

  final ok =
      await generateDuckDBMigrations(checkOnly: args.contains('--check'));
  exit(ok ? 0 : 1);
}
