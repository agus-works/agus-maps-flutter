// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:widgetbook/widgetbook.dart';

import 'package:agus_design_widgetbook/main.dart';

void main() {
  testWidgets(
    'Widgetbook app loads with Windows target platform',
    (WidgetTester tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      await tester.pumpWidget(const AgusDesignWidgetbookApp());

      expect(find.byType(Widgetbook), findsOneWidget);
    },
  );
}
