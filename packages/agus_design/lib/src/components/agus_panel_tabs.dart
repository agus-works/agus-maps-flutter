import 'package:flutter/material.dart';

import 'agus_tabs.dart';

// Legacy type aliases for backward compatibility.
// New code should use AgusTab and AgusTabBar directly.

/// Legacy panel tab data type. Use [AgusTab] instead.
typedef AgusPanelTab = AgusTab;

/// A dense VS Code-like tab strip for panels and sidebars.
///
/// This is a compatibility wrapper around [AgusTabBar] with the panel variant.
/// New code should use [AgusTabBar] directly.
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
  final List<AgusTab> tabs;

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
    return AgusTabBar(
      tabs: tabs,
      selectedId: selectedId,
      variant: AgusTabVariant.panel,
      trailing: trailing,
      onSelected: onSelected,
      onClose: onClose,
    );
  }
}

/// A single compact panel tab button.
///
/// This is a compatibility wrapper around [AgusTabButton] with the panel variant.
/// New code should use [AgusTabButton] directly.
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
  final AgusTab tab;

  /// Whether this tab is selected.
  final bool selected;

  /// Called when the tab is selected.
  final ValueChanged<String>? onSelected;

  /// Called when the close action is pressed.
  final ValueChanged<String>? onClose;

  @override
  Widget build(BuildContext context) {
    return AgusTabButton(
      tab: tab,
      selected: selected,
      variant: AgusTabVariant.panel,
      onSelected: onSelected,
      onClose: onClose,
    );
  }
}
