import 'package:agus_design/agus_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  testWidgets('scope selector emits selected scope', (tester) async {
    AgusSettingScope? selectedScope;

    await pumpAgusWidget(
      tester,
      AgusSettingScopeSelector(
        selectedScope: AgusSettingScope.user,
        onSelected: (scope) => selectedScope = scope,
      ),
    );

    await tester.tap(find.text('Workspace'));

    expect(selectedScope, AgusSettingScope.workspace);
  });

  testWidgets('boolean setting control toggles values', (tester) async {
    Object? changedValue;

    await pumpAgusWidget(
      tester,
      AgusSettingControl(
        schema: testSettingSchemas[1],
        value: true,
        onChanged: (value) => changedValue = value,
      ),
    );

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(changedValue, false);
  });

  testWidgets('select setting control emits dropdown value', (tester) async {
    Object? changedValue;

    await pumpAgusWidget(
      tester,
      AgusSettingControl(
        schema: testSettingSchemas[0],
        value: 'left',
        onChanged: (value) => changedValue = value,
      ),
    );

    await tester.tap(find.text('Left'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Right').last);
    await tester.pumpAndSettle();

    expect(changedValue, 'right');
  });

  testWidgets(
    'number setting control clamps submitted values and ignores invalid input',
    (tester) async {
      Object? changedValue;

      await pumpAgusWidget(
        tester,
        AgusSettingControl(
          schema: testSettingSchemas[2],
          value: 13.0,
          onChanged: (value) => changedValue = value,
        ),
      );

      await tester.enterText(find.byType(TextFormField), '100');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(changedValue, 32.0);

      changedValue = null;
      await tester.enterText(find.byType(TextFormField), 'nope');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(changedValue, isNull);
    },
  );

  testWidgets('folder setting control renders browse button and submits text', (
    tester,
  ) async {
    Object? changedValue;

    await pumpAgusWidget(
      tester,
      AgusSettingControl(
        schema: testSettingSchemas[3],
        value: '',
        onChanged: (value) => changedValue = value,
      ),
      size: const Size(220, 200),
    );

    expect(find.text('Browse'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), '/tmp');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(changedValue, '/tmp');
  });

  testWidgets('json setting control shows JSON button', (tester) async {
    await pumpAgusWidget(
      tester,
      AgusSettingControl(
        schema: testSettingSchemas[4],
        value: '{}',
        onChanged: (_) {},
      ),
    );

    expect(find.text('Edit in JSON'), findsOneWidget);
  });

  testWidgets('setting row shows reset button only when modified', (
    tester,
  ) async {
    Object? changedValue;

    await pumpAgusWidget(
      tester,
      AgusSettingRow(
        schema: testSettingSchemas[2],
        value: 16.0,
        modified: true,
        onChanged: (value) => changedValue = value,
      ),
    );

    await tester.tap(find.text('Reset'));

    expect(changedValue, 13.0);
  });
}
