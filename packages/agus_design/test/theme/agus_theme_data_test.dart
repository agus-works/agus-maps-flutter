import 'package:agus_design/agus_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Agus theme locks Material platform to Android', () {
    final theme = AgusThemeData.dark().toThemeData();

    expect(theme.platform, TargetPlatform.android);
    expect(theme.extension<AgusColors>(), isNotNull);
    expect(theme.extension<AgusDimensions>(), isNotNull);
  });

  test('Agus light theme exposes light brightness and token set', () {
    final theme = AgusThemeData.light().toThemeData();

    expect(theme.brightness, Brightness.light);
    expect(theme.extension<AgusColors>(), AgusColors.light);
    expect(theme.scaffoldBackgroundColor, AgusColors.light.workbenchBackground);
  });

  test('Agus colors copyWith and lerp preserve token access', () {
    final updated = AgusColors.dark.copyWith(
      titleBarBackground: Colors.purple,
      errorBackground: Colors.redAccent,
    );
    final lerped = AgusColors.dark.lerp(updated, 0.5);

    expect(updated.titleBarBackground, Colors.purple);
    expect(updated.errorBackground, Colors.redAccent);
    expect(
      lerped.titleBarBackground,
      isNot(AgusColors.dark.titleBarBackground),
    );
  });

  test('Agus dimensions copyWith and lerp update values', () {
    final updated = AgusDimensions.standard.copyWith(
      sideBarDefaultWidth: 360,
      resizeHandleThickness: 6,
    );
    final lerped = AgusDimensions.standard.lerp(updated, 0.5);

    expect(updated.sideBarDefaultWidth, 360);
    expect(updated.resizeHandleThickness, 6);
    expect(lerped.sideBarDefaultWidth, greaterThan(300));
  });
}
