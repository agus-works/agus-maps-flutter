import 'package:agus_design/agus_design.dart';
import 'package:agus_design/agus_design_demo.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const AgusDesignExampleApp());
}

class AgusDesignExampleApp extends StatefulWidget {
  const AgusDesignExampleApp({super.key});

  @override
  State<AgusDesignExampleApp> createState() => _AgusDesignExampleAppState();
}

class _AgusDesignExampleAppState extends State<AgusDesignExampleApp> {
  ThemeMode themeMode = ThemeMode.dark;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Agus Design Kitchen Sink',
      debugShowCheckedModeBanner: false,
      theme: AgusThemeData.light().toThemeData(),
      darkTheme: AgusThemeData.dark().toThemeData(),
      themeMode: themeMode,
      home: KitchenSinkWorkbench(
        themeMode: themeMode,
        onToggleTheme: () {
          setState(() {
            themeMode = themeMode == ThemeMode.dark
                ? ThemeMode.light
                : ThemeMode.dark;
          });
        },
      ),
    );
  }
}

class KitchenSinkWorkbench extends StatefulWidget {
  const KitchenSinkWorkbench({
    required this.themeMode,
    required this.onToggleTheme,
    super.key,
  });

  final ThemeMode themeMode;
  final VoidCallback onToggleTheme;

  @override
  State<KitchenSinkWorkbench> createState() => _KitchenSinkWorkbenchState();
}

class _KitchenSinkWorkbenchState extends State<KitchenSinkWorkbench> {
  final AgusCommandController _commandController = AgusCommandController();

  String selectedActivity = 'explorer';
  String selectedTab = 'plan';
  String commandStatus = 'Ready';
  bool showPrimarySidebar = true;
  bool showSecondarySidebar = true;
  bool showPanel = true;

  late List<AgusTreeNode> sceneNodes;
  late Set<String> expandedTreeIds;
  late Set<String> selectedSceneNodeIds;
  String? selectedSceneNodeId;

  final Map<String, Object?> settingsValues = <String, Object?>{
    'workbench.sideBar.location': 'left',
    'agus.editor.fontSize': 13.0,
  };

  @override
  void initState() {
    super.initState();
    final demo = const AgusTreeDemoGenerator(seed: 16).build();
    sceneNodes = demo.nodes;
    expandedTreeIds = Set<String>.from(demo.expandedIds);
    selectedSceneNodeIds = Set<String>.from(demo.multiSelectedIds);
    selectedSceneNodeId = demo.singleSelectedId;
  }

  @override
  void dispose() {
    _commandController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final commandGroups = buildAgusWorkbenchCommandGroups(
      onSelected: _handleCommandSelection,
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
            AgusActivityBarItem(
              id: 'source',
              icon: Icons.account_tree,
              tooltip: 'Source Control',
              badgeCount: 3,
            ),
            AgusActivityBarItem(
              id: 'debug',
              icon: Icons.bug_report,
              tooltip: 'Run and Debug',
            ),
            AgusActivityBarItem(
              id: 'extensions',
              icon: Icons.extension,
              tooltip: 'Extensions',
            ),
          ],
          bottomItems: const [
            AgusActivityBarItem(
              id: 'account',
              icon: Icons.account_circle,
              tooltip: 'Accounts',
            ),
            AgusActivityBarItem(
              id: 'settings',
              icon: Icons.settings,
              tooltip: 'Manage',
            ),
          ],
        ),
        primarySidebar: _buildSidebar(),
        secondarySidebar: _buildSecondarySidebar(),
        editor: _buildEditor(),
        bottomPanel: _buildPanel(),
        showPrimarySidebar:
            showPrimarySidebar && selectedActivity != 'settings',
        showSecondarySidebar: showSecondarySidebar,
        showPanel: showPanel,
        onToggleArea: _toggleArea,
        titleBarTrailingActions: [
          IconButton(
            tooltip: widget.themeMode == ThemeMode.dark
                ? 'Switch to light theme'
                : 'Switch to dark theme',
            icon: Icon(
              widget.themeMode == ThemeMode.dark
                  ? Icons.light_mode
                  : Icons.dark_mode,
              size: 18,
            ),
            onPressed: widget.onToggleTheme,
          ),
        ],
        statusBar: AgusStatusBar(
          leftItems: [
            const AgusStatusBarItem(
              id: 'branch',
              label: 'main',
              icon: Icons.call_split,
            ),
            AgusStatusBarItem(
              id: 'command',
              label: commandStatus,
              icon: Icons.keyboard_command_key,
            ),
            AgusStatusBarItem(
              id: 'selection',
              label: '${selectedSceneNodeIds.length} selected',
              icon: Icons.select_all,
            ),
          ],
          rightItems: [
            AgusStatusBarItem(
              id: 'theme',
              label: widget.themeMode == ThemeMode.dark ? 'Dark' : 'Light',
              icon: widget.themeMode == ThemeMode.dark
                  ? Icons.dark_mode
                  : Icons.light_mode,
            ),
            const AgusStatusBarItem(id: 'encoding', label: 'UTF-8'),
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

  void _handleCommandSelection(String id, String label) {
    setState(() {
      commandStatus = '$label triggered';
      switch (id) {
        case 'home':
          selectedActivity = 'explorer';
          showPrimarySidebar = true;
          break;
        case 'inbox':
          selectedActivity = 'source';
          break;
        case 'documents':
          selectedTab = 'theme';
          break;
        case 'folders':
          selectedActivity = 'explorer';
          showPrimarySidebar = true;
          break;
        case 'new-file':
          selectedTab = 'workbench';
          break;
        case 'new-folder':
          showPrimarySidebar = true;
          break;
        case 'copy':
          commandStatus =
              '${selectedSceneNodeIds.length} layer(s) copied to clipboard';
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
              AgusTreeNode(
                id: 'workbench',
                label: 'agus_workbench.dart',
                icon: Icons.code,
              ),
            ],
            onSelected: (id) => setState(() => selectedTab = id),
          ),
        ),
        AgusViewSection(
          title: 'Scene Graph',
          child: AgusTreeView(
            labelColumnTitle: 'Layer',
            columns: agusMetricTreeColumns,
            nodes: sceneNodes,
            expandedIds: expandedTreeIds,
            selectionMode: AgusTreeSelectionMode.multiple,
            selectedIds: selectedSceneNodeIds,
            selectedId: selectedSceneNodeId,
            onSelected: (id) => setState(() => selectedSceneNodeId = id),
            onSelectionChanged: (ids) =>
                setState(() => selectedSceneNodeIds = ids),
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
              commandStatus = 'Renamed layer to $label';
            }),
            onDelete: (id) => setState(() {
              sceneNodes = deleteAgusTreeDemoNode(sceneNodes, nodeId: id);
              expandedTreeIds.removeWhere(
                (expandedId) =>
                    !agusTreeDemoContainsNode(sceneNodes, expandedId),
              );
              selectedSceneNodeIds.removeWhere(
                (selectedId) =>
                    !agusTreeDemoContainsNode(sceneNodes, selectedId),
              );
              if (selectedSceneNodeId != null &&
                  !agusTreeDemoContainsNode(sceneNodes, selectedSceneNodeId!)) {
                selectedSceneNodeId = _firstNodeId(sceneNodes);
              }
              commandStatus = 'Deleted layer';
            }),
            onVisibilityChanged: (id, visibility) => setState(() {
              sceneNodes = updateAgusTreeDemoVisibility(
                sceneNodes,
                nodeId: id,
                visibility: visibility,
              );
              commandStatus = 'Visibility updated';
            }),
          ),
        ),
        AgusViewSection(
          title: 'Outline',
          child: AgusTreeView(
            selectedId: selectedSceneNodeId,
            nodes: [
              AgusTreeNode(
                id: 'selection',
                label: 'Selection',
                icon: Icons.touch_app_outlined,
                badgeLabel: '${selectedSceneNodeIds.length}',
              ),
              AgusTreeNode(
                id: 'visible',
                label: 'Visible Layers',
                icon: Icons.visibility_outlined,
                badgeLabel: _visibleLayerCount.toString(),
              ),
              AgusTreeNode(
                id: 'vertices',
                label: 'Vertex Budget',
                icon: Icons.polyline_outlined,
                badgeLabel: _vertexBudgetLabel,
              ),
            ],
            onSelected: (id) => setState(() => selectedSceneNodeId = id),
          ),
        ),
      ],
    );
  }

  Widget _buildSecondarySidebar() {
    return AgusSidebar(
      title: 'Inspector',
      sections: [
        AgusViewSection(
          title: 'Selection',
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Active layer: ${selectedSceneNodeId ?? 'none'}\n'
              'Multi-select: ${selectedSceneNodeIds.length} items\n'
              'Double click a layer name to rename it.\n'
              'Hover a row to reveal delete.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
        AgusViewSection(
          title: 'Visibility',
          child: AgusTreeView(
            selectedId: selectedSceneNodeId,
            nodes: [
              AgusTreeNode(
                id: 'visible-only',
                label: 'Visible',
                icon: Icons.visibility_outlined,
                badgeLabel: _visibleLayerCount.toString(),
              ),
              AgusTreeNode(
                id: 'hidden-only',
                label: 'Hidden',
                icon: Icons.visibility_off_outlined,
                badgeLabel: (_allLayerCount - _visibleLayerCount).toString(),
              ),
            ],
            onSelected: (id) => setState(() => selectedSceneNodeId = id),
          ),
        ),
      ],
    );
  }

  Widget _buildEditor() {
    if (selectedActivity == 'settings') {
      return AgusSettingsEditor(
        schemas: _settingsSchemas,
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
          tabs: const [
            AgusEditorTab(
              id: 'plan',
              label: 'PLAN.md',
              icon: Icons.description,
              dirty: true,
            ),
            AgusEditorTab(
              id: 'theme',
              label: 'agus_theme_data.dart',
              icon: Icons.code,
              pinned: true,
            ),
            AgusEditorTab(
              id: 'settings',
              label: 'settings_schema.dart',
              icon: Icons.code,
              preview: true,
            ),
            AgusEditorTab(
              id: 'workbench',
              label: 'agus_workbench.dart',
              icon: Icons.code,
            ),
          ],
        ),
        Expanded(
          child: AgusEditorHost(
            label: 'Editor demo',
            child: _EditorPreview(
              selectedTab: selectedTab,
              selectedLayerCount: selectedSceneNodeIds.length,
              commandStatus: commandStatus,
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
              AgusEditorTab(
                id: 'debug-console',
                label: 'Debug Console',
                closable: false,
              ),
              AgusEditorTab(id: 'terminal', label: 'Terminal', closable: false),
            ],
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Agus Design command log\n'
                '> $commandStatus\n'
                '> Expanded nodes: ${expandedTreeIds.length}\n'
                '> Selected layers: ${selectedSceneNodeIds.join(', ')}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String? _firstNodeId(List<AgusTreeNode> nodes) {
    for (final node in nodes) {
      if (node.children.isEmpty) {
        return node.id;
      }
      final childId = _firstNodeId(node.children);
      if (childId != null) {
        return childId;
      }
    }
    return null;
  }

  int get _visibleLayerCount =>
      _countLayersByVisibility(sceneNodes, AgusTreeVisibilityState.visible);

  int get _allLayerCount => _countLeafNodes(sceneNodes);

  String get _vertexBudgetLabel => _sumMetric(sceneNodes, 'vertices');

  int _countLeafNodes(List<AgusTreeNode> nodes) {
    var count = 0;
    for (final node in nodes) {
      if (node.children.isEmpty) {
        count += 1;
      } else {
        count += _countLeafNodes(node.children);
      }
    }
    return count;
  }

  int _countLayersByVisibility(
    List<AgusTreeNode> nodes,
    AgusTreeVisibilityState visibility,
  ) {
    var count = 0;
    for (final node in nodes) {
      if (node.children.isEmpty && node.visibility == visibility) {
        count += 1;
      }
      count += _countLayersByVisibility(node.children, visibility);
    }
    return count;
  }

  String _sumMetric(List<AgusTreeNode> nodes, String id) {
    var total = 0;
    for (final node in nodes) {
      total +=
          int.tryParse((node.columnValues[id] ?? '0').replaceAll(',', '')) ?? 0;
    }
    return total.toString();
  }
}

class _EditorPreview extends StatelessWidget {
  const _EditorPreview({
    required this.selectedTab,
    required this.selectedLayerCount,
    required this.commandStatus,
  });

  final String selectedTab;
  final int selectedLayerCount;
  final String commandStatus;

  @override
  Widget build(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: colors.editorGroupBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Native Flutter editor host for $selectedTab\n\n'
            'Command state: $commandStatus\n'
            'Scene selection: $selectedLayerCount layer(s)\n\n'
            'This slot can host Monaco in a webview, a native editor widget, '
            'local offline web content, or a future high-performance 3D canvas.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ),
    );
  }
}

const _settingsSchemas = [
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
    description: 'Directory used for local/offline web content previews.',
    category: 'Webview',
    type: AgusSettingType.folder,
    defaultValue: '',
  ),
];
