import 'package:agus_design/agus_design.dart';
import 'package:agus_maps_flutter/agus_maps_flutter.dart' as agus_maps_flutter;
import 'package:agus_maps_flutter_example/settings_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  testWidgets('map scale setting clamps submitted values to schema min and max',
      (
    tester,
  ) async {
    final submittedScales = <double>[];

    await pumpExampleWidget(
      tester,
      _settingsTab(
        mapScale: 1,
        onMapScaleChanged: submittedScales.add,
      ),
    );

    await tester.tap(find.text('Map'));
    await tester.pumpAndSettle();
    expect(find.text('Map: Scale'), findsOneWidget);

    final scaleField = find.descendant(
      of: find.ancestor(
        of: find.text('Map: Scale'),
        matching: find.byType(AgusSettingRow),
      ),
      matching: find.byType(TextFormField),
    );

    await tester.enterText(scaleField, '99');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(submittedScales.last, 3.0);

    await tester.enterText(scaleField, '0.01');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(submittedScales.last, 0.25);
  });

  testWidgets('subway layer disables incompatible terrain layer states', (
    tester,
  ) async {
    agus_maps_flutter.MapLayerState? submittedLayerState;

    await pumpExampleWidget(
      tester,
      _settingsTab(
        layerState: const agus_maps_flutter.MapLayerState(
          outdoors: true,
          isolines: true,
          subway: false,
        ),
        onLayerStateChanged: (state) => submittedLayerState = state,
      ),
    );

    await tester.tap(find.text('Map Layers'));
    await tester.pumpAndSettle();

    final subwaySwitch = find.descendant(
      of: find.ancestor(
        of: find.text('Layers: Subway'),
        matching: find.byType(AgusSettingRow),
      ),
      matching: find.byType(Switch),
    );
    await tester.ensureVisible(subwaySwitch);
    await tester.pumpAndSettle();
    await tester.tap(subwaySwitch);
    await tester.pump();

    expect(submittedLayerState, isNotNull);
    expect(submittedLayerState!.subway, isTrue);
    expect(submittedLayerState!.outdoors, isFalse);
    expect(submittedLayerState!.isolines, isFalse);
  });

  testWidgets('navigation settings update immutable routing preferences', (
    tester,
  ) async {
    agus_maps_flutter.NavigationSettings? submittedNavigationSettings;

    await pumpExampleWidget(
      tester,
      _settingsTab(
        navigationSettings: const agus_maps_flutter.NavigationSettings(
          routingOptions: agus_maps_flutter.NavigationRoutingOptions(),
        ),
        onNavigationSettingsChanged: (settings) {
          submittedNavigationSettings = settings;
        },
      ),
    );

    await tester.tap(find.text('Routing'));
    await tester.pumpAndSettle();

    final tollsSwitch = find.descendant(
      of: find.ancestor(
        of: find.text('Route: Avoid Tolls'),
        matching: find.byType(AgusSettingRow),
      ),
      matching: find.byType(Switch),
    );
    await tester.ensureVisible(tollsSwitch);
    await tester.pumpAndSettle();
    await tester.tap(tollsSwitch);
    await tester.pump();

    expect(submittedNavigationSettings, isNotNull);
    expect(submittedNavigationSettings!.routingOptions.avoidTolls, isTrue);
    expect(submittedNavigationSettings!.routingOptions.avoidMotorways, isFalse);
    expect(submittedNavigationSettings!.routingOptions.avoidFerries, isFalse);
    expect(
      submittedNavigationSettings!.routingOptions.avoidUnpavedRoads,
      isFalse,
    );
  });
}

SettingsTab _settingsTab({
  double mapScale = 1,
  agus_maps_flutter.MapLayerState layerState =
      const agus_maps_flutter.MapLayerState(
    outdoors: false,
    isolines: false,
    subway: false,
  ),
  agus_maps_flutter.NavigationSettings navigationSettings =
      const agus_maps_flutter.NavigationSettings(),
  ValueChanged<double>? onMapScaleChanged,
  ValueChanged<agus_maps_flutter.MapLayerState>? onLayerStateChanged,
  ValueChanged<agus_maps_flutter.NavigationSettings>?
      onNavigationSettingsChanged,
}) {
  return SettingsTab(
    mapScale: mapScale,
    interfaceThemeMode: ThemeMode.system,
    mapAppearanceMode: agus_maps_flutter.MapAppearanceMode.system,
    mapLanguageCode: '',
    buildings3dEnabled: false,
    layerState: layerState,
    navigationSettings: navigationSettings,
    onMapScaleChanged: onMapScaleChanged ?? (_) {},
    onResetMapScale: () {},
    onInterfaceThemeModeChanged: (_) {},
    onMapAppearanceModeChanged: (_) {},
    onMapLanguageChanged: (_) {},
    onBuildings3dChanged: (_) {},
    onLayerStateChanged: onLayerStateChanged ?? (_) {},
    onNavigationSettingsChanged: onNavigationSettingsChanged ?? (_) {},
    onClearCachedData: () async {},
  );
}
