import 'package:agus_design/agus_design.dart';
import 'package:flutter/material.dart';

import 'workbench_controller.dart';

/// Builds content for a Primary Side Bar activity.
typedef WorkbenchActivityBuilder = Widget Function(
  BuildContext context,
  WorkbenchActivity activity,
);

/// Builds content for an Editor Area tab.
typedef WorkbenchEditorBuilder = Widget Function(
  BuildContext context,
  WorkbenchEditorTab tab,
);

/// Builds content for a bottom Panel tab.
typedef WorkbenchPanelBuilder = Widget Function(
  BuildContext context,
  WorkbenchPanelTab tab,
);

/// Builds content for a Secondary Side Bar tab.
typedef WorkbenchSecondarySideBarBuilder = Widget Function(
  BuildContext context,
  WorkbenchSecondarySideBarTab tab,
);

/// Builds workbench status bar items.
typedef WorkbenchStatusBarBuilder = AgusStatusBar Function(
  BuildContext context,
  WorkbenchLayoutState state,
);

/// VS Code-style desktop workbench backed by the Agus design system.
class VSCodeWorkbench extends StatelessWidget {
  /// Creates a desktop workbench.
  const VSCodeWorkbench({
    super.key,
    required this.controller,
    required this.activityBuilder,
    required this.editorBuilder,
    required this.panelBuilder,
    required this.secondarySideBarBuilder,
    this.statusBarBuilder,
    this.commandGroups = const <AgusCommandGroup>[],
    this.commandAsyncProviders = const <AgusCommandAsyncProvider>[],
    this.onModalActivitySelected,
  });

  /// Global workbench state.
  final WorkbenchController controller;

  /// Builder for the Primary Side Bar.
  final WorkbenchActivityBuilder activityBuilder;

  /// Builder for Editor Area tab viewports.
  final WorkbenchEditorBuilder editorBuilder;

  /// Builder for bottom Panel tab viewports.
  final WorkbenchPanelBuilder panelBuilder;

  /// Builder for Secondary Side Bar tab viewports.
  final WorkbenchSecondarySideBarBuilder secondarySideBarBuilder;

  /// Optional status-bar builder.
  final WorkbenchStatusBarBuilder? statusBarBuilder;

  /// Commands exposed in the title-bar command center.
  final List<AgusCommandGroup> commandGroups;

  /// Query-driven command providers exposed in the title-bar command center.
  final List<AgusCommandAsyncProvider> commandAsyncProviders;

  /// Called for Activity Bar items that should open as focused modal surfaces.
  final ValueChanged<WorkbenchActivity>? onModalActivitySelected;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final state = controller.state;
        return AgusWorkbench(
          title: 'Agus Maps',
          activityBar: _buildActivityBar(state),
          primarySidebar: _buildPrimarySidebar(context, state),
          secondarySidebar: _buildSecondarySidebar(context, state),
          editor: _buildEditor(context, state),
          bottomPanel: _buildBottomPanel(context, state),
          statusBar: statusBarBuilder?.call(context, state) ??
              _buildDefaultStatusBar(state),
          commandCenter: AgusCommandCenter(
            prompt: 'Search maps, commands, and layers',
            groups: commandGroups,
            asyncProviders: commandAsyncProviders,
          ),
          showPrimarySidebar: state.primarySideBarVisible,
          showSecondarySidebar: state.secondarySideBarVisible,
          showPanel: state.panelVisible,
          onToggleArea: _toggleArea,
        );
      },
    );
  }

  AgusActivityBar _buildActivityBar(WorkbenchLayoutState state) {
    return AgusActivityBar(
      selectedId: state.activeActivity.id,
      onSelected: (id) {
        final activity = _workbenchActivityById(id);
        if (activity.opensAsModal && onModalActivitySelected != null) {
          onModalActivitySelected!(activity);
          return;
        }
        controller.selectActivity(activity);
      },
      items: [
        for (final activity in WorkbenchActivity.values)
          if (!activity.isBottomItem)
            AgusActivityBarItem(
              id: activity.id,
              icon: activity.icon,
              tooltip: activity.label,
            ),
      ],
      bottomItems: [
        for (final activity in WorkbenchActivity.values)
          if (activity.isBottomItem)
            AgusActivityBarItem(
              id: activity.id,
              icon: activity.icon,
              tooltip: activity.label,
            ),
      ],
    );
  }

  Widget _buildPrimarySidebar(
    BuildContext context,
    WorkbenchLayoutState state,
  ) {
    return AgusSidebar(
      title: state.activeActivity.label,
      child: KeyedSubtree(
        key: ValueKey(state.activeActivity),
        child: activityBuilder(context, state.activeActivity),
      ),
    );
  }

  Widget _buildEditor(BuildContext context, WorkbenchLayoutState state) {
    final tabs = [
      for (final tab in state.editorTabOrder)
        AgusTab(
          id: tab.id,
          label: tab.label,
          icon: tab.icon,
          closable: false,
        ),
    ];

    return AgusEditorHost(
      label: '${state.activeEditorTab.label} editor',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AgusTabBar(
            tabs: tabs,
            selectedId: state.activeEditorTab.id,
            variant: AgusTabVariant.editor,
            onSelected: (id) {
              controller.selectEditorTab(_workbenchEditorTabById(id));
            },
            onReorder: (tabs) {
              controller.reorderEditorTabs([
                for (final tab in tabs) _workbenchEditorTabById(tab.id),
              ]);
            },
          ),
          Expanded(
            child: KeyedSubtree(
              key: ValueKey(state.activeEditorTab),
              child: editorBuilder(context, state.activeEditorTab),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPanel(BuildContext context, WorkbenchLayoutState state) {
    return AgusPane(
      header: Row(
        children: [
          Expanded(
            child: AgusTabBar(
              tabs: [
                for (final tab in state.panelTabOrder)
                  AgusTab(
                    id: tab.id,
                    label: tab.label,
                    icon: tab.icon,
                    closable: false,
                  ),
              ],
              selectedId: state.activePanelTab.id,
              variant: AgusTabVariant.editor,
              onSelected: (id) {
                controller.selectPanelTab(_workbenchPanelTabById(id));
              },
              onReorder: (tabs) {
                controller.reorderPanelTabs([
                  for (final tab in tabs) _workbenchPanelTabById(tab.id),
                ]);
              },
            ),
          ),
          _PaneActionButton(
            tooltip: 'Hide Panel',
            icon: Icons.close,
            onPressed: controller.togglePanel,
          ),
        ],
      ),
      child: KeyedSubtree(
        key: ValueKey(state.activePanelTab),
        child: panelBuilder(context, state.activePanelTab),
      ),
    );
  }

  Widget _buildSecondarySidebar(
    BuildContext context,
    WorkbenchLayoutState state,
  ) {
    return AgusViewPaneContainer(
      views: [
        for (final tab in state.secondarySideBarTabOrder)
          AgusViewPane(
            id: tab.id,
            title: tab.label,
            icon: tab.icon,
            initiallyExpanded: true,
            actions: tab == state.secondarySideBarTabOrder.first
                ? [
                    _PaneActionButton(
                      tooltip: 'Hide Secondary Side Bar',
                      icon: Icons.close,
                      onPressed: controller.toggleSecondarySideBar,
                    ),
                  ]
                : const <Widget>[],
            child: KeyedSubtree(
              key: ValueKey(tab),
              child: secondarySideBarBuilder(context, tab),
            ),
          ),
      ],
      onToggle: (id) {
        controller.selectSecondarySideBarTab(
          _workbenchSecondarySideBarTabById(id),
        );
      },
    );
  }

  AgusStatusBar _buildDefaultStatusBar(WorkbenchLayoutState state) {
    return AgusStatusBar(
      leftItems: [
        AgusStatusBarItem(
          id: 'activity',
          label: state.activeActivity.label,
          icon: state.activeActivity.icon,
        ),
      ],
      rightItems: [
        AgusStatusBarItem(
          id: 'editor',
          label: state.activeEditorTab.label,
          icon: state.activeEditorTab.icon,
        ),
      ],
    );
  }

  void _toggleArea(AgusWorkbenchArea area) {
    switch (area) {
      case AgusWorkbenchArea.primarySidebar:
        controller.togglePrimarySideBar();
      case AgusWorkbenchArea.secondarySidebar:
        controller.toggleSecondarySideBar();
      case AgusWorkbenchArea.panel:
        controller.togglePanel();
    }
  }
}

class _PaneActionButton extends StatelessWidget {
  const _PaneActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);
    final dimensions = AgusThemeData.dimensionsOf(context);
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, color: colors.panelTabInactiveForeground),
      iconSize: dimensions.iconSize,
      constraints: BoxConstraints.tightFor(
        width: dimensions.toolbarButtonSize,
        height: dimensions.toolbarButtonSize,
      ),
      padding: EdgeInsets.zero,
      onPressed: onPressed,
    );
  }
}

extension WorkbenchActivityView on WorkbenchActivity {
  /// Stable string id used by design-system widgets.
  String get id {
    return switch (this) {
      WorkbenchActivity.explorer => 'explorer',
      WorkbenchActivity.search => 'search',
      WorkbenchActivity.favorites => 'favorites',
      WorkbenchActivity.downloads => 'downloads',
      WorkbenchActivity.settings => 'settings',
      WorkbenchActivity.about => 'about',
    };
  }

  /// User-visible label.
  String get label {
    return switch (this) {
      WorkbenchActivity.explorer => 'Explorer',
      WorkbenchActivity.search => 'Search',
      WorkbenchActivity.favorites => 'Favorites',
      WorkbenchActivity.downloads => 'Downloads',
      WorkbenchActivity.settings => 'Settings',
      WorkbenchActivity.about => 'About',
    };
  }

  /// Activity icon.
  IconData get icon {
    return switch (this) {
      WorkbenchActivity.explorer => Icons.account_tree_outlined,
      WorkbenchActivity.search => Icons.search,
      WorkbenchActivity.favorites => Icons.favorite_border,
      WorkbenchActivity.downloads => Icons.download_outlined,
      WorkbenchActivity.settings => Icons.settings_outlined,
      WorkbenchActivity.about => Icons.info_outline,
    };
  }

  /// Whether the activity belongs at the bottom of the Activity Bar.
  bool get isBottomItem {
    return switch (this) {
      WorkbenchActivity.settings || WorkbenchActivity.about => true,
      _ => false,
    };
  }

  /// Whether this activity is not rendered inside the Primary Side Bar.
  bool get opensAsModal {
    return switch (this) {
      WorkbenchActivity.settings || WorkbenchActivity.about => true,
      _ => false,
    };
  }
}

extension WorkbenchEditorTabView on WorkbenchEditorTab {
  /// Stable string id used by design-system widgets.
  String get id {
    return switch (this) {
      WorkbenchEditorTab.blank => 'blank',
      WorkbenchEditorTab.map => 'map',
    };
  }

  /// User-visible label.
  String get label {
    return switch (this) {
      WorkbenchEditorTab.blank => 'Blank',
      WorkbenchEditorTab.map => 'Map',
    };
  }

  /// Editor tab icon.
  IconData get icon {
    return switch (this) {
      WorkbenchEditorTab.blank => Icons.tab_unselected,
      WorkbenchEditorTab.map => Icons.map_outlined,
    };
  }
}

extension WorkbenchPanelTabView on WorkbenchPanelTab {
  /// Stable string id used by design-system widgets.
  String get id {
    return switch (this) {
      WorkbenchPanelTab.pointOfInterest => 'point-of-interest',
      WorkbenchPanelTab.debugConsole => 'debug-console',
    };
  }

  /// User-visible label.
  String get label {
    return switch (this) {
      WorkbenchPanelTab.pointOfInterest => 'Point of Interest',
      WorkbenchPanelTab.debugConsole => 'Debug Console',
    };
  }

  /// Panel tab icon.
  IconData get icon {
    return switch (this) {
      WorkbenchPanelTab.pointOfInterest => Icons.place_outlined,
      WorkbenchPanelTab.debugConsole => Icons.terminal,
    };
  }
}

extension WorkbenchSecondarySideBarTabView on WorkbenchSecondarySideBarTab {
  /// Stable string id used by design-system widgets.
  String get id {
    return switch (this) {
      WorkbenchSecondarySideBarTab.properties => 'properties',
      WorkbenchSecondarySideBarTab.inspector => 'inspector',
    };
  }

  /// User-visible label.
  String get label {
    return switch (this) {
      WorkbenchSecondarySideBarTab.properties => 'Properties',
      WorkbenchSecondarySideBarTab.inspector => 'Inspector',
    };
  }

  /// Sidebar tab icon.
  IconData get icon {
    return switch (this) {
      WorkbenchSecondarySideBarTab.properties => Icons.dataset_outlined,
      WorkbenchSecondarySideBarTab.inspector => Icons.rule_folder_outlined,
    };
  }
}

WorkbenchActivity _workbenchActivityById(String id) {
  return WorkbenchActivity.values.firstWhere(
    (activity) => activity.id == id,
    orElse: () => WorkbenchActivity.explorer,
  );
}

WorkbenchEditorTab _workbenchEditorTabById(String id) {
  return WorkbenchEditorTab.values.firstWhere(
    (tab) => tab.id == id,
    orElse: () => WorkbenchEditorTab.map,
  );
}

WorkbenchPanelTab _workbenchPanelTabById(String id) {
  return WorkbenchPanelTab.values.firstWhere(
    (tab) => tab.id == id,
    orElse: () => WorkbenchPanelTab.pointOfInterest,
  );
}

WorkbenchSecondarySideBarTab _workbenchSecondarySideBarTabById(String id) {
  return WorkbenchSecondarySideBarTab.values.firstWhere(
    (tab) => tab.id == id,
    orElse: () => WorkbenchSecondarySideBarTab.properties,
  );
}
