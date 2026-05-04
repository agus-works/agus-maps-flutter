import 'dart:async';

import 'package:flutter/material.dart';

import 'package:agus_maps_flutter/agus_maps_flutter.dart' as agus_maps_flutter;

import '../../../shared/adaptive/form_factor.dart';
import '../../../shared/widgets/compact_property_grid.dart';
import '../../../shared/widgets/panel_surface.dart';

/// Adaptive layer tree inspired by GIS desktop layer docks.
class AdaptiveLayerManager extends StatefulWidget {
  const AdaptiveLayerManager({
    super.key,
    required this.formFactor,
    required this.nativeLayerState,
    required this.buildings3dEnabled,
    required this.onNativeLayerStateChanged,
    required this.onBuildings3dChanged,
    this.layerStore,
    this.activeLayerId,
    this.activeDrawTool,
    this.onRenderingRefresh,
    this.onActiveLayerChanged,
    this.onDrawToolChanged,
    this.onClose,
  });

  final ExampleFormFactor formFactor;
  final agus_maps_flutter.MapLayerState nativeLayerState;
  final bool buildings3dEnabled;
  final ValueChanged<agus_maps_flutter.MapLayerState> onNativeLayerStateChanged;
  final ValueChanged<bool> onBuildings3dChanged;
  final agus_maps_flutter.DuckDBLayerStore? layerStore;
  final String? activeLayerId;
  final agus_maps_flutter.AgusDrawTool? activeDrawTool;
  final Future<void> Function()? onRenderingRefresh;
  final ValueChanged<String>? onActiveLayerChanged;
  final ValueChanged<agus_maps_flutter.AgusDrawTool>? onDrawToolChanged;
  final VoidCallback? onClose;

  @override
  State<AdaptiveLayerManager> createState() => _AdaptiveLayerManagerState();
}

class _AdaptiveLayerManagerState extends State<AdaptiveLayerManager> {
  final Set<String> _expandedNodes = <String>{
    _mapPresentationNodeId,
    _projectLayersNodeId,
  };

  List<agus_maps_flutter.AgusLayer> _layers =
      const <agus_maps_flutter.AgusLayer>[];
  Map<String, List<agus_maps_flutter.AgusLayerFeature>> _featuresByLayer =
      const <String, List<agus_maps_flutter.AgusLayerFeature>>{};
  String _message = '';
  bool _busy = false;

  static const String _mapPresentationNodeId = 'map-presentation';
  static const String _projectLayersNodeId = 'project-layers';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant AdaptiveLayerManager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.layerStore != widget.layerStore) {
      _reload();
    }
  }

  void _toggleNode(String nodeId) {
    setState(() {
      if (_expandedNodes.contains(nodeId)) {
        _expandedNodes.remove(nodeId);
      } else {
        _expandedNodes.add(nodeId);
      }
    });
  }

  Future<void> _reload() async {
    final store = widget.layerStore;
    if (store == null) {
      if (!mounted) return;
      setState(() {
        _layers = const <agus_maps_flutter.AgusLayer>[];
        _featuresByLayer =
            const <String, List<agus_maps_flutter.AgusLayerFeature>>{};
      });
      return;
    }

    final layers = store.listLayers();
    final featuresByLayer =
        <String, List<agus_maps_flutter.AgusLayerFeature>>{};
    for (final layer in layers) {
      featuresByLayer[layer.layerId] = store.listFeatures(layer.layerId);
    }

    if (!mounted) return;
    setState(() {
      _layers = layers;
      _featuresByLayer = featuresByLayer;
    });
  }

  Future<void> _toggleStoredLayer(
    agus_maps_flutter.AgusLayer layer,
    bool visible,
  ) async {
    final store = widget.layerStore;
    if (store == null) return;
    store.setLayerVisibility(layer.layerId, visible);
    await widget.onRenderingRefresh?.call();
    await _reload();
  }

  Future<void> _moveLayer(
    agus_maps_flutter.AgusLayer layer,
    int delta,
  ) async {
    final store = widget.layerStore;
    if (store == null) return;
    store.setLayerZIndex(layer.layerId, layer.zIndex + delta);
    await widget.onRenderingRefresh?.call();
    await _reload();
  }

  Future<void> _deleteLayer(agus_maps_flutter.AgusLayer layer) async {
    final store = widget.layerStore;
    if (store == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete layer?'),
        content: Text(
          'Delete "${layer.name}" and hide its features from the project?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    store.deleteLayer(layer.layerId);
    if (widget.activeLayerId == layer.layerId) {
      final remainingLayers = store.listLayers();
      if (remainingLayers.isNotEmpty) {
        widget.onActiveLayerChanged?.call(remainingLayers.first.layerId);
      }
    }
    await widget.onRenderingRefresh?.call();
    await _reload();
  }

  Future<void> _createLayer() async {
    final store = widget.layerStore;
    if (store == null || _busy) return;

    final nameController = TextEditingController(
      text: 'Drawing layer ${_layers.length + 1}',
    );
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Create Drawing Layer'),
          content: TextField(
            controller: nameController,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Layer name',
              helperText: 'Creates a DuckDB-backed editable drawing layer.',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(nameController.text),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
    nameController.dispose();

    final name = result?.trim();
    if (name == null || name.isEmpty) return;

    final id = _layerIdFromName(name);
    final zIndex = _layers.isEmpty
        ? 1000
        : _layers.map((layer) => layer.zIndex).reduce((a, b) => a > b ? a : b) +
            10;

    store.upsertLayer(
      agus_maps_flutter.AgusLayerDraft(
        layerId: id,
        name: name,
        kind: agus_maps_flutter.AgusLayerKind.userDraw,
        visible: true,
        zIndex: zIndex,
        metadata: const {'source': 'desktop_layer_manager'},
      ),
    );
    widget.onActiveLayerChanged?.call(id);
    await widget.onRenderingRefresh?.call();
    await _reload();
  }

  String _layerIdFromName(String name) {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final base = slug.isEmpty ? 'drawing_layer' : slug;
    final existingIds = _layers.map((layer) => layer.layerId).toSet();
    var candidate = base;
    var suffix = 2;
    while (existingIds.contains(candidate)) {
      candidate = '${base}_$suffix';
      suffix++;
    }
    return candidate;
  }

  Future<void> _backup() async {
    final store = widget.layerStore;
    if (store == null || _busy) return;
    setState(() {
      _busy = true;
      _message = '';
    });

    try {
      final path = await store.backup();
      if (!mounted) return;
      setState(() {
        _message = 'Backup created at $path';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = 'Backup failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final uiSpec = context.exampleUiSpec;
    final compact = widget.formFactor.isDesktop;
    final projectLayerCount = _layers.length;

    if (compact) {
      return _buildDesktopCompact(context, projectLayerCount);
    }

    return PanelSurface(
      title: 'Layer manager',
      subtitle: switch (widget.formFactor) {
        ExampleFormFactor.mobile =>
          'Mobile stack: modal tree, simplified context, large tap targets.',
        ExampleFormFactor.tablet =>
          'Tablet stack: docked tree, larger touch surfaces, expanded metadata.',
        ExampleFormFactor.desktop =>
          'Desktop stack: compact dock, denser controls, mouse and keyboard first.',
      },
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Refresh layer tree',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Back up project layers',
            onPressed: widget.layerStore == null || _busy ? null : _backup,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.backup_outlined),
          ),
          if (widget.onClose != null)
            IconButton(
              tooltip: 'Close layer manager',
              onPressed: widget.onClose,
              icon: const Icon(Icons.close),
            ),
        ],
      ),
      padding: compact
          ? const EdgeInsets.fromLTRB(12, 12, 12, 10)
          : const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LayerTreeGroup(
            nodeId: _mapPresentationNodeId,
            title: 'Map presentation',
            subtitle: 'Basemap overlays and visibility profile',
            icon: Icons.public_outlined,
            countLabel: '${_enabledNativeLayerCount()} / 4',
            expanded: _expandedNodes.contains(_mapPresentationNodeId),
            onToggle: () => _toggleNode(_mapPresentationNodeId),
            child: Column(
              children: [
                _TreeToggleRow(
                  label: '3D buildings',
                  subtitle: 'Scene depth for city-scale map views',
                  icon: Icons.apartment_outlined,
                  value: widget.buildings3dEnabled,
                  onChanged: widget.onBuildings3dChanged,
                  padding: uiSpec.treeRowPadding,
                ),
                _TreeToggleRow(
                  label: 'Outdoors',
                  subtitle: 'Terrain-driven cartography and hiking emphasis',
                  icon: Icons.terrain_outlined,
                  value: widget.nativeLayerState.outdoors,
                  onChanged: (enabled) {
                    widget.onNativeLayerStateChanged(
                      widget.nativeLayerState.copyWith(
                        outdoors: enabled,
                        subway:
                            enabled ? false : widget.nativeLayerState.subway,
                      ),
                    );
                  },
                  padding: uiSpec.treeRowPadding,
                ),
                _TreeToggleRow(
                  label: 'Contour lines',
                  subtitle: 'Elevation isolines for terrain reading',
                  icon: Icons.landscape_outlined,
                  value: widget.nativeLayerState.isolines,
                  onChanged: (enabled) {
                    widget.onNativeLayerStateChanged(
                      widget.nativeLayerState.copyWith(
                        isolines: enabled,
                        subway:
                            enabled ? false : widget.nativeLayerState.subway,
                      ),
                    );
                  },
                  padding: uiSpec.treeRowPadding,
                ),
                _TreeToggleRow(
                  label: 'Subway',
                  subtitle: 'Transit-emphasis cartography',
                  icon: Icons.directions_subway_outlined,
                  value: widget.nativeLayerState.subway,
                  onChanged: (enabled) {
                    widget.onNativeLayerStateChanged(
                      widget.nativeLayerState.copyWith(
                        outdoors:
                            enabled ? false : widget.nativeLayerState.outdoors,
                        isolines:
                            enabled ? false : widget.nativeLayerState.isolines,
                        subway: enabled,
                      ),
                    );
                  },
                  padding: uiSpec.treeRowPadding,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _LayerTreeGroup(
            nodeId: _projectLayersNodeId,
            title: 'Project layers',
            subtitle: widget.layerStore == null
                ? 'DuckDB-backed drawing layers are enabled on Android, macOS, and iOS.'
                : 'QGIS-style stack ordered by z-index for rendering.',
            icon: Icons.layers_outlined,
            countLabel: '$projectLayerCount',
            expanded: _expandedNodes.contains(_projectLayersNodeId),
            onToggle: () => _toggleNode(_projectLayersNodeId),
            child: projectLayerCount == 0
                ? Padding(
                    padding: uiSpec.treeRowPadding,
                    child: _InlineInfoBanner(
                      icon: Icons.info_outline,
                      message: widget.layerStore == null
                          ? 'Map presentation controls work everywhere. Project data layers appear here once the platform DuckDB renderer is active.'
                          : 'No project layers have been created yet.',
                    ),
                  )
                : Column(
                    children: [
                      for (final layer in _layers)
                        _StoredLayerNode(
                          layer: layer,
                          features: _featuresByLayer[layer.layerId] ??
                              const <agus_maps_flutter.AgusLayerFeature>[],
                          compact: compact,
                          expanded:
                              _expandedNodes.contains('layer:${layer.layerId}'),
                          padding: uiSpec.treeRowPadding,
                          onToggleExpanded: () =>
                              _toggleNode('layer:${layer.layerId}'),
                          onVisibleChanged: (value) {
                            unawaited(_toggleStoredLayer(layer, value));
                          },
                          onMoveUp: () => unawaited(_moveLayer(layer, 1)),
                          onMoveDown: () => unawaited(_moveLayer(layer, -1)),
                        ),
                    ],
                  ),
          ),
          if (_message.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _message,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDesktopCompact(BuildContext context, int projectLayerCount) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final storeReady = widget.layerStore != null;

    return ColoredBox(
      color: colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CompactLayerToolbar(
            title: 'Layer Manager',
            subtitle: storeReady
                ? '$projectLayerCount project layers'
                : 'DuckDB layer store is starting',
            busy: _busy,
            onRefresh: _reload,
            onBackup: storeReady && !_busy ? _backup : null,
            onCreateLayer: storeReady ? _createLayer : null,
            onClose: widget.onClose,
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [
                _CompactSectionLabel(
                  label: 'Map presentation',
                  countLabel: '${_enabledNativeLayerCount()} / 4',
                ),
                const SizedBox(height: 6),
                CompactPropertyGrid(
                  rows: [
                    CompactPropertyRow(
                      name: '3D buildings',
                      value: _CompactSwitch(
                        value: widget.buildings3dEnabled,
                        onChanged: widget.onBuildings3dChanged,
                      ),
                    ),
                    CompactPropertyRow(
                      name: 'Outdoors',
                      value: _CompactSwitch(
                        value: widget.nativeLayerState.outdoors,
                        onChanged: (enabled) {
                          widget.onNativeLayerStateChanged(
                            widget.nativeLayerState.copyWith(
                              outdoors: enabled,
                              subway: enabled
                                  ? false
                                  : widget.nativeLayerState.subway,
                            ),
                          );
                        },
                      ),
                    ),
                    CompactPropertyRow(
                      name: 'Contour lines',
                      value: _CompactSwitch(
                        value: widget.nativeLayerState.isolines,
                        onChanged: (enabled) {
                          widget.onNativeLayerStateChanged(
                            widget.nativeLayerState.copyWith(
                              isolines: enabled,
                              subway: enabled
                                  ? false
                                  : widget.nativeLayerState.subway,
                            ),
                          );
                        },
                      ),
                    ),
                    CompactPropertyRow(
                      name: 'Subway',
                      value: _CompactSwitch(
                        value: widget.nativeLayerState.subway,
                        onChanged: (enabled) {
                          widget.onNativeLayerStateChanged(
                            widget.nativeLayerState.copyWith(
                              outdoors: enabled
                                  ? false
                                  : widget.nativeLayerState.outdoors,
                              isolines: enabled
                                  ? false
                                  : widget.nativeLayerState.isolines,
                              subway: enabled,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _DesktopDrawSessionCard(
                  activeTool: widget.activeDrawTool ??
                      agus_maps_flutter.AgusDrawTool.none,
                  hasEditableLayer: _layers
                      .any((layer) => layer.layerId == widget.activeLayerId),
                  activeLayerName: _activeLayerName(),
                  onToolChanged: widget.onDrawToolChanged,
                ),
                const SizedBox(height: 12),
                _CompactSectionLabel(
                  label: 'Project layers',
                  countLabel: '$projectLayerCount',
                ),
                const SizedBox(height: 6),
                _buildDesktopLayerGrid(context),
                if (_message.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    _message,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
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

  Widget _buildDesktopLayerGrid(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_layers.isEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            widget.layerStore == null
                ? 'Map presentation controls work now. Project data layers appear once the DuckDB renderer is active.'
                : 'No project layers yet. Create a Drawing Layer to start editing.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return CompactDataGrid(
      columns: const [
        CompactDataColumn(label: '', width: 26),
        CompactDataColumn(label: 'Layer'),
        CompactDataColumn(label: 'Features', width: 64),
        CompactDataColumn(label: 'Z', width: 40),
        CompactDataColumn(label: '', width: 92),
      ],
      rows: [
        for (final layer in _layers) _buildDesktopLayerRow(context, layer),
      ],
    );
  }

  List<Widget> _buildDesktopLayerRow(
    BuildContext context,
    agus_maps_flutter.AgusLayer layer,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final featureCount = _featuresByLayer[layer.layerId]?.length ?? 0;
    final selected = layer.layerId == widget.activeLayerId;
    final nameStyle = theme.textTheme.bodySmall?.copyWith(
      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      color: selected ? colorScheme.primary : colorScheme.onSurface,
    );

    return [
      _CompactIconButton(
        tooltip: layer.visible ? 'Hide layer' : 'Show layer',
        icon: layer.visible ? Icons.visibility : Icons.visibility_off,
        selected: layer.visible,
        onPressed: () => unawaited(_toggleStoredLayer(layer, !layer.visible)),
      ),
      InkWell(
        onTap: () => widget.onActiveLayerChanged?.call(layer.layerId),
        child: Row(
          children: [
            Icon(
              selected ? Icons.edit_location_alt : Icons.layers_outlined,
              size: 15,
              color:
                  selected ? colorScheme.primary : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                layer.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: nameStyle,
              ),
            ),
          ],
        ),
      ),
      Text('$featureCount', style: theme.textTheme.bodySmall),
      Text('${layer.zIndex}', style: theme.textTheme.bodySmall),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _CompactIconButton(
            tooltip: 'Move up',
            icon: Icons.keyboard_arrow_up,
            onPressed: () => unawaited(_moveLayer(layer, 1)),
          ),
          _CompactIconButton(
            tooltip: 'Move down',
            icon: Icons.keyboard_arrow_down,
            onPressed: () => unawaited(_moveLayer(layer, -1)),
          ),
          _CompactIconButton(
            tooltip: 'Delete layer',
            icon: Icons.delete_outline,
            onPressed: () => unawaited(_deleteLayer(layer)),
          ),
        ],
      ),
    ];
  }

  String _activeLayerName() {
    for (final layer in _layers) {
      if (layer.layerId == widget.activeLayerId) return layer.name;
    }
    return 'No editable layer selected';
  }

  int _enabledNativeLayerCount() {
    var count = 0;
    if (widget.buildings3dEnabled) count += 1;
    if (widget.nativeLayerState.outdoors) count += 1;
    if (widget.nativeLayerState.isolines) count += 1;
    if (widget.nativeLayerState.subway) count += 1;
    return count;
  }
}

class _CompactLayerToolbar extends StatelessWidget {
  const _CompactLayerToolbar({
    required this.title,
    required this.subtitle,
    required this.busy,
    required this.onRefresh,
    required this.onBackup,
    required this.onCreateLayer,
    required this.onClose,
  });

  final String title;
  final String subtitle;
  final bool busy;
  final VoidCallback onRefresh;
  final VoidCallback? onBackup;
  final VoidCallback? onCreateLayer;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return SizedBox(
      height: 40,
      child: Padding(
        padding: const EdgeInsets.only(left: 10, right: 4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: onCreateLayer,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('New Layer'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
            _CompactIconButton(
              tooltip: 'Refresh layers',
              icon: Icons.refresh,
              onPressed: onRefresh,
            ),
            _CompactIconButton(
              tooltip: 'Back up project layers',
              icon: busy ? Icons.hourglass_top : Icons.backup_outlined,
              onPressed: onBackup,
            ),
            if (onClose != null)
              _CompactIconButton(
                tooltip: 'Close Layer Manager',
                icon: Icons.close,
                onPressed: onClose,
              ),
          ],
        ),
      ),
    );
  }
}

class _CompactSectionLabel extends StatelessWidget {
  const _CompactSectionLabel({required this.label, required this.countLabel});

  final String label;
  final String countLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ),
        Text(
          countLabel,
          style: theme.textTheme.labelSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _DesktopDrawSessionCard extends StatelessWidget {
  const _DesktopDrawSessionCard({
    required this.activeTool,
    required this.hasEditableLayer,
    required this.activeLayerName,
    required this.onToolChanged,
  });

  final agus_maps_flutter.AgusDrawTool activeTool;
  final bool hasEditableLayer;
  final String activeLayerName;
  final ValueChanged<agus_maps_flutter.AgusDrawTool>? onToolChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(4),
        color: colorScheme.surfaceContainerLowest,
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Edit session',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              activeLayerName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                _DrawToolChip(
                  label: 'Map',
                  icon: Icons.pan_tool_alt_outlined,
                  tool: agus_maps_flutter.AgusDrawTool.none,
                  activeTool: activeTool,
                  enabled: true,
                  onToolChanged: onToolChanged,
                ),
                _DrawToolChip(
                  label: 'Point',
                  icon: Icons.add_location_alt_outlined,
                  tool: agus_maps_flutter.AgusDrawTool.pin,
                  activeTool: activeTool,
                  enabled: hasEditableLayer,
                  onToolChanged: onToolChanged,
                ),
                _DrawToolChip(
                  label: 'Segment',
                  icon: Icons.linear_scale,
                  tool: agus_maps_flutter.AgusDrawTool.segment,
                  activeTool: activeTool,
                  enabled: hasEditableLayer,
                  onToolChanged: onToolChanged,
                ),
                _DrawToolChip(
                  label: 'Line',
                  icon: Icons.timeline,
                  tool: agus_maps_flutter.AgusDrawTool.line,
                  activeTool: activeTool,
                  enabled: hasEditableLayer,
                  onToolChanged: onToolChanged,
                ),
                _DrawToolChip(
                  label: 'Polygon',
                  icon: Icons.polyline_outlined,
                  tool: agus_maps_flutter.AgusDrawTool.polygon,
                  activeTool: activeTool,
                  enabled: hasEditableLayer,
                  onToolChanged: onToolChanged,
                ),
              ],
            ),
            if (!hasEditableLayer) ...[
              const SizedBox(height: 6),
              Text(
                'Create or select a project layer before drawing.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DrawToolChip extends StatelessWidget {
  const _DrawToolChip({
    required this.label,
    required this.icon,
    required this.tool,
    required this.activeTool,
    required this.enabled,
    required this.onToolChanged,
  });

  final String label;
  final IconData icon;
  final agus_maps_flutter.AgusDrawTool tool;
  final agus_maps_flutter.AgusDrawTool activeTool;
  final bool enabled;
  final ValueChanged<agus_maps_flutter.AgusDrawTool>? onToolChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selected = activeTool == tool;
    final foreground = !enabled
        ? colorScheme.onSurfaceVariant.withValues(alpha: 0.55)
        : selected
            ? colorScheme.onPrimaryContainer
            : colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: enabled ? () => onToolChanged?.call(tool) : null,
      borderRadius: BorderRadius.circular(4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? colorScheme.primaryContainer : colorScheme.surface,
          border: Border.all(
            color: selected ? colorScheme.primary : colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: foreground),
              const SizedBox(width: 4),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: foreground,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactSwitch extends StatelessWidget {
  const _CompactSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return CompactBooleanToggle(
      value: value,
      onChanged: onChanged,
    );
  }
}

class _CompactIconButton extends StatelessWidget {
  const _CompactIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selected = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 16),
      selectedIcon: Icon(icon, size: 16, color: colorScheme.primary),
      isSelected: selected,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 26, height: 26),
      onPressed: onPressed,
    );
  }
}

class _LayerTreeGroup extends StatelessWidget {
  const _LayerTreeGroup({
    required this.nodeId,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.countLabel,
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  final String nodeId;
  final String title;
  final String subtitle;
  final IconData icon;
  final String countLabel;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.65),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: Row(
                children: [
                  Icon(icon, color: colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _CountChip(label: countLabel),
                  const SizedBox(width: 6),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            Divider(
              height: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.7),
            ),
            child,
          ],
        ],
      ),
    );
  }
}

class _TreeToggleRow extends StatelessWidget {
  const _TreeToggleRow({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.onChanged,
    required this.padding,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox.adaptive(
            value: value,
            onChanged: (nextValue) => onChanged(nextValue ?? false),
          ),
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Icon(icon, size: 20, color: colorScheme.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StoredLayerNode extends StatelessWidget {
  const _StoredLayerNode({
    required this.layer,
    required this.features,
    required this.compact,
    required this.expanded,
    required this.padding,
    required this.onToggleExpanded,
    required this.onVisibleChanged,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final agus_maps_flutter.AgusLayer layer;
  final List<agus_maps_flutter.AgusLayerFeature> features;
  final bool compact;
  final bool expanded;
  final EdgeInsets padding;
  final VoidCallback onToggleExpanded;
  final ValueChanged<bool> onVisibleChanged;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final featurePreview = features.take(4).toList(growable: false);
    final hasChildren = features.isNotEmpty;

    return Column(
      children: [
        Padding(
          padding: padding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasChildren)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: IconButton(
                    visualDensity: compact
                        ? VisualDensity.compact
                        : VisualDensity.standard,
                    onPressed: onToggleExpanded,
                    icon: Icon(
                      expanded ? Icons.expand_more : Icons.chevron_right,
                    ),
                    tooltip: expanded ? 'Collapse layer' : 'Expand layer',
                  ),
                )
              else
                const SizedBox(width: 40),
              Checkbox.adaptive(
                value: layer.visible,
                onChanged: (value) => onVisibleChanged(value ?? false),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Icon(
                  _layerIcon(layer.kind),
                  size: 20,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          layer.name,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        _BadgeChip(label: _kindLabel(layer.kind)),
                        _BadgeChip(label: '${features.length} features'),
                        if (layer.locked) const _BadgeChip(label: 'Locked'),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'z-index ${layer.zIndex}'
                      '${_zoomRangeLabel(layer)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    visualDensity: compact
                        ? VisualDensity.compact
                        : VisualDensity.standard,
                    tooltip: 'Raise layer',
                    onPressed: onMoveUp,
                    icon: const Icon(Icons.keyboard_arrow_up),
                  ),
                  IconButton(
                    visualDensity: compact
                        ? VisualDensity.compact
                        : VisualDensity.standard,
                    tooltip: 'Lower layer',
                    onPressed: onMoveDown,
                    icon: const Icon(Icons.keyboard_arrow_down),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (expanded) ...[
          for (final feature in featurePreview)
            _FeatureTreeLeaf(
              feature: feature,
              padding: EdgeInsets.fromLTRB(
                padding.left + 68,
                0,
                padding.right,
                compact ? 8 : 10,
              ),
            ),
          if (features.length > featurePreview.length)
            Padding(
              padding: EdgeInsets.fromLTRB(
                padding.left + 68,
                0,
                padding.right,
                compact ? 8 : 12,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '+${features.length - featurePreview.length} more features',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }

  String _zoomRangeLabel(agus_maps_flutter.AgusLayer layer) {
    if (layer.minZoom == null && layer.maxZoom == null) {
      return '';
    }
    return ' · zoom ${layer.minZoom ?? 0}-${layer.maxZoom ?? '∞'}';
  }

  String _kindLabel(agus_maps_flutter.AgusLayerKind kind) {
    return switch (kind) {
      agus_maps_flutter.AgusLayerKind.nativeMwm => 'Native',
      agus_maps_flutter.AgusLayerKind.userDraw => 'User draw',
      agus_maps_flutter.AgusLayerKind.comapsSupported => 'Preset',
      agus_maps_flutter.AgusLayerKind.duckdbQuery => 'Query',
    };
  }

  IconData _layerIcon(agus_maps_flutter.AgusLayerKind kind) {
    return switch (kind) {
      agus_maps_flutter.AgusLayerKind.nativeMwm => Icons.public_outlined,
      agus_maps_flutter.AgusLayerKind.userDraw => Icons.draw_outlined,
      agus_maps_flutter.AgusLayerKind.comapsSupported => Icons.explore_outlined,
      agus_maps_flutter.AgusLayerKind.duckdbQuery => Icons.storage_outlined,
    };
  }
}

class _FeatureTreeLeaf extends StatelessWidget {
  const _FeatureTreeLeaf({
    required this.feature,
    required this.padding,
  });

  final agus_maps_flutter.AgusLayerFeature feature;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: colorScheme.secondary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _featureTitle(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_geometryLabel()} · ${feature.featureId}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _featureTitle() {
    final title = feature.properties['title'];
    if (title is String && title.trim().isNotEmpty) {
      return title.trim();
    }
    final note = feature.properties['note'];
    if (note is String && note.trim().isNotEmpty) {
      return note.trim();
    }
    return 'Untitled feature';
  }

  String _geometryLabel() {
    return switch (feature.geometryKind) {
      agus_maps_flutter.AgusGeometryKind.point => 'Point',
      agus_maps_flutter.AgusGeometryKind.line => 'Line',
      agus_maps_flutter.AgusGeometryKind.segment => 'Segment',
      agus_maps_flutter.AgusGeometryKind.polygon => 'Polygon',
      agus_maps_flutter.AgusGeometryKind.multipoint => 'Multi-point',
      agus_maps_flutter.AgusGeometryKind.multiline => 'Multi-line',
      agus_maps_flutter.AgusGeometryKind.multipolygon => 'Multi-polygon',
      agus_maps_flutter.AgusGeometryKind.collection => 'Collection',
    };
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}

class _BadgeChip extends StatelessWidget {
  const _BadgeChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
        ),
      ),
    );
  }
}

class _InlineInfoBanner extends StatelessWidget {
  const _InlineInfoBanner({
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
