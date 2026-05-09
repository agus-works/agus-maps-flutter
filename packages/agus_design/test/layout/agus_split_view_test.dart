import 'dart:ui';

import 'package:agus_design/agus_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  testWidgets(
    'split view lays out horizontal panes with the requested extent',
    (tester) async {
      const firstKey = Key('first-pane');

      await pumpAgusWidget(
        tester,
        const AgusSplitView(
          axis: Axis.horizontal,
          initialFirstExtent: 180,
          first: ColoredBox(key: firstKey, color: Colors.red),
          second: ColoredBox(color: Colors.blue),
        ),
        size: const Size(700, 300),
      );

      expect(tester.getSize(find.byKey(firstKey)).width, 180);
    },
  );

  testWidgets(
    'split view clamps horizontal panes to the maximum allowed extent',
    (tester) async {
      const firstKey = Key('first-pane');

      await pumpAgusWidget(
        tester,
        const AgusSplitView(
          axis: Axis.horizontal,
          initialFirstExtent: 650,
          minFirstExtent: 120,
          minSecondExtent: 120,
          first: ColoredBox(key: firstKey, color: Colors.red),
          second: ColoredBox(color: Colors.blue),
        ),
        size: const Size(700, 300),
      );

      expect(tester.getSize(find.byKey(firstKey)).width, 572);
    },
  );

  testWidgets('split view can size and resize the second horizontal pane', (
    tester,
  ) async {
    double? reportedExtent;
    const secondKey = Key('second-pane');

    await pumpAgusWidget(
      tester,
      AgusSplitView(
        axis: Axis.horizontal,
        sizedPane: AgusSplitViewPane.second,
        initialFirstExtent: 180,
        minFirstExtent: 120,
        minSecondExtent: 120,
        onSizedExtentChanged: (extent) => reportedExtent = extent,
        first: const ColoredBox(color: Colors.red),
        second: const ColoredBox(key: secondKey, color: Colors.blue),
      ),
      size: const Size(700, 300),
    );

    expect(tester.getSize(find.byKey(secondKey)).width, 180);

    final handle = find.byWidgetPredicate(
      (widget) =>
          widget is MouseRegion &&
          widget.cursor == SystemMouseCursors.resizeColumn,
    );
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(-40, 0));
    await gesture.up();
    await tester.pump();

    expect(reportedExtent, greaterThan(180));
    expect(tester.getSize(find.byKey(secondKey)).width, greaterThan(180));
  });

  testWidgets('split view lays out vertical panes with the requested extent', (
    tester,
  ) async {
    const firstKey = Key('first-pane');

    await pumpAgusWidget(
      tester,
      const AgusSplitView(
        axis: Axis.vertical,
        initialFirstExtent: 180,
        minFirstExtent: 120,
        minSecondExtent: 120,
        first: ColoredBox(key: firstKey, color: Colors.red),
        second: ColoredBox(color: Colors.blue),
      ),
      size: const Size(400, 500),
    );

    expect(tester.getSize(find.byKey(firstKey)).height, 180);
  });

  testWidgets('split view clamps vertical panes to minimum extent', (
    tester,
  ) async {
    const firstKey = Key('first-pane');

    await pumpAgusWidget(
      tester,
      const AgusSplitView(
        axis: Axis.vertical,
        initialFirstExtent: 40,
        minFirstExtent: 120,
        minSecondExtent: 120,
        first: ColoredBox(key: firstKey, color: Colors.red),
        second: ColoredBox(color: Colors.blue),
      ),
      size: const Size(400, 500),
    );

    expect(tester.getSize(find.byKey(firstKey)).height, 120);
  });

  testWidgets('split view handle shows focus color on mouse hover', (
    tester,
  ) async {
    await pumpAgusWidget(
      tester,
      const AgusSplitView(
        axis: Axis.horizontal,
        initialFirstExtent: 180,
        first: ColoredBox(color: Colors.red),
        second: ColoredBox(color: Colors.blue),
      ),
      size: const Size(700, 300),
    );

    final handle = find.byWidgetPredicate(
      (widget) =>
          widget is MouseRegion &&
          widget.cursor == SystemMouseCursors.resizeColumn,
    );
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: tester.getCenter(handle));
    await tester.pump();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is ColoredBox && widget.color == AgusColors.dark.focusBorder,
      ),
      findsOneWidget,
    );

    await gesture.removePointer();
  });
}
