import 'package:flutter/material.dart';

import '../theme/agus_colors.dart';
import '../theme/agus_theme_data.dart';

/// Severity level for a notification.
enum AgusNotificationSeverity {
  /// Informational notification.
  info,

  /// Warning notification.
  warning,

  /// Error notification.
  error,

  /// Success notification.
  success,
}

/// A single notification item.
@immutable
class AgusNotification {
  /// Creates a notification.
  const AgusNotification({
    required this.id,
    required this.message,
    this.title,
    this.severity = AgusNotificationSeverity.info,
    this.actions = const <AgusNotificationAction>[],
    this.dismissible = true,
  });

  /// Stable identifier for this notification.
  final String id;

  /// Main notification message.
  final String message;

  /// Optional title text.
  final String? title;

  /// Severity level affecting color and icon.
  final AgusNotificationSeverity severity;

  /// Optional action buttons.
  final List<AgusNotificationAction> actions;

  /// Whether the notification can be dismissed.
  final bool dismissible;
}

/// An action button in a notification.
@immutable
class AgusNotificationAction {
  /// Creates a notification action.
  const AgusNotificationAction({required this.label, required this.onPressed});

  /// Action button label.
  final String label;

  /// Called when the action is pressed.
  final VoidCallback onPressed;
}

/// A VS Code-style toast notification indicator.
class AgusNotificationToast extends StatelessWidget {
  /// Creates a notification toast.
  const AgusNotificationToast({
    required this.notification,
    this.onDismiss,
    super.key,
  });

  /// Notification data to render.
  final AgusNotification notification;

  /// Called when the notification is dismissed.
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);
    final theme = Theme.of(context);

    final backgroundColor = _backgroundColorForSeverity(
      notification.severity,
      colors,
    );
    final foregroundColor = _foregroundColorForSeverity(
      notification.severity,
      colors,
    );
    final icon = _iconForSeverity(notification.severity);

    return Material(
      color: backgroundColor,
      elevation: 8,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480, minWidth: 280),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: colors.contrastBorder),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: foregroundColor),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (notification.title != null) ...[
                    Text(
                      notification.title!,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: foregroundColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  Text(
                    notification.message,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: foregroundColor,
                    ),
                  ),
                  if (notification.actions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final action in notification.actions)
                          TextButton(
                            onPressed: action.onPressed,
                            style: TextButton.styleFrom(
                              foregroundColor: foregroundColor,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              minimumSize: const Size(0, 24),
                            ),
                            child: Text(
                              action.label,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: foregroundColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (notification.dismissible) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                color: foregroundColor,
                constraints: const BoxConstraints.tightFor(
                  width: 24,
                  height: 24,
                ),
                padding: EdgeInsets.zero,
                onPressed: onDismiss,
                tooltip: 'Dismiss',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _backgroundColorForSeverity(
    AgusNotificationSeverity severity,
    AgusColors colors,
  ) {
    return switch (severity) {
      AgusNotificationSeverity.info => colors.infoBackground,
      AgusNotificationSeverity.warning => colors.warningBackground,
      AgusNotificationSeverity.error => colors.errorBackground,
      AgusNotificationSeverity.success => colors.editorBackground,
    };
  }

  Color _foregroundColorForSeverity(
    AgusNotificationSeverity severity,
    AgusColors colors,
  ) {
    return switch (severity) {
      AgusNotificationSeverity.info => colors.infoForeground,
      AgusNotificationSeverity.warning => colors.warningForeground,
      AgusNotificationSeverity.error => colors.errorForeground,
      AgusNotificationSeverity.success => colors.foreground,
    };
  }

  IconData _iconForSeverity(AgusNotificationSeverity severity) {
    return switch (severity) {
      AgusNotificationSeverity.info => Icons.info_outline,
      AgusNotificationSeverity.warning => Icons.warning_amber,
      AgusNotificationSeverity.error => Icons.error_outline,
      AgusNotificationSeverity.success => Icons.check_circle_outline,
    };
  }
}

/// A manager for showing and dismissing notifications as overlays.
class AgusNotificationManager {
  AgusNotificationManager._();

  static final _instance = AgusNotificationManager._();
  static AgusNotificationManager get instance => _instance;

  final List<OverlayEntry> _activeToasts = [];
  final Map<String, OverlayEntry> _toastMap = {};

  /// Shows a notification toast as an overlay.
  void show({
    required BuildContext context,
    required AgusNotification notification,
    Duration duration = const Duration(seconds: 4),
  }) {
    final overlay = Overlay.of(context);
    late final OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) => Positioned(
        bottom: 24 + (_activeToasts.length * 100),
        right: 24,
        child: AgusNotificationToast(
          notification: notification,
          onDismiss: () => dismiss(notification.id),
        ),
      ),
    );

    overlay.insert(entry);
    _activeToasts.add(entry);
    _toastMap[notification.id] = entry;

    if (notification.dismissible) {
      Future.delayed(duration, () => dismiss(notification.id));
    }
  }

  /// Dismisses a notification by ID.
  void dismiss(String id) {
    final entry = _toastMap.remove(id);
    if (entry != null) {
      entry.remove();
      _activeToasts.remove(entry);
      _reposition();
    }
  }

  /// Dismisses all active notifications.
  void dismissAll() {
    for (final entry in _activeToasts) {
      entry.remove();
    }
    _activeToasts.clear();
    _toastMap.clear();
  }

  void _reposition() {
    for (var i = 0; i < _activeToasts.length; i++) {
      _activeToasts[i].markNeedsBuild();
    }
  }
}
