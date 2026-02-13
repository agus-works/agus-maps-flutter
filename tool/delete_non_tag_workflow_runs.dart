#!/usr/bin/env dart

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

import 'src/process_runner.dart' show commandExists, runProcess;

const String _defaultRepoUrl =
    'https://github.com/agus-works/agus-maps-flutter/';
const String _defaultWorkflow = 'devops.yml';
final RegExp _strictVersionTag = RegExp(r'^v[0-9]+\.[0-9]+\.[0-9]+$');

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption(
      'repo',
      defaultsTo: _defaultRepoUrl,
      help: 'GitHub repository URL or OWNER/REPO',
    )
    ..addOption(
      'workflow',
      defaultsTo: _defaultWorkflow,
      help: 'Workflow file name or workflow ID to inspect',
    )
    ..addFlag(
      'execute',
      defaultsTo: false,
      help: 'Actually delete runs. By default this tool is dry-run.',
    )
    ..addOption(
      'max-pages',
      defaultsTo: '20',
      help: 'Maximum pages to fetch (100 runs per page)',
    )
    ..addOption(
      'max-delete',
      help: 'Stop deleting after this many runs (execute mode only)',
    )
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Show this help message',
    );

  try {
    final results = parser.parse(args);

    if (results['help'] as bool) {
      _printHelp(parser);
      exit(0);
    }

    final maxPages = int.tryParse(results['max-pages'] as String);
    if (maxPages == null || maxPages <= 0) {
      throw FormatException('--max-pages must be a positive integer');
    }

    final maxDeleteRaw = results['max-delete'] as String?;
    final maxDelete =
        maxDeleteRaw == null ? null : int.tryParse(maxDeleteRaw.trim());
    if (maxDeleteRaw != null && (maxDelete == null || maxDelete <= 0)) {
      throw FormatException('--max-delete must be a positive integer');
    }

    if (!await commandExists('gh')) {
      throw StateError('GitHub CLI (gh) is not available in PATH.');
    }

    final repoInput = results['repo'] as String;
    final workflow = results['workflow'] as String;
    final execute = results['execute'] as bool;
    final repo = _normalizeRepo(repoInput);

    print('Repository      : $repo');
    print('Workflow        : $workflow');
    print('Mode            : ${execute ? 'EXECUTE' : 'DRY-RUN'}');
    print('Tag keep pattern: ${_strictVersionTag.pattern}');
    print('Max pages       : $maxPages');
    if (maxDelete != null) {
      print('Max delete      : $maxDelete');
    }
    print('');

    final runs = await _fetchWorkflowRuns(
      repo: repo,
      workflow: workflow,
      maxPages: maxPages,
    );

    if (runs.isEmpty) {
      print('No workflow runs found.');
      exit(0);
    }

    final candidates = runs.where(_isDeletionCandidate).toList();
    final skippedActive =
        candidates.where((run) => _isActive(run.status)).toList();
    final deletable =
        candidates.where((run) => !_isActive(run.status)).toList();

    print('Scanned runs         : ${runs.length}');
    print('Runs kept            : ${runs.length - candidates.length}');
    print('Deletion candidates  : ${candidates.length}');
    print('Skipped active runs  : ${skippedActive.length}');
    print('Deletable runs       : ${deletable.length}');
    print('');

    if (deletable.isEmpty) {
      print('Nothing to delete.');
      exit(0);
    }

    final runIds = deletable.map((run) => run.id).toList();
    for (final run in deletable) {
      final branch = run.headBranch ?? '<null>';
      print('Candidate: #${run.id} status=${run.status} '
          'conclusion=${run.conclusion ?? '<null>'} '
          'event=${run.event ?? '<null>'} '
          'head_branch=$branch');
    }
    print('');

    if (!execute) {
      print('Dry-run mode: no workflow runs were deleted.');
      print('Re-run with --execute to perform deletions.');
      exit(0);
    }

    var deleted = 0;
    var failed = 0;

    for (final runId in runIds) {
      if (maxDelete != null && deleted >= maxDelete) {
        print('Reached --max-delete limit ($maxDelete).');
        break;
      }

      try {
        await runProcess(
          'gh',
          [
            'api',
            '--method',
            'DELETE',
            'repos/$repo/actions/runs/$runId',
          ],
          throwOnError: true,
        );
        deleted += 1;
        print('Deleted run #$runId');
      } catch (e) {
        failed += 1;
        stderr.writeln('Failed deleting run #$runId: $e');
      }
    }

    print('');
    print('Deletion complete.');
    print('Deleted: $deleted');
    print('Failed : $failed');

    exit(failed == 0 ? 0 : 2);
  } on FormatException catch (e) {
    stderr.writeln('Error: ${e.message}');
    stderr.writeln('Run with --help for usage information.');
    exit(1);
  } catch (e, stackTrace) {
    stderr.writeln('Error: $e');
    if (Platform.environment['DEBUG'] == 'true') {
      stderr.writeln(stackTrace);
    }
    exit(1);
  }
}

void _printHelp(ArgParser parser) {
  print('Delete non-tag workflow runs from GitHub Actions');
  print('');
  print('Usage: dart run tool/delete_non_tag_workflow_runs.dart [options]');
  print('');
  print('Behavior:');
  print('- Always deletes failed/cancelled runs (when not active)');
  print('- Keeps successful runs, even when branch does not match vX.Y.Z');
  print(
      '- For non-success states, applies vX.Y.Z keep rule on head branch/tag');
  print('- Scans only one workflow (default: devops.yml)');
  print('- Skips active runs (queued/in_progress)');
  print('- Dry-run by default; use --execute to delete');
  print('');
  print('Options:');
  print(parser.usage);
  print('');
  print('Examples:');
  print('  dart run tool/delete_non_tag_workflow_runs.dart');
  print('  dart run tool/delete_non_tag_workflow_runs.dart --execute');
  print(
      '  dart run tool/delete_non_tag_workflow_runs.dart --execute --max-delete 5');
  print(
      '  dart run tool/delete_non_tag_workflow_runs.dart --repo https://github.com/agus-works/agus-maps-flutter/');
}

String _normalizeRepo(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    throw FormatException('--repo cannot be empty');
  }

  if (!trimmed.contains('://')) {
    final normalized = trimmed.replaceAll(RegExp(r'^/+|/+$'), '');
    if (!_looksLikeOwnerRepo(normalized)) {
      throw FormatException('Invalid --repo value: $input');
    }
    return normalized;
  }

  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.host.toLowerCase() != 'github.com') {
    throw FormatException('Only github.com URLs are supported for --repo');
  }

  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.length < 2) {
    throw FormatException(
        'Expected repository URL in form https://github.com/OWNER/REPO');
  }

  final owner = segments[0];
  final repo = segments[1].replaceAll(RegExp(r'\.git$'), '');
  final ownerRepo = '$owner/$repo';
  if (!_looksLikeOwnerRepo(ownerRepo)) {
    throw FormatException('Invalid repository path in URL: $input');
  }
  return ownerRepo;
}

bool _looksLikeOwnerRepo(String value) {
  final parts = value.split('/');
  return parts.length == 2 && parts[0].isNotEmpty && parts[1].isNotEmpty;
}

bool _isDeletionCandidate(_WorkflowRun run) {
  final conclusion = (run.conclusion ?? '').toLowerCase();

  if (conclusion == 'failure' || conclusion == 'cancelled') {
    return true;
  }

  if (conclusion == 'success') {
    return false;
  }

  final headBranch = run.headBranch;
  if (headBranch == null || headBranch.isEmpty) {
    return true;
  }
  return !_strictVersionTag.hasMatch(headBranch);
}

bool _isActive(String status) {
  return status == 'queued' || status == 'in_progress' || status == 'waiting';
}

Future<List<_WorkflowRun>> _fetchWorkflowRuns({
  required String repo,
  required String workflow,
  required int maxPages,
}) async {
  final runs = <_WorkflowRun>[];

  for (var page = 1; page <= maxPages; page += 1) {
    final result = await runProcess(
      'gh',
      [
        'api',
        '--method',
        'GET',
        '--raw-field',
        'per_page=100',
        '--raw-field',
        'page=$page',
        'repos/$repo/actions/workflows/$workflow/runs',
      ],
      throwOnError: true,
    );

    final body = result.stdout.toString();
    final map = jsonDecode(body) as Map<String, dynamic>;
    final pageRuns = (map['workflow_runs'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();

    if (pageRuns.isEmpty) {
      break;
    }

    runs.addAll(pageRuns.map(_WorkflowRun.fromJson));

    if (pageRuns.length < 100) {
      break;
    }
  }

  return runs;
}

class _WorkflowRun {
  _WorkflowRun({
    required this.id,
    required this.status,
    required this.conclusion,
    required this.event,
    required this.headBranch,
  });

  factory _WorkflowRun.fromJson(Map<String, dynamic> json) {
    return _WorkflowRun(
      id: json['id'] as int,
      status: (json['status'] as String?) ?? 'unknown',
      conclusion: json['conclusion'] as String?,
      event: json['event'] as String?,
      headBranch: json['head_branch'] as String?,
    );
  }

  final int id;
  final String status;
  final String? conclusion;
  final String? event;
  final String? headBranch;
}
