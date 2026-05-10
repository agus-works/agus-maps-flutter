import 'package:flutter/material.dart';

import '../theme/agus_theme_data.dart';

/// Immutable data used by [AgusPanelTabBar] to render a compact panel tab.
@immutable
class AgusPanelTab {
  /// Creates a panel tab with an optional icon and close affordance.
  const AgusPanelTab({
    required this.id,
    required this.label,
    this.icon,
    this.closable = false,
  });

  /// Stable identifier used for selection and callbacks.
  final String id;

  /// User-visible tab label.
  final String label;

  /// Optional leading icon.
  final IconData? icon;

  /// Whether this tab shows a close action.
  final bool closable;
}

/// A dense VS Code-like tab strip for panels and sidebars.
class AgusPanelTabBar extends StatelessWidget {
  /// Creates a panel tab bar.
  const AgusPanelTabBar({
    required this.tabs,
    required this.selectedId,
    this.trailing = const <Widget>[],
    this.onSelected,
    this.onClose,
    super.key,
  });

  /// Tabs rendered from left to right.
  final List<AgusPanelTab> tabs;

  /// Identifier of the selected tab.
  final String? selectedId;

  /// Widgets pinned to the trailing edge of the strip.
  final List<Widget> trailing;

  /// Called when a tab is selected.
  final ValueChanged<String>? onSelected;

  /// Called when a closable tab close button is pressed.
  final ValueChanged<String>? onClose;

  @override
  Widget build(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);
    final dimensions = AgusThemeData.dimensionsOf(context);

    return Material(
      color: colors.panelBackground,
      child: SizedBox(
        height: dimensions.panelTabHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.panelBorder)),
          ),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final tab in tabs)
                        AgusPanelTabButton(
                          tab: tab,
                          selected: tab.id == selectedId,
                          onSelected: onSelected,
                          onClose: onClose,
                        ),
                    ],
                  ),
                ),
              ),
              ...trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// A single compact panel tab button.
class AgusPanelTabButton extends StatelessWidget {
  /// Creates a panel tab button.
  const AgusPanelTabButton({
    required this.tab,
    required this.selected,
    this.onSelected,
    this.onClose,
    super.key,
  });

  /// Tab data rendered by this button.
  final AgusPanelTab tab;

  /// Whether this tab is selected.
  final bool selected;

  /// Called when the tab is selected.
  final ValueChanged<String>? onSelected;

  /// Called when the close action is pressed.
  final ValueChanged<String>? onClose;

  @override
  Widget build(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);
    final dimensions = AgusThemeData.dimensionsOf(context);
    final foreground = selected
        ? colors.panelTabActiveForeground
        : colors.panelTabInactiveForeground;

    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      child: Material(
        color: selected ? colors.editorBackground : Colors.transparent,
        child: InkWell(
          hoverColor: colors.hoverBackground,
          onTap: () => onSelected?.call(tab.id),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: selected ? colors.focusBorder : Colors.transparent,
                  width: 1,
                ),
                right: BorderSide(color: colors.panelBorder),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.only(left: 10, right: 6),
              child: SizedBox(
                height: dimensions.panelTabHeight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (tab.icon != null) ...[
                      Icon(
                        tab.icon,
                        size: dimensions.iconSize,
                        color: foreground,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      tab.label.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: foreground,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        letterSpacing: 0.2,
                      ),
                    ),
                    if (tab.closable) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'Close ${tab.label}',
                        icon: const Icon(Icons.close),
                        iconSize: dimensions.iconSize,
                        color: foreground,
                        constraints: BoxConstraints.tightFor(
                          width: dimensions.toolbarButtonSize,
                          height: dimensions.toolbarButtonSize,
                        ),
                        padding: EdgeInsets.zero,
                        onPressed: onClose == null
                            ? null
                            : () => onClose!(tab.id),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
