import 'package:flutter/material.dart';

import '../theme/agus_colors.dart';
import '../theme/agus_theme_data.dart';

abstract class AgusContextMenuEntry<T> {
  const AgusContextMenuEntry();
}

class AgusContextMenuAction<T> extends AgusContextMenuEntry<T> {
  const AgusContextMenuAction({
    required this.value,
    required this.label,
    this.icon,
    this.shortcutLabel,
    this.enabled = true,
    this.destructive = false,
  });

  final T value;
  final String label;
  final IconData? icon;
  final String? shortcutLabel;
  final bool enabled;
  final bool destructive;
}

class AgusContextMenuSeparator<T> extends AgusContextMenuEntry<T> {
  const AgusContextMenuSeparator();
}

Future<T?> showAgusContextMenu<T>({
  required BuildContext context,
  required Offset globalPosition,
  required List<AgusContextMenuEntry<T>> entries,
  double minWidth = 190,
}) {
  final overlay = Overlay.maybeOf(context)?.context.findRenderObject();
  if (overlay is! RenderBox) {
    return Future<T?>.value();
  }

  final colors = AgusThemeData.colorsOf(context);
  return showMenu<T>(
    context: context,
    color: colors.sideBarBackground,
    surfaceTintColor: Colors.transparent,
    elevation: 8,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(4),
      side: BorderSide(color: colors.sideBarBorder),
    ),
    constraints: BoxConstraints(minWidth: minWidth),
    position: RelativeRect.fromRect(
      Rect.fromPoints(globalPosition, globalPosition),
      Offset.zero & overlay.size,
    ),
    items: [
      for (final entry in entries) _popupEntryFor(context, colors, entry),
    ],
  );
}

PopupMenuEntry<T> _popupEntryFor<T>(
  BuildContext context,
  AgusColors colors,
  AgusContextMenuEntry<T> entry,
) {
  if (entry is AgusContextMenuSeparator<T>) {
    return PopupMenuDivider(height: 5, color: colors.sideBarBorder);
  }
  if (entry is AgusContextMenuAction<T>) {
    return PopupMenuItem<T>(
      value: entry.enabled ? entry.value : null,
      enabled: entry.enabled,
      height: 28,
      padding: EdgeInsets.zero,
      child: _AgusContextMenuActionRow(action: entry),
    );
  }
  return PopupMenuDivider(height: 0, color: colors.sideBarBorder);
}

class _AgusContextMenuActionRow<T> extends StatelessWidget {
  const _AgusContextMenuActionRow({required this.action});

  final AgusContextMenuAction<T> action;

  @override
  Widget build(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);
    final foreground = action.enabled
        ? action.destructive
              ? colors.errorBackground
              : colors.sideBarForeground
        : colors.sideBarForeground.withValues(alpha: 0.42);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            child: action.icon == null
                ? null
                : Icon(action.icon, size: 15, color: foreground),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              action.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: foreground),
            ),
          ),
          if (action.shortcutLabel != null) ...[
            const SizedBox(width: 18),
            Text(
              action.shortcutLabel!,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: foreground.withValues(alpha: 0.62),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
