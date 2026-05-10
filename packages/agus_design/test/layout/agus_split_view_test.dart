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

      expect(tester.getSize(find.byKey(firstKey)).width, 579);
    },
  );

  testWidgets(
    'split view separates horizontal panes by one pixel with a wider hitbox',
    (tester) async {
      const firstKey = Key('first-pane');
      const secondKey = Key('second-pane');

      await pumpAgusWidget(
        tester,
        const AgusSplitView(
          axis: Axis.horizontal,
          initialFirstExtent: 180,
          first: ColoredBox(key: firstKey, color: Colors.red),
          second: ColoredBox(key: secondKey, color: Colors.blue),
        ),
        size: const Size(700, 300),
      );

      final firstRight = tester.getTopRight(find.byKey(firstKey)).dx;
      final secondLeft = tester.getTopLeft(find.byKey(secondKey)).dx;
      final handleSize = tester.getSize(_resizeColumnHandle());
      final separatorSize = tester.getSize(
        _separatorLine(AgusColors.dark.editorGroupBorder),
      );

      expect(secondLeft - firstRight, 1);
      expect(separatorSize.width, 1);
      expect(separatorSize.height, 300);
      expect(handleSize.width, AgusDimensions.standard.resizeHandleThickness);
      expect(handleSize.height, 300);
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

    final handle = _resizeColumnHandle();
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

  testWidgets(
    'split view separates vertical panes by one pixel with a wider hitbox',
    (tester) async {
      const firstKey = Key('first-pane');
      const secondKey = Key('second-pane');

      await pumpAgusWidget(
        tester,
        const AgusSplitView(
          axis: Axis.vertical,
          initialFirstExtent: 180,
          minFirstExtent: 120,
          minSecondExtent: 120,
          first: ColoredBox(key: firstKey, color: Colors.red),
          second: ColoredBox(key: secondKey, color: Colors.blue),
        ),
        size: const Size(400, 500),
      );

      final firstBottom = tester.getBottomLeft(find.byKey(firstKey)).dy;
      final secondTop = tester.getTopLeft(find.byKey(secondKey)).dy;
      final handleSize = tester.getSize(_resizeRowHandle());
      final separatorSize = tester.getSize(
        _separatorLine(AgusColors.dark.editorGroupBorder),
      );

      expect(secondTop - firstBottom, 1);
      expect(separatorSize.width, 400);
      expect(separatorSize.height, 1);
      expect(handleSize.width, 400);
      expect(handleSize.height, AgusDimensions.standard.resizeHandleThickness);
    },
  );

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

    final handle = _resizeColumnHandle();
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
    expect(
      tester.getSize(_separatorLine(AgusColors.dark.focusBorder)).width,
      1,
    );

    await gesture.removePointer();
  });

  testWidgets('split view resizes from the hitbox outside the visible line', (
    tester,
  ) async {
    double? reportedExtent;
    const firstKey = Key('first-pane');

    await pumpAgusWidget(
      tester,
      AgusSplitView(
        axis: Axis.horizontal,
        initialFirstExtent: 180,
        onSizedExtentChanged: (extent) => reportedExtent = extent,
        first: const ColoredBox(key: firstKey, color: Colors.red),
        second: const ColoredBox(color: Colors.blue),
      ),
      size: const Size(700, 300),
    );

    final handleRect = tester.getRect(_resizeColumnHandle());
    final separatorRect = tester.getRect(
      _separatorLine(AgusColors.dark.editorGroupBorder),
    );
    final dragStart = Offset(handleRect.right - 0.5, handleRect.center.dy);

    expect(handleRect.width, greaterThan(separatorRect.width));
    expect(dragStart.dx, greaterThan(separatorRect.right));

    final gesture = await tester.startGesture(dragStart);
    await gesture.moveBy(const Offset(40, 0));
    await gesture.up();
    await tester.pump();

    expect(reportedExtent, greaterThan(180));
    expect(tester.getSize(find.byKey(firstKey)).width, greaterThan(180));
  });
}

Finder _resizeColumnHandle() {
  return find.byWidgetPredicate(
    (widget) =>
        widget is MouseRegion &&
        widget.cursor == SystemMouseCursors.resizeColumn,
  );
}

Finder _resizeRowHandle() {
  return find.byWidgetPredicate(
    (widget) =>
        widget is MouseRegion && widget.cursor == SystemMouseCursors.resizeRow,
  );
}

Finder _separatorLine(Color color) {
  return find.byWidgetPredicate(
    (widget) => widget is ColoredBox && widget.color == color,
  );
}
