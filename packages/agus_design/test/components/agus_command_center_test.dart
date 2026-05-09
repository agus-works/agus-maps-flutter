import 'package:agus_design/agus_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  List<AgusCommandGroup> buildGroups({
    required VoidCallback onHome,
    required VoidCallback onInbox,
  }) {
    return [
      AgusCommandGroup(
        heading: 'Navigation',
        items: [
          AgusCommandItem(
            id: 'home',
            label: 'Home',
            icon: Icons.home_outlined,
            shortcut: const SingleActivator(LogicalKeyboardKey.keyH),
            shortcutLabel: 'H',
            onSelected: onHome,
          ),
          AgusCommandItem(
            id: 'inbox',
            label: 'Inbox',
            icon: Icons.inbox_outlined,
            shortcut: const SingleActivator(LogicalKeyboardKey.keyI),
            shortcutLabel: 'I',
            onSelected: onInbox,
          ),
        ],
      ),
    ];
  }

  testWidgets('command bar renders prompt and trailing shortcut', (
    tester,
  ) async {
    await pumpAgusWidget(
      tester,
      const SizedBox(
        width: 460,
        height: 24,
        child: AgusCommandBar(
          prompt: 'Search or run a command',
          trailing: Text('⌘K'),
        ),
      ),
    );

    expect(find.text('Search or run a command'), findsOneWidget);
    expect(find.text('⌘K'), findsOneWidget);
  });

  testWidgets('command dialog supports keyboard navigation and selection', (
    tester,
  ) async {
    String? selected;
    final groups = buildGroups(
      onHome: () => selected = 'home',
      onInbox: () => selected = 'inbox',
    );

    await pumpAgusWidget(
      tester,
      SizedBox(
        width: 460,
        child: AgusCommandDialog(groups: groups, prompt: 'Jump to a view'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('NAVIGATION'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(selected, 'inbox');
  });

  testWidgets('command center opens overlay and selects a command', (
    tester,
  ) async {
    String? selected;
    final controller = AgusCommandController();
    final groups = buildGroups(
      onHome: () => selected = 'home',
      onInbox: () => selected = 'inbox',
    );

    await pumpAgusWidget(
      tester,
      AgusCommandShortcutHost(
        controller: controller,
        groups: groups,
        openShortcut: const SingleActivator(LogicalKeyboardKey.keyP),
        child: Center(
          child: SizedBox(
            width: 460,
            height: 24,
            child: AgusCommandCenter(
              controller: controller,
              groups: groups,
              prompt: 'Jump to a view',
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Jump to a view'));
    await tester.pumpAndSettle();

    expect(find.text('NAVIGATION'), findsOneWidget);
    await tester.tap(find.text('Inbox'));
    await tester.pumpAndSettle();

    expect(selected, 'inbox');
    expect(find.text('NAVIGATION'), findsNothing);
  });
}
