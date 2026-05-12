import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/agus_theme_data.dart';

/// A responsive VS Code-style dialog surface with keyboard-first interactions.
class AgusDialog extends StatelessWidget {
  /// Creates a dialog with responsive sizing and Escape cancellation.
  const AgusDialog({
    this.title,
    this.titleIcon,
    required this.content,
    this.actions = const <Widget>[],
    this.minWidth = 320,
    this.maxWidth = 560,
    this.minHeight = 120,
    this.maxHeight = 640,
    super.key,
  });

  /// Optional title text.
  final String? title;

  /// Optional icon shown before the title.
  final IconData? titleIcon;

  /// Main content of the dialog.
  final Widget content;

  /// Action buttons shown at the bottom.
  final List<Widget> actions;

  /// Minimum dialog width.
  final double minWidth;

  /// Maximum dialog width.
  final double maxWidth;

  /// Minimum dialog height.
  final double minHeight;

  /// Maximum dialog height.
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);

    return Dialog(
      backgroundColor: colors.editorBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: colors.contrastBorder),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: minWidth,
          maxWidth: maxWidth,
          minHeight: minHeight,
          maxHeight: maxHeight,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) _buildTitle(context),
            Flexible(child: SingleChildScrollView(child: content)),
            if (actions.isNotEmpty) _buildActions(context),
          ],
        ),
      ),
    );
  }

  Widget _buildTitle(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.contrastBorder)),
      ),
      child: Row(
        children: [
          if (titleIcon != null) ...[
            Icon(titleIcon, size: 18, color: colors.foreground),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              title!,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: colors.foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.contrastBorder)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            actions[i],
          ],
        ],
      ),
    );
  }
}

/// A keyboard-first form field with submit/cancel shortcuts.
class AgusFormField extends StatefulWidget {
  /// Creates a form field with Enter submit and Escape cancel support.
  const AgusFormField({
    this.label,
    this.hint,
    this.initialValue,
    this.multiline = false,
    this.autofocus = false,
    this.onSubmit,
    this.onCancel,
    this.validator,
    super.key,
  });

  /// Optional label text above the field.
  final String? label;

  /// Placeholder hint text.
  final String? hint;

  /// Initial field value.
  final String? initialValue;

  /// Whether the field supports multiple lines.
  final bool multiline;

  /// Whether to focus the field on mount.
  final bool autofocus;

  /// Called when Enter is pressed (single-line) or Ctrl/Cmd+Enter (multiline).
  final ValueChanged<String>? onSubmit;

  /// Called when Escape is pressed.
  final VoidCallback? onCancel;

  /// Optional validator for the field value.
  final FormFieldValidator<String>? validator;

  @override
  State<AgusFormField> createState() => _AgusFormFieldState();
}

class _AgusFormFieldState extends State<AgusFormField> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colors.foreground,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
        ],
        Focus(
          onKeyEvent: _handleKeyEvent,
          child: TextFormField(
            controller: _controller,
            autofocus: widget.autofocus,
            maxLines: widget.multiline ? null : 1,
            minLines: widget.multiline ? 3 : 1,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.foreground),
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: TextStyle(color: colors.descriptionForeground),
              errorText: _errorText,
              filled: true,
              fillColor: colors.inputBackground,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(2),
                borderSide: BorderSide(color: colors.inputBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(2),
                borderSide: BorderSide(color: colors.inputBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(2),
                borderSide: BorderSide(color: colors.focusBorder, width: 1.5),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(2),
                borderSide: BorderSide(color: colors.errorForeground),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
            ),
          ),
        ),
      ],
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onCancel?.call();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter) {
      final isMultilineSubmit =
          widget.multiline &&
          (HardwareKeyboard.instance.isMetaPressed ||
              HardwareKeyboard.instance.isControlPressed);
      final isSingleLineSubmit = !widget.multiline;

      if (isMultilineSubmit || isSingleLineSubmit) {
        _handleSubmit();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  void _handleSubmit() {
    final value = _controller.text;
    final validator = widget.validator;

    if (validator != null) {
      final error = validator(value);
      if (error != null) {
        setState(() => _errorText = error);
        return;
      }
    }

    setState(() => _errorText = null);
    widget.onSubmit?.call(value);
  }
}

/// Shows an [AgusDialog] and returns the result.
Future<T?> showAgusDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: builder,
  );
}
