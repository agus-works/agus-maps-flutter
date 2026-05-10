import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/agus_colors.dart';
import '../theme/agus_theme_data.dart';

enum AgusButtonVariant { primary, secondary, subtle, toolbar }

class AgusButton extends StatefulWidget {
  const AgusButton({
    required this.onPressed,
    this.label,
    this.icon,
    this.tooltip,
    this.variant = AgusButtonVariant.secondary,
    this.autofocus = false,
    this.focusNode,
    this.minWidth = 0,
    this.minHeight = 26,
    this.padding,
    super.key,
  }) : assert(label != null || icon != null);

  const AgusButton.icon({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.variant = AgusButtonVariant.toolbar,
    this.autofocus = false,
    this.focusNode,
    this.minWidth = 26,
    this.minHeight = 24,
    this.padding = const EdgeInsets.all(4),
    super.key,
  }) : label = null;

  final String? label;
  final IconData? icon;
  final String? tooltip;
  final VoidCallback? onPressed;
  final AgusButtonVariant variant;
  final bool autofocus;
  final FocusNode? focusNode;
  final double minWidth;
  final double minHeight;
  final EdgeInsetsGeometry? padding;

  @override
  State<AgusButton> createState() => _AgusButtonState();
}

class _AgusButtonState extends State<AgusButton> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  bool get _enabled => widget.onPressed != null;

  @override
  Widget build(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);
    final state = _AgusButtonVisualState(
      enabled: _enabled,
      hovered: _hovered,
      pressed: _pressed,
      focused: _focused,
    );
    final palette = _AgusButtonPalette.resolve(colors, widget.variant, state);
    final textStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: palette.foreground,
      fontWeight: FontWeight.w600,
    );
    final content = Semantics(
      button: true,
      enabled: _enabled,
      label: widget.label ?? widget.tooltip,
      child: FocusableActionDetector(
        enabled: _enabled,
        autofocus: widget.autofocus,
        focusNode: widget.focusNode,
        mouseCursor: _enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed?.call();
              return null;
            },
          ),
        },
        onShowFocusHighlight: (focused) {
          if (_focused != focused) {
            setState(() => _focused = focused);
          }
        },
        onShowHoverHighlight: (hovered) {
          if (_hovered != hovered) {
            setState(() => _hovered = hovered);
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
          onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
          onTapUp: _enabled
              ? (_) {
                  setState(() => _pressed = false);
                  widget.onPressed?.call();
                }
              : null,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: widget.minWidth,
              minHeight: widget.minHeight,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: palette.background,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: palette.border),
              ),
              child: Padding(
                padding:
                    widget.padding ??
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.icon != null)
                      Icon(widget.icon, size: 15, color: palette.foreground),
                    if (widget.icon != null && widget.label != null)
                      const SizedBox(width: 6),
                    if (widget.label != null)
                      Flexible(
                        child: Text(
                          widget.label!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textStyle,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.tooltip == null) {
      return content;
    }
    return Tooltip(message: widget.tooltip!, child: content);
  }
}

class _AgusButtonVisualState {
  const _AgusButtonVisualState({
    required this.enabled,
    required this.hovered,
    required this.pressed,
    required this.focused,
  });

  final bool enabled;
  final bool hovered;
  final bool pressed;
  final bool focused;
}

class _AgusButtonPalette {
  const _AgusButtonPalette({
    required this.background,
    required this.foreground,
    required this.border,
  });

  final Color background;
  final Color foreground;
  final Color border;

  static _AgusButtonPalette resolve(
    AgusColors colors,
    AgusButtonVariant variant,
    _AgusButtonVisualState state,
  ) {
    if (!state.enabled) {
      return _AgusButtonPalette(
        background: switch (variant) {
          AgusButtonVariant.primary => colors.focusBorder.withValues(
            alpha: 0.26,
          ),
          AgusButtonVariant.secondary => colors.inputBackground.withValues(
            alpha: 0.52,
          ),
          AgusButtonVariant.subtle ||
          AgusButtonVariant.toolbar => Colors.transparent,
        },
        foreground: colors.sideBarForeground.withValues(alpha: 0.42),
        border: Colors.transparent,
      );
    }

    final focusedBorder = state.focused
        ? colors.focusBorder
        : Colors.transparent;
    return switch (variant) {
      AgusButtonVariant.primary => _AgusButtonPalette(
        background: state.pressed
            ? colors.selectionBackground
            : state.hovered
            ? colors.focusBorder.withValues(alpha: 0.82)
            : colors.focusBorder.withValues(alpha: 0.72),
        foreground: Colors.white,
        border: state.focused ? focusedBorder : Colors.transparent,
      ),
      AgusButtonVariant.secondary => _AgusButtonPalette(
        background: state.pressed
            ? colors.selectionBackground
            : state.hovered
            ? colors.hoverBackground
            : colors.inputBackground,
        foreground: colors.sideBarForeground,
        border: state.focused ? focusedBorder : colors.inputBorder,
      ),
      AgusButtonVariant.subtle => _AgusButtonPalette(
        background: state.pressed
            ? colors.selectionBackground
            : state.hovered
            ? colors.hoverBackground
            : Colors.transparent,
        foreground: colors.sideBarForeground,
        border: focusedBorder,
      ),
      AgusButtonVariant.toolbar => _AgusButtonPalette(
        background: state.pressed
            ? colors.selectionBackground
            : state.hovered
            ? colors.hoverBackground
            : Colors.transparent,
        foreground: colors.sideBarForeground,
        border: focusedBorder,
      ),
    };
  }
}
