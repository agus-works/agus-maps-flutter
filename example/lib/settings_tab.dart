import 'package:flutter/material.dart';

import 'package:agus_maps_flutter/agus_maps_flutter.dart' as agus_maps_flutter;

class SettingsTab extends StatelessWidget {
  final double mapScale;
  final ThemeMode interfaceThemeMode;
  final agus_maps_flutter.MapAppearanceMode mapAppearanceMode;
  final String mapLanguageCode;
  final bool buildings3dEnabled;
  final agus_maps_flutter.MapLayerState layerState;
  final ValueChanged<double> onMapScaleChanged;
  final VoidCallback onResetMapScale;
  final ValueChanged<ThemeMode> onInterfaceThemeModeChanged;
  final ValueChanged<agus_maps_flutter.MapAppearanceMode>
      onMapAppearanceModeChanged;
  final ValueChanged<String> onMapLanguageChanged;
  final ValueChanged<bool> onBuildings3dChanged;
  final ValueChanged<agus_maps_flutter.MapLayerState> onLayerStateChanged;

  const SettingsTab({
    super.key,
    required this.mapScale,
    required this.interfaceThemeMode,
    required this.mapAppearanceMode,
    required this.mapLanguageCode,
    required this.buildings3dEnabled,
    required this.layerState,
    required this.onMapScaleChanged,
    required this.onResetMapScale,
    required this.onInterfaceThemeModeChanged,
    required this.onMapAppearanceModeChanged,
    required this.onMapLanguageChanged,
    required this.onBuildings3dChanged,
    required this.onLayerStateChanged,
  });

  static const double _minScale = 0.25;
  static const double _maxScale = 3.0;
  static const List<DropdownMenuEntry<String>> _languageEntries = [
    DropdownMenuEntry(value: '', label: 'Automatic'),
    DropdownMenuEntry(value: 'default', label: 'Local names'),
    DropdownMenuEntry(value: 'en', label: 'English'),
    DropdownMenuEntry(value: 'es', label: 'Spanish'),
    DropdownMenuEntry(value: 'fr', label: 'French'),
    DropdownMenuEntry(value: 'de', label: 'German'),
    DropdownMenuEntry(value: 'it', label: 'Italian'),
    DropdownMenuEntry(value: 'ja', label: 'Japanese'),
    DropdownMenuEntry(value: 'zh', label: 'Chinese'),
  ];

  @override
  Widget build(BuildContext context) {
    final scaleText = mapScale.toStringAsFixed(2);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            border: Border(
              bottom: BorderSide(color: theme.dividerColor),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.settings, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Settings',
                style: theme.textTheme.titleMedium,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SettingsCard(
                icon: Icons.palette_outlined,
                title: 'Appearance',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ThemeSegments(
                      label: 'Interface',
                      selected: interfaceThemeMode,
                      onChanged: onInterfaceThemeModeChanged,
                    ),
                    const SizedBox(height: 16),
                    _MapAppearanceSegments(
                      selected: mapAppearanceMode,
                      onChanged: onMapAppearanceModeChanged,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _SettingsCard(
                icon: Icons.map_outlined,
                title: 'Map options',
                child: Column(
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('3D buildings'),
                      secondary: const Icon(Icons.apartment),
                      value: buildings3dEnabled,
                      onChanged: onBuildings3dChanged,
                    ),
                    const Divider(),
                    DropdownMenu<String>(
                      width: double.infinity,
                      label: const Text('Map language'),
                      initialSelection: mapLanguageCode,
                      dropdownMenuEntries: _languageEntries,
                      onSelected: (value) {
                        if (value != null) onMapLanguageChanged(value);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _SettingsCard(
                icon: Icons.layers_outlined,
                title: 'Layers',
                child: Column(
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Outdoors'),
                      secondary: const Icon(Icons.terrain),
                      value: layerState.outdoors,
                      onChanged: (enabled) => onLayerStateChanged(
                        layerState.copyWith(
                          outdoors: enabled,
                          subway: enabled ? false : layerState.subway,
                        ),
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Contour lines'),
                      secondary: const Icon(Icons.landscape_outlined),
                      value: layerState.isolines,
                      onChanged: (enabled) => onLayerStateChanged(
                        layerState.copyWith(
                          isolines: enabled,
                          subway: enabled ? false : layerState.subway,
                        ),
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Subway'),
                      secondary: const Icon(Icons.directions_subway),
                      value: layerState.subway,
                      onChanged: (enabled) => onLayerStateChanged(
                        layerState.copyWith(
                          outdoors: enabled ? false : layerState.outdoors,
                          isolines: enabled ? false : layerState.isolines,
                          subway: enabled,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _SettingsCard(
                icon: Icons.text_fields,
                title: 'Map label scale',
                trailing:
                    Text('${scaleText}x', style: theme.textTheme.titleSmall),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Adjust label and icon size without changing zoom.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    Slider(
                      value: mapScale.clamp(_minScale, _maxScale),
                      min: _minScale,
                      max: _maxScale,
                      divisions: 55,
                      label: '${scaleText}x',
                      onChanged: onMapScaleChanged,
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: onResetMapScale,
                        child: const Text('Reset to 1.00x'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;
  final Widget? trailing;

  const _SettingsCard({
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(title, style: theme.textTheme.titleMedium),
                const Spacer(),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _ThemeSegments extends StatelessWidget {
  final String label;
  final ThemeMode selected;
  final ValueChanged<ThemeMode> onChanged;

  const _ThemeSegments({
    required this.label,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(
                value: ThemeMode.system, icon: Icon(Icons.phone_iphone)),
            ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode)),
            ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode)),
          ],
          selected: {selected},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => onChanged(selection.first),
        ),
      ],
    );
  }
}

class _MapAppearanceSegments extends StatelessWidget {
  final agus_maps_flutter.MapAppearanceMode selected;
  final ValueChanged<agus_maps_flutter.MapAppearanceMode> onChanged;

  const _MapAppearanceSegments({
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Map', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        SegmentedButton<agus_maps_flutter.MapAppearanceMode>(
          segments: const [
            ButtonSegment(
              value: agus_maps_flutter.MapAppearanceMode.system,
              icon: Icon(Icons.phone_iphone),
            ),
            ButtonSegment(
              value: agus_maps_flutter.MapAppearanceMode.light,
              icon: Icon(Icons.light_mode),
            ),
            ButtonSegment(
              value: agus_maps_flutter.MapAppearanceMode.dark,
              icon: Icon(Icons.dark_mode),
            ),
          ],
          selected: {selected},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => onChanged(selection.first),
        ),
      ],
    );
  }
}
