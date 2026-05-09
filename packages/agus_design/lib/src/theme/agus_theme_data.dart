import 'package:flutter/material.dart';

import 'agus_colors.dart';
import 'agus_dimensions.dart';

class AgusThemeData {
  const AgusThemeData({
    required this.colors,
    required this.dimensions,
    this.brightness = Brightness.dark,
  });

  factory AgusThemeData.dark() {
    return const AgusThemeData(
      colors: AgusColors.dark,
      dimensions: AgusDimensions.standard,
    );
  }

  factory AgusThemeData.light() {
    return const AgusThemeData(
      colors: AgusColors.light,
      dimensions: AgusDimensions.standard,
      brightness: Brightness.light,
    );
  }

  final AgusColors colors;
  final AgusDimensions dimensions;
  final Brightness brightness;

  ThemeData toThemeData() {
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: colors.statusBarBackground,
      onPrimary: colors.statusBarForeground,
      secondary: colors.focusBorder,
      onSecondary: colors.statusBarForeground,
      error: colors.errorBackground,
      onError: colors.statusBarForeground,
      surface: colors.sideBarBackground,
      onSurface: colors.editorForeground,
    );

    return ThemeData(
      platform: TargetPlatform.android,
      useMaterial3: false,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colors.workbenchBackground,
      canvasColor: colors.workbenchBackground,
      dividerColor: colors.editorGroupBorder,
      hoverColor: colors.hoverBackground,
      focusColor: colors.focusBorder.withValues(alpha: 0.24),
      highlightColor: colors.selectionBackground,
      splashFactory: NoSplash.splashFactory,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      iconTheme: IconThemeData(
        color: colors.sideBarForeground,
        size: dimensions.iconSize,
      ),
      textTheme: _textTheme(colors),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: colors.inputBackground,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(dimensions.borderRadius),
          borderSide: BorderSide(color: colors.inputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(dimensions.borderRadius),
          borderSide: BorderSide(color: colors.inputBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(dimensions.borderRadius),
          borderSide: BorderSide(color: colors.focusBorder),
        ),
      ),
      extensions: <ThemeExtension<dynamic>>[colors, dimensions],
    );
  }

  static AgusColors colorsOf(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AgusColors>() ??
        (theme.brightness == Brightness.light
            ? AgusColors.light
            : AgusColors.dark);
  }

  static AgusDimensions dimensionsOf(BuildContext context) {
    return Theme.of(context).extension<AgusDimensions>() ??
        AgusDimensions.standard;
  }

  static TextTheme _textTheme(AgusColors colors) {
    const fallback = <String>['Segoe UI', 'Helvetica Neue', 'Arial'];
    final base = TextStyle(
      color: colors.editorForeground,
      fontSize: 13,
      height: 1.2,
      letterSpacing: 0,
      fontFamilyFallback: fallback,
    );

    return TextTheme(
      bodySmall: base.copyWith(fontSize: 12),
      bodyMedium: base,
      bodyLarge: base.copyWith(fontSize: 14),
      labelSmall: base.copyWith(fontSize: 11),
      labelMedium: base.copyWith(fontSize: 12),
      labelLarge: base.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
      titleSmall: base.copyWith(fontSize: 12, fontWeight: FontWeight.w600),
      titleMedium: base.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
      titleLarge: base.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
    );
  }
}

class AgusTheme extends StatelessWidget {
  const AgusTheme({required this.data, required this.child, super.key});

  final AgusThemeData data;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Theme(data: data.toThemeData(), child: child);
  }
}
