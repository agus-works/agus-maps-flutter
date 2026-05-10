import 'package:agus_maps_flutter_example/features/workbench/workbench_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('activity selection reselect hides primary sidebar', () {
    final controller = WorkbenchController();

    controller.selectActivity(WorkbenchActivity.search);
    expect(controller.state.activeActivity, WorkbenchActivity.search);
    expect(controller.state.primarySideBarVisible, isTrue);

    controller.selectActivity(WorkbenchActivity.search);
    expect(controller.state.primarySideBarVisible, isFalse);

    controller.selectActivity(WorkbenchActivity.downloads);
    expect(controller.state.activeActivity, WorkbenchActivity.downloads);
    expect(controller.state.primarySideBarVisible, isTrue);
  });

  test('panel and secondary sidebar tab selection makes surfaces visible', () {
    final controller = WorkbenchController(
      state: const WorkbenchLayoutState(
        panelVisible: false,
        secondarySideBarVisible: false,
      ),
    );

    controller.selectPanelTab(WorkbenchPanelTab.debugConsole);
    expect(controller.state.activePanelTab, WorkbenchPanelTab.debugConsole);
    expect(controller.state.panelVisible, isTrue);

    controller
        .selectSecondarySideBarTab(WorkbenchSecondarySideBarTab.inspector);
    expect(
      controller.state.activeSecondarySideBarTab,
      WorkbenchSecondarySideBarTab.inspector,
    );
    expect(controller.state.secondarySideBarVisible, isTrue);
  });

  test('resizing clamps to min and max boundaries', () {
    final controller = WorkbenchController();

    controller.resizePrimarySideBar(-10000);
    controller.resizeSecondarySideBar(-10000);
    controller.resizePanel(-10000);
    expect(controller.state.primarySideBarWidth, 240);
    expect(controller.state.secondarySideBarWidth, 240);
    expect(controller.state.panelHeight, 160);

    controller.resizePrimarySideBar(10000);
    controller.resizeSecondarySideBar(10000);
    controller.resizePanel(10000);
    expect(controller.state.primarySideBarWidth, 560);
    expect(controller.state.secondarySideBarWidth, 560);
    expect(controller.state.panelHeight, 520);
  });
}
