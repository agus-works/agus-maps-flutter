import 'package:agus_design/agus_design.dart';
import 'package:flutter/material.dart';

/// Builds the icon used for a search result row.
typedef MapSearchResultIconBuilder<T> = IconData Function(T result);

/// Returns whether route actions should be disabled for a result.
typedef MapSearchResultDisabledBuilder<T> = bool Function(T result);

/// Reusable VS Code-inspired map search surface for side bars and overlays.
class MapSearchPanel<T> extends StatelessWidget {
  /// Creates a search panel with an input, empty states, and result rows.
  const MapSearchPanel({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.results,
    required this.titleFor,
    required this.subtitleFor,
    required this.iconFor,
    required this.onOpen,
    required this.onChanged,
    required this.onSubmitted,
    required this.onResultSelected,
    this.onResultRoute,
    this.routeDisabledFor,
    this.placeholder = 'Search',
    this.trailing,
    this.searching = false,
    this.expandResults = true,
    this.resultPanelMaxHeight,
  });

  /// Search text controller.
  final TextEditingController controller;

  /// Focus node for the search field.
  final FocusNode focusNode;

  /// Current result list.
  final List<T> results;

  /// Result title accessor.
  final String Function(T result) titleFor;

  /// Result subtitle accessor.
  final String Function(T result) subtitleFor;

  /// Result icon accessor.
  final MapSearchResultIconBuilder<T> iconFor;

  /// Called when the search input is focused or tapped.
  final VoidCallback onOpen;

  /// Called when the query changes.
  final ValueChanged<String> onChanged;

  /// Called when the query is submitted.
  final ValueChanged<String> onSubmitted;

  /// Called when a result row is selected.
  final ValueChanged<T> onResultSelected;

  /// Optional route action for a result.
  final ValueChanged<T>? onResultRoute;

  /// Whether the route action is disabled for a result.
  final MapSearchResultDisabledBuilder<T>? routeDisabledFor;

  /// Placeholder shown inside the search box.
  final String placeholder;

  /// Optional trailing widget beside the search box.
  final Widget? trailing;

  /// Whether the native search provider is still running.
  final bool searching;

  /// Whether result content should fill available height.
  final bool expandResults;

  /// Optional maximum height used when [expandResults] is false.
  final double? resultPanelMaxHeight;

  @override
  Widget build(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);
    final hasQuery = controller.text.trim().isNotEmpty;
    final resultsView = _buildResults(context, hasQuery);

    return Material(
      color: colors.sideBarBackground,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: colors.sideBarBorder),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          mainAxisSize: expandResults ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: AgusSearchBox(
                      controller: controller,
                      focusNode: focusNode,
                      placeholder: placeholder,
                      onTap: onOpen,
                      onChanged: onChanged,
                      onSubmitted: onSubmitted,
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 6),
                    trailing!,
                  ],
                ],
              ),
            ),
            if (expandResults)
              Expanded(child: resultsView)
            else if (hasQuery)
              ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: 72,
                  maxHeight: resultPanelMaxHeight ?? 220,
                ),
                child: resultsView,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(BuildContext context, bool hasQuery) {
    if (!hasQuery) {
      return const AgusEmptyState(
        icon: Icons.search,
        title: 'Search',
        message: 'Type to search places, coordinates, or favorites.',
      );
    }

    if (results.isEmpty) {
      return AgusEmptyState(
        icon: Icons.manage_search,
        title: 'Search results',
        message: searching ? 'Searching...' : 'No results',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      shrinkWrap: !expandResults,
      itemCount: results.length,
      itemBuilder: (context, index) {
        final result = results[index];
        return _MapSearchResultTile<T>(
          result: result,
          title: titleFor(result),
          subtitle: subtitleFor(result),
          icon: iconFor(result),
          routeEnabled: routeDisabledFor?.call(result) != true,
          onSelected: onResultSelected,
          onRoute: onResultRoute,
        );
      },
    );
  }
}

class _MapSearchResultTile<T> extends StatefulWidget {
  const _MapSearchResultTile({
    required this.result,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.routeEnabled,
    required this.onSelected,
    this.onRoute,
  });

  final T result;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool routeEnabled;
  final ValueChanged<T> onSelected;
  final ValueChanged<T>? onRoute;

  @override
  State<_MapSearchResultTile<T>> createState() =>
      _MapSearchResultTileState<T>();
}

class _MapSearchResultTileState<T> extends State<_MapSearchResultTile<T>> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);
    final textTheme = Theme.of(context).textTheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: _hovered ? colors.hoverBackground : Colors.transparent,
        child: InkWell(
          onTap: () => widget.onSelected(widget.result),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  size: 16,
                  color: colors.sideBarForeground.withValues(alpha: 0.72),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: colors.sideBarForeground,
                          height: 1.15,
                        ),
                      ),
                      Text(
                        widget.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelSmall?.copyWith(
                          color: colors.sideBarForeground.withValues(
                            alpha: 0.68,
                          ),
                          height: 1.15,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.onRoute != null)
                  IconButton(
                    tooltip: 'Route',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(
                      width: 28,
                      height: 28,
                    ),
                    padding: EdgeInsets.zero,
                    iconSize: 16,
                    onPressed: widget.routeEnabled
                        ? () => widget.onRoute!(widget.result)
                        : null,
                    icon: const Icon(Icons.alt_route),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
