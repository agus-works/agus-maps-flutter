import 'package:agus_design/agus_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  testWidgets('pane renders header, subtitle, actions, and child', (
    tester,
  ) async {
    await pumpAgusWidget(
      tester,
      const AgusPane(
        title: 'Panel',
        subtitle: '2 items',
        actions: [Icon(Icons.refresh)],
        child: Text('Content'),
      ),
    );

    expect(find.text('Panel'), findsOneWidget);
    expect(find.text('2 items'), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
    expect(find.text('Content'), findsOneWidget);
  });

  testWidgets('pane omits default header when no header data is supplied', (
    tester,
  ) async {
    await pumpAgusWidget(tester, const AgusPane(child: Text('Only content')));

    expect(find.text('Only content'), findsOneWidget);
    expect(find.byType(Divider), findsNothing);
  });

  testWidgets('empty state renders optional icon, message, and action', (
    tester,
  ) async {
    await pumpAgusWidget(
      tester,
      const AgusEmptyState(
        icon: Icons.info_outline,
        title: 'Nothing selected',
        message: 'Select an item to inspect details.',
        action: Text('Create item'),
      ),
    );

    expect(find.byIcon(Icons.info_outline), findsOneWidget);
    expect(find.text('Nothing selected'), findsOneWidget);
    expect(find.text('Select an item to inspect details.'), findsOneWidget);
    expect(find.text('Create item'), findsOneWidget);
  });
}
