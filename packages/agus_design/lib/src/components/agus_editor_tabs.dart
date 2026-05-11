import 'package:flutter/material.dart';

import 'agus_tabs.dart';

// Legacy type aliases for backward compatibility.
// New code should use AgusTab and AgusTabBar directly.

/// Legacy editor tab data type. Use [AgusTab] instead.
typedef AgusEditorTab = AgusTab;

/// Called with the full tab list after an editor tab has been reordered.
typedef AgusEditorTabReorderCallback = AgusTabReorderCallback;

/// A horizontally scrollable editor tab strip with selection, close, and
/// optional drag reordering.
///
/// This is a compatibility wrapper around [AgusTabBar] with the editor variant.
/// New code should use [AgusTabBar] directly.
class AgusEditorTabBar extends StatelessWidget {
  /// Creates an editor tab bar for the provided [tabs].
  const AgusEditorTabBar({
    required this.tabs,
    required this.selectedId,
    this.onSelected,
    this.onClose,
    this.onReorder,
    super.key,
  });

  /// Tabs rendered from left to right.
  final List<AgusTab> tabs;

  /// Identifier of the currently selected tab, or null when nothing is active.
  final String? selectedId;

  /// Called when a tab is selected.
  final ValueChanged<String>? onSelected;

  /// Called when a tab close button is pressed.
  final ValueChanged<String>? onClose;

  /// Called with a reordered copy of [tabs] after a tab is dragged and dropped.
  ///
  /// Leave this null to disable tab reordering.
  final AgusTabReorderCallback? onReorder;

  @override
  Widget build(BuildContext context) {
    return AgusTabBar(
      tabs: tabs,
      selectedId: selectedId,
      variant: AgusTabVariant.editor,
      onSelected: onSelected,
      onClose: onClose,
      onReorder: onReorder,
    );
  }
}

/// A single editor tab button used inside [AgusEditorTabBar].
///
/// This is a compatibility wrapper around [AgusTabButton] with the editor variant.
/// New code should use [AgusTabButton] directly.
class AgusEditorTabButton extends StatelessWidget {
  /// Creates an editor tab button for [tab].
  const AgusEditorTabButton({
    required this.tab,
    required this.selected,
    this.onSelected,
    this.onClose,
    super.key,
  });

  /// Tab data rendered by this button.
  final AgusTab tab;

  /// Whether this button represents the selected tab.
  final bool selected;

  /// Called when the button body is tapped.
  final ValueChanged<String>? onSelected;

  /// Called when the close affordance is pressed.
  final ValueChanged<String>? onClose;

  @override
  Widget build(BuildContext context) {
    return AgusTabButton(
      tab: tab,
      selected: selected,
      variant: AgusTabVariant.editor,
      onSelected: onSelected,
      onClose: onClose,
    );
  }
}
