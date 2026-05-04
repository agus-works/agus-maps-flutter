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

/// VS Code-style desktop workbench with resizable panes and viewport tabs.
class VSCodeWorkbench extends StatelessWidget {
  /// Creates a desktop workbench.
  const VSCodeWorkbench({
    super.key,
    required this.controller,
    required this.activityBuilder,
    required this.editorBuilder,
    required this.panelBuilder,
    required this.secondarySideBarBuilder,
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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final state = controller.state;
        return ColoredBox(
          color: Theme.of(context).colorScheme.surface,
          child: SafeArea(
            child: Row(
              children: [
                _ActivityBar(controller: controller, state: state),
                const _ThinSeparator(axis: Axis.horizontal),
                if (state.primarySideBarVisible) ...[
                  SizedBox(
                    width: state.primarySideBarWidth,
                    child: _PrimarySideBar(
                      state: state,
                      child: activityBuilder(context, state.activeActivity),
                    ),
                  ),
                  _ResizeHandle(
                    axis: Axis.horizontal,
                    onDrag: controller.resizePrimarySideBar,
                  ),
                ],
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: _EditorArea(
                                controller: controller,
                                state: state,
                                builder: editorBuilder,
                              ),
                            ),
                            if (state.secondarySideBarVisible) ...[
                              _ResizeHandle(
                                axis: Axis.horizontal,
                                onDrag: (delta) {
                                  controller.resizeSecondarySideBar(-delta);
                                },
                              ),
                              SizedBox(
                                width: state.secondarySideBarWidth,
                                child: _SecondarySideBar(
                                  controller: controller,
                                  state: state,
                                  builder: secondarySideBarBuilder,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (state.panelVisible) ...[
                        _ResizeHandle(
                          axis: Axis.vertical,
                          onDrag: (delta) {
                            controller.resizePanel(-delta);
                          },
                        ),
                        SizedBox(
                          height: state.panelHeight,
                          child: _Panel(
                            controller: controller,
                            state: state,
                            builder: panelBuilder,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ActivityBar extends StatelessWidget {
  const _ActivityBar({required this.controller, required this.state});

  final WorkbenchController controller;
  final WorkbenchLayoutState state;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerHighest,
      child: SizedBox(
        width: 52,
        child: Column(
          children: [
            const SizedBox(height: 8),
            for (final activity in WorkbenchActivity.values)
              _ActivityBarButton(
                activity: activity,
                selected: state.activeActivity == activity &&
                    state.primarySideBarVisible,
                onPressed: () => controller.selectActivity(activity),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _ActivityBarButton extends StatelessWidget {
  const _ActivityBarButton({
    required this.activity,
    required this.selected,
    required this.onPressed,
  });

  final WorkbenchActivity activity;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: _activityLabel(activity),
      waitDuration: const Duration(milliseconds: 500),
      child: SizedBox(
        width: 52,
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (selected)
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: 3,
                  height: 28,
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(2),
                    ),
                  ),
                ),
              ),
            IconButton(
              onPressed: onPressed,
              icon: Icon(_activityIcon(activity)),
              color:
                  selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _PrimarySideBar extends StatelessWidget {
  const _PrimarySideBar({required this.state, required this.child});

  final WorkbenchLayoutState state;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _WorkbenchPane(
      header: _PaneHeader(
        title: _activityTitle(state.activeActivity),
        subtitle: 'Primary Side Bar',
      ),
      child: child,
    );
  }
}

class _EditorArea extends StatelessWidget {
  const _EditorArea({
    required this.controller,
    required this.state,
    required this.builder,
  });

  final WorkbenchController controller;
  final WorkbenchLayoutState state;
  final WorkbenchEditorBuilder builder;

  @override
  Widget build(BuildContext context) {
    final tabs = WorkbenchEditorTab.values;
    return _WorkbenchPane(
      header: Row(
        children: [
          for (final tab in tabs)
            _WorkbenchTabButton(
              label: _editorTabLabel(tab),
              selected: state.activeEditorTab == tab,
              onPressed: () => controller.selectEditorTab(tab),
            ),
          const Spacer(),
          _LayoutControls(controller: controller, state: state),
        ],
      ),
      child: KeyedSubtree(
        key: ValueKey(state.activeEditorTab),
        child: builder(context, state.activeEditorTab),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.controller,
    required this.state,
    required this.builder,
  });

  final WorkbenchController controller;
  final WorkbenchLayoutState state;
  final WorkbenchPanelBuilder builder;

  @override
  Widget build(BuildContext context) {
    final tabs = WorkbenchPanelTab.values;
    return _WorkbenchPane(
      header: Row(
        children: [
          for (final tab in tabs)
            _WorkbenchTabButton(
              label: _panelTabLabel(tab),
              selected: state.activePanelTab == tab,
              onPressed: () => controller.selectPanelTab(tab),
            ),
          const Spacer(),
          IconButton(
            tooltip: 'Hide Panel',
            visualDensity: VisualDensity.compact,
            onPressed: controller.togglePanel,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      child: KeyedSubtree(
        key: ValueKey(state.activePanelTab),
        child: builder(context, state.activePanelTab),
      ),
    );
  }
}

class _SecondarySideBar extends StatelessWidget {
  const _SecondarySideBar({
    required this.controller,
    required this.state,
    required this.builder,
  });

  final WorkbenchController controller;
  final WorkbenchLayoutState state;
  final WorkbenchSecondarySideBarBuilder builder;

  @override
  Widget build(BuildContext context) {
    final tabs = WorkbenchSecondarySideBarTab.values;
    return _WorkbenchPane(
      header: Row(
        children: [
          for (final tab in tabs)
            _WorkbenchTabButton(
              label: _secondarySideBarTabLabel(tab),
              selected: state.activeSecondarySideBarTab == tab,
              onPressed: () => controller.selectSecondarySideBarTab(tab),
            ),
          const Spacer(),
          IconButton(
            tooltip: 'Hide Secondary Side Bar',
            visualDensity: VisualDensity.compact,
            onPressed: controller.toggleSecondarySideBar,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      child: KeyedSubtree(
        key: ValueKey(state.activeSecondarySideBarTab),
        child: builder(context, state.activeSecondarySideBarTab),
      ),
    );
  }
}

class _WorkbenchPane extends StatelessWidget {
  const _WorkbenchPane({required this.header, required this.child});

  final Widget header;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 36, child: header),
          const _ThinSeparator(axis: Axis.vertical),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _PaneHeader extends StatelessWidget {
  const _PaneHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkbenchTabButton extends StatelessWidget {
  const _WorkbenchTabButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return InkWell(
      onTap: onPressed,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? colorScheme.surfaceContainerHigh : null,
          border: Border(
            right: BorderSide(color: colorScheme.outlineVariant),
            bottom: BorderSide(
              color: selected ? colorScheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Center(
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: selected
                    ? colorScheme.onSurface
                    : colorScheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LayoutControls extends StatelessWidget {
  const _LayoutControls({required this.controller, required this.state});

  final WorkbenchController controller;
  final WorkbenchLayoutState state;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _LayoutControlButton(
              tooltip: 'Toggle Primary Side Bar',
              selected: state.primarySideBarVisible,
              icon: Icons.view_sidebar,
              onPressed: controller.togglePrimarySideBar,
            ),
            _LayoutControlButton(
              tooltip: 'Toggle Panel',
              selected: state.panelVisible,
              icon: Icons.horizontal_split,
              onPressed: controller.togglePanel,
            ),
            _LayoutControlButton(
              tooltip: 'Toggle Secondary Side Bar',
              selected: state.secondarySideBarVisible,
              icon: Icons.vertical_split,
              onPressed: controller.toggleSecondarySideBar,
            ),
          ],
        ),
      ),
    );
  }
}

class _LayoutControlButton extends StatelessWidget {
  const _LayoutControlButton({
    required this.tooltip,
    required this.selected,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final bool selected;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
      icon: Icon(icon),
      color: selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
    );
  }
}

class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({required this.axis, required this.onDrag});

  final Axis axis;
  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outlineVariant;
    final cursor = axis == Axis.horizontal
        ? SystemMouseCursors.resizeLeftRight
        : SystemMouseCursors.resizeUpDown;
    return MouseRegion(
      cursor: cursor,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: axis == Axis.horizontal
            ? (details) => onDrag(details.delta.dx)
            : null,
        onVerticalDragUpdate: axis == Axis.vertical
            ? (details) => onDrag(details.delta.dy)
            : null,
        child: SizedBox(
          width: axis == Axis.horizontal ? 1 : double.infinity,
          height: axis == Axis.vertical ? 1 : double.infinity,
          child: _ThinSeparator(axis: axis, color: color),
        ),
      ),
    );
  }
}

class _ThinSeparator extends StatelessWidget {
  const _ThinSeparator({required this.axis, this.color});

  final Axis axis;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ?? Theme.of(context).colorScheme.outlineVariant;
    return ColoredBox(
      color: resolvedColor,
      child: SizedBox(
        width: axis == Axis.horizontal ? 1 : double.infinity,
        height: axis == Axis.vertical ? 1 : double.infinity,
      ),
    );
  }
}

String _activityLabel(WorkbenchActivity activity) {
  return switch (activity) {
    WorkbenchActivity.explorer => 'Explorer',
    WorkbenchActivity.search => 'Search',
    WorkbenchActivity.favorites => 'Favorites',
    WorkbenchActivity.downloads => 'Downloads',
    WorkbenchActivity.settings => 'Settings',
    WorkbenchActivity.about => 'About',
  };
}

String _activityTitle(WorkbenchActivity activity) {
  return _activityLabel(activity).toUpperCase();
}

IconData _activityIcon(WorkbenchActivity activity) {
  return switch (activity) {
    WorkbenchActivity.explorer => Icons.account_tree_outlined,
    WorkbenchActivity.search => Icons.search,
    WorkbenchActivity.favorites => Icons.favorite_border,
    WorkbenchActivity.downloads => Icons.download_outlined,
    WorkbenchActivity.settings => Icons.settings_outlined,
    WorkbenchActivity.about => Icons.info_outline,
  };
}

String _editorTabLabel(WorkbenchEditorTab tab) {
  return switch (tab) {
    WorkbenchEditorTab.blank => 'Blank',
    WorkbenchEditorTab.map => 'Map',
  };
}

String _panelTabLabel(WorkbenchPanelTab tab) {
  return switch (tab) {
    WorkbenchPanelTab.pointOfInterest => 'POINT OF INTEREST',
    WorkbenchPanelTab.debugConsole => 'DEBUG CONSOLE',
  };
}

String _secondarySideBarTabLabel(WorkbenchSecondarySideBarTab tab) {
  return switch (tab) {
    WorkbenchSecondarySideBarTab.properties => 'PROPERTIES',
    WorkbenchSecondarySideBarTab.inspector => 'INSPECTOR',
  };
}
