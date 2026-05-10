import 'package:agus_design/agus_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  testWidgets('input box accepts text and submit callbacks', (tester) async {
    final controller = TextEditingController();
    String? submitted;
    addTearDown(controller.dispose);

    await pumpAgusWidget(
      tester,
      Center(
        child: SizedBox(
          width: 260,
          child: AgusInputBox(
            controller: controller,
            placeholder: 'Layer name',
            onSubmitted: (value) => submitted = value,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Road edits');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(controller.text, 'Road edits');
    expect(submitted, 'Road edits');
  });

  testWidgets('search box clears text and reports an empty query', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'gibraltar');
    final changes = <String>[];
    var cleared = false;
    addTearDown(controller.dispose);

    await pumpAgusWidget(
      tester,
      Center(
        child: SizedBox(
          width: 260,
          child: AgusSearchBox(
            controller: controller,
            onChanged: changes.add,
            onCleared: () => cleared = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();

    expect(controller.text, isEmpty);
    expect(changes.last, isEmpty);
    expect(cleared, isTrue);
  });
}
