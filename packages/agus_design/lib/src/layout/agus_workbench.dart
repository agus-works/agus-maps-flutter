import 'package:flutter/material.dart';

import '../components/agus_activity_bar.dart';
import '../components/agus_status_bar.dart';
import '../components/agus_title_bar.dart';
import '../theme/agus_theme_data.dart';
import 'agus_split_view.dart';

enum AgusWorkbenchArea { primarySidebar, secondarySidebar, panel }

class AgusWorkbench extends StatelessWidget {
  const AgusWorkbench({
    required this.title,
    required this.activityBar,
    required this.editor,
    required this.statusBar,
    this.primarySidebar,
    this.secondarySidebar,
    this.bottomPanel,
    this.commandCenter,
    this.titleBarLeadingActions = const <Widget>[],
    this.titleBarTrailingActions = const <Widget>[],
    this.showPrimarySidebar = true,
    this.showSecondarySidebar = false,
    this.showPanel = true,
    this.showPaneControls = true,
    this.onToggleArea,
    super.key,
  });

  final String title;
  final AgusActivityBar activityBar;
  final Widget? primarySidebar;
  final Widget? secondarySidebar;
  final Widget editor;
  final Widget? bottomPanel;
  final AgusStatusBar statusBar;
  final Widget? commandCenter;
  final List<Widget> titleBarLeadingActions;
  final List<Widget> titleBarTrailingActions;
  final bool showPrimarySidebar;
  final bool showSecondarySidebar;
  final bool showPanel;
  final bool showPaneControls;
  final ValueChanged<AgusWorkbenchArea>? onToggleArea;

  @override
  Widget build(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);
    final dimensions = AgusThemeData.dimensionsOf(context);
    final editorWithPanel = showPanel && bottomPanel != null
        ? AgusSplitView(
            axis: Axis.vertical,
            sizedPane: AgusSplitViewPane.second,
            initialFirstExtent: dimensions.panelDefaultHeight,
            minFirstExtent: 160,
            minSecondExtent: dimensions.panelMinHeight,
            first: editor,
            second: bottomPanel!,
          )
        : editor;

    Widget body = editorWithPanel;

    if (showSecondarySidebar && secondarySidebar != null) {
      body = AgusSplitView(
        axis: Axis.horizontal,
        sizedPane: AgusSplitViewPane.second,
        initialFirstExtent: dimensions.secondarySideBarDefaultWidth,
        minFirstExtent: 160,
        minSecondExtent: dimensions.sideBarMinWidth,
        first: body,
        second: secondarySidebar!,
      );
    }

    if (showPrimarySidebar && primarySidebar != null) {
      body = AgusSplitView(
        axis: Axis.horizontal,
        initialFirstExtent: dimensions.sideBarDefaultWidth,
        minFirstExtent: dimensions.sideBarMinWidth,
        first: primarySidebar!,
        second: body,
      );
    }

    return ColoredBox(
      color: colors.workbenchBackground,
      child: Column(
        children: [
          AgusTitleBar(
            title: title,
            commandCenter: commandCenter,
            leadingActions: titleBarLeadingActions,
            trailingActions: _buildTrailingActions(context),
          ),
          Expanded(
            child: Row(
              children: [
                activityBar,
                Expanded(child: body),
              ],
            ),
          ),
          statusBar,
        ],
      ),
    );
  }

  List<Widget> _buildTrailingActions(BuildContext context) {
    final actions = <Widget>[];
    
    if (showPaneControls) {
      final paneButtons = _paneControlButtons(context);
      if (paneButtons.isNotEmpty) {
        actions.addAll(paneButtons);
        if (titleBarTrailingActions.isNotEmpty) {
          actions.add(const SizedBox(width: 8));
          actions.add(_buildDivider(context));
          actions.add(const SizedBox(width: 8));
        }
      }
    }
    
    actions.addAll(titleBarTrailingActions);
    return actions;
  }

  Widget _buildDivider(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);
    final dimensions = AgusThemeData.dimensionsOf(context);
    
    return SizedBox(
      height: dimensions.titleBarHeight * 0.5,
      child: VerticalDivider(
        width: 1,
        thickness: 1,
        color: colors.titleBarForeground.withValues(alpha: 0.15),
      ),
    );
  }

  List<Widget> _paneControlButtons(BuildContext context) {
    final buttons = <Widget>[];
    if (primarySidebar != null) {
      buttons.add(
        _AgusWorkbenchPaneToggleButton(
          icon: Icons.view_sidebar,
          tooltip: 'Toggle primary sidebar',
          selected: showPrimarySidebar,
          onPressed: onToggleArea == null
              ? null
              : () => onToggleArea!(AgusWorkbenchArea.primarySidebar),
        ),
      );
    }
    if (bottomPanel != null) {
      buttons.add(
        _AgusWorkbenchPaneToggleButton(
          icon: Icons.space_dashboard,
          tooltip: 'Toggle panel',
          selected: showPanel,
          onPressed: onToggleArea == null
              ? null
              : () => onToggleArea!(AgusWorkbenchArea.panel),
        ),
      );
    }
    if (secondarySidebar != null) {
      buttons.add(
        _AgusWorkbenchPaneToggleButton(
          icon: Icons.vertical_split,
          tooltip: 'Toggle secondary sidebar',
          selected: showSecondarySidebar,
          onPressed: onToggleArea == null
              ? null
              : () => onToggleArea!(AgusWorkbenchArea.secondarySidebar),
        ),
      );
    }

    return buttons;
  }
}

class _AgusWorkbenchPaneToggleButton extends StatelessWidget {
  const _AgusWorkbenchPaneToggleButton({
    required this.icon,
    required this.tooltip,
    required this.selected,
    this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);
    final dimensions = AgusThemeData.dimensionsOf(context);
    final foreground = selected
        ? colors.titleBarForeground
        : colors.titleBarForeground.withValues(alpha: 0.6);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(dimensions.borderRadius),
        ),
        child: Tooltip(
          message: tooltip,
          child: Container(
            width: dimensions.toolbarButtonSize,
            height: dimensions.toolbarButtonSize,
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: dimensions.iconSize,
              color: foreground,
            ),
          ),
        ),
      ),
    );
  }
}
