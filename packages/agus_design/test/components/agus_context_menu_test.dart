import 'dart:async';

import 'package:agus_design/agus_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  testWidgets('context menu shows VS Code-style actions and returns value', (
    tester,
  ) async {
    final completer = Completer<String?>();

    await pumpAgusWidget(
      tester,
      Builder(
        builder: (context) {
          return GestureDetector(
            onTapDown: (details) {
              unawaited(
                showAgusContextMenu<String>(
                  context: context,
                  globalPosition: details.globalPosition,
                  entries: const [
                    AgusContextMenuAction(
                      value: 'add',
                      icon: Icons.add,
                      label: 'Add Feature...',
                    ),
                    AgusContextMenuSeparator(),
                    AgusContextMenuAction(
                      value: 'delete',
                      icon: Icons.delete_outline,
                      label: 'Delete Layer',
                      destructive: true,
                    ),
                  ],
                ).then(completer.complete),
              );
            },
            child: const SizedBox.expand(child: Text('Open Menu')),
          );
        },
      ),
    );

    await tester.tap(find.text('Open Menu'));
    await tester.pumpAndSettle();

    expect(find.text('Add Feature...'), findsOneWidget);
    expect(find.text('Delete Layer'), findsOneWidget);

    await tester.tap(find.text('Add Feature...'));
    await tester.pumpAndSettle();

    expect(await completer.future, 'add');
  });
}
