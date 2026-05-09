import 'package:agus_design/agus_design.dart';
import 'package:agus_design/agus_design_demo.dart';
import 'package:flutter/material.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../src/catalog_data.dart';

@widgetbook.UseCase(
  name: 'Interactive',
  type: AgusActivityBar,
  path: '[Components]/navigation',
)
Widget buildAgusActivityBarUseCase(BuildContext context) {
  final selectedId = context.knobs.object.dropdown<String>(
    label: 'Selected item',
    initialOption: 'explorer',
    options: const ['explorer', 'search', 'source', 'debug', 'extensions'],
  );
  final showBottomItems = context.knobs.boolean(
    label: 'Show bottom items',
    initialValue: true,
  );
  final sourceBadgeCount = context.knobs.int.slider(
    label: 'Source badge',
    initialValue: 3,
    min: 0,
    max: 120,
  );
  final disableSearch = context.knobs.boolean(
    label: 'Disable search',
    initialValue: false,
  );
  final disableExtensions = context.knobs.boolean(
    label: 'Disable extensions',
    initialValue: false,
  );

  return previewFrame(
    context,
    width: 48,
    height: 420,
    padding: EdgeInsets.zero,
    child: ActivityBarPreview(
      key: ValueKey(
        '$selectedId-$showBottomItems-$sourceBadgeCount-$disableSearch-$disableExtensions',
      ),
      initialSelectedId: selectedId,
      items: buildActivityItems(
        sourceBadgeCount: sourceBadgeCount,
        disableSearch: disableSearch,
        disableExtensions: disableExtensions,
      ),
      bottomItems: showBottomItems ? buildBottomActivityItems() : const [],
    ),
  );
}

@widgetbook.UseCase(
  name: 'Button states',
  type: AgusActivityBarButton,
  path: '[Components]/navigation',
)
Widget buildAgusActivityBarButtonUseCase(BuildContext context) {
  final selected = context.knobs.boolean(label: 'Selected', initialValue: true);
  final enabled = context.knobs.boolean(label: 'Enabled', initialValue: true);
  final badgeCount = context.knobs.int.slider(
    label: 'Badge',
    initialValue: 3,
    min: 0,
    max: 120,
  );

  return previewFrame(
    context,
    width: 48,
    height: 56,
    padding: EdgeInsets.zero,
    child: AgusActivityBarButton(
      item: AgusActivityBarItem(
        id: 'source',
        icon: Icons.account_tree,
        tooltip: 'Source Control',
        enabled: enabled,
        badgeCount: badgeCount,
      ),
      selected: selected,
      onSelected: (_) {},
    ),
  );
}

@widgetbook.UseCase(
  name: 'Workspace tabs',
  type: AgusEditorTabBar,
  path: '[Components]/navigation',
)
Widget buildAgusEditorTabBarUseCase(BuildContext context) {
  final tabCount = context.knobs.int.slider(
    label: 'Open tab count',
    initialValue: 8,
    min: 4,
    max: 12,
    description:
        'Adds overflow tabs so horizontal touch, wheel, and scrollbar behavior can be inspected.',
  );
  final previewWidth = context.knobs.int.slider(
    label: 'Preview width',
    initialValue: 420,
    min: 260,
    max: 760,
    description:
        'Narrower widths mimic VS Code when more editor tabs are open than can fit.',
  );
  final dirtyPlan = context.knobs.boolean(
    label: 'Dirty plan tab',
    initialValue: true,
  );
  final pinTheme = context.knobs.boolean(
    label: 'Pin theme tab',
    initialValue: true,
  );
  final previewSettings = context.knobs.boolean(
    label: 'Preview settings tab',
    initialValue: true,
  );
  final closableWorkbench = context.knobs.boolean(
    label: 'Closable workbench tab',
    initialValue: true,
  );
  final tabs = [
    ...buildEditorTabs(
      dirtyPlan: dirtyPlan,
      pinTheme: pinTheme,
      previewSettings: previewSettings,
      closableWorkbench: closableWorkbench,
    ),
    for (var index = 5; index <= tabCount; index++)
      AgusEditorTab(
        id: 'tab-$index',
        label: 'workspace_part_$index.dart',
        icon: Icons.code,
        dirty: index.isEven,
        preview: index % 3 == 0,
      ),
  ];
  final selectedId = context.knobs.object.dropdown<String>(
    label: 'Selected tab',
    initialOption: tabs.last.id,
    options: [for (final tab in tabs) tab.id],
    description:
        'Changing this to an offscreen tab should automatically reveal it.',
  );

  return previewFrame(
    context,
    width: previewWidth.toDouble(),
    height: 60,
    padding: EdgeInsets.zero,
    child: EditorTabBarPreview(
      key: ValueKey(
        '$selectedId-$tabCount-$previewWidth-$dirtyPlan-$pinTheme-$previewSettings-$closableWorkbench',
      ),
      initialSelectedId: selectedId,
      tabs: tabs,
    ),
  );
}

@widgetbook.UseCase(
  name: 'Tab states',
  type: AgusEditorTabButton,
  path: '[Components]/navigation',
)
Widget buildAgusEditorTabButtonUseCase(BuildContext context) {
  final selected = context.knobs.boolean(label: 'Selected', initialValue: true);
  final dirty = context.knobs.boolean(label: 'Dirty', initialValue: false);
  final pinned = context.knobs.boolean(label: 'Pinned', initialValue: false);
  final preview = context.knobs.boolean(label: 'Preview', initialValue: false);
  final closable = context.knobs.boolean(label: 'Closable', initialValue: true);

  return previewFrame(
    context,
    width: 220,
    height: 35,
    padding: EdgeInsets.zero,
    child: AgusEditorTabButton(
      tab: AgusEditorTab(
        id: 'sample',
        label: 'agus_workbench.dart',
        icon: Icons.code,
        dirty: dirty,
        pinned: pinned,
        preview: preview,
        closable: closable,
      ),
      selected: selected,
      onSelected: (_) {},
      onClose: (_) {},
    ),
  );
}

@widgetbook.UseCase(
  name: 'Explorer tree',
  type: AgusTreeView,
  path: '[Components]/navigation',
)
Widget buildAgusTreeViewUseCase(BuildContext context) {
  final seed = context.knobs.int.slider(
    label: 'Seed',
    initialValue: 11,
    min: 1,
    max: 99,
  );
  final showMetrics = context.knobs.boolean(
    label: 'Show metrics columns',
    initialValue: true,
  );
  final multiSelect = context.knobs.boolean(
    label: 'Multi select',
    initialValue: true,
  );
  final alternateIcons = context.knobs.boolean(
    label: 'Alternate visibility icons',
    initialValue: false,
  );
  final demo = buildExplorerTreeDemo(seed: seed);

  return previewFrame(
    context,
    width: showMetrics ? 520 : 360,
    height: 360,
    padding: EdgeInsets.zero,
    child: TreeViewPreview(
      key: ValueKey('$seed-$showMetrics-$multiSelect-$alternateIcons'),
      nodes: demo.nodes,
      initialSelectedId: demo.singleSelectedId,
      initialSelectedIds: demo.multiSelectedIds,
      initialExpandedIds: demo.expandedIds,
      selectionMode: multiSelect
          ? AgusTreeSelectionMode.multiple
          : AgusTreeSelectionMode.single,
      columns: showMetrics ? agusMetricTreeColumns : const <AgusTreeColumn>[],
      labelColumnTitle: 'Layer',
      visibilityIcons: alternateIcons
          ? agusAltVisibilityIcons
          : const AgusTreeVisibilityIcons(),
      enableMutations: true,
    ),
  );
}

@widgetbook.UseCase(
  name: 'Item states',
  type: AgusStatusBarItemView,
  path: '[Components]/navigation',
)
Widget buildAgusStatusBarItemViewUseCase(BuildContext context) {
  final progress = context.knobs.boolean(
    label: 'Progress',
    initialValue: false,
  );
  final severity = context.knobs.object.segmented<AgusStatusBarItemSeverity>(
    label: 'Severity',
    initialOption: AgusStatusBarItemSeverity.standard,
    options: AgusStatusBarItemSeverity.values,
    labelBuilder: (value) => value.name,
  );
  final label = context.knobs.string(label: 'Label', initialValue: 'Dart');

  return previewFrame(
    context,
    width: 180,
    height: 30,
    padding: EdgeInsets.zero,
    child: AgusStatusBarItemView(
      item: AgusStatusBarItem(
        id: 'sample',
        label: label,
        icon: progress ? null : Icons.code,
        progress: progress,
        severity: severity,
      ),
    ),
  );
}

@widgetbook.UseCase(
  name: 'Status indicators',
  type: AgusStatusBar,
  path: '[Components]/navigation',
)
Widget buildAgusStatusBarUseCase(BuildContext context) {
  final busy = context.knobs.boolean(
    label: 'Busy progress',
    initialValue: true,
  );
  final warning = context.knobs.boolean(
    label: 'Show warning item',
    initialValue: true,
  );
  final error = context.knobs.boolean(
    label: 'Show error item',
    initialValue: false,
  );

  return previewFrame(
    context,
    width: 880,
    height: 34,
    padding: EdgeInsets.zero,
    child: AgusStatusBar(
      leftItems: [
        const AgusStatusBarItem(
          id: 'branch',
          label: 'main',
          icon: Icons.call_split,
        ),
        AgusStatusBarItem(
          id: 'sync',
          label: busy ? 'Syncing...' : '0 changes',
          progress: busy,
          icon: busy ? null : Icons.sync,
        ),
        if (warning)
          const AgusStatusBarItem(
            id: 'warning',
            label: '1 warning',
            severity: AgusStatusBarItemSeverity.warning,
          ),
        if (error)
          const AgusStatusBarItem(
            id: 'error',
            label: 'Build failed',
            severity: AgusStatusBarItemSeverity.error,
          ),
      ],
      rightItems: const [
        AgusStatusBarItem(id: 'encoding', label: 'UTF-8'),
        AgusStatusBarItem(id: 'eol', label: 'LF'),
        AgusStatusBarItem(id: 'language', label: 'Dart'),
      ],
    ),
  );
}
