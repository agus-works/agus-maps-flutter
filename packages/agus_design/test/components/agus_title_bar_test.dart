import 'package:agus_design/agus_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  testWidgets('title bar renders title and default command center', (
    tester,
  ) async {
    await pumpAgusWidget(
      tester,
      const AgusTitleBar(title: 'Agus Design'),
      size: const Size(960, 80),
    );

    expect(find.text('Agus Design'), findsOneWidget);
    expect(find.text('Search or run a command'), findsOneWidget);

    final titleText = tester.widget<Text>(find.text('Agus Design'));
    expect(titleText.style?.fontWeight, FontWeight.w500);
  });

  testWidgets('title bar renders custom actions and command center', (
    tester,
  ) async {
    await pumpAgusWidget(
      tester,
      AgusTitleBar(
        title: 'Agus Design',
        commandCenter: const AgusCommandCenter(prompt: 'Open anything'),
        leadingActions: const [Icon(Icons.menu)],
        trailingActions: const [Icon(Icons.minimize), Icon(Icons.close)],
      ),
      size: const Size(960, 80),
    );

    expect(find.text('Open anything'), findsOneWidget);
    expect(find.byIcon(Icons.menu), findsOneWidget);
    expect(find.byIcon(Icons.minimize), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets('command center renders prompt and trailing widget', (
    tester,
  ) async {
    await pumpAgusWidget(
      tester,
      const AgusCommandCenter(
        prompt: 'Search files',
        trailing: Icon(Icons.keyboard_command_key),
      ),
    );

    expect(find.text('Search files'), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_command_key), findsOneWidget);
  });

  testWidgets('title bar layout uses flexible spacing', (tester) async {
    await pumpAgusWidget(
      tester,
      const AgusTitleBar(
        title: 'Very Long Application Title Here',
        trailingActions: [
          Icon(Icons.minimize),
          Icon(Icons.maximize),
          Icon(Icons.close),
        ],
      ),
      size: const Size(1200, 80),
    );

    expect(find.text('Very Long Application Title Here'), findsOneWidget);
    expect(find.byIcon(Icons.minimize), findsOneWidget);
  });

  testWidgets('title bar respects narrow widths', (tester) async {
    await pumpAgusWidget(
      tester,
      const AgusTitleBar(title: 'Agus'),
      size: const Size(600, 80),
    );

    expect(find.text('Agus'), findsOneWidget);
    expect(find.text('Search or run a command'), findsOneWidget);
  });
}
