import 'package:agus_maps_flutter/agus_maps_flutter.dart' as agus_maps_flutter;
import 'package:agus_design/agus_design.dart';
import 'package:flutter/material.dart';

/// Blank placeholder shown in the default non-map editor tab.
class BlankEditorPlaceholder extends StatelessWidget {
  /// Creates the blank placeholder tab.
  const BlankEditorPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Card(
          elevation: 0,
          color: colorScheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.tab_unselected,
                  size: 48,
                  color: colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text('Blank editor viewport',
                    style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  'This tab reserves the Editor Area architecture for future '
                  'documents, layouts, SQL views, and map-related tools.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom Panel viewport for the selected point of interest.
class PointOfInterestPanel extends StatelessWidget {
  /// Creates a point-of-interest details panel.
  const PointOfInterestPanel({super.key, required this.placePage});

  /// Current native place-page selection.
  final agus_maps_flutter.PlacePageData? placePage;

  @override
  Widget build(BuildContext context) {
    final placePage = this.placePage;
    if (placePage == null) {
      return const AgusEmptyState(
        icon: Icons.place_outlined,
        title: 'No point of interest selected',
        message: 'Click a map element to inspect its place-page details here.',
      );
    }

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.all(12),
      children: [
        _PanelTitle(
          icon: Icons.place,
          title: placePage.title.isEmpty ? 'Selected feature' : placePage.title,
          subtitle: placePage.subtitle,
        ),
        const SizedBox(height: 12),
        AgusPropertyGrid(
          rows: _propertyRows([
            ('Title', placePage.title),
            ('Secondary title', placePage.secondaryTitle),
            ('Subtitle', placePage.subtitle),
            ('Address', placePage.address),
            ('Coordinates', placePage.coordinates.decimal ?? ''),
            ('OSM', placePage.coordinates.osm ?? ''),
            ('Raw types', placePage.rawTypes.join(', ')),
            ('Route point', placePage.isRoutePoint ? 'Yes' : 'No'),
            ('Bookmark ID', placePage.bookmarkId?.toString() ?? ''),
            ('Track ID', placePage.trackId?.toString() ?? ''),
          ]),
        ),
      ],
    );
  }
}

/// Bottom Panel viewport containing application debug logs.
class DebugConsolePanel extends StatelessWidget {
  /// Creates a debug console panel.
  const DebugConsolePanel({super.key, required this.log});

  /// Newline-separated log output.
  final String log;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (log.trim().isEmpty) {
      return const AgusEmptyState(
        icon: Icons.terminal,
        title: 'Debug Console',
        message: 'Runtime messages will appear here as the map initializes.',
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(color: colorScheme.surfaceContainerLowest),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        reverse: true,
        child: SelectableText(
          log,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontFamily: 'monospace',
            fontSize: 12,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}

/// Secondary Side Bar property grid for the selected map element.
class PropertiesSideBar extends StatelessWidget {
  /// Creates a properties side bar.
  const PropertiesSideBar({super.key, required this.placePage});

  /// Current native place-page selection.
  final agus_maps_flutter.PlacePageData? placePage;

  @override
  Widget build(BuildContext context) {
    final placePage = this.placePage;
    if (placePage == null) {
      return const AgusEmptyState(
        icon: Icons.view_list_outlined,
        title: 'Properties',
        message: 'Select a map feature to populate this property grid.',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _PanelTitle(
          icon: Icons.dataset_outlined,
          title: 'Feature properties',
          subtitle: placePage.title,
        ),
        const SizedBox(height: 12),
        AgusPropertyGrid(
          rows: _propertyRows([
            ('Name', placePage.title),
            ('Category', placePage.subtitle),
            ('Address', placePage.address),
            ('Latitude', placePage.lat.toStringAsFixed(7)),
            ('Longitude', placePage.lon.toStringAsFixed(7)),
            ('Mwm name', placePage.featureId.mwmName),
            ('Mwm version', placePage.featureId.mwmVersion.toString()),
            ('Feature index', placePage.featureId.index.toString()),
            for (final entry in placePage.metadataTags)
              (entry.key, entry.value),
          ]),
        ),
      ],
    );
  }
}

/// Secondary Side Bar inspector placeholder for future stacked editors.
class InspectorSideBar extends StatelessWidget {
  /// Creates an inspector placeholder.
  const InspectorSideBar({super.key});

  @override
  Widget build(BuildContext context) {
    return const AgusEmptyState(
      icon: Icons.rule_folder_outlined,
      title: 'Inspector',
      message: 'Layer, style, and selection inspector groups will stack here.',
    );
  }
}

class _PanelTitle extends StatelessWidget {
  const _PanelTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      children: [
        CircleAvatar(
          backgroundColor: colorScheme.primaryContainer,
          child: Icon(icon, color: colorScheme.onPrimaryContainer),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
              ),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

List<AgusPropertyRow> _propertyRows(List<(String, String)> rows) {
  return rows
      .where((row) => row.$2.trim().isNotEmpty)
      .map(
        (row) => AgusPropertyRow(
          name: row.$1,
          value: AgusPropertyText(row.$2),
        ),
      )
      .toList(growable: false);
}
