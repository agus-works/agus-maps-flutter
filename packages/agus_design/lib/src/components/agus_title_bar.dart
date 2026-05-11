import 'package:flutter/material.dart';

import 'agus_command.dart';
import '../theme/agus_theme_data.dart';

class AgusTitleBar extends StatelessWidget {
  const AgusTitleBar({
    required this.title,
    this.commandCenter,
    this.leadingActions = const <Widget>[],
    this.trailingActions = const <Widget>[],
    super.key,
  });

  final String title;
  final Widget? commandCenter;
  final List<Widget> leadingActions;
  final List<Widget> trailingActions;

  @override
  Widget build(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);
    final dimensions = AgusThemeData.dimensionsOf(context);

    return Material(
      color: colors.titleBarBackground,
      child: SizedBox(
        height: dimensions.titleBarHeight,
        child: Row(
          children: [
            const SizedBox(width: 12),
            ...leadingActions,
            if (leadingActions.isNotEmpty) const SizedBox(width: 8),
            Flexible(
              flex: 1,
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.titleBarForeground,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            Flexible(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 600,
                      minWidth: 300,
                    ),
                    child: SizedBox(
                      height: dimensions.commandCenterHeight,
                      child: commandCenter ?? const AgusCommandCenter(),
                    ),
                  ),
                ),
              ),
            ),
            if (trailingActions.isNotEmpty)
              Flexible(
                flex: 1,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: trailingActions,
                ),
              ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
