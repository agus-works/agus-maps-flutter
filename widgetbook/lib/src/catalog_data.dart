import 'package:agus_design/agus_design.dart';
import 'package:agus_design/agus_design_demo.dart';
import 'package:flutter/material.dart';

Widget previewFrame(
  BuildContext context, {
  required Widget child,
  double? width,
  double? height,
  EdgeInsets padding = const EdgeInsets.all(12),
}) {
  final colors = AgusThemeData.colorsOf(context);

  return SizedBox(
    width: width,
    height: height,
    child: ColoredBox(
      color: colors.workbenchBackground,
      child: Padding(padding: padding, child: child),
    ),
  );
}

List<AgusActivityBarItem> buildActivityItems({
  int sourceBadgeCount = 3,
  bool disableSearch = false,
  bool disableExtensions = false,
}) {
  return [
    const AgusActivityBarItem(
      id: 'explorer',
      icon: Icons.folder,
      tooltip: 'Explorer',
    ),
    AgusActivityBarItem(
      id: 'search',
      icon: Icons.search,
      tooltip: 'Search',
      enabled: !disableSearch,
    ),
    AgusActivityBarItem(
      id: 'source',
      icon: Icons.account_tree,
      tooltip: 'Source Control',
      badgeCount: sourceBadgeCount,
    ),
    const AgusActivityBarItem(
      id: 'debug',
      icon: Icons.bug_report,
      tooltip: 'Run and Debug',
    ),
    AgusActivityBarItem(
      id: 'extensions',
      icon: Icons.extension,
      tooltip: 'Extensions',
      enabled: !disableExtensions,
    ),
  ];
}

List<AgusActivityBarItem> buildBottomActivityItems({
  bool disableManage = false,
}) {
  return [
    const AgusActivityBarItem(
      id: 'account',
      icon: Icons.account_circle,
      tooltip: 'Accounts',
    ),
    AgusActivityBarItem(
      id: 'settings',
      icon: Icons.settings,
      tooltip: 'Manage',
      enabled: !disableManage,
    ),
  ];
}

List<AgusEditorTab> buildEditorTabs({
  bool dirtyPlan = true,
  bool pinTheme = true,
  bool previewSettings = true,
  bool closableWorkbench = true,
}) {
  return [
    AgusEditorTab(
      id: 'plan',
      label: 'PLAN.md',
      icon: Icons.description,
      dirty: dirtyPlan,
    ),
    AgusEditorTab(
      id: 'theme',
      label: 'agus_theme_data.dart',
      icon: Icons.code,
      pinned: pinTheme,
    ),
    AgusEditorTab(
      id: 'settings',
      label: 'settings_schema.dart',
      icon: Icons.code,
      preview: previewSettings,
    ),
    AgusEditorTab(
      id: 'workbench',
      label: 'agus_workbench.dart',
      icon: Icons.code,
      closable: closableWorkbench,
    ),
  ];
}

AgusTreeDemoBundle buildExplorerTreeDemo({int seed = 11}) {
  return AgusTreeDemoGenerator(seed: seed).build(rootCount: 4);
}

List<AgusTreeNode> buildExplorerNodes({bool showOutlineBadges = true}) {
  return buildExplorerTreeDemo().nodes;
}

const sampleSettingSchemas = <AgusSettingSchema>[
  AgusSettingSchema(
    id: 'workbench.sideBar.location',
    title: 'Workbench: Side Bar Location',
    description:
        'Controls whether the primary sidebar appears on the left or right side of the workbench.',
    category: 'Workbench',
    type: AgusSettingType.select,
    defaultValue: 'left',
    options: [
      AgusSettingOption(value: 'left', label: 'Left'),
      AgusSettingOption(value: 'right', label: 'Right'),
    ],
  ),
  AgusSettingSchema(
    id: 'workbench.activityBar.visible',
    title: 'Workbench: Activity Bar Visible',
    description: 'Controls whether the Activity Bar is visible.',
    category: 'Workbench',
    type: AgusSettingType.boolean,
    defaultValue: true,
  ),
  AgusSettingSchema(
    id: 'agus.editor.fontSize',
    title: 'Editor: Font Size',
    description: 'Controls the font size used by code editor hosts.',
    category: 'Editor',
    type: AgusSettingType.number,
    defaultValue: 13.0,
    minimum: 8,
    maximum: 32,
  ),
  AgusSettingSchema(
    id: 'agus.webview.localRoot',
    title: 'Webview: Local Root',
    description: 'Directory used for local and offline web content previews.',
    category: 'Webview',
    type: AgusSettingType.folder,
    defaultValue: '',
  ),
  AgusSettingSchema(
    id: 'agus.editor.experimentalData',
    title: 'Editor: Experimental Data',
    description: 'JSON-backed extension settings that stay in the JSON editor.',
    category: 'Editor',
    type: AgusSettingType.json,
    defaultValue: '{}',
    jsonOnly: true,
  ),
];

Map<String, Object?> buildSampleSettingValues({
  bool showModifiedValues = true,
}) {
  if (!showModifiedValues) {
    return const <String, Object?>{};
  }

  return <String, Object?>{
    'workbench.sideBar.location': 'right',
    'agus.editor.fontSize': 16.0,
    'workbench.activityBar.visible': true,
    'agus.webview.localRoot': '/workspace/previews',
  };
}

enum AgusSettingPreviewKind { boolean, select, number, folder, string, json }

extension AgusSettingPreviewKindLabel on AgusSettingPreviewKind {
  String get label {
    return switch (this) {
      AgusSettingPreviewKind.boolean => 'Boolean',
      AgusSettingPreviewKind.select => 'Select',
      AgusSettingPreviewKind.number => 'Number',
      AgusSettingPreviewKind.folder => 'Folder',
      AgusSettingPreviewKind.string => 'String',
      AgusSettingPreviewKind.json => 'JSON only',
    };
  }
}

AgusSettingSchema buildSettingSchemaPreview(AgusSettingPreviewKind kind) {
  return switch (kind) {
    AgusSettingPreviewKind.boolean => sampleSettingSchemas[1],
    AgusSettingPreviewKind.select => sampleSettingSchemas[0],
    AgusSettingPreviewKind.number => sampleSettingSchemas[2],
    AgusSettingPreviewKind.folder => sampleSettingSchemas[3],
    AgusSettingPreviewKind.string => const AgusSettingSchema(
      id: 'agus.editor.fontFamily',
      title: 'Editor: Font Family',
      description: 'Controls the editor font family.',
      category: 'Editor',
      type: AgusSettingType.string,
      defaultValue: 'JetBrains Mono',
    ),
    AgusSettingPreviewKind.json => sampleSettingSchemas[4],
  };
}

Object? buildSettingValuePreview(AgusSettingPreviewKind kind) {
  return switch (kind) {
    AgusSettingPreviewKind.boolean => true,
    AgusSettingPreviewKind.select => 'right',
    AgusSettingPreviewKind.number => 18.0,
    AgusSettingPreviewKind.folder => '/workspace/previews',
    AgusSettingPreviewKind.string => 'Fira Code',
    AgusSettingPreviewKind.json => '{"enabled": true}',
  };
}

class ActivityBarPreview extends StatefulWidget {
  const ActivityBarPreview({
    required this.initialSelectedId,
    required this.items,
    this.bottomItems = const <AgusActivityBarItem>[],
    super.key,
  });

  final String? initialSelectedId;
  final List<AgusActivityBarItem> items;
  final List<AgusActivityBarItem> bottomItems;

  @override
  State<ActivityBarPreview> createState() => _ActivityBarPreviewState();
}

class _ActivityBarPreviewState extends State<ActivityBarPreview> {
  late String? selectedId = widget.initialSelectedId;

  @override
  Widget build(BuildContext context) {
    return AgusActivityBar(
      items: widget.items,
      bottomItems: widget.bottomItems,
      selectedId: selectedId,
      onSelected: (id) => setState(() => selectedId = id),
    );
  }
}

class EditorTabBarPreview extends StatefulWidget {
  const EditorTabBarPreview({
    required this.initialSelectedId,
    required this.tabs,
    super.key,
  });

  final String initialSelectedId;
  final List<AgusEditorTab> tabs;

  @override
  State<EditorTabBarPreview> createState() => _EditorTabBarPreviewState();
}

class _EditorTabBarPreviewState extends State<EditorTabBarPreview> {
  late String selectedId = widget.initialSelectedId;
  late List<AgusEditorTab> tabs = List<AgusEditorTab>.from(widget.tabs);

  @override
  Widget build(BuildContext context) {
    return AgusEditorTabBar(
      tabs: tabs,
      selectedId: selectedId,
      onSelected: (id) => setState(() => selectedId = id),
      onClose: (id) {
        setState(() {
          tabs = tabs.where((tab) => tab.id != id).toList();
          if (!tabs.any((tab) => tab.id == selectedId) && tabs.isNotEmpty) {
            selectedId = tabs.first.id;
          }
        });
      },
    );
  }
}

class TreeViewPreview extends StatefulWidget {
  const TreeViewPreview({
    required this.nodes,
    this.initialSelectedId,
    this.initialSelectedIds = const <String>{},
    this.initialExpandedIds = const <String>{},
    this.selectionMode = AgusTreeSelectionMode.single,
    this.columns = const <AgusTreeColumn>[],
    this.labelColumnTitle,
    this.visibilityIcons = const AgusTreeVisibilityIcons(),
    this.enableMutations = false,
    super.key,
  });

  final List<AgusTreeNode> nodes;
  final String? initialSelectedId;
  final Set<String> initialSelectedIds;
  final Set<String> initialExpandedIds;
  final AgusTreeSelectionMode selectionMode;
  final List<AgusTreeColumn> columns;
  final String? labelColumnTitle;
  final AgusTreeVisibilityIcons visibilityIcons;
  final bool enableMutations;

  @override
  State<TreeViewPreview> createState() => _TreeViewPreviewState();
}

class _TreeViewPreviewState extends State<TreeViewPreview> {
  late List<AgusTreeNode> nodes = widget.nodes;
  late String? selectedId = widget.initialSelectedId;
  late Set<String> selectedIds = Set<String>.from(widget.initialSelectedIds);
  late Set<String> expandedIds = Set<String>.from(widget.initialExpandedIds);

  @override
  Widget build(BuildContext context) {
    return AgusTreeView(
      labelColumnTitle: widget.labelColumnTitle,
      columns: widget.columns,
      nodes: nodes,
      selectedId: selectedId,
      selectedIds: selectedIds,
      expandedIds: expandedIds,
      selectionMode: widget.selectionMode,
      visibilityIcons: widget.visibilityIcons,
      onSelected: (id) => setState(() => selectedId = id),
      onSelectionChanged: (ids) => setState(() => selectedIds = ids),
      onToggle: (id) => setState(() {
        if (!expandedIds.add(id)) {
          expandedIds.remove(id);
        }
      }),
      onRename: widget.enableMutations
          ? (id, label) => setState(() {
              nodes = renameAgusTreeDemoNode(nodes, nodeId: id, label: label);
            })
          : null,
      onDelete: widget.enableMutations
          ? (id) => setState(() {
              nodes = deleteAgusTreeDemoNode(nodes, nodeId: id);
              expandedIds.removeWhere(
                (expandedId) => !agusTreeDemoContainsNode(nodes, expandedId),
              );
              selectedIds.removeWhere(
                (selectedId) => !agusTreeDemoContainsNode(nodes, selectedId),
              );
              if (selectedId != null &&
                  !agusTreeDemoContainsNode(nodes, selectedId!)) {
                selectedId = selectedIds.isEmpty ? null : selectedIds.first;
              }
            })
          : null,
      onVisibilityChanged: widget.enableMutations
          ? (id, visibility) => setState(() {
              nodes = updateAgusTreeDemoVisibility(
                nodes,
                nodeId: id,
                visibility: visibility,
              );
            })
          : null,
    );
  }
}

class CommandCenterPreview extends StatefulWidget {
  const CommandCenterPreview({required this.prompt, super.key});

  final String prompt;

  @override
  State<CommandCenterPreview> createState() => _CommandCenterPreviewState();
}

class _CommandCenterPreviewState extends State<CommandCenterPreview> {
  final AgusCommandController _controller = AgusCommandController();
  String lastCommand = 'Use ⌘K or the listed shortcuts.';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final commandGroups = buildAgusWorkbenchCommandGroups(
      onSelected: (_, label) => setState(() => lastCommand = '$label selected'),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AgusCommandShortcutHost(
          controller: _controller,
          groups: commandGroups,
          child: SizedBox(
            width: 460,
            height: 24,
            child: AgusCommandCenter(
              controller: _controller,
              groups: commandGroups,
              prompt: widget.prompt,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(lastCommand, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class CommandBarPreview extends StatefulWidget {
  const CommandBarPreview({
    required this.prompt,
    required this.active,
    super.key,
  });

  final String prompt;
  final bool active;

  @override
  State<CommandBarPreview> createState() => _CommandBarPreviewState();
}

class _CommandBarPreviewState extends State<CommandBarPreview> {
  String lastInteraction = 'Press the bar to inspect the trigger surface.';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 460,
          height: 24,
          child: AgusCommandBar(
            prompt: widget.prompt,
            active: widget.active,
            trailing: DecoratedBox(
              decoration: BoxDecoration(
                color: AgusThemeData.colorsOf(
                  context,
                ).titleBarBackground.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  '⌘K',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ),
            onPressed: () =>
                setState(() => lastInteraction = 'Command bar pressed'),
          ),
        ),
        const SizedBox(height: 12),
        Text(lastInteraction, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class CommandDialogPreview extends StatefulWidget {
  const CommandDialogPreview({required this.prompt, super.key});

  final String prompt;

  @override
  State<CommandDialogPreview> createState() => _CommandDialogPreviewState();
}

class _CommandDialogPreviewState extends State<CommandDialogPreview> {
  String lastCommand = 'Use ↑ ↓ and Enter to inspect keyboard selection.';

  @override
  Widget build(BuildContext context) {
    final commandGroups = buildAgusWorkbenchCommandGroups(
      onSelected: (_, label) => setState(() => lastCommand = '$label selected'),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 460,
          child: AgusCommandDialog(
            groups: commandGroups,
            prompt: widget.prompt,
            autofocus: false,
          ),
        ),
        const SizedBox(height: 12),
        Text(lastCommand, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class SettingsEditorPreview extends StatefulWidget {
  const SettingsEditorPreview({
    required this.schemas,
    required this.initialValues,
    this.initialScope = AgusSettingScope.user,
    super.key,
  });

  final List<AgusSettingSchema> schemas;
  final Map<String, Object?> initialValues;
  final AgusSettingScope initialScope;

  @override
  State<SettingsEditorPreview> createState() => _SettingsEditorPreviewState();
}

class _SettingsEditorPreviewState extends State<SettingsEditorPreview> {
  late final Map<String, Object?> values = Map<String, Object?>.from(
    widget.initialValues,
  );

  @override
  Widget build(BuildContext context) {
    return AgusSettingsEditor(
      schemas: widget.schemas,
      values: values,
      initialScope: widget.initialScope,
      onChanged: (id, value) => setState(() => values[id] = value),
    );
  }
}

class WorkbenchPreview extends StatefulWidget {
  const WorkbenchPreview({
    required this.showPrimarySidebar,
    required this.showSecondarySidebar,
    required this.showPanel,
    required this.initialActivityId,
    super.key,
  });

  final bool showPrimarySidebar;
  final bool showSecondarySidebar;
  final bool showPanel;
  final String initialActivityId;

  @override
  State<WorkbenchPreview> createState() => _WorkbenchPreviewState();
}

class _WorkbenchPreviewState extends State<WorkbenchPreview> {
  final AgusCommandController _commandController = AgusCommandController();
  late String selectedActivity = widget.initialActivityId;
  late bool showPrimarySidebar = widget.showPrimarySidebar;
  late bool showSecondarySidebar = widget.showSecondarySidebar;
  late bool showPanel = widget.showPanel;
  String selectedTab = 'plan';
  late final AgusTreeDemoBundle demo = buildExplorerTreeDemo(seed: 21);
  late List<AgusTreeNode> sceneNodes = demo.nodes;
  late Set<String> expandedTreeIds = Set<String>.from(demo.expandedIds);
  late Set<String> selectedTreeIds = Set<String>.from(demo.multiSelectedIds);
  String? selectedTreeId;
  late final Map<String, Object?> settingsValues = buildSampleSettingValues();

  @override
  void initState() {
    super.initState();
    selectedTreeId = demo.singleSelectedId;
  }

  @override
  void dispose() {
    _commandController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final commandGroups = buildAgusWorkbenchCommandGroups(
      onSelected: (_, label) => setState(
        () => selectedTab = label == 'Documents' ? 'theme' : selectedTab,
      ),
    );

    return AgusCommandShortcutHost(
      controller: _commandController,
      groups: commandGroups,
      child: AgusWorkbench(
        title: 'Agus Design',
        commandCenter: AgusCommandCenter(
          controller: _commandController,
          groups: commandGroups,
          prompt: 'Jump to a view, layer, or action',
        ),
        activityBar: AgusActivityBar(
          selectedId: selectedActivity,
          onSelected: (id) => setState(() => selectedActivity = id),
          items: buildActivityItems(),
          bottomItems: buildBottomActivityItems(),
        ),
        primarySidebar: _buildSidebar(),
        secondarySidebar: _buildInspector(),
        editor: _buildEditor(),
        bottomPanel: _buildPanel(),
        showPrimarySidebar: showPrimarySidebar,
        showSecondarySidebar: showSecondarySidebar,
        showPanel: showPanel,
        onToggleArea: _toggleArea,
        statusBar: AgusStatusBar(
          leftItems: [
            const AgusStatusBarItem(
              id: 'branch',
              label: 'main',
              icon: Icons.call_split,
            ),
            AgusStatusBarItem(
              id: 'selection',
              label: '${selectedTreeIds.length} selected',
              icon: Icons.select_all,
            ),
            const AgusStatusBarItem(
              id: 'problems',
              label: '0  0',
              icon: Icons.error_outline,
            ),
          ],
          rightItems: [
            AgusStatusBarItem(
              id: 'encoding',
              label: selectedActivity == 'settings' ? 'Settings' : 'UTF-8',
            ),
            const AgusStatusBarItem(id: 'eol', label: 'LF'),
            const AgusStatusBarItem(id: 'language', label: 'Dart'),
          ],
        ),
      ),
    );
  }

  void _toggleArea(AgusWorkbenchArea area) {
    setState(() {
      switch (area) {
        case AgusWorkbenchArea.primarySidebar:
          showPrimarySidebar = !showPrimarySidebar;
          break;
        case AgusWorkbenchArea.secondarySidebar:
          showSecondarySidebar = !showSecondarySidebar;
          break;
        case AgusWorkbenchArea.panel:
          showPanel = !showPanel;
          break;
      }
    });
  }

  Widget _buildSidebar() {
    return AgusSidebar(
      title: 'Explorer',
      sections: [
        AgusViewSection(
          title: 'Open Editors',
          child: AgusTreeView(
            selectedId: selectedTab,
            nodes: const [
              AgusTreeNode(
                id: 'plan',
                label: 'PLAN.md',
                icon: Icons.description,
              ),
              AgusTreeNode(
                id: 'theme',
                label: 'agus_theme_data.dart',
                icon: Icons.code,
              ),
              AgusTreeNode(
                id: 'settings',
                label: 'settings_schema.dart',
                icon: Icons.code,
              ),
            ],
            onSelected: (id) => setState(() => selectedTab = id),
          ),
        ),
        AgusViewSection(
          title: 'Workspace Directory',
          child: AgusTreeView(
            labelColumnTitle: 'Layer',
            columns: agusMetricTreeColumns,
            selectionMode: AgusTreeSelectionMode.multiple,
            selectedId: selectedTreeId,
            selectedIds: selectedTreeIds,
            expandedIds: expandedTreeIds,
            onSelected: (id) => setState(() => selectedTreeId = id),
            onSelectionChanged: (ids) => setState(() => selectedTreeIds = ids),
            onToggle: (id) => setState(() {
              if (!expandedTreeIds.add(id)) {
                expandedTreeIds.remove(id);
              }
            }),
            onRename: (id, label) => setState(() {
              sceneNodes = renameAgusTreeDemoNode(
                sceneNodes,
                nodeId: id,
                label: label,
              );
            }),
            onDelete: (id) => setState(() {
              sceneNodes = deleteAgusTreeDemoNode(sceneNodes, nodeId: id);
              expandedTreeIds.removeWhere(
                (expandedId) =>
                    !agusTreeDemoContainsNode(sceneNodes, expandedId),
              );
              selectedTreeIds.removeWhere(
                (selectedId) =>
                    !agusTreeDemoContainsNode(sceneNodes, selectedId),
              );
              if (selectedTreeId != null &&
                  !agusTreeDemoContainsNode(sceneNodes, selectedTreeId!)) {
                selectedTreeId = selectedTreeIds.isEmpty
                    ? null
                    : selectedTreeIds.first;
              }
            }),
            onVisibilityChanged: (id, visibility) => setState(() {
              sceneNodes = updateAgusTreeDemoVisibility(
                sceneNodes,
                nodeId: id,
                visibility: visibility,
              );
            }),
            nodes: sceneNodes,
          ),
        ),
      ],
    );
  }

  Widget _buildInspector() {
    return AgusSidebar(
      title: 'Inspector',
      sections: const [
        AgusViewSection(
          title: 'Selection',
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Text('Use the Widgetbook inspector addon for live details.'),
          ),
        ),
      ],
    );
  }

  Widget _buildEditor() {
    if (selectedActivity == 'settings') {
      return AgusSettingsEditor(
        schemas: sampleSettingSchemas,
        values: settingsValues,
        onChanged: (id, value) => setState(() => settingsValues[id] = value),
      );
    }

    return Column(
      children: [
        AgusEditorTabBar(
          selectedId: selectedTab,
          onSelected: (id) => setState(() => selectedTab = id),
          onClose: (id) => setState(() => selectedTab = 'plan'),
          tabs: buildEditorTabs(),
        ),
        Expanded(
          child: AgusEditorHost(
            label: 'Widgetbook editor preview',
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Agus Design editor host for $selectedTab.\n\n'
                'Use Widgetbook knobs to explore shell-level layout states.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPanel() {
    final colors = AgusThemeData.colorsOf(context);

    return ColoredBox(
      color: colors.panelBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AgusEditorTabBar(
            selectedId: 'output',
            tabs: const [
              AgusEditorTab(id: 'problems', label: 'Problems', closable: false),
              AgusEditorTab(id: 'output', label: 'Output', closable: false),
              AgusEditorTab(id: 'terminal', label: 'Terminal', closable: false),
            ],
          ),
          const Expanded(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text('flutter analyze\nflutter test\nWidgetbook ready'),
            ),
          ),
        ],
      ),
    );
  }
}
