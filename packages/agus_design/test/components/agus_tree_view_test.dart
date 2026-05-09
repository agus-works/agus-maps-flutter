import 'dart:ui';

import 'package:agus_design/agus_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  const nodes = [
    AgusTreeNode(
      id: 'root',
      label: 'Root',
      icon: Icons.folder,
      children: [
        AgusTreeNode(
          id: 'child',
          label: 'Child',
          icon: Icons.description,
          badgeLabel: '3',
        ),
      ],
    ),
    AgusTreeNode(
      id: 'disabled',
      label: 'Disabled',
      icon: Icons.lock_outline,
      disabled: true,
    ),
  ];

  testWidgets('tree view renders expanded children and badges', (tester) async {
    await pumpAgusWidget(
      tester,
      const AgusTreeView(
        nodes: nodes,
        expandedIds: {'root'},
        selectedId: 'child',
      ),
    );

    expect(find.text('Child'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('tree view emits selection and toggle callbacks', (tester) async {
    String? selectedId;
    String? toggledId;

    await pumpAgusWidget(
      tester,
      AgusTreeView(
        nodes: nodes,
        onSelected: (id) => selectedId = id,
        onToggle: (id) => toggledId = id,
      ),
    );

    await tester.tap(find.text('Root'));
    await tester.tap(find.byIcon(Icons.keyboard_arrow_right));

    expect(selectedId, 'root');
    expect(toggledId, 'root');
  });

  testWidgets('tree view ignores taps on disabled rows', (tester) async {
    String? selectedId;

    await pumpAgusWidget(
      tester,
      AgusTreeView(nodes: nodes, onSelected: (id) => selectedId = id),
    );

    await tester.tap(find.text('Disabled'));

    expect(selectedId, isNull);
  });

  testWidgets('tree view supports multi-select and visibility columns', (
    tester,
  ) async {
    Set<String>? selectedIds;
    AgusTreeVisibilityState? visibility;

    await pumpAgusWidget(
      tester,
      AgusTreeView(
        labelColumnTitle: 'Layer',
        columns: const [
          AgusTreeColumn(id: 'features', label: 'Features'),
          AgusTreeColumn(id: 'segments', label: 'Segments'),
        ],
        selectionMode: AgusTreeSelectionMode.multiple,
        selectedIds: const {'child'},
        expandedIds: const {'root'},
        nodes: const [
          AgusTreeNode(
            id: 'root',
            label: 'Root',
            icon: Icons.folder,
            visibility: AgusTreeVisibilityState.mixed,
            columnValues: {'features': '4', 'segments': '24'},
            children: [
              AgusTreeNode(
                id: 'child',
                label: 'Child',
                icon: Icons.description,
                visibility: AgusTreeVisibilityState.visible,
                columnValues: {'features': '2', 'segments': '12'},
              ),
            ],
          ),
        ],
        onSelectionChanged: (ids) => selectedIds = ids,
        onVisibilityChanged: (id, nextVisibility) =>
            visibility = nextVisibility,
      ),
    );

    expect(find.text('Features'), findsOneWidget);
    expect(find.text('24'), findsOneWidget);

    await tester.tap(find.text('Root'));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.visibility).first);
    await tester.pump();

    expect(selectedIds, {'child', 'root'});
    expect(visibility, AgusTreeVisibilityState.visible);
  });

  testWidgets('tree view compresses metric columns in narrow widths', (
    tester,
  ) async {
    await pumpAgusWidget(
      tester,
      SizedBox(
        width: 300,
        height: 120,
        child: AgusTreeView(
          labelColumnTitle: 'Layer',
          columns: const [
            AgusTreeColumn(id: 'features', label: 'Features', width: 72),
            AgusTreeColumn(id: 'segments', label: 'Segments', width: 84),
            AgusTreeColumn(id: 'vertices', label: 'Vertices', width: 88),
          ],
          expandedIds: const {'root'},
          nodes: const [
            AgusTreeNode(
              id: 'root',
              label: 'Root layer',
              icon: Icons.folder,
              visibility: AgusTreeVisibilityState.visible,
              columnValues: {
                'features': '4',
                'segments': '24',
                'vertices': '128',
              },
              children: [
                AgusTreeNode(
                  id: 'child',
                  label: 'Child layer',
                  icon: Icons.description,
                  columnValues: {
                    'features': '2',
                    'segments': '12',
                    'vertices': '64',
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Layer'), findsOneWidget);
    expect(find.text('Root layer'), findsOneWidget);
    expect(find.text('128'), findsOneWidget);
  });

  testWidgets('tree view clips deep label affordances in narrow widths', (
    tester,
  ) async {
    await pumpAgusWidget(
      tester,
      const SizedBox(
        width: 240,
        height: 140,
        child: AgusTreeView(
          expandedIds: {'root', 'branch', 'leaf-parent'},
          nodes: [
            AgusTreeNode(
              id: 'root',
              label: 'Root',
              icon: Icons.folder,
              children: [
                AgusTreeNode(
                  id: 'branch',
                  label: 'Branch',
                  icon: Icons.folder,
                  children: [
                    AgusTreeNode(
                      id: 'leaf-parent',
                      label: 'Leaf parent',
                      icon: Icons.folder,
                      children: [
                        AgusTreeNode(
                          id: 'leaf',
                          label:
                              'Very long nested layer label that must never overflow',
                          icon: Icons.description,
                          visibility: AgusTreeVisibilityState.visible,
                          badgeLabel: '999',
                          deletable: true,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Very long nested'), findsOneWidget);
  });

  testWidgets('tree view renames on double tap and deletes on hover', (
    tester,
  ) async {
    String? renamedLabel;
    String? deletedId;

    await pumpAgusWidget(
      tester,
      AgusTreeView(
        expandedIds: const {'root'},
        nodes: const [
          AgusTreeNode(
            id: 'root',
            label: 'Root',
            icon: Icons.folder,
            children: [
              AgusTreeNode(
                id: 'child',
                label: 'Child',
                icon: Icons.description,
                renamable: true,
                deletable: true,
              ),
            ],
          ),
        ],
        onRename: (id, label) => renamedLabel = label,
        onDelete: (id) => deletedId = id,
      ),
    );

    await tester.tap(find.text('Child'));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(find.text('Child'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Renamed Child');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(find.text('Child')));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pump();

    expect(renamedLabel, 'Renamed Child');
    expect(deletedId, 'child');
  });
}
