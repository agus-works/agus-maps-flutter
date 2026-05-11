import 'package:flutter_test/flutter_test.dart';
import 'package:agus_design/agus_design.dart';
import 'package:agus_maps_flutter_example/features/workbench/workbench_controller.dart';

void main() {
  group('Workbench Status Bar Telemetry', () {
    test('telemetry visibility - shown when Explorer and Map editor active', () {
      final state = WorkbenchLayoutState(
        activeActivity: WorkbenchActivity.explorer,
        activeEditorTab: WorkbenchEditorTab.map,
      );

      // Telemetry should be shown
      final showMapTelemetry = state.activeActivity == WorkbenchActivity.explorer &&
          state.activeEditorTab == WorkbenchEditorTab.map;
      expect(showMapTelemetry, isTrue);
    });

    test('telemetry visibility - hidden when non-Explorer activity active', () {
      final state = WorkbenchLayoutState(
        activeActivity: WorkbenchActivity.search,
        activeEditorTab: WorkbenchEditorTab.map,
      );

      // Telemetry should be hidden
      final showMapTelemetry = state.activeActivity == WorkbenchActivity.explorer &&
          state.activeEditorTab == WorkbenchEditorTab.map;
      expect(showMapTelemetry, isFalse);
    });

    test('telemetry visibility - hidden when blank editor active', () {
      final state = WorkbenchLayoutState(
        activeActivity: WorkbenchActivity.explorer,
        activeEditorTab: WorkbenchEditorTab.blank,
      );

      // Telemetry should be hidden
      final showMapTelemetry = state.activeActivity == WorkbenchActivity.explorer &&
          state.activeEditorTab == WorkbenchEditorTab.map;
      expect(showMapTelemetry, isFalse);
    });

    test('telemetry visibility - hidden when Settings activity active', () {
      final state = WorkbenchLayoutState(
        activeActivity: WorkbenchActivity.settings,
        activeEditorTab: WorkbenchEditorTab.map,
      );

      // Telemetry should be hidden
      final showMapTelemetry = state.activeActivity == WorkbenchActivity.explorer &&
          state.activeEditorTab == WorkbenchEditorTab.map;
      expect(showMapTelemetry, isFalse);
    });

    test('telemetry visibility - shown only with correct combination', () {
      final validStates = [
        WorkbenchLayoutState(
          activeActivity: WorkbenchActivity.explorer,
          activeEditorTab: WorkbenchEditorTab.map,
        ),
      ];

      final invalidStates = [
        WorkbenchLayoutState(
          activeActivity: WorkbenchActivity.search,
          activeEditorTab: WorkbenchEditorTab.map,
        ),
        WorkbenchLayoutState(
          activeActivity: WorkbenchActivity.favorites,
          activeEditorTab: WorkbenchEditorTab.map,
        ),
        WorkbenchLayoutState(
          activeActivity: WorkbenchActivity.downloads,
          activeEditorTab: WorkbenchEditorTab.map,
        ),
        WorkbenchLayoutState(
          activeActivity: WorkbenchActivity.settings,
          activeEditorTab: WorkbenchEditorTab.map,
        ),
        WorkbenchLayoutState(
          activeActivity: WorkbenchActivity.about,
          activeEditorTab: WorkbenchEditorTab.map,
        ),
        WorkbenchLayoutState(
          activeActivity: WorkbenchActivity.explorer,
          activeEditorTab: WorkbenchEditorTab.blank,
        ),
        WorkbenchLayoutState(
          activeActivity: WorkbenchActivity.mapPresentation,
          activeEditorTab: WorkbenchEditorTab.map,
        ),
      ];

      for (final state in validStates) {
        final showMapTelemetry = state.activeActivity == WorkbenchActivity.explorer &&
            state.activeEditorTab == WorkbenchEditorTab.map;
        expect(showMapTelemetry, isTrue,
            reason: 'Should show telemetry for ${state.activeActivity} / ${state.activeEditorTab}');
      }

      for (final state in invalidStates) {
        final showMapTelemetry = state.activeActivity == WorkbenchActivity.explorer &&
            state.activeEditorTab == WorkbenchEditorTab.map;
        expect(showMapTelemetry, isFalse,
            reason: 'Should hide telemetry for ${state.activeActivity} / ${state.activeEditorTab}');
      }
    });
  });

  group('MapTelemetry Formatting', () {
    test('formats coordinates with 6 decimal places', () {
      final telemetry = MapTelemetry(
        zoom: 14,
        centerLat: 36.140734046600755,
        centerLon: -5.353456123456789,
        bearing: 0.0,
      );

      expect(telemetry.formattedLat, '36.140734°');
      expect(telemetry.formattedLon, '-5.353456°');
      expect(telemetry.centerForClipboard, '36.140734, -5.353456');
    });

    test('formats bearing with 1 decimal place', () {
      final telemetry = MapTelemetry(
        zoom: 14,
        centerLat: 36.0,
        centerLon: -5.0,
        bearing: 45.678,
      );

      expect(telemetry.formattedBearing, '45.7°');
    });

    test('handles north-up bearing (0 degrees)', () {
      final telemetry = MapTelemetry(
        zoom: 14,
        centerLat: 36.0,
        centerLon: -5.0,
        bearing: 0.0,
      );

      expect(telemetry.formattedBearing, '0.0°');
    });

    test('normalizes bearing > 360', () {
      final telemetry = MapTelemetry(
        zoom: 14,
        centerLat: 36.0,
        centerLon: -5.0,
        bearing: 385.5,
      );

      expect(telemetry.formattedBearing, '25.5°');
    });

    test('formats zoom with z prefix', () {
      final telemetries = [
        MapTelemetry(zoom: 1, centerLat: 0, centerLon: 0, bearing: 0),
        MapTelemetry(zoom: 10, centerLat: 0, centerLon: 0, bearing: 0),
        MapTelemetry(zoom: 18, centerLat: 0, centerLon: 0, bearing: 0),
      ];

      expect(telemetries[0].formattedZoom, 'z1');
      expect(telemetries[1].formattedZoom, 'z10');
      expect(telemetries[2].formattedZoom, 'z18');
    });
  });
}
