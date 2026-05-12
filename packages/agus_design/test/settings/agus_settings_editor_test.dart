import 'package:agus_design/agus_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  testWidgets('settings editor renders in a narrow host without overflow', (
    tester,
  ) async {
    await pumpAgusWidget(
      tester,
      const AgusSettingsEditor(schemas: testSettingSchemas),
      size: const Size(300, 420),
    );

    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Editor: Font Size'), findsOneWidget);
    expect(find.text('Category'), findsOneWidget);
  });

  testWidgets('settings editor shows category tree on wide layouts', (
    tester,
  ) async {
    await pumpAgusWidget(
      tester,
      const AgusSettingsEditor(schemas: testSettingSchemas),
      size: const Size(900, 600),
    );

    expect(find.text('Workbench'), findsOneWidget);
    expect(find.text('Editor'), findsOneWidget);
  });

  testWidgets('settings editor filters rows by search query', (tester) async {
    await pumpAgusWidget(
      tester,
      const AgusSettingsEditor(schemas: testSettingSchemas),
      size: const Size(900, 600),
    );

    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Search settings',
      ),
      'font',
    );
    await tester.pumpAndSettle();

    expect(find.text('Editor: Font Size'), findsOneWidget);
    expect(find.text('Workbench: Side Bar Location'), findsNothing);
  });

  testWidgets('settings search spans categories in wide mode', (tester) async {
    await pumpAgusWidget(
      tester,
      const AgusSettingsEditor(schemas: testSettingSchemas),
      size: const Size(900, 600),
    );

    await tester.tap(find.text('Workbench').first);
    await tester.pumpAndSettle();
    expect(find.text('Editor: Font Size'), findsNothing);

    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Search settings',
      ),
      'font',
    );
    await tester.pumpAndSettle();

    expect(find.text('Editor: Font Size'), findsOneWidget);
    expect(find.text('Workbench: Side Bar Location'), findsNothing);
  });

  testWidgets('settings editor allows selecting categories in wide mode', (
    tester,
  ) async {
    await pumpAgusWidget(
      tester,
      const AgusSettingsEditor(schemas: testSettingSchemas),
      size: const Size(900, 600),
    );

    await tester.tap(find.text('Workbench').first);
    await tester.pumpAndSettle();

    expect(find.text('Workbench: Side Bar Location'), findsOneWidget);
    expect(find.text('Editor: Font Size'), findsNothing);
  });

  testWidgets('settings editor propagates changed values and reset', (
    tester,
  ) async {
    final values = <String, Object?>{'agus.editor.fontSize': 16.0};
    final changes = <Object?>[];

    await pumpAgusWidget(
      tester,
      AgusSettingsEditor(
        schemas: testSettingSchemas,
        values: values,
        onChanged: (_, value) => changes.add(value),
      ),
      size: const Size(900, 600),
    );

    await tester.tap(find.text('Reset'));

    expect(changes, contains(13.0));
  });
}
