import 'package:agus_design/agus_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  testWidgets('property grid renders rows and trailing actions', (
    tester,
  ) async {
    await pumpAgusWidget(
      tester,
      const AgusPropertyGrid(
        rows: [
          AgusPropertyRow(
            name: 'Latitude',
            value: AgusPropertyText('36.1407000'),
          ),
          AgusPropertyRow(
            name: 'Visible',
            value: AgusPropertyText('On'),
            trailing: Icon(Icons.visibility),
          ),
        ],
      ),
    );

    expect(find.text('Latitude'), findsOneWidget);
    expect(find.text('36.1407000'), findsOneWidget);
    expect(find.byIcon(Icons.visibility), findsOneWidget);
  });

  testWidgets('property grid uses empty label when rows are empty', (
    tester,
  ) async {
    await pumpAgusWidget(
      tester,
      const AgusPropertyGrid(rows: [], emptyLabel: 'No feature selected.'),
    );

    expect(find.text('No feature selected.'), findsOneWidget);
  });

  testWidgets('property grid accepts zero-width labels and row boundaries', (
    tester,
  ) async {
    await pumpAgusWidget(
      tester,
      const AgusPropertyGrid(
        nameWidth: 0,
        rowHeight: 0,
        rows: [
          AgusPropertyRow(name: 'Name', value: AgusPropertyText('Gibraltar')),
        ],
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Gibraltar'), findsOneWidget);
  });

  test('property grid rejects negative dimensions', () {
    expect(
      () => AgusPropertyGrid(rows: const [], nameWidth: -1),
      throwsAssertionError,
    );
    expect(
      () => AgusPropertyGrid(rows: const [], rowHeight: -1),
      throwsAssertionError,
    );
  });
}
