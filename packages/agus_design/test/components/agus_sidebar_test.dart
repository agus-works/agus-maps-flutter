import 'package:agus_design/agus_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  testWidgets('sidebar renders uppercase title, actions, and sections', (
    tester,
  ) async {
    await pumpAgusWidget(
      tester,
      AgusSidebar(
        title: 'Explorer',
        actions: const [Icon(Icons.add)],
        sections: const [
          AgusViewSection(title: 'Outline', child: Text('Widgets')),
        ],
      ),
    );

    expect(find.text('EXPLORER'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.text('OUTLINE'), findsOneWidget);
  });

  testWidgets(
    'view section starts collapsed when configured and toggles open',
    (tester) async {
      await pumpAgusWidget(
        tester,
        const AgusViewSection(
          title: 'Outline',
          initiallyExpanded: false,
          child: Text('Widgets'),
        ),
      );

      expect(find.text('Widgets'), findsNothing);

      await tester.tap(find.text('OUTLINE'));
      await tester.pumpAndSettle();

      expect(find.text('Widgets'), findsOneWidget);
    },
  );
}
