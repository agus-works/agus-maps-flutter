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
        trailingActions: const [Icon(Icons.minimize)],
      ),
      size: const Size(960, 80),
    );

    expect(find.text('Open anything'), findsOneWidget);
    expect(find.byIcon(Icons.menu), findsOneWidget);
    expect(find.byIcon(Icons.minimize), findsOneWidget);
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
}
