import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agus_design/agus_design.dart';

void main() {
  group('MapTelemetry', () {
    test('formats latitude correctly', () {
      final telemetry = MapTelemetry(
        zoom: 14,
        centerLat: 36.140734,
        centerLon: -5.353456,
        bearing: 45.0,
      );

      expect(telemetry.formattedLat, '36.140734°');
    });

    test('formats longitude correctly', () {
      final telemetry = MapTelemetry(
        zoom: 14,
        centerLat: 36.140734,
        centerLon: -5.353456,
        bearing: 45.0,
      );

      expect(telemetry.formattedLon, '-5.353456°');
    });

    test('formats zoom correctly', () {
      final telemetry = MapTelemetry(
        zoom: 14,
        centerLat: 36.140734,
        centerLon: -5.353456,
        bearing: 45.0,
      );

      expect(telemetry.formattedZoom, 'z14');
    });

    test('formats bearing correctly', () {
      final telemetry = MapTelemetry(
        zoom: 14,
        centerLat: 36.140734,
        centerLon: -5.353456,
        bearing: 45.5,
      );

      expect(telemetry.formattedBearing, '45.5°');
    });

    test('normalizes bearing to 0-360 range', () {
      final telemetry = MapTelemetry(
        zoom: 14,
        centerLat: 36.140734,
        centerLon: -5.353456,
        bearing: 370.0,
      );

      expect(telemetry.formattedBearing, '10.0°');
    });

    test('formats center for clipboard', () {
      final telemetry = MapTelemetry(
        zoom: 14,
        centerLat: 36.140734,
        centerLon: -5.353456,
        bearing: 45.0,
      );

      expect(telemetry.centerForClipboard, '36.140734, -5.353456');
    });

    test('formats selected point when available', () {
      final telemetry = MapTelemetry(
        zoom: 14,
        centerLat: 36.140734,
        centerLon: -5.353456,
        bearing: 45.0,
        selectedPointLat: 36.5,
        selectedPointLon: -5.5,
      );

      expect(telemetry.formattedSelectedPoint, '36.500000°, -5.500000°');
      expect(telemetry.selectedPointForClipboard, '36.500000, -5.500000');
    });

    test('returns null for selected point when not available', () {
      final telemetry = MapTelemetry(
        zoom: 14,
        centerLat: 36.140734,
        centerLon: -5.353456,
        bearing: 45.0,
      );

      expect(telemetry.formattedSelectedPoint, isNull);
      expect(telemetry.selectedPointForClipboard, isNull);
    });
  });

  group('MapTelemetryStatusBarBuilder', () {
    testWidgets('builds zoom item with copy support', (tester) async {
      final telemetry = MapTelemetry(
        zoom: 14,
        centerLat: 36.140734,
        centerLon: -5.353456,
        bearing: 45.0,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final items = MapTelemetryStatusBarBuilder.buildItems(
                  context: context,
                  telemetry: telemetry,
                );

                // Verify zoom item
                final zoomItem = items.firstWhere(
                  (item) => item.id == 'map-zoom',
                );
                expect(zoomItem.label, 'z14');
                expect(zoomItem.icon, Icons.zoom_out_map);
                expect(zoomItem.copyValue, '14');
                expect(zoomItem.tooltip, contains('Zoom level: 14'));
                expect(zoomItem.onDoubleTap, isNotNull);
                expect(zoomItem.onLongPress, isNotNull);

                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
    });

    testWidgets('builds bearing item with copy support', (tester) async {
      final telemetry = MapTelemetry(
        zoom: 14,
        centerLat: 36.140734,
        centerLon: -5.353456,
        bearing: 45.5,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final items = MapTelemetryStatusBarBuilder.buildItems(
                  context: context,
                  telemetry: telemetry,
                );

                // Verify bearing item
                final bearingItem = items.firstWhere(
                  (item) => item.id == 'map-bearing',
                );
                expect(bearingItem.label, '45.5°');
                expect(bearingItem.icon, Icons.explore);
                expect(bearingItem.copyValue, '45.5');
                expect(bearingItem.tooltip, contains('Bearing: 45.5°'));
                expect(bearingItem.onDoubleTap, isNotNull);
                expect(bearingItem.onLongPress, isNotNull);

                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
    });

    testWidgets('builds center item with copy support', (tester) async {
      final telemetry = MapTelemetry(
        zoom: 14,
        centerLat: 36.140734,
        centerLon: -5.353456,
        bearing: 45.0,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final items = MapTelemetryStatusBarBuilder.buildItems(
                  context: context,
                  telemetry: telemetry,
                );

                // Verify center item
                final centerItem = items.firstWhere(
                  (item) => item.id == 'map-center',
                );
                expect(centerItem.label, '36.140734°, -5.353456°');
                expect(centerItem.icon, Icons.my_location);
                expect(centerItem.copyValue, '36.140734, -5.353456');
                expect(
                  centerItem.tooltip,
                  contains('Center: 36.140734, -5.353456'),
                );
                expect(centerItem.onDoubleTap, isNotNull);
                expect(centerItem.onLongPress, isNotNull);

                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
    });

    testWidgets('builds selected point item when available', (tester) async {
      final telemetry = MapTelemetry(
        zoom: 14,
        centerLat: 36.140734,
        centerLon: -5.353456,
        bearing: 45.0,
        selectedPointLat: 36.5,
        selectedPointLon: -5.5,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final items = MapTelemetryStatusBarBuilder.buildItems(
                  context: context,
                  telemetry: telemetry,
                );

                // Verify selected point item exists
                final selectedItem = items.firstWhere(
                  (item) => item.id == 'map-selected-point',
                );
                expect(selectedItem.label, '36.500000°, -5.500000°');
                expect(selectedItem.icon, Icons.place);
                expect(selectedItem.copyValue, '36.500000, -5.500000');
                expect(
                  selectedItem.tooltip,
                  contains('Selected: 36.500000, -5.500000'),
                );
                expect(selectedItem.onDoubleTap, isNotNull);
                expect(selectedItem.onLongPress, isNotNull);

                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
    });

    testWidgets('does not build selected point item when not available', (
      tester,
    ) async {
      final telemetry = MapTelemetry(
        zoom: 14,
        centerLat: 36.140734,
        centerLon: -5.353456,
        bearing: 45.0,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final items = MapTelemetryStatusBarBuilder.buildItems(
                  context: context,
                  telemetry: telemetry,
                );

                // Verify selected point item does not exist
                final hasSelectedItem = items.any(
                  (item) => item.id == 'map-selected-point',
                );
                expect(hasSelectedItem, isFalse);

                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
    });

    testWidgets('builds 3 items without selected point', (tester) async {
      final telemetry = MapTelemetry(
        zoom: 14,
        centerLat: 36.140734,
        centerLon: -5.353456,
        bearing: 45.0,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final items = MapTelemetryStatusBarBuilder.buildItems(
                  context: context,
                  telemetry: telemetry,
                );

                // Should have zoom, bearing, and center (3 items)
                expect(items.length, 3);

                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
    });

    testWidgets('builds 4 items with selected point', (tester) async {
      final telemetry = MapTelemetry(
        zoom: 14,
        centerLat: 36.140734,
        centerLon: -5.353456,
        bearing: 45.0,
        selectedPointLat: 36.5,
        selectedPointLon: -5.5,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final items = MapTelemetryStatusBarBuilder.buildItems(
                  context: context,
                  telemetry: telemetry,
                );

                // Should have zoom, bearing, center, and selected point (4 items)
                expect(items.length, 4);

                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
    });
  });
}
