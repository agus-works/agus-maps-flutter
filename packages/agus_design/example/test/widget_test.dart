import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agus_design_example/main.dart';

void main() {
  testWidgets('renders the Agus Design kitchen sink workbench', (tester) async {
    await tester.pumpWidget(const AgusDesignExampleApp());

    expect(find.text('Agus Design'), findsOneWidget);
    expect(find.text('EXPLORER'), findsOneWidget);
    expect(find.text('PLAN.md'), findsWidgets);
  });

  testWidgets('opens settings from the Activity Bar without render overflow', (
    tester,
  ) async {
    await tester.pumpWidget(const AgusDesignExampleApp());

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Editor: Font Size'), findsOneWidget);
    expect(find.text('EXPLORER'), findsNothing);
  });

  testWidgets('toggles between dark and light themes from the title bar', (
    tester,
  ) async {
    await tester.pumpWidget(const AgusDesignExampleApp());

    expect(find.text('Dark'), findsOneWidget);
    expect(find.byTooltip('Switch to light theme'), findsOneWidget);

    await tester.tap(find.byTooltip('Switch to light theme'));
    await tester.pumpAndSettle();

    expect(find.text('Light'), findsOneWidget);
    expect(find.byTooltip('Switch to dark theme'), findsOneWidget);
  });
}
