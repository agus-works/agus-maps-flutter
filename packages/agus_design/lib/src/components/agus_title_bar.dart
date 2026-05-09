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
            const SizedBox(width: 8),
            ...leadingActions,
            SizedBox(
              width: 180,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.titleBarForeground,
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: SizedBox(
                    height: dimensions.commandCenterHeight,
                    child: commandCenter ?? const AgusCommandCenter(),
                  ),
                ),
              ),
            ),
            ...trailingActions,
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
