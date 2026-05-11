import 'package:agus_design/agus_design.dart';
import 'package:agus_maps_flutter/agus_maps_flutter.dart' as agus_maps_flutter;
import 'package:agus_maps_flutter_example/features/map/widgets/adaptive_layer_manager.dart';
import 'package:agus_maps_flutter_example/shared/adaptive/form_factor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers.dart';

void main() {
  testWidgets(
      'desktop layer manager separates controls and project layers views', (
    tester,
  ) async {
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
        mwmLayers: const [
          MwmLayerInfo(
            regionName: 'Gibraltar',
            snapshotVersion: '250608',
            fileSize: 2048,
            filePath: '/maps/Gibraltar.mwm',
            isBundled: false,
            isActive: true,
          ),
        ],
      ),
      size: const Size(420, 640),
    );

    expect(find.byType(AgusViewContainer), findsOneWidget);
    expect(find.text('Layer Manager'), findsOneWidget);  // Toolbar title (not uppercased)
    expect(find.text('PROJECT LAYERS'), findsOneWidget);  // View title (uppercased)
    expect(find.text('MWM MAPS'), findsOneWidget);  // View title (uppercased)
    expect(find.text('Layer store starting'), findsOneWidget);

    await tester.tap(find.text('PROJECT LAYERS'));
    await tester.pump();

    expect(find.text('Layer store starting'), findsNothing);

    expect(find.text('Gibraltar'), findsOneWidget);
    expect(find.text('250608'), findsWidgets);
  });

  testWidgets('desktop MWM layer rows expose context menu actions', (
    tester,
  ) async {
    String? visibilityRegion;
    bool? nextVisibility;
    MwmLayerInfo? focusedLayer;
    MwmLayerInfo? updatedLayer;
    MwmLayerOrderMode? orderMode;

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
        mwmLayers: const [
          MwmLayerInfo(
            regionName: 'Gibraltar',
            snapshotVersion: '250608',
            fileSize: 2048,
            filePath: '/maps/Gibraltar.mwm',
            isBundled: false,
            visible: true,
            isActive: true,
          ),
        ],
        onMwmLayerVisibilityChanged: (regionName, visible) {
          visibilityRegion = regionName;
          nextVisibility = visible;
        },
        onMwmLayerFocused: (layer) => focusedLayer = layer,
        onMwmLayerUpdated: (layer) => updatedLayer = layer,
        onMwmLayerOrderChanged: (mode) => orderMode = mode,
      ),
      size: const Size(420, 640),
    );

    final position = tester.getCenter(find.text('Gibraltar'));
    await tester.tapAt(position, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    expect(find.text('Hide Map Layer'), findsOneWidget);
    expect(find.text('Focus Map'), findsOneWidget);
    expect(find.text('Update from Mirror...'), findsOneWidget);
    expect(find.text('Delete Download'), findsOneWidget);
    expect(find.text('Order by Date'), findsOneWidget);

    await tester.tap(find.text('Hide Map Layer'));
    await tester.pumpAndSettle();

    expect(visibilityRegion, 'Gibraltar');
    expect(nextVisibility, isFalse);

    await tester.tapAt(position, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Focus Map'));
    await tester.pumpAndSettle();

    expect(focusedLayer?.regionName, 'Gibraltar');

    await tester.tapAt(position, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Update from Mirror...'));
    await tester.pumpAndSettle();

    expect(updatedLayer?.regionName, 'Gibraltar');

    await tester.tapAt(position, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Order by Date'));
    await tester.pumpAndSettle();

    expect(orderMode, MwmLayerOrderMode.byDate);
  });

  testWidgets('bundled MWM layer delete action is disabled', (tester) async {
    MwmLayerInfo? deletedLayer;

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
        mwmLayers: const [
          MwmLayerInfo(
            regionName: 'World',
            snapshotVersion: '250608',
            fileSize: 4096,
            filePath: '/maps/World.mwm',
            isBundled: true,
            isActive: true,
          ),
        ],
        onMwmLayerDeleted: (layer) => deletedLayer = layer,
      ),
      size: const Size(420, 640),
    );

    await tester.tapAt(
      tester.getCenter(find.text('World')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    expect(find.text('Delete Bundled Map'), findsOneWidget);
    expect(find.text('Bundled Map Always Visible'), findsOneWidget);
    await tester.tap(find.text('Delete Bundled Map'));
    await tester.pumpAndSettle();

    expect(deletedLayer, isNull);
  });
}
