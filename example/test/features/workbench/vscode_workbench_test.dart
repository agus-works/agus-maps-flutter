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
    );

    expect(find.byType(AgusWorkbench), findsOneWidget);
    expect(find.byType(AgusPanelTabBar), findsNWidgets(2));
    expect(find.text('activity:explorer'), findsOneWidget);
    expect(find.text('editor:map'), findsOneWidget);
    expect(find.text('panel:pointOfInterest'), findsOneWidget);
    expect(find.text('side:properties'), findsOneWidget);

    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    expect(controller.state.activeActivity, WorkbenchActivity.search);
    expect(find.text('activity:search'), findsOneWidget);

    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    expect(controller.state.primarySideBarVisible, isFalse);

    await tester.tap(find.text('Blank'));
    await tester.pumpAndSettle();
    expect(controller.state.activeEditorTab, WorkbenchEditorTab.blank);
    expect(find.text('editor:blank'), findsOneWidget);

    await tester.tap(find.text('DEBUG CONSOLE'));
    await tester.pumpAndSettle();
    expect(controller.state.activePanelTab, WorkbenchPanelTab.debugConsole);
    expect(controller.state.panelVisible, isTrue);
    expect(find.text('panel:debugConsole'), findsOneWidget);

    await tester.tap(find.byTooltip('Hide Panel'));
    await tester.pumpAndSettle();
    expect(controller.state.panelVisible, isFalse);

    await tester.tap(find.text('INSPECTOR'));
    await tester.pumpAndSettle();
    expect(
      controller.state.activeSecondarySideBarTab,
      WorkbenchSecondarySideBarTab.inspector,
    );
    expect(find.text('side:inspector'), findsOneWidget);
  });
}
