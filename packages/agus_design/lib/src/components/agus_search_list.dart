import 'package:flutter/material.dart';

import '../theme/agus_theme_data.dart';

/// A single result item in a VS Code-style search/result list.
@immutable
class AgusSearchResultItem {
  /// Creates a search result item.
  const AgusSearchResultItem({
    required this.id,
    required this.label,
    this.icon,
    this.metadata,
    this.shortcut,
    this.enabled = true,
    this.onTap,
  });

  /// Stable identifier for this item.
  final String id;

  /// Primary label text.
  final String label;

  /// Optional leading icon.
  final IconData? icon;

  /// Optional trailing metadata (e.g., file path, line number).
  final String? metadata;

  /// Optional keyboard shortcut label.
  final String? shortcut;

  /// Whether this item can be selected.
  final bool enabled;

  /// Called when the item is tapped.
  final VoidCallback? onTap;
}

/// A VS Code-style search/result list with loading, empty, and disabled states.
class AgusSearchResultList extends StatelessWidget {
  /// Creates a search result list.
  const AgusSearchResultList({
    required this.items,
    this.selectedId,
    this.loading = false,
    this.emptyMessage = 'No results',
    this.onItemSelected,
    super.key,
  });

  /// Items to display.
  final List<AgusSearchResultItem> items;

  /// Currently selected item ID.
  final String? selectedId;

  /// Whether the list is in a loading state.
  final bool loading;

  /// Message to show when items is empty.
  final String emptyMessage;

  /// Called when an item is selected.
  final ValueChanged<String>? onItemSelected;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return _buildLoading(context);
    }

    if (items.isEmpty) {
      return _buildEmpty(context);
    }

    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return AgusSearchResultRow(
          item: item,
          selected: item.id == selectedId,
          onTap: () => onItemSelected?.call(item.id),
        );
      },
    );
  }

  Widget _buildLoading(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(colors.foreground),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Loading...',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.descriptionForeground,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off,
              size: 48,
              color: colors.descriptionForeground,
            ),
            const SizedBox(height: 12),
            Text(
              emptyMessage,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.descriptionForeground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single row in a search result list.
class AgusSearchResultRow extends StatelessWidget {
  /// Creates a search result row.
  const AgusSearchResultRow({
    required this.item,
    required this.selected,
    this.onTap,
    super.key,
  });

  /// The item data to render.
  final AgusSearchResultItem item;

  /// Whether this row is selected.
  final bool selected;

  /// Called when the row is tapped.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);
    final dimensions = AgusThemeData.dimensionsOf(context);

    final foreground = item.enabled
        ? (selected ? colors.listActiveSelectionForeground : colors.foreground)
        : colors.disabledForeground;
    final background = selected
        ? colors.listActiveSelectionBackground
        : Colors.transparent;

    return Semantics(
      button: true,
      selected: selected,
      enabled: item.enabled,
      label: item.label,
      child: Material(
        color: background,
        child: InkWell(
          hoverColor: selected ? null : colors.listHoverBackground,
          onTap: item.enabled ? (onTap ?? item.onTap) : null,
          child: Container(
            constraints: BoxConstraints(minHeight: dimensions.listItemHeight),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                if (item.icon != null) ...[
                  Icon(
                    item.icon,
                    size: dimensions.iconSize,
                    color: foreground,
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: foreground,
                        ),
                      ),
                      if (item.metadata != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.metadata!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colors.descriptionForeground,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (item.shortcut != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: colors.contrastBorder),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      item.shortcut!,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.descriptionForeground,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
