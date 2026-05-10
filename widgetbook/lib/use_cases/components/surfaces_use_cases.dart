import 'package:agus_design/agus_design.dart';
import 'package:agus_design/agus_design_demo.dart';
import 'package:flutter/material.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../src/catalog_data.dart';

@widgetbook.UseCase(
  name: 'Window title bar',
  type: AgusTitleBar,
  path: '[Components]/surfaces',
)
Widget buildAgusTitleBarUseCase(BuildContext context) {
  final title = context.knobs.string(
    label: 'Title',
    initialValue: 'Agus Design Workspace',
  );
  final prompt = context.knobs.string(
    label: 'Command prompt',
    initialValue: 'Search or run a command',
  );
  final showLeading = context.knobs.boolean(
    label: 'Show leading action',
    initialValue: true,
  );
  final showTrailing = context.knobs.boolean(
    label: 'Show trailing action',
    initialValue: true,
  );

  return previewFrame(
    context,
    width: 960,
    height: 35,
    padding: EdgeInsets.zero,
    child: AgusTitleBar(
      title: title,
      commandCenter: AgusCommandCenter(prompt: prompt),
      leadingActions: showLeading
          ? const [Icon(Icons.menu, size: 18)]
          : const <Widget>[],
      trailingActions: showTrailing
          ? const [Icon(Icons.minimize, size: 18)]
          : const <Widget>[],
    ),
  );
}

@widgetbook.UseCase(
  name: 'Command center',
  type: AgusCommandCenter,
  path: '[Components]/surfaces',
)
Widget buildAgusCommandCenterUseCase(BuildContext context) {
  final prompt = context.knobs.string(
    label: 'Prompt',
    initialValue: 'Jump to a view, layer, or action',
  );

  return previewFrame(
    context,
    width: 460,
    height: 80,
    padding: EdgeInsets.zero,
    child: CommandCenterPreview(prompt: prompt),
  );
}

@widgetbook.UseCase(
  name: 'Command bar',
  type: AgusCommandBar,
  path: '[Components]/surfaces',
)
Widget buildAgusCommandBarUseCase(BuildContext context) {
  final prompt = context.knobs.string(
    label: 'Prompt',
    initialValue: 'Search or run a command',
  );
  final active = context.knobs.boolean(label: 'Active', initialValue: false);

  return previewFrame(
    context,
    width: 460,
    height: 80,
    padding: EdgeInsets.zero,
    child: CommandBarPreview(prompt: prompt, active: active),
  );
}

@widgetbook.UseCase(
  name: 'Command dialog',
  type: AgusCommandDialog,
  path: '[Components]/surfaces',
)
Widget buildAgusCommandDialogUseCase(BuildContext context) {
  final prompt = context.knobs.string(
    label: 'Prompt',
    initialValue: 'Search for layers, files, and actions',
  );

  return previewFrame(
    context,
    width: 460,
    height: 340,
    padding: EdgeInsets.zero,
    child: CommandDialogPreview(prompt: prompt),
  );
}

@widgetbook.UseCase(
  name: 'Explorer sidebar',
  type: AgusSidebar,
  path: '[Components]/surfaces',
)
Widget buildAgusSidebarUseCase(BuildContext context) {
  final title = context.knobs.string(label: 'Title', initialValue: 'Explorer');
  final showActions = context.knobs.boolean(
    label: 'Show actions',
    initialValue: true,
  );
  final sectionExpanded = context.knobs.boolean(
    label: 'Open editors expanded',
    initialValue: true,
  );
  final demo = buildExplorerTreeDemo(seed: 13);

  return previewFrame(
    context,
    width: 420,
    height: 460,
    padding: EdgeInsets.zero,
    child: AgusSidebar(
      title: title,
      actions: showActions
          ? const [
              Icon(Icons.add, size: 16),
              SizedBox(width: 8),
              Icon(Icons.more_horiz, size: 16),
            ]
          : const <Widget>[],
      sections: [
        AgusViewSection(
          title: 'Open Editors',
          initiallyExpanded: sectionExpanded,
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Text('PLAN.md\nagus_theme_data.dart\nsettings_schema.dart'),
          ),
        ),
        AgusViewSection(
          title: 'Workspace',
          actions: const [Icon(Icons.refresh, size: 16)],
          child: SizedBox(
            height: 280,
            child: TreeViewPreview(
              key: const ValueKey('sidebar-tree'),
              nodes: demo.nodes,
              initialSelectedId: demo.singleSelectedId,
              initialSelectedIds: demo.multiSelectedIds,
              initialExpandedIds: demo.expandedIds,
              columns: agusMetricTreeColumns,
              labelColumnTitle: 'Layer',
              selectionMode: AgusTreeSelectionMode.multiple,
              enableMutations: true,
            ),
          ),
        ),
      ],
    ),
  );
}

@widgetbook.UseCase(
  name: 'Collapsible section',
  type: AgusViewSection,
  path: '[Components]/surfaces',
)
Widget buildAgusViewSectionUseCase(BuildContext context) {
  final initiallyExpanded = context.knobs.boolean(
    label: 'Initially expanded',
    initialValue: true,
  );
  final title = context.knobs.string(
    label: 'Section title',
    initialValue: 'Outline',
  );

  return previewFrame(
    context,
    width: 320,
    child: AgusViewSection(
      title: title,
      initiallyExpanded: initiallyExpanded,
      actions: const [Icon(Icons.more_horiz, size: 16)],
      child: const Padding(
        padding: EdgeInsets.all(12),
        child: Text('Classes\nWidgets\nExtensions'),
      ),
    ),
  );
}

@widgetbook.UseCase(
  name: 'Editor host',
  type: AgusEditorHost,
  path: '[Components]/surfaces',
)
Widget buildAgusEditorHostUseCase(BuildContext context) {
  final label = context.knobs.stringOrNull(
    label: 'Semantics label',
    initialValue: 'Editor preview',
  );
  final showBorder = context.knobs.boolean(
    label: 'Show border',
    initialValue: true,
  );

  return previewFrame(
    context,
    width: 720,
    height: 300,
    padding: EdgeInsets.zero,
    child: AgusEditorHost(
      label: label,
      showBorder: showBorder,
      child: const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'AgusEditorHost can wrap Monaco, a webview, a native code editor, or a preview canvas.',
        ),
      ),
    ),
  );
}

@widgetbook.UseCase(
  name: 'Panel tab bar',
  type: AgusPanelTabBar,
  path: '[Components]/surfaces',
)
Widget buildAgusPanelTabBarUseCase(BuildContext context) {
  final showIcons = context.knobs.boolean(
    label: 'Show icons',
    initialValue: true,
  );
  final showClose = context.knobs.boolean(
    label: 'Show close buttons',
    initialValue: true,
  );
  final selectedId = context.knobs.object.dropdown<String>(
    label: 'Selected tab',
    initialOption: 'properties',
    options: const ['problems', 'properties', 'debug'],
  );

  return previewFrame(
    context,
    width: 520,
    height: 80,
    padding: EdgeInsets.zero,
    child: AgusPanelTabBar(
      selectedId: selectedId,
      tabs: [
        AgusPanelTab(
          id: 'problems',
          label: 'Problems',
          icon: showIcons ? Icons.error_outline : null,
        ),
        AgusPanelTab(
          id: 'properties',
          label: 'Properties',
          icon: showIcons ? Icons.list_alt : null,
          closable: showClose,
        ),
        AgusPanelTab(
          id: 'debug',
          label: 'Debug Console',
          icon: showIcons ? Icons.terminal : null,
          closable: showClose,
        ),
      ],
      trailing: const [
        Icon(Icons.add, size: 16),
        SizedBox(width: 8),
        Icon(Icons.more_horiz, size: 16),
        SizedBox(width: 8),
      ],
    ),
  );
}

@widgetbook.UseCase(
  name: 'Docked pane',
  type: AgusPane,
  path: '[Components]/surfaces',
)
Widget buildAgusPaneUseCase(BuildContext context) {
  final title = context.knobs.string(label: 'Title', initialValue: 'Inspector');
  final subtitle = context.knobs.stringOrNull(
    label: 'Subtitle',
    initialValue: 'Selected feature',
  );
  final showActions = context.knobs.boolean(
    label: 'Show actions',
    initialValue: true,
  );

  return previewFrame(
    context,
    width: 420,
    height: 320,
    padding: EdgeInsets.zero,
    child: AgusPane(
      title: title,
      subtitle: subtitle,
      actions: showActions
          ? const [
              Icon(Icons.refresh, size: 16),
              SizedBox(width: 8),
              Icon(Icons.more_horiz, size: 16),
            ]
          : const <Widget>[],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: AgusPropertyGrid(
          rows: const [
            AgusPropertyRow(
              name: 'Kind',
              value: AgusPropertyText('Point of interest'),
            ),
            AgusPropertyRow(name: 'Zoom', value: AgusPropertyText('14.0')),
            AgusPropertyRow(
              name: 'Coordinates',
              value: AgusPropertyText('37.7749, -122.4194'),
            ),
          ],
        ),
      ),
    ),
  );
}

@widgetbook.UseCase(
  name: 'Empty state',
  type: AgusEmptyState,
  path: '[Components]/surfaces',
)
Widget buildAgusEmptyStateUseCase(BuildContext context) {
  final title = context.knobs.string(
    label: 'Title',
    initialValue: 'No layer selected',
  );
  final message = context.knobs.stringOrNull(
    label: 'Message',
    initialValue: 'Select a project layer to inspect its attributes.',
  );
  final showAction = context.knobs.boolean(
    label: 'Show action',
    initialValue: true,
  );

  return previewFrame(
    context,
    width: 360,
    height: 260,
    padding: EdgeInsets.zero,
    child: AgusEmptyState(
      icon: Icons.layers_clear,
      title: title,
      message: message,
      action: showAction
          ? OutlinedButton(onPressed: () {}, child: const Text('Create layer'))
          : null,
    ),
  );
}

@widgetbook.UseCase(
  name: 'Property grid',
  type: AgusPropertyGrid,
  path: '[Components]/surfaces',
)
Widget buildAgusPropertyGridUseCase(BuildContext context) {
  final empty = context.knobs.boolean(label: 'Empty', initialValue: false);
  final nameWidth = context.knobs.double.slider(
    label: 'Name column width',
    initialValue: 112,
    min: 64,
    max: 180,
    divisions: 8,
  );
  final rowHeight = context.knobs.double.slider(
    label: 'Row height',
    initialValue: 22,
    min: 0,
    max: 48,
    divisions: 12,
  );

  return previewFrame(
    context,
    width: 420,
    height: 220,
    child: AgusPropertyGrid(
      nameWidth: nameWidth,
      rowHeight: rowHeight,
      emptyLabel: 'No metadata available.',
      rows: empty
          ? const <AgusPropertyRow>[]
          : const [
              AgusPropertyRow(name: 'Name', value: AgusPropertyText('Market')),
              AgusPropertyRow(name: 'Visible', value: AgusPropertyText('Yes')),
              AgusPropertyRow(
                name: 'Features',
                value: AgusPropertyText('1,284'),
              ),
              AgusPropertyRow(
                name: 'Bounds',
                value: AgusPropertyText(
                  '37.70,-122.52 - 37.83,-122.35',
                  maxLines: 2,
                ),
              ),
            ],
    ),
  );
}
