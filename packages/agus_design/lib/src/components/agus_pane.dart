import 'package:flutter/material.dart';

import '../theme/agus_theme_data.dart';

/// Dense docked pane chrome for workbench panels and inspectors.
class AgusPane extends StatelessWidget {
  /// Creates a pane with an optional header and actions.
  const AgusPane({
    required this.child,
    this.title,
    this.subtitle,
    this.header,
    this.actions = const <Widget>[],
    this.backgroundColor,
    super.key,
  });

  /// Optional title rendered in the default header.
  final String? title;

  /// Optional subtitle rendered under [title].
  final String? subtitle;

  /// Custom header. When provided, [title], [subtitle], and [actions] are not
  /// used.
  final Widget? header;

  /// Header actions rendered after the title/subtitle group.
  final List<Widget> actions;

  /// Main pane content.
  final Widget child;

  /// Optional background override.
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);
    final resolvedHeader = header ?? _buildDefaultHeader(context);

    return Material(
      color: backgroundColor ?? colors.panelBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (resolvedHeader != null) ...[
            SizedBox(height: 35, child: resolvedHeader),
            Divider(height: 1, color: colors.panelBorder),
          ],
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget? _buildDefaultHeader(BuildContext context) {
    final title = this.title;
    if (title == null && actions.isEmpty) {
      return null;
    }

    final colors = AgusThemeData.colorsOf(context);
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 4),
      child: Row(
        children: [
          if (title != null)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelLarge?.copyWith(
                      color: colors.editorForeground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.labelSmall?.copyWith(
                        color: colors.editorForeground.withValues(alpha: 0.65),
                      ),
                    ),
                ],
              ),
            )
          else
            const Spacer(),
          ...actions,
        ],
      ),
    );
  }
}

/// Reusable empty/info state for workbench panes.
class AgusEmptyState extends StatelessWidget {
  /// Creates an empty state with a small icon, title, and optional message.
  const AgusEmptyState({
    required this.title,
    this.message,
    this.icon,
    this.action,
    super.key,
  });

  /// Main empty-state label.
  final String title;

  /// Optional supporting message.
  final String? message;

  /// Optional icon shown above [title].
  final IconData? icon;

  /// Optional trailing call to action.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 36, color: colors.editorForeground),
              const SizedBox(height: 12),
            ],
            Text(
              title,
              textAlign: TextAlign.center,
              style: textTheme.titleSmall?.copyWith(
                color: colors.editorForeground,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(
                  color: colors.editorForeground.withValues(alpha: 0.72),
                ),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 12), action!],
          ],
        ),
      ),
    );
  }
}
