import 'package:flutter/material.dart';

import '../theme/agus_theme_data.dart';

@immutable
class AgusActivityBarItem {
  const AgusActivityBarItem({
    required this.id,
    required this.icon,
    required this.tooltip,
    this.badgeCount,
    this.onPressed,
    this.enabled = true,
  });

  final String id;
  final IconData icon;
  final String tooltip;
  final int? badgeCount;
  final VoidCallback? onPressed;
  final bool enabled;
}

class AgusActivityBar extends StatelessWidget {
  const AgusActivityBar({
    required this.items,
    this.bottomItems = const <AgusActivityBarItem>[],
    this.selectedId,
    this.onSelected,
    super.key,
  });

  final List<AgusActivityBarItem> items;
  final List<AgusActivityBarItem> bottomItems;
  final String? selectedId;
  final ValueChanged<String>? onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);
    final dimensions = AgusThemeData.dimensionsOf(context);

    return Material(
      color: colors.activityBarBackground,
      child: SizedBox(
        width: dimensions.activityBarWidth,
        child: Column(
          children: [
            for (final item in items)
              AgusActivityBarButton(
                item: item,
                selected: item.id == selectedId,
                onSelected: onSelected,
              ),
            const Spacer(),
            for (final item in bottomItems)
              AgusActivityBarButton(
                item: item,
                selected: item.id == selectedId,
                onSelected: onSelected,
              ),
          ],
        ),
      ),
    );
  }
}

class AgusActivityBarButton extends StatelessWidget {
  const AgusActivityBarButton({
    required this.item,
    required this.selected,
    this.onSelected,
    super.key,
  });

  final AgusActivityBarItem item;
  final bool selected;
  final ValueChanged<String>? onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);
    final dimensions = AgusThemeData.dimensionsOf(context);
    final foreground = selected
        ? colors.activityBarActiveForeground
        : colors.activityBarForeground;

    return Tooltip(
      message: item.tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: Semantics(
        button: true,
        selected: selected,
        label: item.tooltip,
        child: SizedBox(
          width: dimensions.activityBarWidth,
          height: dimensions.activityBarWidth,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: InkWell(
                  hoverColor: colors.hoverBackground,
                  onTap: item.enabled
                      ? () {
                          onSelected?.call(item.id);
                          item.onPressed?.call();
                        }
                      : null,
                  child: Icon(
                    item.icon,
                    color: item.enabled
                        ? foreground
                        : foreground.withValues(alpha: 0.35),
                    size: 24,
                  ),
                ),
              ),
              if (selected)
                Positioned(
                  left: 0,
                  top: (dimensions.activityBarWidth - 24) / 2,
                  width: 2,
                  height: 24,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.activityBarActiveForeground,
                    ),
                  ),
                ),
              if (item.badgeCount != null && item.badgeCount! > 0)
                Positioned(
                  right: 5,
                  top: 6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.activityBarBadgeBackground,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: Text(
                        item.badgeCount! > 99 ? '99+' : '${item.badgeCount}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.activityBarBadgeForeground,
                          fontSize: 10,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
