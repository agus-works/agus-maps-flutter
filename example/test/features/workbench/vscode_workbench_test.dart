import 'package:agus_design/agus_design.dart';
import 'package:agus_maps_flutter_example/features/workbench/vscode_workbench.dart';
import 'package:agus_maps_flutter_example/features/workbench/workbench_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers.dart';

void main() {
  testWidgets('workbench uses design widgets and maps controller state', (
    tester,
  ) async {
    final controller = WorkbenchController();

    await pumpExampleWidget(
      tester,
      VSCodeWorkbench(
        controller: controller,
        activityBuilder: (_, activity) => Text('activity:${activity.name}'),
        editorBuilder: (_, tab) => Text('editor:${tab.name}'),
        panelBuilder: (_, tab) => Text('panel:${tab.name}'),
        secondarySideBarBuilder: (_, tab) => Text('side:${tab.name}'),
        commandGroups: [
          AgusCommandGroup(
            heading: 'Workbench',
            items: [
              AgusCommandItem(
                id: 'show-search',
                label: 'Show Search',
                icon: Icons.search,
                onSelected: () {
                  controller.selectActivity(WorkbenchActivity.search);
                },
              ),
            ],
          ),
        ],
        statusBarBuilder: (_, state) => AgusStatusBar(
          leftItems: [
            AgusStatusBarItem(
              id: 'activity',
              label: state.activeActivity.name,
              icon: Icons.public,
            ),
          ],
          rightItems: const [
            AgusStatusBarItem(id: 'ready', label: 'Ready'),
          ],
        ),
      ),
      size: const Size(1600, 900),
    );

    expect(find.byType(AgusWorkbench), findsOneWidget);
    expect(find.byType(AgusPanelTabBar), findsNothing);
    expect(find.byType(AgusEditorTabBar), findsNWidgets(2));
    expect(find.byType(AgusViewPaneContainer), findsOneWidget);
    expect(find.text('activity:explorer'), findsOneWidget);
    expect(find.text('editor:map'), findsOneWidget);
    expect(find.text('panel:pointOfInterest'), findsOneWidget);
    expect(find.text('side:properties'), findsOneWidget);
    expect(find.text('side:inspector'), findsOneWidget);

    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    expect(controller.state.activeActivity, WorkbenchActivity.search);
    expect(find.text('activity:search'), findsOneWidget);

    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    expect(controller.state.primarySideBarVisible, isFalse);

    await tester.tap(_tabText(0, 'Blank'));
    await tester.pumpAndSettle();
    expect(controller.state.activeEditorTab, WorkbenchEditorTab.blank);
    expect(find.text('editor:blank'), findsOneWidget);

    await tester.tap(_tabText(1, 'Debug Console'));
    await tester.pumpAndSettle();
    expect(controller.state.activePanelTab, WorkbenchPanelTab.debugConsole);
    expect(controller.state.panelVisible, isTrue);
    expect(find.text('panel:debugConsole'), findsOneWidget);

    controller
        .selectSecondarySideBarTab(WorkbenchSecondarySideBarTab.inspector);
    await tester.pumpAndSettle();
    expect(
      controller.state.activeSecondarySideBarTab,
      WorkbenchSecondarySideBarTab.inspector,
    );
    expect(find.text('side:inspector'), findsOneWidget);

    await tester.tap(find.byTooltip('Hide Panel'));
    await tester.pumpAndSettle();
    expect(controller.state.panelVisible, isFalse);

    await tester.tap(find.text('Search maps, commands, and layers'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show Search'));
    await tester.pumpAndSettle();
    expect(controller.state.activeActivity, WorkbenchActivity.search);
  });

  testWidgets('workbench renders reordered tabs with content keyed by tab id', (
    tester,
  ) async {
    final controller = WorkbenchController(
      state: const WorkbenchLayoutState(
        activeEditorTab: WorkbenchEditorTab.map,
        activePanelTab: WorkbenchPanelTab.pointOfInterest,
        activeSecondarySideBarTab: WorkbenchSecondarySideBarTab.properties,
        editorTabOrder: [WorkbenchEditorTab.map, WorkbenchEditorTab.blank],
        panelTabOrder: [
          WorkbenchPanelTab.debugConsole,
          WorkbenchPanelTab.pointOfInterest,
        ],
        secondarySideBarTabOrder: [
          WorkbenchSecondarySideBarTab.inspector,
          WorkbenchSecondarySideBarTab.properties,
        ],
      ),
    );

    await pumpExampleWidget(
      tester,
      VSCodeWorkbench(
        controller: controller,
        activityBuilder: (_, activity) => Text('activity:${activity.name}'),
        editorBuilder: (_, tab) => Text('editor:${tab.name}'),
        panelBuilder: (_, tab) => Text('panel:${tab.name}'),
        secondarySideBarBuilder: (_, tab) => Text('side:${tab.name}'),
      ),
      size: const Size(1600, 900),
    );

    final mapRect = tester.getRect(_tabText(0, 'Map'));
    final blankRect = tester.getRect(_tabText(0, 'Blank'));
    final debugRect = tester.getRect(_tabText(1, 'Debug Console'));
    final pointRect = tester.getRect(_tabText(1, 'Point of Interest'));
    final inspectorRect = tester.getRect(find.text('INSPECTOR'));
    final propertiesRect = tester.getRect(find.text('PROPERTIES'));

    expect(mapRect.left, lessThan(blankRect.left));
    expect(debugRect.left, lessThan(pointRect.left));
    expect(inspectorRect.top, lessThan(propertiesRect.top));
    expect(find.text('editor:map'), findsOneWidget);
    expect(find.text('panel:pointOfInterest'), findsOneWidget);
    expect(find.text('side:properties'), findsOneWidget);
    expect(find.text('side:inspector'), findsOneWidget);
  });
}

Finder _tabText(int tabBarIndex, String text) {
  return find.descendant(
    of: find.byType(AgusEditorTabBar).at(tabBarIndex),
    matching: find.text(text),
  );
}
