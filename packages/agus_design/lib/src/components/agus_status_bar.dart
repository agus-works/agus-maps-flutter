import 'package:flutter/material.dart';

import '../theme/agus_theme_data.dart';

enum AgusStatusBarItemSeverity { standard, warning, error }

@immutable
class AgusStatusBarItem {
  const AgusStatusBarItem({
    required this.id,
    required this.label,
    this.icon,
    this.onPressed,
    this.severity = AgusStatusBarItemSeverity.standard,
    this.progress = false,
  });

  final String id;
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final AgusStatusBarItemSeverity severity;
  final bool progress;
}

class AgusStatusBar extends StatelessWidget {
  const AgusStatusBar({
    this.leftItems = const <AgusStatusBarItem>[],
    this.rightItems = const <AgusStatusBarItem>[],
    super.key,
  });

  final List<AgusStatusBarItem> leftItems;
  final List<AgusStatusBarItem> rightItems;

  @override
  Widget build(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);
    final dimensions = AgusThemeData.dimensionsOf(context);

    return Material(
      color: colors.statusBarBackground,
      child: SizedBox(
        height: dimensions.statusBarHeight,
        child: Row(
          children: [
            for (final item in leftItems) AgusStatusBarItemView(item: item),
            const Spacer(),
            for (final item in rightItems) AgusStatusBarItemView(item: item),
          ],
        ),
      ),
    );
  }
}

class AgusStatusBarItemView extends StatelessWidget {
  const AgusStatusBarItemView({required this.item, super.key});

  final AgusStatusBarItem item;

  @override
  Widget build(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);
    final background = switch (item.severity) {
      AgusStatusBarItemSeverity.warning => colors.warningBackground,
      AgusStatusBarItemSeverity.error => colors.errorBackground,
      AgusStatusBarItemSeverity.standard => Colors.transparent,
    };

    return Material(
      color: background,
      child: InkWell(
        hoverColor: colors.statusBarItemHoverBackground,
        onTap: item.onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (item.progress)
                SizedBox(
                  width: 11,
                  height: 11,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.4,
                    valueColor: AlwaysStoppedAnimation(
                      colors.statusBarForeground,
                    ),
                  ),
                )
              else if (item.icon != null)
                Icon(item.icon, size: 14, color: colors.statusBarForeground),
              if (item.progress || item.icon != null) const SizedBox(width: 4),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.statusBarForeground,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
