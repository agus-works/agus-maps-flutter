import 'package:agus_design/agus_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  testWidgets('editor host applies semantics label', (tester) async {
    await pumpAgusWidget(
      tester,
      const AgusEditorHost(label: 'Preview host', child: Text('Editor')),
    );

    final semanticsWidget = tester.widget<Semantics>(
      find.descendant(
        of: find.byType(AgusEditorHost),
        matching: find.byType(Semantics),
      ),
    );

    expect(semanticsWidget.properties.label, 'Preview host');
  });

  testWidgets('editor host toggles border decoration', (tester) async {
    await pumpAgusWidget(
      tester,
      const AgusEditorHost(showBorder: true, child: Text('Editor')),
    );

    final decoratedBox = tester.widget<DecoratedBox>(find.byType(DecoratedBox));
    final decoration = decoratedBox.decoration as BoxDecoration;

    expect(decoration.border, isNotNull);
  });
}
