import 'package:flutter/material.dart';

import '../theme/agus_theme_data.dart';
import 'agus_button.dart';

class AgusInputBox extends StatefulWidget {
  const AgusInputBox({
    this.controller,
    this.focusNode,
    this.placeholder,
    this.leading,
    this.trailing,
    this.enabled = true,
    this.autofocus = false,
    this.obscureText = false,
    this.textInputAction,
    this.onTap,
    this.onChanged,
    this.onSubmitted,
    super.key,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? placeholder;
  final Widget? leading;
  final Widget? trailing;
  final bool enabled;
  final bool autofocus;
  final bool obscureText;
  final TextInputAction? textInputAction;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<AgusInputBox> createState() => _AgusInputBoxState();
}

class _AgusInputBoxState extends State<AgusInputBox> {
  FocusNode? _internalFocusNode;

  FocusNode get _focusNode =>
      widget.focusNode ?? (_internalFocusNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant AgusInputBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode == widget.focusNode) {
      return;
    }
    (oldWidget.focusNode ?? _internalFocusNode)?.removeListener(
      _handleFocusChanged,
    );
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    _internalFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);
    final foreground = widget.enabled
        ? colors.inputForeground
        : colors.inputForeground.withValues(alpha: 0.42);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: widget.enabled
            ? colors.inputBackground
            : colors.inputBackground.withValues(alpha: 0.56),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: _focusNode.hasFocus ? colors.focusBorder : colors.inputBorder,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7),
        child: Row(
          children: [
            if (widget.leading != null) ...[
              IconTheme(
                data: IconThemeData(
                  size: 14,
                  color: foreground.withValues(alpha: 0.72),
                ),
                child: widget.leading!,
              ),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: _focusNode,
                enabled: widget.enabled,
                autofocus: widget.autofocus,
                obscureText: widget.obscureText,
                textInputAction: widget.textInputAction,
                onTap: widget.onTap,
                onChanged: widget.onChanged,
                onSubmitted: widget.onSubmitted,
                cursorColor: colors.inputForeground,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  isDense: true,
                  filled: false,
                  hintText: widget.placeholder,
                  hintStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: foreground.withValues(alpha: 0.52),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 5),
                ),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: foreground),
              ),
            ),
            if (widget.trailing != null) ...[
              const SizedBox(width: 6),
              widget.trailing!,
            ],
          ],
        ),
      ),
    );
  }

  void _handleFocusChanged() {
    if (mounted) {
      setState(() {});
    }
  }
}

class AgusSearchBox extends StatefulWidget {
  const AgusSearchBox({
    this.controller,
    this.focusNode,
    this.placeholder = 'Search',
    this.enabled = true,
    this.autofocus = false,
    this.onTap,
    this.onChanged,
    this.onSubmitted,
    this.onCleared,
    super.key,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String placeholder;
  final bool enabled;
  final bool autofocus;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onCleared;

  @override
  State<AgusSearchBox> createState() => _AgusSearchBoxState();
}

class _AgusSearchBoxState extends State<AgusSearchBox> {
  TextEditingController? _internalController;

  TextEditingController get _controller =>
      widget.controller ??
      (_internalController ??= TextEditingController()
        ..addListener(_handleTextChanged));

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_handleTextChanged);
  }

  @override
  void didUpdateWidget(covariant AgusSearchBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) {
      return;
    }
    oldWidget.controller?.removeListener(_handleTextChanged);
    widget.controller?.addListener(_handleTextChanged);
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_handleTextChanged);
    _internalController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AgusInputBox(
      controller: _controller,
      focusNode: widget.focusNode,
      placeholder: widget.placeholder,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      leading: const Icon(Icons.search),
      trailing: _controller.text.isEmpty
          ? null
          : AgusButton.icon(
              icon: Icons.close,
              tooltip: 'Clear search',
              onPressed: widget.enabled ? _clear : null,
            ),
      textInputAction: TextInputAction.search,
      onTap: widget.onTap,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
    );
  }

  void _clear() {
    _controller.clear();
    widget.onChanged?.call('');
    widget.onCleared?.call();
  }

  void _handleTextChanged() {
    if (mounted) {
      setState(() {});
    }
  }
}
