import 'package:agus_design/agus_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  AgusActivityBar buildActivityBar() {
    return const AgusActivityBar(
      selectedId: 'explorer',
      items: [
        AgusActivityBarItem(
          id: 'explorer',
          icon: Icons.folder,
          tooltip: 'Explorer',
        ),
      ],
    );
  }

  AgusStatusBar buildStatusBar() {
    return const AgusStatusBar(
      leftItems: [AgusStatusBarItem(id: 'branch', label: 'main')],
    );
  }

  testWidgets('workbench renders shell regions', (tester) async {
    await pumpAgusWidget(
      tester,
      AgusWorkbench(
        title: 'Agus Design',
        activityBar: buildActivityBar(),
        primarySidebar: const Text('Primary'),
        secondarySidebar: const Text('Secondary'),
        editor: const Text('Editor'),
        bottomPanel: const Text('Panel'),
        statusBar: buildStatusBar(),
        showSecondarySidebar: true,
      ),
      size: const Size(1200, 800),
    );

    expect(find.text('Agus Design'), findsOneWidget);
    expect(find.text('Primary'), findsOneWidget);
    expect(find.text('Secondary'), findsOneWidget);
    expect(find.text('Panel'), findsOneWidget);
    expect(find.text('main'), findsOneWidget);
    expect(find.byType(AgusSplitView), findsNWidgets(3));
  });

  testWidgets('workbench respects visibility flags', (tester) async {
    await pumpAgusWidget(
      tester,
      AgusWorkbench(
        title: 'Agus Design',
        activityBar: buildActivityBar(),
        primarySidebar: const Text('Primary'),
        editor: const Text('Editor'),
        bottomPanel: const Text('Panel'),
        statusBar: buildStatusBar(),
        showPrimarySidebar: false,
        showPanel: false,
      ),
      size: const Size(1200, 800),
    );

    expect(find.text('Primary'), findsNothing);
    expect(find.text('Panel'), findsNothing);
    expect(find.text('Editor'), findsOneWidget);
  });

  testWidgets('workbench title bar pane controls emit toggle callbacks', (
    tester,
  ) async {
    final toggledAreas = <AgusWorkbenchArea>[];

    await pumpAgusWidget(
      tester,
      AgusWorkbench(
        title: 'Agus Design',
        activityBar: buildActivityBar(),
        primarySidebar: const Text('Primary'),
        secondarySidebar: const Text('Secondary'),
        editor: const Text('Editor'),
        bottomPanel: const Text('Panel'),
        statusBar: buildStatusBar(),
        showSecondarySidebar: true,
        onToggleArea: toggledAreas.add,
      ),
      size: const Size(1200, 800),
    );

    await tester.tap(find.byTooltip('Toggle primary sidebar'));
    await tester.tap(find.byTooltip('Toggle panel'));
    await tester.tap(find.byTooltip('Toggle secondary sidebar'));

    expect(toggledAreas, [
      AgusWorkbenchArea.primarySidebar,
      AgusWorkbenchArea.panel,
      AgusWorkbenchArea.secondarySidebar,
    ]);
  });

  testWidgets('workbench pane controls show divider with trailing actions', (
    tester,
  ) async {
    await pumpAgusWidget(
      tester,
      AgusWorkbench(
        title: 'Agus Design',
        activityBar: buildActivityBar(),
        primarySidebar: const Text('Primary'),
        editor: const Text('Editor'),
        bottomPanel: const Text('Panel'),
        statusBar: buildStatusBar(),
        titleBarTrailingActions: const [Icon(Icons.settings)],
      ),
      size: const Size(1200, 800),
    );

    expect(find.byType(VerticalDivider), findsOneWidget);
    expect(find.byTooltip('Toggle primary sidebar'), findsOneWidget);
    expect(find.byTooltip('Toggle panel'), findsOneWidget);
    expect(find.byIcon(Icons.settings), findsOneWidget);
  });

  testWidgets('workbench pane controls hide divider without trailing actions', (
    tester,
  ) async {
    await pumpAgusWidget(
      tester,
      AgusWorkbench(
        title: 'Agus Design',
        activityBar: buildActivityBar(),
        primarySidebar: const Text('Primary'),
        editor: const Text('Editor'),
        bottomPanel: const Text('Panel'),
        statusBar: buildStatusBar(),
      ),
      size: const Size(1200, 800),
    );

    expect(find.byType(VerticalDivider), findsNothing);
    expect(find.byTooltip('Toggle primary sidebar'), findsOneWidget);
  });

  testWidgets('workbench respects showPaneControls flag', (tester) async {
    await pumpAgusWidget(
      tester,
      AgusWorkbench(
        title: 'Agus Design',
        activityBar: buildActivityBar(),
        primarySidebar: const Text('Primary'),
        editor: const Text('Editor'),
        bottomPanel: const Text('Panel'),
        statusBar: buildStatusBar(),
        showPaneControls: false,
      ),
      size: const Size(1200, 800),
    );

    expect(find.byTooltip('Toggle primary sidebar'), findsNothing);
    expect(find.byTooltip('Toggle panel'), findsNothing);
  });
}
