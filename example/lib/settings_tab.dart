import 'package:agus_design/agus_design.dart';
import 'package:agus_maps_flutter/agus_maps_flutter.dart' as agus_maps_flutter;
import 'package:flutter/material.dart';

/// Example settings rendered with the Agus design-system settings editor.
class SettingsTab extends StatelessWidget {
  /// Creates the settings tab.
  const SettingsTab({
    super.key,
    required this.mapScale,
    required this.interfaceThemeMode,
    required this.mapAppearanceMode,
    required this.mapLanguageCode,
    required this.buildings3dEnabled,
    required this.layerState,
    required this.navigationSettings,
    required this.onMapScaleChanged,
    required this.onResetMapScale,
    required this.onInterfaceThemeModeChanged,
    required this.onMapAppearanceModeChanged,
    required this.onMapLanguageChanged,
    required this.onBuildings3dChanged,
    required this.onLayerStateChanged,
    required this.onNavigationSettingsChanged,
    required this.onClearCachedData,
  });

  /// Current map UI scale.
  final double mapScale;

  /// Current app theme mode.
  final ThemeMode interfaceThemeMode;

  /// Current native map appearance mode.
  final agus_maps_flutter.MapAppearanceMode mapAppearanceMode;

  /// Current native map language code.
  final String mapLanguageCode;

  /// Whether 3D buildings are enabled.
  final bool buildings3dEnabled;

  /// Current native layer visibility state.
  final agus_maps_flutter.MapLayerState layerState;

  /// Current native navigation settings.
  final agus_maps_flutter.NavigationSettings navigationSettings;

  /// Called when map scale changes.
  final ValueChanged<double> onMapScaleChanged;

  /// Called when map scale should reset.
  final VoidCallback onResetMapScale;

  /// Called when app theme mode changes.
  final ValueChanged<ThemeMode> onInterfaceThemeModeChanged;

  /// Called when native map appearance changes.
  final ValueChanged<agus_maps_flutter.MapAppearanceMode>
      onMapAppearanceModeChanged;

  /// Called when native map language changes.
  final ValueChanged<String> onMapLanguageChanged;

  /// Called when 3D buildings change.
  final ValueChanged<bool> onBuildings3dChanged;

  /// Called when native map layer state changes.
  final ValueChanged<agus_maps_flutter.MapLayerState> onLayerStateChanged;

  /// Called when navigation settings change.
  final ValueChanged<agus_maps_flutter.NavigationSettings>
      onNavigationSettingsChanged;

  /// Clears cached example app data.
  final Future<void> Function() onClearCachedData;

  static const double _minScale = 0.25;
  static const double _maxScale = 3.0;

  @override
  Widget build(BuildContext context) {
    return AgusPane(
      title: 'Settings',
      subtitle: 'Interface, map, layer, and navigation configuration',
      actions: [
        IconButton(
          tooltip: 'Reset map scale',
          onPressed: onResetMapScale,
          icon: const Icon(Icons.restart_alt),
        ),
        IconButton(
          tooltip: 'Clear cached data',
          onPressed: () => onClearCachedData(),
          icon: const Icon(Icons.delete_sweep_outlined),
        ),
      ],
      child: AgusSettingsEditor(
        schemas: _schemas,
        values: _values,
        onChanged: _handleChanged,
      ),
    );
  }

  Map<String, Object?> get _values {
    return {
      _SettingsId.mapScale: mapScale,
      _SettingsId.interfaceTheme: interfaceThemeMode.name,
      _SettingsId.mapAppearance: mapAppearanceMode.name,
      _SettingsId.mapLanguage: mapLanguageCode,
      _SettingsId.buildings3d: buildings3dEnabled,
      _SettingsId.layerOutdoors: layerState.outdoors,
      _SettingsId.layerIsolines: layerState.isolines,
      _SettingsId.layerSubway: layerState.subway,
      _SettingsId.navigationUnits: navigationSettings.measurementUnits.name,
      _SettingsId.navigationVoice: navigationSettings.turnNotificationsEnabled,
      _SettingsId.navigationStreetNames: navigationSettings.announceStreetNames,
      _SettingsId.navigationSpeedLimit: navigationSettings.showSpeedLimit,
      _SettingsId.navigationSpeedCameras:
          navigationSettings.speedCameraMode.name,
      _SettingsId.routeAvoidTolls: navigationSettings.routingOptions.avoidTolls,
      _SettingsId.routeAvoidMotorways:
          navigationSettings.routingOptions.avoidMotorways,
      _SettingsId.routeAvoidFerries:
          navigationSettings.routingOptions.avoidFerries,
      _SettingsId.routeAvoidUnpaved:
          navigationSettings.routingOptions.avoidUnpavedRoads,
    };
  }

  void _handleChanged(String id, Object? value) {
    switch (id) {
      case _SettingsId.mapScale:
        final next = _number(value, fallback: mapScale)
            .clamp(_minScale, _maxScale)
            .toDouble();
        onMapScaleChanged(next);
      case _SettingsId.interfaceTheme:
        onInterfaceThemeModeChanged(_themeMode(value));
      case _SettingsId.mapAppearance:
        onMapAppearanceModeChanged(_mapAppearanceMode(value));
      case _SettingsId.mapLanguage:
        onMapLanguageChanged(value?.toString() ?? '');
      case _SettingsId.buildings3d:
        onBuildings3dChanged(value == true);
      case _SettingsId.layerOutdoors:
        final enabled = value == true;
        onLayerStateChanged(
          layerState.copyWith(
            outdoors: enabled,
            subway: enabled ? false : layerState.subway,
          ),
        );
      case _SettingsId.layerIsolines:
        final enabled = value == true;
        onLayerStateChanged(
          layerState.copyWith(
            isolines: enabled,
            subway: enabled ? false : layerState.subway,
          ),
        );
      case _SettingsId.layerSubway:
        final enabled = value == true;
        onLayerStateChanged(
          layerState.copyWith(
            outdoors: enabled ? false : layerState.outdoors,
            isolines: enabled ? false : layerState.isolines,
            subway: enabled,
          ),
        );
      case _SettingsId.navigationUnits:
        onNavigationSettingsChanged(
          navigationSettings.copyWith(
            measurementUnits: _navigationUnits(value),
          ),
        );
      case _SettingsId.navigationVoice:
        onNavigationSettingsChanged(
          navigationSettings.copyWith(turnNotificationsEnabled: value == true),
        );
      case _SettingsId.navigationStreetNames:
        onNavigationSettingsChanged(
          navigationSettings.copyWith(announceStreetNames: value == true),
        );
      case _SettingsId.navigationSpeedLimit:
        onNavigationSettingsChanged(
          navigationSettings.copyWith(showSpeedLimit: value == true),
        );
      case _SettingsId.navigationSpeedCameras:
        onNavigationSettingsChanged(
          navigationSettings.copyWith(speedCameraMode: _speedCameraMode(value)),
        );
      case _SettingsId.routeAvoidTolls:
        _updateRouting(avoidTolls: value == true);
      case _SettingsId.routeAvoidMotorways:
        _updateRouting(avoidMotorways: value == true);
      case _SettingsId.routeAvoidFerries:
        _updateRouting(avoidFerries: value == true);
      case _SettingsId.routeAvoidUnpaved:
        _updateRouting(avoidUnpavedRoads: value == true);
    }
  }

  void _updateRouting({
    bool? avoidTolls,
    bool? avoidMotorways,
    bool? avoidFerries,
    bool? avoidUnpavedRoads,
  }) {
    onNavigationSettingsChanged(
      navigationSettings.copyWith(
        routingOptions: navigationSettings.routingOptions.copyWith(
          avoidTolls: avoidTolls,
          avoidMotorways: avoidMotorways,
          avoidFerries: avoidFerries,
          avoidUnpavedRoads: avoidUnpavedRoads,
        ),
      ),
    );
  }

  double _number(Object? value, {required double fallback}) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  ThemeMode _themeMode(Object? value) {
    return ThemeMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => ThemeMode.system,
    );
  }

  agus_maps_flutter.MapAppearanceMode _mapAppearanceMode(Object? value) {
    return agus_maps_flutter.MapAppearanceMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => agus_maps_flutter.MapAppearanceMode.system,
    );
  }

  agus_maps_flutter.NavigationMeasurementUnits _navigationUnits(Object? value) {
    return agus_maps_flutter.NavigationMeasurementUnits.values.firstWhere(
      (units) => units.name == value,
      orElse: () => agus_maps_flutter.NavigationMeasurementUnits.metric,
    );
  }

  agus_maps_flutter.NavigationSpeedCameraMode _speedCameraMode(Object? value) {
    return agus_maps_flutter.NavigationSpeedCameraMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => agus_maps_flutter.NavigationSpeedCameraMode.auto,
    );
  }
}

abstract final class _SettingsId {
  static const mapScale = 'map.scale';
  static const interfaceTheme = 'interface.theme';
  static const mapAppearance = 'map.appearance';
  static const mapLanguage = 'map.language';
  static const buildings3d = 'map.buildings3d';
  static const layerOutdoors = 'map.layers.outdoors';
  static const layerIsolines = 'map.layers.isolines';
  static const layerSubway = 'map.layers.subway';
  static const navigationUnits = 'navigation.units';
  static const navigationVoice = 'navigation.voice';
  static const navigationStreetNames = 'navigation.streetNames';
  static const navigationSpeedLimit = 'navigation.speedLimit';
  static const navigationSpeedCameras = 'navigation.speedCameras';
  static const routeAvoidTolls = 'navigation.route.avoidTolls';
  static const routeAvoidMotorways = 'navigation.route.avoidMotorways';
  static const routeAvoidFerries = 'navigation.route.avoidFerries';
  static const routeAvoidUnpaved = 'navigation.route.avoidUnpaved';
}

const _schemas = <AgusSettingSchema>[
  AgusSettingSchema(
    id: _SettingsId.mapScale,
    title: 'Map: Scale',
    description: 'Controls the rendered map user-interface scale multiplier.',
    category: 'Map',
    type: AgusSettingType.number,
    defaultValue: 1.0,
    minimum: SettingsTab._minScale,
    maximum: SettingsTab._maxScale,
    tags: ['zoom', 'display', 'scale'],
  ),
  AgusSettingSchema(
    id: _SettingsId.interfaceTheme,
    title: 'Interface: Theme',
    description:
        'Controls whether the application uses light, dark, or system.',
    category: 'Appearance',
    type: AgusSettingType.select,
    defaultValue: 'system',
    options: [
      AgusSettingOption(
        value: 'system',
        label: 'System',
        description: 'Follow the operating system appearance.',
      ),
      AgusSettingOption(
        value: 'light',
        label: 'Light',
        description: 'Use a light workbench theme.',
      ),
      AgusSettingOption(
        value: 'dark',
        label: 'Dark',
        description: 'Use a dark workbench theme.',
      ),
    ],
    tags: ['theme', 'appearance', 'light', 'dark', 'system'],
  ),
  AgusSettingSchema(
    id: _SettingsId.mapAppearance,
    title: 'Map: Appearance',
    description: 'Controls the native map rendering theme.',
    category: 'Appearance',
    type: AgusSettingType.select,
    defaultValue: 'system',
    options: [
      AgusSettingOption(value: 'system', label: 'System'),
      AgusSettingOption(value: 'light', label: 'Light'),
      AgusSettingOption(value: 'dark', label: 'Dark'),
    ],
    tags: ['basemap', 'theme', 'appearance', 'light', 'dark'],
  ),
  AgusSettingSchema(
    id: _SettingsId.mapLanguage,
    title: 'Map: Language',
    description: 'Controls the preferred native map label language.',
    category: 'Map',
    type: AgusSettingType.select,
    defaultValue: '',
    options: [
      AgusSettingOption(value: '', label: 'Automatic'),
      AgusSettingOption(value: 'default', label: 'Local names'),
      AgusSettingOption(value: 'en', label: 'English'),
      AgusSettingOption(value: 'es', label: 'Spanish'),
      AgusSettingOption(value: 'fr', label: 'French'),
      AgusSettingOption(value: 'de', label: 'German'),
      AgusSettingOption(value: 'it', label: 'Italian'),
      AgusSettingOption(value: 'ja', label: 'Japanese'),
      AgusSettingOption(value: 'zh', label: 'Chinese'),
    ],
    tags: ['locale', 'labels', 'language', 'names', 'translation'],
  ),
  AgusSettingSchema(
    id: _SettingsId.buildings3d,
    title: 'Map: 3D Buildings',
    description: 'Shows 3D building geometry where supported by map data.',
    category: 'Map Layers',
    type: AgusSettingType.boolean,
    defaultValue: false,
    tags: ['buildings', '3d', 'extrusion', 'scene', 'layers'],
  ),
  AgusSettingSchema(
    id: _SettingsId.layerOutdoors,
    title: 'Layers: Outdoors',
    description: 'Enables terrain-focused outdoor cartography.',
    category: 'Map Layers',
    type: AgusSettingType.boolean,
    defaultValue: false,
    tags: ['terrain', 'hiking', 'outdoor', 'style', 'layers'],
  ),
  AgusSettingSchema(
    id: _SettingsId.layerIsolines,
    title: 'Layers: Contour Lines',
    description: 'Shows elevation isolines. This disables subway styling.',
    category: 'Map Layers',
    type: AgusSettingType.boolean,
    defaultValue: false,
    tags: ['contours', 'elevation', 'terrain', 'isolines', 'layers'],
  ),
  AgusSettingSchema(
    id: _SettingsId.layerSubway,
    title: 'Layers: Subway',
    description: 'Enables subway-emphasis cartography and disables terrain.',
    category: 'Map Layers',
    type: AgusSettingType.boolean,
    defaultValue: false,
    tags: ['transit', 'metro', 'underground', 'transport', 'layers'],
  ),
  AgusSettingSchema(
    id: _SettingsId.navigationUnits,
    title: 'Navigation: Measurement Units',
    description: 'Controls distance and speed units used in route guidance.',
    category: 'Navigation',
    type: AgusSettingType.select,
    defaultValue: 'metric',
    options: [
      AgusSettingOption(value: 'metric', label: 'Metric'),
      AgusSettingOption(value: 'imperial', label: 'Imperial'),
    ],
    tags: ['distance', 'speed', 'units', 'kilometers', 'miles'],
  ),
  AgusSettingSchema(
    id: _SettingsId.navigationVoice,
    title: 'Navigation: Voice Guidance',
    description: 'Enables spoken turn notifications.',
    category: 'Navigation',
    type: AgusSettingType.boolean,
    defaultValue: true,
    tags: ['voice', 'spoken', 'turns', 'guidance', 'directions'],
  ),
  AgusSettingSchema(
    id: _SettingsId.navigationStreetNames,
    title: 'Navigation: Street Names',
    description: 'Includes street names in spoken navigation prompts.',
    category: 'Navigation',
    type: AgusSettingType.boolean,
    defaultValue: true,
    tags: ['voice', 'streets', 'spoken', 'announcements', 'guidance'],
  ),
  AgusSettingSchema(
    id: _SettingsId.navigationSpeedLimit,
    title: 'Navigation: Speed Limit',
    description: 'Shows speed-limit guidance while navigating.',
    category: 'Navigation',
    type: AgusSettingType.boolean,
    defaultValue: true,
    tags: ['speed', 'limit', 'driving', 'guidance', 'road'],
  ),
  AgusSettingSchema(
    id: _SettingsId.navigationSpeedCameras,
    title: 'Navigation: Speed Cameras',
    description: 'Controls speed-camera warnings.',
    category: 'Navigation',
    type: AgusSettingType.select,
    defaultValue: 'auto',
    options: [
      AgusSettingOption(value: 'auto', label: 'Automatic'),
      AgusSettingOption(value: 'always', label: 'Always'),
      AgusSettingOption(value: 'never', label: 'Never'),
    ],
    tags: ['camera', 'speed', 'alerts', 'warnings', 'driving'],
  ),
  AgusSettingSchema(
    id: _SettingsId.routeAvoidTolls,
    title: 'Route: Avoid Tolls',
    description: 'Avoids toll roads during route calculation.',
    category: 'Routing',
    type: AgusSettingType.boolean,
    defaultValue: false,
    tags: ['route', 'avoid', 'toll', 'paid', 'roads'],
  ),
  AgusSettingSchema(
    id: _SettingsId.routeAvoidMotorways,
    title: 'Route: Avoid Motorways',
    description: 'Avoids motorways during route calculation.',
    category: 'Routing',
    type: AgusSettingType.boolean,
    defaultValue: false,
    tags: ['route', 'avoid', 'highway', 'motorway', 'roads'],
  ),
  AgusSettingSchema(
    id: _SettingsId.routeAvoidFerries,
    title: 'Route: Avoid Ferries',
    description: 'Avoids ferry segments during route calculation.',
    category: 'Routing',
    type: AgusSettingType.boolean,
    defaultValue: false,
    tags: ['route', 'avoid', 'ferry', 'boat', 'water'],
  ),
  AgusSettingSchema(
    id: _SettingsId.routeAvoidUnpaved,
    title: 'Route: Avoid Unpaved Roads',
    description: 'Avoids unpaved roads during route calculation.',
    category: 'Routing',
    type: AgusSettingType.boolean,
    defaultValue: false,
    tags: ['route', 'avoid', 'unpaved', 'gravel', 'roads'],
  ),
];
