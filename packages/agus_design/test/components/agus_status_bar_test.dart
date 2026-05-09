import 'package:agus_design/agus_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  testWidgets('status bar renders left and right items', (tester) async {
    await pumpAgusWidget(
      tester,
      const AgusStatusBar(
        leftItems: [
          AgusStatusBarItem(
            id: 'branch',
            label: 'main',
            icon: Icons.call_split,
          ),
        ],
        rightItems: [AgusStatusBarItem(id: 'language', label: 'Dart')],
      ),
    );

    expect(find.text('main'), findsOneWidget);
    expect(find.text('Dart'), findsOneWidget);
  });

  testWidgets('status bar renders progress and severity variants', (
    tester,
  ) async {
    await pumpAgusWidget(
      tester,
      const AgusStatusBar(
        leftItems: [
          AgusStatusBarItem(id: 'sync', label: 'Syncing', progress: true),
          AgusStatusBarItem(
            id: 'warning',
            label: 'Warning',
            severity: AgusStatusBarItemSeverity.warning,
          ),
          AgusStatusBarItem(
            id: 'error',
            label: 'Error',
            severity: AgusStatusBarItemSeverity.error,
          ),
        ],
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Warning'), findsOneWidget);
    expect(find.text('Error'), findsOneWidget);
  });

  testWidgets('status bar item view emits taps and renders icon state', (
    tester,
  ) async {
    var tapped = false;

    await pumpAgusWidget(
      tester,
      AgusStatusBarItemView(
        item: AgusStatusBarItem(
          id: 'language',
          label: 'Dart',
          icon: Icons.code,
          onPressed: () => tapped = true,
        ),
      ),
      size: const Size(180, 40),
    );

    await tester.tap(find.text('Dart'));

    expect(find.byIcon(Icons.code), findsOneWidget);
    expect(tapped, isTrue);
  });
}
