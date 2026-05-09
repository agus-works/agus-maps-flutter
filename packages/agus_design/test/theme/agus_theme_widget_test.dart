import 'package:agus_design/agus_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  testWidgets(
    'AgusThemeData colorsOf falls back to light colors for light themes',
    (tester) async {
      late AgusColors resolvedColors;

      await pumpAgusWidget(
        tester,
        Builder(
          builder: (context) {
            resolvedColors = AgusThemeData.colorsOf(context);
            return const SizedBox.shrink();
          },
        ),
        theme: ThemeData.light(),
      );

      expect(resolvedColors, AgusColors.light);
    },
  );

  testWidgets(
    'AgusThemeData colorsOf falls back to dark colors for dark themes',
    (tester) async {
      late AgusColors resolvedColors;

      await pumpAgusWidget(
        tester,
        Builder(
          builder: (context) {
            resolvedColors = AgusThemeData.colorsOf(context);
            return const SizedBox.shrink();
          },
        ),
        theme: ThemeData.dark(),
      );

      expect(resolvedColors, AgusColors.dark);
    },
  );

  testWidgets('AgusTheme injects Agus light theme into descendants', (
    tester,
  ) async {
    late Color resolvedBackground;

    await tester.pumpWidget(
      AgusTheme(
        data: AgusThemeData.light(),
        child: Builder(
          builder: (context) {
            resolvedBackground = AgusThemeData.colorsOf(
              context,
            ).workbenchBackground;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(resolvedBackground, AgusColors.light.workbenchBackground);
  });
}
