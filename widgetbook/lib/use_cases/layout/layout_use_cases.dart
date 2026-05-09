import 'package:agus_design/agus_design.dart';
import 'package:flutter/material.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../src/catalog_data.dart';

@widgetbook.UseCase(
  name: 'Resizable panes',
  type: AgusSplitView,
  path: '[Layouts]/workspace',
)
Widget buildAgusSplitViewUseCase(BuildContext context) {
  final axis = context.knobs.object.segmented<Axis>(
    label: 'Axis',
    initialOption: Axis.horizontal,
    options: const [Axis.horizontal, Axis.vertical],
    labelBuilder: (value) =>
        value == Axis.horizontal ? 'Horizontal' : 'Vertical',
  );
  final initialFirstExtent = context.knobs.double.slider(
    label: 'Initial sized extent',
    initialValue: axis == Axis.horizontal ? 220 : 160,
    min: 100,
    max: axis == Axis.horizontal ? 420 : 240,
    divisions: 8,
  );
  final sizedPane = context.knobs.object.segmented<AgusSplitViewPane>(
    label: 'Sized pane',
    initialOption: AgusSplitViewPane.first,
    options: AgusSplitViewPane.values,
    labelBuilder: (value) =>
        value == AgusSplitViewPane.first ? 'First pane' : 'Second pane',
  );

  final preview = AgusSplitView(
    axis: axis,
    initialFirstExtent: initialFirstExtent,
    sizedPane: sizedPane,
    minFirstExtent: 100,
    minSecondExtent: 120,
    first: ColoredBox(
      color: AgusThemeData.colorsOf(context).sideBarBackground,
      child: const Center(child: Text('Primary pane')),
    ),
    second: ColoredBox(
      color: AgusThemeData.colorsOf(context).editorBackground,
      child: const Center(child: Text('Editor pane')),
    ),
  );

  return previewFrame(
    context,
    width: axis == Axis.horizontal ? 760 : 420,
    height: axis == Axis.horizontal ? 300 : 420,
    padding: EdgeInsets.zero,
    child: preview,
  );
}

@widgetbook.UseCase(
  name: 'Full workbench',
  type: AgusWorkbench,
  path: '[Layouts]/workspace',
)
Widget buildAgusWorkbenchUseCase(BuildContext context) {
  final showPrimarySidebar = context.knobs.boolean(
    label: 'Show primary sidebar',
    initialValue: true,
  );
  final showSecondarySidebar = context.knobs.boolean(
    label: 'Show secondary sidebar',
    initialValue: false,
  );
  final showPanel = context.knobs.boolean(
    label: 'Show bottom panel',
    initialValue: true,
  );
  final initialActivityId = context.knobs.object.dropdown<String>(
    label: 'Initial activity',
    initialOption: 'explorer',
    options: const ['explorer', 'search', 'source', 'debug', 'settings'],
  );

  return previewFrame(
    context,
    width: 1200,
    height: 760,
    padding: EdgeInsets.zero,
    child: WorkbenchPreview(
      key: ValueKey(
        '$showPrimarySidebar-$showSecondarySidebar-$showPanel-$initialActivityId',
      ),
      showPrimarySidebar: showPrimarySidebar,
      showSecondarySidebar: showSecondarySidebar,
      showPanel: showPanel,
      initialActivityId: initialActivityId,
    ),
  );
}
