import 'package:flutter/material.dart';

import 'package:agus_maps_flutter/agus_maps_flutter.dart' as agus_maps_flutter;

/// Bottom sheet that renders place details from the map.
class PlacePageSheet extends StatelessWidget {
  /// Creates a place page sheet.
  const PlacePageSheet({
    required this.data,
    required this.onClose,
    super.key,
  });

  /// Place details to render.
  final agus_maps_flutter.PlacePageData data;

  /// Callback invoked when the sheet is dismissed.
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final metadataEntries = data.metadataTags.entries
        .map(
          (entry) => _MetadataEntry(
            label: agus_maps_flutter.PlacePageLocalization.localizeMetadataTag(
              entry.key,
            ),
            value: entry.value,
          ),
        )
        .where((entry) => entry.label.isNotEmpty)
        .toList()
      ..sort((a, b) => a.label.compareTo(b.label));

    final localizedSubtitle = data.subtitle;

    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: Material(
          elevation: 6,
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          data.title.isNotEmpty ? data.title : 'Map point',
                          style: textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        onPressed: onClose,
                        icon: const Icon(Icons.close),
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                  if (data.secondaryTitle.isNotEmpty)
                    Text(
                      data.secondaryTitle,
                      style: textTheme.titleSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (localizedSubtitle.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        localizedSubtitle,
                        style: textTheme.bodyMedium,
                      ),
                    ),
                  if (data.address.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        data.address,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  if ((data.coordinates.decimal ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        data.coordinates.decimal ?? '',
                        style: textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  if (metadataEntries.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Divider(color: colorScheme.outlineVariant),
                    const SizedBox(height: 8),
                    for (final entry in metadataEntries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 130,
                              child: Text(
                                entry.label,
                                style: textTheme.labelMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                entry.value,
                                style: textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MetadataEntry {
  final String label;
  final String value;

  const _MetadataEntry({
    required this.label,
    required this.value,
  });
}
