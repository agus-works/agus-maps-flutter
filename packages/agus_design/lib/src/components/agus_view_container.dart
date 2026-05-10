import 'package:flutter/material.dart';

import '../theme/agus_theme_data.dart';

/// Immutable data for a collapsible workbench view.
///
/// Visual Studio Code calls the accordion sections in side bars "Views" and
/// the host that contains them a "View Container".
@immutable
class AgusView {
  /// Creates a view rendered by [AgusViewContainer].
  const AgusView({
    required this.id,
    required this.title,
    required this.child,
    this.icon,
    this.countLabel,
    this.actions = const <Widget>[],
    this.initiallyExpanded = true,
  });

  /// Stable identifier used for expansion and callbacks.
  final String id;

  /// User-visible view title.
  final String title;

  /// Optional icon shown before [title].
  final IconData? icon;

  /// Optional count or compact badge rendered after the title.
  final String? countLabel;

  /// Optional action widgets pinned to the trailing edge of the view header.
  final List<Widget> actions;

  /// Whether this view starts expanded when the container is uncontrolled.
  final bool initiallyExpanded;

  /// Content shown when the view is expanded.
  final Widget child;
}

/// A VS Code-like view container for vertical side-bar panes.
class AgusViewContainer extends StatefulWidget {
  /// Creates a view container.
  const AgusViewContainer({
    required this.views,
    this.expandedIds,
    this.onToggle,
    this.onExpandedIdsChanged,
    this.allowMultipleExpanded = true,
    this.headerHeight = 24,
    this.emptyLabel = 'No views available.',
    super.key,
  }) : assert(headerHeight >= 0);

  /// Views rendered from top to bottom.
  final List<AgusView> views;

  /// Controlled expanded view ids.
  ///
  /// When null, the container manages expansion internally using each view's
  /// [AgusView.initiallyExpanded] value.
  final Set<String>? expandedIds;

  /// Called with the toggled view id.
  final ValueChanged<String>? onToggle;

  /// Called with the next expanded id set after a toggle.
  final ValueChanged<Set<String>>? onExpandedIdsChanged;

  /// Whether multiple views may be expanded at the same time.
  final bool allowMultipleExpanded;

  /// Header height for each view.
  final double headerHeight;

  /// Text rendered when [views] is empty.
  final String emptyLabel;

  @override
  State<AgusViewContainer> createState() => _AgusViewContainerState();
}

class _AgusViewContainerState extends State<AgusViewContainer> {
  late Set<String> _expandedIds = _initialExpandedIds();

  Set<String> get _effectiveExpandedIds {
    return widget.expandedIds ?? _expandedIds;
  }

  @override
  void didUpdateWidget(covariant AgusViewContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final viewIds = widget.views.map((view) => view.id).toSet();
    if (widget.expandedIds == null) {
      _expandedIds = _expandedIds.intersection(viewIds);
      for (final view in widget.views) {
        final wasPresent = oldWidget.views.any(
          (oldView) => oldView.id == view.id,
        );
        if (!wasPresent && view.initiallyExpanded) {
          _expandedIds.add(view.id);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);
    if (widget.views.isEmpty) {
      return ColoredBox(
        color: colors.sideBarBackground,
        child: Center(
          child: Text(
            widget.emptyLabel,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.sideBarForeground.withValues(alpha: 0.72),
            ),
          ),
        ),
      );
    }

    return ColoredBox(
      color: colors.sideBarBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final view in widget.views) _AgusViewSection(view: view),
        ],
      ),
    );
  }

  Set<String> _initialExpandedIds() {
    return {
      for (final view in widget.views)
        if (view.initiallyExpanded) view.id,
    };
  }

  void _toggleView(String id) {
    final wasExpanded = _effectiveExpandedIds.contains(id);
    final nextIds = <String>{};
    if (widget.allowMultipleExpanded) {
      nextIds.addAll(_effectiveExpandedIds);
      if (wasExpanded) {
        nextIds.remove(id);
      } else {
        nextIds.add(id);
      }
    } else if (!wasExpanded) {
      nextIds.add(id);
    }

    if (widget.expandedIds == null) {
      setState(() => _expandedIds = nextIds);
    }
    widget.onToggle?.call(id);
    widget.onExpandedIdsChanged?.call(Set.unmodifiable(nextIds));
  }
}

class _AgusViewSection extends StatelessWidget {
  const _AgusViewSection({required this.view});

  final AgusView view;

  @override
  Widget build(BuildContext context) {
    final state = context.findAncestorStateOfType<_AgusViewContainerState>()!;
    final expanded = state._effectiveExpandedIds.contains(view.id);
    final colors = AgusThemeData.colorsOf(context);
    final dimensions = AgusThemeData.dimensionsOf(context);
    final textTheme = Theme.of(context).textTheme;

    return Column(
      key: ValueKey('agus-view-${view.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: expanded,
          label: view.title,
          child: Material(
            color: colors.sideBarBackground,
            child: InkWell(
              hoverColor: colors.hoverBackground,
              onTap: () => state._toggleView(view.id),
              child: SizedBox(
                height: state.widget.headerHeight,
                child: Row(
                  children: [
                    const SizedBox(width: 2),
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_right,
                      size: dimensions.iconSize,
                      color: colors.sideBarForeground,
                    ),
                    const SizedBox(width: 2),
                    if (view.icon != null) ...[
                      Icon(
                        view.icon,
                        size: dimensions.iconSize,
                        color: colors.sideBarForeground,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        view.title.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelMedium?.copyWith(
                          color: colors.sideBarForeground,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (view.countLabel != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        view.countLabel!,
                        style: textTheme.labelSmall?.copyWith(
                          color: colors.sideBarForeground.withValues(
                            alpha: 0.72,
                          ),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    ...view.actions,
                  ],
                ),
              ),
            ),
          ),
        ),
        if (expanded) view.child,
      ],
    );
  }
}
