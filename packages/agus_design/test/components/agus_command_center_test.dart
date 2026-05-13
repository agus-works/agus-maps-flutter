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

  test('command item supports fuzzy matching and label highlights', () {
    const item = AgusCommandItem(
      id: 'new-file',
      label: 'New File',
      keywords: ['create document'],
    );

    final fuzzy = item.match('nf');
    final keyword = item.match('doc');

    expect(fuzzy, isNotNull);
    expect(fuzzy!.labelIndexes, containsAll(<int>[0, 4]));
    expect(keyword, isNotNull);
    expect(keyword!.labelIndexes, isEmpty);
    expect(item.match('zz'), isNull);
  });

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

  testWidgets('command dialog fuzzy-filters and ranks matching items', (
    tester,
  ) async {
    await pumpAgusWidget(
      tester,
      const SizedBox(
        width: 460,
        child: AgusCommandDialog(
          groups: [
            AgusCommandGroup(
              heading: 'Actions',
              items: [
                AgusCommandItem(
                  id: 'open-file',
                  label: 'Open File',
                  keywords: ['document'],
                ),
                AgusCommandItem(id: 'new-file', label: 'New File'),
                AgusCommandItem(id: 'settings', label: 'Settings'),
              ],
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'nf');
    await tester.pumpAndSettle();

    expect(find.text('New File'), findsOneWidget);
    expect(find.text('Settings'), findsNothing);
  });

  testWidgets('command dialog appends async provider results for query', (
    tester,
  ) async {
    String? selected;

    await pumpAgusWidget(
      tester,
      SizedBox(
        width: 460,
        child: AgusCommandDialog(
          groups: const [],
          asyncProviders: [
            (query) async => [
              AgusCommandGroup(
                heading: 'Locations',
                items: [
                  AgusCommandItem(
                    id: 'search-$query',
                    label: 'Search Location: $query',
                    icon: Icons.place_outlined,
                    onSelected: () => selected = query,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Gibraltar');
    await tester.pumpAndSettle();

    expect(find.text('LOCATIONS'), findsOneWidget);
    await tester.tap(find.text('Search Location: Gibraltar'));
    await tester.pumpAndSettle();

    expect(selected, 'Gibraltar');
  });

  testWidgets('command dialog de-duplicates repeated command ids', (
    tester,
  ) async {
    await pumpAgusWidget(
      tester,
      const SizedBox(
        width: 460,
        child: AgusCommandDialog(
          groups: [
            AgusCommandGroup(
              heading: 'Primary',
              items: [AgusCommandItem(id: 'open', label: 'Open')],
            ),
            AgusCommandGroup(
              heading: 'Secondary',
              items: [AgusCommandItem(id: 'open', label: 'Open Duplicate')],
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Open Duplicate'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('command center survives an open overlay rebuild', (
    tester,
  ) async {
    final controller = AgusCommandController();
    var showExtra = false;
    late StateSetter rebuildCommandCenter;

    await pumpAgusWidget(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          rebuildCommandCenter = setState;
          return Column(
            children: [
              SizedBox(
                width: 460,
                height: 24,
                child: AgusCommandCenter(
                  controller: controller,
                  groups: [
                    AgusCommandGroup(
                      heading: 'Actions',
                      items: [
                        const AgusCommandItem(id: 'open', label: 'Open'),
                        if (showExtra)
                          const AgusCommandItem(
                            id: 'extra',
                            label: 'Extra Command',
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    await tester.tap(find.text('Search or run a command'));
    await tester.pumpAndSettle();
    rebuildCommandCenter(() => showExtra = true);
    await tester.pumpAndSettle();

    expect(find.text('Extra Command'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
