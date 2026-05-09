import 'package:flutter/material.dart';

import '../theme/agus_theme_data.dart';

class AgusEditorHost extends StatelessWidget {
  const AgusEditorHost({
    required this.child,
    this.label,
    this.showBorder = false,
    super.key,
  });

  final Widget child;
  final String? label;
  final bool showBorder;

  @override
  Widget build(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);

    return Semantics(
      label: label,
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.editorBackground,
          border: showBorder
              ? Border.all(color: colors.editorGroupBorder)
              : null,
        ),
        child: child,
      ),
    );
  }
}
