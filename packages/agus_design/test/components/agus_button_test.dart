import 'package:agus_design/agus_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  testWidgets('button invokes taps without material ink ripple', (
    tester,
  ) async {
    var presses = 0;

    await pumpAgusWidget(
      tester,
      Center(
        child: AgusButton(
          label: 'Run Command',
          icon: Icons.play_arrow,
          variant: AgusButtonVariant.primary,
          onPressed: () => presses++,
        ),
      ),
    );

    await tester.tap(find.text('Run Command'));
    await tester.pump();

    expect(presses, 1);
    expect(
      find.descendant(
        of: find.byType(AgusButton),
        matching: find.byType(InkWell),
      ),
      findsNothing,
    );
  });

  testWidgets('disabled button ignores taps and exposes semantics', (
    tester,
  ) async {
    var presses = 0;

    await pumpAgusWidget(
      tester,
      Center(
        child: AgusButton(
          label: 'Disabled Action',
          onPressed: null,
          tooltip: 'Cannot run now',
        ),
      ),
    );

    await tester.tap(find.text('Disabled Action'), warnIfMissed: false);
    await tester.pump();

    expect(presses, 0);
    expect(find.text('Disabled Action'), findsOneWidget);
  });
}
