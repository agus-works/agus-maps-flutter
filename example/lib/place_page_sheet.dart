import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:agus_maps_flutter/agus_maps_flutter.dart' as agus_maps_flutter;

/// Bottom sheet that renders place details from the map.
class PlacePageSheet extends StatelessWidget {
  /// Creates a place page sheet.
  const PlacePageSheet({
    required this.data,
    required this.onClose,
    this.onRouteTo,
    this.routeInProgress = false,
    this.mobileLandscape = false,
    super.key,
  });

  /// Place details to render.
  final agus_maps_flutter.PlacePageData data;

  /// Callback invoked when the sheet is dismissed.
  final VoidCallback onClose;

  /// Callback invoked when route planning should target this place.
  final VoidCallback? onRouteTo;

  /// Whether a route action is currently being prepared.
  final bool routeInProgress;

  /// Whether this sheet should use the dedicated phone-landscape side layout.
  final bool mobileLandscape;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final metadataEntries = data.metadataTags
        .map(
          (entry) => _MetadataEntry(
            // NOTE: PlacePageLocalization has been removed.
            // Use the metadata key directly with simple humanization.
            label: _humanizeMetadataTag(entry.key),
            value: entry.value,
          ),
        )
        .where((entry) => entry.label.isNotEmpty)
        .toList()
      ..sort((a, b) => a.label.compareTo(b.label));

    final localizedSubtitle = data.subtitle;
    final content = _PlacePageContent(
      data: data,
      metadataEntries: metadataEntries,
      localizedSubtitle: localizedSubtitle,
      onClose: onClose,
      onRouteTo: onRouteTo,
      routeInProgress: routeInProgress,
      textTheme: textTheme,
      colorScheme: colorScheme,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (mobileLandscape) {
          final width = math.min(
            390.0,
            math.max(320.0, constraints.maxWidth * 0.46),
          );
          return Align(
            alignment: Alignment.centerRight,
            child: SafeArea(
              minimum: const EdgeInsets.fromLTRB(8, 10, 10, 10),
              child: SizedBox(
                width: width,
                height: math.max(240.0, constraints.maxHeight - 20),
                child: _PlacePageSurface(
                  colorScheme: colorScheme,
                  borderRadius: BorderRadius.circular(20),
                  child: content,
                ),
              ),
            ),
          );
        }

        final maxHeight = math.min(
          520.0,
          math.max(240.0, constraints.maxHeight * 0.64),
        );
        return Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            minimum: const EdgeInsets.all(12),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 560,
                maxHeight: maxHeight,
              ),
              child: _PlacePageSurface(
                colorScheme: colorScheme,
                borderRadius: BorderRadius.circular(16),
                child: content,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PlacePageSurface extends StatelessWidget {
  const _PlacePageSurface({
    required this.colorScheme,
    required this.borderRadius,
    required this.child,
  });

  final ColorScheme colorScheme;
  final BorderRadius borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      color: colorScheme.surface,
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _PlacePageContent extends StatelessWidget {
  const _PlacePageContent({
    required this.data,
    required this.metadataEntries,
    required this.localizedSubtitle,
    required this.onClose,
    required this.onRouteTo,
    required this.routeInProgress,
    required this.textTheme,
    required this.colorScheme,
  });

  final agus_maps_flutter.PlacePageData data;
  final List<_MetadataEntry> metadataEntries;
  final String localizedSubtitle;
  final VoidCallback onClose;
  final VoidCallback? onRouteTo;
  final bool routeInProgress;
  final TextTheme textTheme;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  data.title.isNotEmpty ? data.title : 'Map point',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
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
                if (onRouteTo != null) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      onPressed: routeInProgress ? null : onRouteTo,
                      icon: routeInProgress
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.alt_route),
                      label: Text(routeInProgress ? 'Routing' : 'Route'),
                    ),
                  ),
                ],
                if (metadataEntries.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Divider(color: colorScheme.outlineVariant),
                  const SizedBox(height: 8),
                  for (final entry in metadataEntries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _MetadataRow(
                        entry: entry,
                        textTheme: textTheme,
                        colorScheme: colorScheme,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetadataRow extends StatelessWidget {
  const _MetadataRow({
    required this.entry,
    required this.textTheme,
    required this.colorScheme,
  });

  final _MetadataEntry entry;
  final TextTheme textTheme;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 330;
        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.label,
                style: textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(entry.value, style: textTheme.bodyMedium),
            ],
          );
        }

        return Row(
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
              child: Text(entry.value, style: textTheme.bodyMedium),
            ),
          ],
        );
      },
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

/// Humanize a metadata tag key for display.
/// e.g., "opening_hours" → "Opening Hours", "contact:phone" → "Phone"
String _humanizeMetadataTag(String tag) {
  if (tag.isEmpty) return '';

  // Handle contact: prefix specially
  if (tag.startsWith('contact:')) {
    tag = tag.substring('contact:'.length);
  }

  // Replace underscores and colons with spaces
  final normalized = tag.replaceAll('_', ' ').replaceAll(':', ' ');

  // Capitalize each word
  return normalized
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .map((part) =>
          part[0].toUpperCase() + (part.length > 1 ? part.substring(1) : ''))
      .join(' ');
}
