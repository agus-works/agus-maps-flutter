import 'dart:ui' show Tristate;

import 'package:agus_design/agus_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  const tabs = [
    AgusPanelTab(id: 'problems', label: 'Problems', icon: Icons.error_outline),
    AgusPanelTab(id: 'output', label: 'Output', closable: true),
  ];

  testWidgets('panel tab bar renders selected, trailing, and close states', (
    tester,
  ) async {
    await pumpAgusWidget(
      tester,
      const AgusPanelTabBar(
        tabs: tabs,
        selectedId: 'output',
        trailing: [Icon(Icons.more_horiz)],
      ),
    );

    expect(find.text('PROBLEMS'), findsOneWidget);
    expect(find.text('OUTPUT'), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz), findsOneWidget);
    expect(find.byTooltip('Close Output'), findsOneWidget);
  });

  testWidgets('panel tab bar emits selection and close callbacks', (
    tester,
  ) async {
    String? selectedId;
    String? closedId;

    await pumpAgusWidget(
      tester,
      AgusPanelTabBar(
        tabs: tabs,
        selectedId: 'problems',
        onSelected: (id) => selectedId = id,
        onClose: (id) => closedId = id,
      ),
    );

    await tester.tap(find.text('OUTPUT'));
    await tester.tap(find.byTooltip('Close Output'));

    expect(selectedId, 'output');
    expect(closedId, 'output');
  });

  testWidgets('panel tab bar scrolls instead of overflowing in narrow widths', (
    tester,
  ) async {
    await pumpAgusWidget(
      tester,
      const SizedBox(
        width: 90,
        child: AgusPanelTabBar(
          tabs: [
            AgusPanelTab(id: 'problems', label: 'Problems'),
            AgusPanelTab(id: 'debug', label: 'Debug Console'),
          ],
          selectedId: 'problems',
          trailing: [Icon(Icons.close)],
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('PROBLEMS'), findsOneWidget);
  });

  testWidgets('panel tab button exposes selected semantics', (tester) async {
    await pumpAgusWidget(
      tester,
      const AgusPanelTabButton(
        tab: AgusPanelTab(id: 'debug', label: 'Debug Console'),
        selected: true,
      ),
    );

    final semantics = tester.getSemantics(find.text('DEBUG CONSOLE'));
    expect(semantics.flagsCollection.isSelected, Tristate.isTrue);
    expect(semantics.flagsCollection.isButton, isTrue);
  });
}
