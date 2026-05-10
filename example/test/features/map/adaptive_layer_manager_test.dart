import 'package:agus_design/agus_design.dart';
import 'package:agus_maps_flutter/agus_maps_flutter.dart' as agus_maps_flutter;
import 'package:agus_maps_flutter_example/features/map/widgets/adaptive_layer_manager.dart';
import 'package:agus_maps_flutter_example/shared/adaptive/form_factor.dart';
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
      ),
      size: const Size(420, 640),
    );

    expect(find.byType(AgusViewContainer), findsOneWidget);
    expect(find.text('LAYER MANAGER'), findsOneWidget);
    expect(find.text('PROJECT LAYERS'), findsOneWidget);
    expect(find.text('Layer store starting'), findsOneWidget);

    await tester.tap(find.text('PROJECT LAYERS'));
    await tester.pump();

    expect(find.text('Layer store starting'), findsNothing);
  });
}
