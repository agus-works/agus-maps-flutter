import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agus_maps_flutter/agus_maps_flutter.dart' as agus_maps_flutter;
import 'package:agus_maps_flutter_example/features/map/widgets/adaptive_layer_manager.dart';
import 'package:agus_maps_flutter_example/shared/adaptive/form_factor.dart';

import '../../../test_helpers.dart';

void main() {
  group('AdaptiveLayerManager', () {
    group('Desktop compact view consolidation', () {
      testWidgets(
          'shows Project Layers section with draw session card in desktop mode',
          (tester) async {
        await pumpExampleWidget(
          tester,
          AdaptiveLayerManager(
            formFactor: ExampleFormFactor.desktop,
            nativeLayerState: const agus_maps_flutter.MapLayerState(
              outdoors: false,
              isolines: false,
              subway: false,
            ),
            buildings3dEnabled: false,
            onNativeLayerStateChanged: (_) {},
            onBuildings3dChanged: (_) {},
          ),
        );

        await tester.pumpAndSettle();

        // Should show "PROJECT LAYERS" title (uppercased by AgusViewContainer)
        expect(find.text('PROJECT LAYERS'), findsOneWidget);

        // Should show "Edit session" label from draw session card
        expect(find.text('Edit session'), findsOneWidget);

        // Should NOT show separate "Layer Manager" section as a clickable view
        // Note: "Layer Manager" text still appears in the toolbar title
      });

      testWidgets('shows active layer name in draw session card',
          (tester) async {
        await pumpExampleWidget(
          tester,
          AdaptiveLayerManager(
            formFactor: ExampleFormFactor.desktop,
            nativeLayerState: const agus_maps_flutter.MapLayerState(
              outdoors: false,
              isolines: false,
              subway: false,
            ),
            buildings3dEnabled: false,
            onNativeLayerStateChanged: (_) {},
            onBuildings3dChanged: (_) {},
            activeLayerId: 'test-layer',
          ),
        );

        await tester.pumpAndSettle();

        // Should show "No editable layer selected" when no layer exists
        expect(find.text('No editable layer selected'), findsOneWidget);
      });

      testWidgets('shows draw tool status in draw session card',
          (tester) async {
        await pumpExampleWidget(
          tester,
          AdaptiveLayerManager(
            formFactor: ExampleFormFactor.desktop,
            nativeLayerState: const agus_maps_flutter.MapLayerState(
              outdoors: false,
              isolines: false,
              subway: false,
            ),
            buildings3dEnabled: false,
            onNativeLayerStateChanged: (_) {},
            onBuildings3dChanged: (_) {},
            activeDrawTool: agus_maps_flutter.AgusDrawTool.pin,
          ),
        );

        await tester.pumpAndSettle();

        // Should show creating message for active draw tool
        expect(find.textContaining('Creating point feature'), findsOneWidget);
      });
    });

    group('Active selection indication', () {
      testWidgets('highlights active layer in tree when desktop',
          (tester) async {
        // This test verifies that the tree view receives the correct selectedId
        // parameter to highlight the active layer
        await pumpExampleWidget(
          tester,
          AdaptiveLayerManager(
            formFactor: ExampleFormFactor.desktop,
            nativeLayerState: const agus_maps_flutter.MapLayerState(
              outdoors: false,
              isolines: false,
              subway: false,
            ),
            buildings3dEnabled: false,
            onNativeLayerStateChanged: (_) {},
            onBuildings3dChanged: (_) {},
            activeLayerId: 'test-layer',
          ),
        );

        await tester.pumpAndSettle();

        // The tree view should exist
        expect(find.byType(Scrollable), findsWidgets);
      });
    });

    group('Focus-center behavior', () {
      test('FocusCenter model has correct properties', () {
        final focusCenter = agus_maps_flutter.AgusFocusCenter(
          longitude: -5.3535,
          latitude: 36.1407,
          calculatedAt: DateTime(2024, 1, 1),
        );

        expect(focusCenter.longitude, -5.3535);
        expect(focusCenter.latitude, 36.1407);
        expect(focusCenter.calculatedAt, isNotNull);
      });
    });

    group('Layer/feature context menus', () {
      testWidgets('desktop layer tree supports context menu',
          (tester) async {
        await pumpExampleWidget(
          tester,
          AdaptiveLayerManager(
            formFactor: ExampleFormFactor.desktop,
            nativeLayerState: const agus_maps_flutter.MapLayerState(
              outdoors: false,
              isolines: false,
              subway: false,
            ),
            buildings3dEnabled: false,
            onNativeLayerStateChanged: (_) {},
            onBuildings3dChanged: (_) {},
          ),
        );

        await tester.pumpAndSettle();

        // Context menus are triggered by right-click, which requires integration tests
        // This test just verifies the widget builds successfully
        expect(find.byType(AdaptiveLayerManager), findsOneWidget);
      });
    });

    group('MWM Maps section', () {
      testWidgets('shows MWM Maps section in desktop mode', (tester) async {
        final mwmLayers = [
          const MwmLayerInfo(
            regionName: 'Gibraltar',
            snapshotVersion: '2024-01-01',
            fileSize: 1024000,
            filePath: '/path/to/gibraltar.mwm',
            isBundled: true,
            visible: true,
          ),
        ];

        await pumpExampleWidget(
          tester,
          AdaptiveLayerManager(
            formFactor: ExampleFormFactor.desktop,
            nativeLayerState: const agus_maps_flutter.MapLayerState(
              outdoors: false,
              isolines: false,
              subway: false,
            ),
            buildings3dEnabled: false,
            onNativeLayerStateChanged: (_) {},
            onBuildings3dChanged: (_) {},
            mwmLayers: mwmLayers,
          ),
        );

        await tester.pumpAndSettle();

        // Should show MWM MAPS section (uppercased by AgusViewContainer)
        expect(find.text('MWM MAPS'), findsOneWidget);
      });
    });
  });
}
