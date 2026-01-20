import 'package:flutter/material.dart';

class SettingsTab extends StatelessWidget {
  final double mapScale;
  final ValueChanged<double> onMapScaleChanged;
  final VoidCallback onResetMapScale;

  const SettingsTab({
    super.key,
    required this.mapScale,
    required this.onMapScaleChanged,
    required this.onResetMapScale,
  });

  static const double _minScale = 0.25;
  static const double _maxScale = 3.0;

  @override
  Widget build(BuildContext context) {
    final scaleText = mapScale.toStringAsFixed(2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: Border(
              bottom: BorderSide(color: Theme.of(context).dividerColor),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.settings, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Settings',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.text_fields,
                              color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Map label scale',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const Spacer(),
                          Text(
                            '${scaleText}x',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Adjust label and icon size without changing zoom.',
                        style: Theme.of(context).textTheme.bodySmall,
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
              ),
            ],
          ),
        ),
      ],
    );
  }
}
