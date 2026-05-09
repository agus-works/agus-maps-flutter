import 'package:agus_design/agus_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  testWidgets('activity bar emits selection changes for enabled items', (
    tester,
  ) async {
    String? selectedId;

    await pumpAgusWidget(
      tester,
      AgusActivityBar(
        selectedId: 'explorer',
        onSelected: (id) => selectedId = id,
        items: const [
          AgusActivityBarItem(
            id: 'explorer',
            icon: Icons.folder,
            tooltip: 'Explorer',
          ),
          AgusActivityBarItem(
            id: 'search',
            icon: Icons.search,
            tooltip: 'Search',
          ),
        ],
      ),
    );

    await tester.tap(find.byIcon(Icons.search));

    expect(selectedId, 'search');
  });

  testWidgets('activity bar does not emit selection for disabled items', (
    tester,
  ) async {
    String? selectedId;

    await pumpAgusWidget(
      tester,
      AgusActivityBar(
        selectedId: 'explorer',
        onSelected: (id) => selectedId = id,
        items: const [
          AgusActivityBarItem(
            id: 'explorer',
            icon: Icons.folder,
            tooltip: 'Explorer',
          ),
          AgusActivityBarItem(
            id: 'search',
            icon: Icons.search,
            tooltip: 'Search',
            enabled: false,
          ),
        ],
      ),
    );

    await tester.tap(find.byIcon(Icons.search));

    expect(selectedId, isNull);
  });

  testWidgets('activity bar renders bottom items and caps large badges', (
    tester,
  ) async {
    await pumpAgusWidget(
      tester,
      const AgusActivityBar(
        selectedId: 'source',
        items: [
          AgusActivityBarItem(
            id: 'source',
            icon: Icons.account_tree,
            tooltip: 'Source Control',
            badgeCount: 120,
          ),
        ],
        bottomItems: [
          AgusActivityBarItem(
            id: 'settings',
            icon: Icons.settings,
            tooltip: 'Manage',
          ),
        ],
      ),
      size: const Size(120, 420),
    );

    expect(find.text('99+'), findsOneWidget);
    expect(find.byIcon(Icons.settings), findsOneWidget);
  });

  testWidgets('activity bar button renders badge and selected indicator', (
    tester,
  ) async {
    await pumpAgusWidget(
      tester,
      const AgusActivityBarButton(
        item: AgusActivityBarItem(
          id: 'source',
          icon: Icons.account_tree,
          tooltip: 'Source Control',
          badgeCount: 4,
        ),
        selected: true,
      ),
      size: const Size(80, 80),
    );

    expect(find.text('4'), findsOneWidget);
    expect(find.byType(DecoratedBox), findsWidgets);
  });

  testWidgets('activity bar button emits item id when tapped', (tester) async {
    String? selectedId;

    await pumpAgusWidget(
      tester,
      AgusActivityBarButton(
        item: const AgusActivityBarItem(
          id: 'search',
          icon: Icons.search,
          tooltip: 'Search',
        ),
        selected: false,
        onSelected: (id) => selectedId = id,
      ),
      size: const Size(80, 80),
    );

    await tester.tap(find.byIcon(Icons.search));

    expect(selectedId, 'search');
  });
}
