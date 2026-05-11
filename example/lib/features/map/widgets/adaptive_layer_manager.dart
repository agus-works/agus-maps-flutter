import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'package:agus_design/agus_design.dart';
import 'package:agus_maps_flutter/agus_maps_flutter.dart' as agus_maps_flutter;

import '../../../shared/adaptive/form_factor.dart';
import '../../../shared/widgets/panel_surface.dart';

@immutable
class MwmLayerInfo {
  const MwmLayerInfo({
    required this.regionName,
    required this.snapshotVersion,
    required this.fileSize,
    required this.filePath,
    required this.isBundled,
    this.visible = true,
    this.isActive = true,
  });

  final String regionName;
  final String snapshotVersion;
  final int fileSize;
  final String filePath;
  final bool isBundled;
  final bool visible;
  final bool isActive;
}

enum MwmLayerOrderMode { byMap, byDate }

/// Adaptive layer tree inspired by GIS desktop layer docks.
class AdaptiveMapPresentationPanel extends StatelessWidget {
  const AdaptiveMapPresentationPanel({
    super.key,
    required this.formFactor,
    required this.nativeLayerState,
    required this.buildings3dEnabled,
    required this.onNativeLayerStateChanged,
    required this.onBuildings3dChanged,
  });

  final ExampleFormFactor formFactor;
  final agus_maps_flutter.MapLayerState nativeLayerState;
  final bool buildings3dEnabled;
  final ValueChanged<agus_maps_flutter.MapLayerState> onNativeLayerStateChanged;
  final ValueChanged<bool> onBuildings3dChanged;

  @override
  Widget build(BuildContext context) {
    if (formFactor.isDesktop) {
      return ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child: ListView(
          padding: const EdgeInsets.all(8),
          children: [
            _CompactSectionLabel(
              label: 'Map presentation',
              countLabel:
                  '${_enabledNativeLayerCount(nativeLayerState, buildings3dEnabled)} / 4',
            ),
            const SizedBox(height: 6),
            _MapPresentationPropertyGrid(
              nativeLayerState: nativeLayerState,
              buildings3dEnabled: buildings3dEnabled,
              onNativeLayerStateChanged: onNativeLayerStateChanged,
              onBuildings3dChanged: onBuildings3dChanged,
            ),
          ],
        ),
      );
    }

    final uiSpec = context.exampleUiSpec;
    return PanelSurface(
      title: 'Map presentation',
      subtitle: 'Basemap overlays and visibility profile',
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TreeToggleRow(
            label: '3D buildings',
            subtitle: 'Scene depth for city-scale map views',
            icon: Icons.apartment_outlined,
            value: buildings3dEnabled,
            onChanged: onBuildings3dChanged,
            padding: uiSpec.treeRowPadding,
          ),
          _TreeToggleRow(
            label: 'Outdoors',
            subtitle: 'Terrain-driven cartography and hiking emphasis',
            icon: Icons.terrain_outlined,
            value: nativeLayerState.outdoors,
            onChanged: (enabled) {
              onNativeLayerStateChanged(
                nativeLayerState.copyWith(
                  outdoors: enabled,
                  subway: enabled ? false : nativeLayerState.subway,
                ),
              );
            },
            padding: uiSpec.treeRowPadding,
          ),
          _TreeToggleRow(
            label: 'Contour lines',
            subtitle: 'Elevation isolines for terrain reading',
            icon: Icons.landscape_outlined,
            value: nativeLayerState.isolines,
            onChanged: (enabled) {
              onNativeLayerStateChanged(
                nativeLayerState.copyWith(
                  isolines: enabled,
                  subway: enabled ? false : nativeLayerState.subway,
                ),
              );
            },
            padding: uiSpec.treeRowPadding,
          ),
          _TreeToggleRow(
            label: 'Subway',
            subtitle: 'Transit-emphasis cartography',
            icon: Icons.directions_subway_outlined,
            value: nativeLayerState.subway,
            onChanged: (enabled) {
              onNativeLayerStateChanged(
                nativeLayerState.copyWith(
                  outdoors: enabled ? false : nativeLayerState.outdoors,
                  isolines: enabled ? false : nativeLayerState.isolines,
                  subway: enabled,
                ),
              );
            },
            padding: uiSpec.treeRowPadding,
          ),
        ],
      ),
    );
  }
}

class _MapPresentationPropertyGrid extends StatelessWidget {
  const _MapPresentationPropertyGrid({
    required this.nativeLayerState,
    required this.buildings3dEnabled,
    required this.onNativeLayerStateChanged,
    required this.onBuildings3dChanged,
  });

  final agus_maps_flutter.MapLayerState nativeLayerState;
  final bool buildings3dEnabled;
  final ValueChanged<agus_maps_flutter.MapLayerState> onNativeLayerStateChanged;
  final ValueChanged<bool> onBuildings3dChanged;

  @override
  Widget build(BuildContext context) {
    return AgusPropertyGrid(
      rows: [
        AgusPropertyRow(
          name: '3D buildings',
          value: _CompactSwitch(
            value: buildings3dEnabled,
            onChanged: onBuildings3dChanged,
          ),
        ),
        AgusPropertyRow(
          name: 'Outdoors',
          value: _CompactSwitch(
            value: nativeLayerState.outdoors,
            onChanged: (enabled) {
              onNativeLayerStateChanged(
                nativeLayerState.copyWith(
                  outdoors: enabled,
                  subway: enabled ? false : nativeLayerState.subway,
                ),
              );
            },
          ),
        ),
        AgusPropertyRow(
          name: 'Contour lines',
          value: _CompactSwitch(
            value: nativeLayerState.isolines,
            onChanged: (enabled) {
              onNativeLayerStateChanged(
                nativeLayerState.copyWith(
                  isolines: enabled,
                  subway: enabled ? false : nativeLayerState.subway,
                ),
              );
            },
          ),
        ),
        AgusPropertyRow(
          name: 'Subway',
          value: _CompactSwitch(
            value: nativeLayerState.subway,
            onChanged: (enabled) {
              onNativeLayerStateChanged(
                nativeLayerState.copyWith(
                  outdoors: enabled ? false : nativeLayerState.outdoors,
                  isolines: enabled ? false : nativeLayerState.isolines,
                  subway: enabled,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

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
    this.onActiveFeatureChanged,
    this.onDrawToolChanged,
    this.onEditFeature,
    this.layerStoreStatus,
    this.layerStoreRevision = 0,
    this.mwmLayers = const <MwmLayerInfo>[],
    this.mwmLayerOrderMode = MwmLayerOrderMode.byMap,
    this.onMwmLayerVisibilityChanged,
    this.onMwmLayerDeleted,
    this.onMwmLayerUpdated,
    this.onMwmLayerFocused,
    this.onMwmLayerOrderChanged,
    this.onProjectLayerFocused,
    this.onFeatureFocused,
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
  final ValueChanged<agus_maps_flutter.AgusLayerFeature?>?
      onActiveFeatureChanged;
  final ValueChanged<agus_maps_flutter.AgusDrawTool>? onDrawToolChanged;
  final ValueChanged<agus_maps_flutter.AgusLayerFeature>? onEditFeature;
  final String? layerStoreStatus;
  final int layerStoreRevision;
  final List<MwmLayerInfo> mwmLayers;
  final MwmLayerOrderMode mwmLayerOrderMode;
  final void Function(String regionName, bool visible)?
      onMwmLayerVisibilityChanged;
  final ValueChanged<MwmLayerInfo>? onMwmLayerDeleted;
  final ValueChanged<MwmLayerInfo>? onMwmLayerUpdated;
  final ValueChanged<MwmLayerInfo>? onMwmLayerFocused;
  final ValueChanged<MwmLayerOrderMode>? onMwmLayerOrderChanged;
  final ValueChanged<String>? onProjectLayerFocused;
  final ValueChanged<agus_maps_flutter.AgusLayerFeature>? onFeatureFocused;
  final VoidCallback? onClose;

  @override
  State<AdaptiveLayerManager> createState() => _AdaptiveLayerManagerState();
}

class _AdaptiveLayerManagerState extends State<AdaptiveLayerManager> {
  final Set<String> _expandedNodes = <String>{
    _projectLayersNodeId,
  };

  List<agus_maps_flutter.AgusLayer> _layers =
      const <agus_maps_flutter.AgusLayer>[];
  Map<String, List<agus_maps_flutter.AgusLayerFeature>> _featuresByLayer =
      const <String, List<agus_maps_flutter.AgusLayerFeature>>{};
  List<AgusTreeColumn> _desktopLayerColumns = const [
    AgusTreeColumn(id: 'kind', label: 'Kind', width: 82),
    AgusTreeColumn(id: 'features', label: 'Features', width: 72),
    AgusTreeColumn(id: 'z', label: 'Z', width: 52),
  ];
  String? _selectedFeatureKey;
  String _message = '';
  bool _busy = false;

  static const String _projectLayersNodeId = 'project-layers';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant AdaptiveLayerManager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.layerStore != widget.layerStore ||
        oldWidget.layerStoreRevision != widget.layerStoreRevision) {
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

  void _selectFeature(agus_maps_flutter.AgusLayerFeature feature) {
    widget.onActiveLayerChanged?.call(feature.layerId);
    widget.onActiveFeatureChanged?.call(feature);
    setState(() {
      _selectedFeatureKey = _featureKey(feature);
      _message =
          feature.geometryKind == agus_maps_flutter.AgusGeometryKind.point
              ? 'Selected point. Use Move to reposition it on the map.'
              : 'Selected ${_geometryKindLabel(feature.geometryKind)} feature.';
    });
  }

  Future<void> _startFeatureForLayer(String layerId) async {
    widget.onActiveLayerChanged?.call(layerId);
    final tool = await _showDrawToolPicker(context);
    if (tool == null) return;
    widget.onDrawToolChanged?.call(tool);
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
    try {
      store.setLayerVisibility(layer.layerId, visible);
      await widget.onRenderingRefresh?.call();
      await _reload();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = 'Layer visibility update failed: $error';
      });
    }
  }

  Future<void> _moveLayer(
    agus_maps_flutter.AgusLayer layer,
    int delta,
  ) async {
    final store = widget.layerStore;
    if (store == null) return;
    try {
      store.setLayerZIndex(layer.layerId, layer.zIndex + delta);
      await widget.onRenderingRefresh?.call();
      await _reload();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = 'Layer order update failed: $error';
      });
    }
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

    // Clear focus center cache before deleting
    store.clearLayerFocusCenter(layer.layerId);

    store.deleteLayer(layer.layerId);
    if (widget.activeLayerId == layer.layerId) {
      final remainingLayers = store.listLayers();
      if (remainingLayers.isNotEmpty) {
        widget.onActiveLayerChanged?.call(remainingLayers.first.layerId);
      } else {
        widget.onActiveFeatureChanged?.call(null);
      }
    }
    await widget.onRenderingRefresh?.call();
    await _reload();
  }

  Future<void> _focusOnLayer(String layerId) async {
    final store = widget.layerStore;
    if (store == null) return;

    try {
      // Try to get cached focus center from DuckDB
      final cached = store.getLayerFocusCenter(layerId);
      if (cached != null) {
        widget.onProjectLayerFocused?.call(layerId);
        setState(() {
          _message = 'Focused on layer (cached center)';
        });
        return;
      }

      // Fallback: calculate from layer features' bounding boxes
      final features = store.listFeatures(layerId);
      if (features.isEmpty) {
        setState(() {
          _message = 'Cannot focus: layer has no features';
        });
        return;
      }

      // Calculate center from all feature bounding boxes
      double? minLon, minLat, maxLon, maxLat;
      for (final feature in features) {
        final bbox = feature.boundingBox;
        if (bbox == null) continue;
        minLon = minLon == null ? bbox.minLon : min(minLon, bbox.minLon);
        minLat = minLat == null ? bbox.minLat : min(minLat, bbox.minLat);
        maxLon = maxLon == null ? bbox.maxLon : max(maxLon, bbox.maxLon);
        maxLat = maxLat == null ? bbox.maxLat : max(maxLat, bbox.maxLat);
      }

      if (minLon == null || minLat == null || maxLon == null || maxLat == null) {
        setState(() {
          _message = 'Cannot focus: no valid bounding boxes';
        });
        return;
      }

      final centerLon = (minLon + maxLon) / 2;
      final centerLat = (minLat + maxLat) / 2;

      // Cache the calculated center
      store.setLayerFocusCenter(layerId, centerLon, centerLat);

      widget.onProjectLayerFocused?.call(layerId);
      setState(() {
        _message = 'Focused on layer (calculated center)';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = 'Focus failed: $error';
      });
    }
  }

  Future<void> _focusOnFeature(
      agus_maps_flutter.AgusLayerFeature feature) async {
    final store = widget.layerStore;
    if (store == null) return;

    try {
      // Try to get cached focus center from DuckDB
      final cached = store.getFeatureFocusCenter(feature.layerId, feature.featureId);
      if (cached != null) {
        widget.onFeatureFocused?.call(feature);
        setState(() {
          _message = 'Focused on feature (cached center)';
        });
        return;
      }

      // Fallback: calculate from feature bounding box
      final bbox = feature.boundingBox;
      if (bbox == null) {
        setState(() {
          _message = 'Cannot focus: feature has no bounding box';
        });
        return;
      }

      final centerLon = (bbox.minLon + bbox.maxLon) / 2;
      final centerLat = (bbox.minLat + bbox.maxLat) / 2;

      // Cache the calculated center
      store.setFeatureFocusCenter(feature.layerId, feature.featureId, centerLon, centerLat);

      widget.onFeatureFocused?.call(feature);
      setState(() {
        _message = 'Focused on feature (calculated center)';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = 'Focus failed: $error';
      });
    }
  }

  Future<void> _createLayer() async {
    final store = widget.layerStore;
    if (store == null || _busy) return;

    final result = await _showLayerNamePrompt(
      context,
      initialValue: 'Drawing layer ${_layers.length + 1}',
    );
    if (!mounted) return;

    final name = result?.trim();
    if (name == null || name.isEmpty) return;

    setState(() {
      _busy = true;
      _message = '';
    });

    try {
      final id = _layerIdFromName(name);
      final zIndex = _layers.isEmpty
          ? 1000
          : _layers
                  .map((layer) => layer.zIndex)
                  .reduce((a, b) => a > b ? a : b) +
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
      if (!mounted) return;
      setState(() {
        _message = 'Created layer "$name".';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = 'Layer creation failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
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

    if (widget.formFactor.isMobile) {
      return _buildMobileLayerManager(context, projectLayerCount);
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
            nodeId: _projectLayersNodeId,
            title: 'Project layers',
            subtitle: widget.layerStore == null
                ? widget.layerStoreStatus ??
                    'DuckDB-backed drawing layers are starting.'
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
                          ? widget.layerStoreStatus ??
                              'Map presentation controls work now. Project data layers appear once the DuckDB store is active.'
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
                          active: layer.layerId == widget.activeLayerId,
                          expanded:
                              _expandedNodes.contains('layer:${layer.layerId}'),
                          padding: uiSpec.treeRowPadding,
                          selectedFeatureKey: _selectedFeatureKey,
                          onToggleExpanded: () =>
                              _toggleNode('layer:${layer.layerId}'),
                          onFeatureSelected: _selectFeature,
                          onEditFeature: widget.onEditFeature,
                          onVisibleChanged: (value) {
                            unawaited(_toggleStoredLayer(layer, value));
                          },
                          onMoveUp: () => unawaited(_moveLayer(layer, 1)),
                          onMoveDown: () => unawaited(_moveLayer(layer, -1)),
                          onActivateLayer: () =>
                              widget.onActiveLayerChanged?.call(layer.layerId),
                          onDelete: () => unawaited(_deleteLayer(layer)),
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
    final mwmLayerCount = widget.mwmLayers.length;

    return ColoredBox(
      color: colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CompactLayerToolbar(
            title: 'Layer Manager',
            subtitle: storeReady
                ? '$projectLayerCount project layers'
                : widget.layerStoreStatus ?? 'DuckDB layer store is starting',
            busy: _busy,
            onRefresh: _reload,
            onBackup: storeReady && !_busy ? _backup : null,
            onCreateLayer: storeReady ? _createLayer : null,
            onClose: widget.onClose,
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(8),
              child: AgusViewContainer(
                views: [
                  AgusView(
                    id: _projectLayersNodeId,
                    title: 'Project Layers',
                    icon: Icons.layers_outlined,
                    countLabel: '$projectLayerCount',
                    actions: [
                      IconButton(
                        tooltip: 'Create drawing layer',
                        onPressed: storeReady ? _createLayer : null,
                        icon: const Icon(Icons.add, size: 16),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 28,
                          height: 24,
                        ),
                      ),
                    ],
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _DesktopDrawSessionCard(
                            activeTool: widget.activeDrawTool ??
                                agus_maps_flutter.AgusDrawTool.none,
                            hasEditableLayer: _layers.any(
                              (layer) => layer.layerId == widget.activeLayerId,
                            ),
                            activeLayerName: _activeLayerName(),
                          ),
                        ),
                        _buildDesktopLayerGrid(context),
                      ],
                    ),
                  ),
                  AgusView(
                    id: 'mwm-maps',
                    title: 'MWM Maps',
                    icon: Icons.public,
                    countLabel: '$mwmLayerCount',
                    actions: [
                      AgusButton.icon(
                        icon:
                            widget.mwmLayerOrderMode == MwmLayerOrderMode.byMap
                                ? Icons.sort_by_alpha
                                : Icons.calendar_month_outlined,
                        tooltip:
                            widget.mwmLayerOrderMode == MwmLayerOrderMode.byMap
                                ? 'Order MWM maps by date'
                                : 'Order MWM maps by map',
                        onPressed: widget.onMwmLayerOrderChanged == null
                            ? null
                            : () {
                                widget.onMwmLayerOrderChanged!(
                                  widget.mwmLayerOrderMode ==
                                          MwmLayerOrderMode.byMap
                                      ? MwmLayerOrderMode.byDate
                                      : MwmLayerOrderMode.byMap,
                                );
                              },
                      ),
                    ],
                    child: _buildDesktopMwmLayerGrid(context),
                  ),
                  if (_message.isNotEmpty)
                    AgusView(
                      id: 'layer-status',
                      title: 'Status',
                      icon: Icons.info_outline,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          _message,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayerManager(BuildContext context, int projectLayerCount) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final activeTool =
        widget.activeDrawTool ?? agus_maps_flutter.AgusDrawTool.none;
    final storeReady = widget.layerStore != null;

    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.75),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 24,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Column(
                  children: [
                    Center(
                      child: Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: colorScheme.outlineVariant,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Layers',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                storeReady
                                    ? '$projectLayerCount layers - map stays live behind this panel'
                                    : widget.layerStoreStatus ??
                                        'DuckDB layer store is starting',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Refresh layers',
                          onPressed: _reload,
                          icon: const Icon(Icons.refresh),
                        ),
                        IconButton(
                          tooltip: 'Close layers',
                          onPressed: widget.onClose,
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: storeReady && !_busy ? _createLayer : null,
                        icon: const Icon(Icons.add),
                        label: const Text('New layer'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: 'Back up project layers',
                      onPressed: storeReady && !_busy ? _backup : null,
                      icon: _busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.backup_outlined),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: _MobileDrawSessionCard(
                  activeTool: activeTool,
                  hasEditableLayer: _layers.any(
                    (layer) => layer.layerId == widget.activeLayerId,
                  ),
                  activeLayerName: _activeLayerName(),
                  onToolChanged: widget.onDrawToolChanged,
                ),
              ),
              if (_message.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    _message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              Expanded(
                child: projectLayerCount == 0
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: _InlineInfoBanner(
                          icon: storeReady
                              ? Icons.add_location_alt_outlined
                              : Icons.info_outline,
                          message: storeReady
                              ? 'Create a layer, choose it as the edit layer, then add point, line, segment, or polygon features on the map.'
                              : widget.layerStoreStatus ??
                                  'Project layers appear once the DuckDB store is active.',
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 18),
                        itemCount: _layers.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final layer = _layers[index];
                          final features = _featuresByLayer[layer.layerId] ??
                              const <agus_maps_flutter.AgusLayerFeature>[];
                          return _MobileLayerCard(
                            layer: layer,
                            features: features,
                            active: layer.layerId == widget.activeLayerId,
                            expanded: _expandedNodes.contains(
                              'layer:${layer.layerId}',
                            ),
                            selectedFeatureKey: _selectedFeatureKey,
                            onToggleExpanded: () =>
                                _toggleNode('layer:${layer.layerId}'),
                            onActivateLayer: () =>
                                widget.onActiveLayerChanged?.call(
                              layer.layerId,
                            ),
                            onAddFeature: () => unawaited(
                              _startFeatureForLayer(layer.layerId),
                            ),
                            onFeatureSelected: _selectFeature,
                            onEditFeature: widget.onEditFeature,
                            onVisibleChanged: (value) {
                              unawaited(_toggleStoredLayer(layer, value));
                            },
                            onMoveUp: () => unawaited(_moveLayer(layer, 1)),
                            onMoveDown: () => unawaited(_moveLayer(layer, -1)),
                            onDelete: () => unawaited(_deleteLayer(layer)),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopLayerGrid(BuildContext context) {
    if (_layers.isEmpty) {
      return AgusEmptyState(
        icon: widget.layerStore == null
            ? Icons.info_outline
            : Icons.add_location_alt_outlined,
        title: widget.layerStore == null ? 'Layer store starting' : 'No layers',
        message: widget.layerStore == null
            ? widget.layerStoreStatus ??
                'Project data layers appear once the DuckDB store is active.'
            : 'Create a Drawing Layer to start editing.',
      );
    }

    return SizedBox(
      height: 280,
      child: AgusTreeView(
        labelColumnTitle: 'Layer',
        labelColumnWidth: 170,
        minLabelColumnWidth: 120,
        selectedId: _selectedFeatureKey ??
            (widget.activeLayerId == null
                ? null
                : 'layer:${widget.activeLayerId}'),
        expandedIds: _expandedNodes,
        columns: _desktopLayerColumns,
        nodes: _desktopLayerTreeNodes(),
        onSelected: _selectDesktopLayerTreeNode,
        onToggle: _toggleNode,
        onColumnReorder: (columns) {
          setState(() => _desktopLayerColumns = columns);
        },
        onContextMenuRequested: _showDesktopLayerTreeContextMenu,
        onVisibilityChanged: (id, visibility) {
          unawaited(_setDesktopLayerVisibility(id, visibility));
        },
      ),
    );
  }

  Widget _buildDesktopMwmLayerGrid(BuildContext context) {
    if (widget.mwmLayers.isEmpty) {
      return const AgusEmptyState(
        icon: Icons.public,
        title: 'No MWM layers',
        message:
            'Downloaded and bundled CoMaps MWM files appear here after registration.',
      );
    }

    // Group layers by region
    final Map<String, List<MwmLayerInfo>> layersByRegion = {};
    for (final layer in widget.mwmLayers) {
      layersByRegion.putIfAbsent(layer.regionName, () => []).add(layer);
    }

    // Sort versions within each region (newest first)
    for (final versions in layersByRegion.values) {
      versions.sort(
        (a, b) => b.snapshotVersion.compareTo(a.snapshotVersion),
      );
    }

    // Get ordered region names
    final orderedRegions = layersByRegion.keys.toList();
    // Keep them in the order they appear in mwmLayers (already sorted by mode)
    orderedRegions.sort((a, b) {
      final aFirst = widget.mwmLayers.indexWhere((l) => l.regionName == a);
      final bFirst = widget.mwmLayers.indexWhere((l) => l.regionName == b);
      return aFirst.compareTo(bFirst);
    });

    return SizedBox(
      height: 220,
      child: AgusTreeView(
        labelColumnTitle: 'Map',
        labelColumnWidth: 190,
        minLabelColumnWidth: 140,
        columns: const [
          AgusTreeColumn(id: 'source', label: 'Source', width: 86),
          AgusTreeColumn(id: 'size', label: 'Size', width: 70),
          AgusTreeColumn(id: 'version', label: 'Version', width: 86),
        ],
        expandedIds: {
          for (final regionName in orderedRegions) 'mwm:$regionName',
        },
        nodes: [
          for (final regionName in orderedRegions)
            () {
              final versions = layersByRegion[regionName]!;
              final activeVersion =
                  versions.firstWhere((l) => l.isActive, orElse: () => versions.first);
              return AgusTreeNode(
                id: 'mwm:$regionName',
                label: regionName,
                icon: Icons.map_outlined,
                expanded: true,
                visibility: activeVersion.isBundled
                    ? AgusTreeVisibilityState.locked
                    : activeVersion.visible
                        ? AgusTreeVisibilityState.visible
                        : AgusTreeVisibilityState.hidden,
                badgeLabel: activeVersion.isBundled ? 'BUNDLED' : 'DOWNLOADED',
                columnValues: {
                  'source': activeVersion.isBundled ? 'Bundled' : 'Local',
                  'size': _formatBytes(activeVersion.fileSize),
                  'version': activeVersion.snapshotVersion,
                },
                children: [
                  for (final version in versions)
                    AgusTreeNode(
                      id: 'mwm:${version.regionName}:${version.snapshotVersion}',
                      label: version.snapshotVersion,
                      icon: Icons.calendar_month_outlined,
                      visibility: version.isBundled
                          ? AgusTreeVisibilityState.locked
                          : version.visible
                              ? AgusTreeVisibilityState.visible
                              : AgusTreeVisibilityState.hidden,
                      badgeLabel: version.isActive ? 'ACTIVE' : null,
                      columnValues: {
                        'source': version.isBundled ? 'Bundled' : 'Downloaded',
                        'size': _formatBytes(version.fileSize),
                        'version': version.snapshotVersion,
                      },
                    ),
                ],
              );
            }(),
        ],
        onContextMenuRequested: _showDesktopMwmLayerContextMenu,
        onVisibilityChanged: (id, visibility) {
          final layer = _mwmLayerFromTreeId(id);
          if (layer == null) return;
          widget.onMwmLayerVisibilityChanged?.call(
            layer.regionName,
            visibility == AgusTreeVisibilityState.visible,
          );
        },
      ),
    );
  }

  MwmLayerInfo? _mwmLayerFromTreeId(String id) {
    if (!id.startsWith('mwm:')) return null;
    final parts = id.split(':');
    if (parts.length < 2) return null;
    final regionName = parts[1];
    for (final layer in widget.mwmLayers) {
      if (layer.regionName == regionName) return layer;
    }
    return null;
  }

  List<AgusTreeNode> _desktopLayerTreeNodes() {
    return [
      for (final layer in _layers)
        AgusTreeNode(
          id: 'layer:${layer.layerId}',
          label: layer.name,
          icon: Icons.layers_outlined,
          expanded: _expandedNodes.contains('layer:${layer.layerId}'),
          visibility: layer.locked
              ? AgusTreeVisibilityState.locked
              : layer.visible
                  ? AgusTreeVisibilityState.visible
                  : AgusTreeVisibilityState.hidden,
          badgeLabel: layer.layerId == widget.activeLayerId ? 'ACTIVE' : null,
          columnValues: {
            'kind': _layerKindLabel(layer.kind),
            'features': '${_featuresByLayer[layer.layerId]?.length ?? 0}',
            'z': '${layer.zIndex}',
          },
          children: [
            for (final feature in _featuresByLayer[layer.layerId] ??
                const <agus_maps_flutter.AgusLayerFeature>[])
              AgusTreeNode(
                id: _featureKey(feature),
                label: _featureLabel(feature),
                icon: _featureIcon(feature.geometryKind),
                columnValues: {
                  'kind': _geometryKindLabel(feature.geometryKind),
                  'features': '1',
                  'z': '${feature.zIndex ?? layer.zIndex}',
                },
              ),
          ],
        ),
    ];
  }

  void _selectDesktopLayerTreeNode(String id) {
    if (id.startsWith('layer:')) {
      final layerId = id.substring('layer:'.length);
      widget.onActiveLayerChanged?.call(layerId);
      setState(() => _selectedFeatureKey = null);
      return;
    }

    for (final features in _featuresByLayer.values) {
      for (final feature in features) {
        if (_featureKey(feature) == id) {
          _selectFeature(feature);
          return;
        }
      }
    }
  }

  Future<void> _setDesktopLayerVisibility(
    String id,
    AgusTreeVisibilityState visibility,
  ) async {
    if (!id.startsWith('layer:')) return;
    final layerId = id.substring('layer:'.length);
    agus_maps_flutter.AgusLayer? layer;
    for (final candidate in _layers) {
      if (candidate.layerId == layerId) {
        layer = candidate;
        break;
      }
    }
    if (layer == null || layer.locked) return;
    await _toggleStoredLayer(
        layer, visibility == AgusTreeVisibilityState.visible);
  }

  Future<void> _showDesktopLayerTreeContextMenu(
    String id,
    Offset globalPosition,
  ) async {
    final entries = _desktopLayerTreeContextMenuItems(id);
    if (entries.isEmpty) return;

    final selectedAction = await showAgusContextMenu<_DesktopLayerTreeAction>(
      context: context,
      globalPosition: globalPosition,
      entries: entries,
    );
    if (selectedAction == null) return;
    await _handleDesktopLayerTreeContextAction(id, selectedAction);
  }

  Future<void> _showDesktopMwmLayerContextMenu(
    String id,
    Offset globalPosition,
  ) async {
    final layer = _mwmLayerFromTreeId(id);
    if (layer == null) return;

    final selectedAction = await showAgusContextMenu<_MwmLayerTreeAction>(
      context: context,
      globalPosition: globalPosition,
      entries: [
        AgusContextMenuAction(
          value: _MwmLayerTreeAction.toggleVisibility,
          icon: layer.visible
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
          label: layer.isBundled
              ? 'Bundled Map Always Visible'
              : layer.visible
                  ? 'Hide Map Layer'
                  : 'Show Map Layer',
          enabled: !layer.isBundled,
        ),
        const AgusContextMenuAction(
          value: _MwmLayerTreeAction.focus,
          icon: Icons.my_location,
          label: 'Focus Map',
        ),
        const AgusContextMenuSeparator(),
        const AgusContextMenuAction(
          value: _MwmLayerTreeAction.update,
          icon: Icons.system_update_alt,
          label: 'Update from Mirror...',
        ),
        AgusContextMenuAction(
          value: _MwmLayerTreeAction.delete,
          icon: Icons.delete_outline,
          label: layer.isBundled ? 'Delete Bundled Map' : 'Delete Download',
          enabled: !layer.isBundled,
          destructive: true,
        ),
        const AgusContextMenuSeparator(),
        AgusContextMenuAction(
          value: _MwmLayerTreeAction.orderByMap,
          icon: Icons.sort_by_alpha,
          label: 'Order by Map',
          enabled: widget.mwmLayerOrderMode != MwmLayerOrderMode.byMap,
        ),
        AgusContextMenuAction(
          value: _MwmLayerTreeAction.orderByDate,
          icon: Icons.calendar_month_outlined,
          label: 'Order by Date',
          enabled: widget.mwmLayerOrderMode != MwmLayerOrderMode.byDate,
        ),
      ],
    );
    if (selectedAction == null) return;

    switch (selectedAction) {
      case _MwmLayerTreeAction.toggleVisibility:
        widget.onMwmLayerVisibilityChanged
            ?.call(layer.regionName, !layer.visible);
      case _MwmLayerTreeAction.focus:
        widget.onMwmLayerFocused?.call(layer);
      case _MwmLayerTreeAction.update:
        widget.onMwmLayerUpdated?.call(layer);
      case _MwmLayerTreeAction.delete:
        widget.onMwmLayerDeleted?.call(layer);
      case _MwmLayerTreeAction.orderByMap:
        widget.onMwmLayerOrderChanged?.call(MwmLayerOrderMode.byMap);
      case _MwmLayerTreeAction.orderByDate:
        widget.onMwmLayerOrderChanged?.call(MwmLayerOrderMode.byDate);
    }
  }

  List<AgusContextMenuEntry<_DesktopLayerTreeAction>>
      _desktopLayerTreeContextMenuItems(String id) {
    if (id.startsWith('layer:')) {
      final layer = _layerByTreeId(id);
      if (layer == null) return const [];
      return [
        const AgusContextMenuAction(
          value: _DesktopLayerTreeAction.addFeature,
          icon: Icons.add_location_alt_outlined,
          label: 'Add Feature...',
        ),
        AgusContextMenuAction(
          value: _DesktopLayerTreeAction.toggleVisibility,
          icon: layer.visible
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
          label: layer.visible ? 'Hide Layer' : 'Show Layer',
        ),
        const AgusContextMenuAction(
          value: _DesktopLayerTreeAction.focusLayer,
          icon: Icons.my_location,
          label: 'Focus Layer',
        ),
        const AgusContextMenuSeparator(),
        const AgusContextMenuAction(
          value: _DesktopLayerTreeAction.raise,
          icon: Icons.arrow_upward,
          label: 'Raise Layer',
        ),
        const AgusContextMenuAction(
          value: _DesktopLayerTreeAction.lower,
          icon: Icons.arrow_downward,
          label: 'Lower Layer',
        ),
        const AgusContextMenuSeparator(),
        const AgusContextMenuAction(
          value: _DesktopLayerTreeAction.delete,
          icon: Icons.delete_outline,
          label: 'Delete Layer',
          destructive: true,
        ),
      ];
    }

    if (_featureByTreeId(id) != null) {
      return const [
        AgusContextMenuAction(
          value: _DesktopLayerTreeAction.addFeature,
          icon: Icons.add_location_alt_outlined,
          label: 'Add Feature...',
        ),
        AgusContextMenuAction(
          value: _DesktopLayerTreeAction.editFeature,
          icon: Icons.edit_location_alt_outlined,
          label: 'Edit Feature Vertices',
        ),
        AgusContextMenuAction(
          value: _DesktopLayerTreeAction.focusFeature,
          icon: Icons.my_location,
          label: 'Focus Feature',
        ),
      ];
    }

    return const [];
  }

  Future<void> _handleDesktopLayerTreeContextAction(
    String id,
    _DesktopLayerTreeAction action,
  ) async {
    if (id.startsWith('layer:')) {
      final layer = _layerByTreeId(id);
      if (layer == null) return;
      switch (action) {
        case _DesktopLayerTreeAction.addFeature:
          await _startFeatureForLayer(layer.layerId);
        case _DesktopLayerTreeAction.focusLayer:
          await _focusOnLayer(layer.layerId);
        case _DesktopLayerTreeAction.toggleVisibility:
          await _toggleStoredLayer(layer, !layer.visible);
        case _DesktopLayerTreeAction.raise:
          await _moveLayer(layer, 1);
        case _DesktopLayerTreeAction.lower:
          await _moveLayer(layer, -1);
        case _DesktopLayerTreeAction.delete:
          await _deleteLayer(layer);
        case _DesktopLayerTreeAction.editFeature ||
              _DesktopLayerTreeAction.focusFeature:
          return;
      }
      return;
    }

    final feature = _featureByTreeId(id);
    if (feature == null) return;
    switch (action) {
      case _DesktopLayerTreeAction.addFeature:
        await _startFeatureForLayer(feature.layerId);
      case _DesktopLayerTreeAction.focusFeature:
        await _focusOnFeature(feature);
      case _DesktopLayerTreeAction.editFeature:
        _selectFeature(feature);
        widget.onEditFeature?.call(feature);
      case _DesktopLayerTreeAction.toggleVisibility ||
            _DesktopLayerTreeAction.focusLayer ||
            _DesktopLayerTreeAction.raise ||
            _DesktopLayerTreeAction.lower ||
            _DesktopLayerTreeAction.delete:
        return;
    }
  }

  agus_maps_flutter.AgusLayer? _layerByTreeId(String id) {
    if (!id.startsWith('layer:')) return null;
    final layerId = id.substring('layer:'.length);
    for (final layer in _layers) {
      if (layer.layerId == layerId) return layer;
    }
    return null;
  }

  agus_maps_flutter.AgusLayerFeature? _featureByTreeId(String id) {
    for (final features in _featuresByLayer.values) {
      for (final feature in features) {
        if (_featureKey(feature) == id) return feature;
      }
    }
    return null;
  }

  String _featureLabel(agus_maps_flutter.AgusLayerFeature feature) {
    final name = feature.properties['name'];
    if (name is String && name.trim().isNotEmpty) {
      return name.trim();
    }
    return '${_geometryKindLabel(feature.geometryKind)} ${feature.featureId}';
  }

  String _activeLayerName() {
    for (final layer in _layers) {
      if (layer.layerId == widget.activeLayerId) return layer.name;
    }
    return 'No editable layer selected';
  }
}

enum _DesktopLayerTreeAction {
  addFeature,
  editFeature,
  focusLayer,
  focusFeature,
  toggleVisibility,
  raise,
  lower,
  delete,
}

enum _MwmLayerTreeAction {
  toggleVisibility,
  focus,
  update,
  delete,
  orderByMap,
  orderByDate,
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

Future<String?> _showLayerNamePrompt(
  BuildContext context, {
  required String initialValue,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _LayerNamePromptDialog(
      initialValue: initialValue,
      fullscreen: context.exampleFormFactor.isMobile,
    ),
  );
}

Future<agus_maps_flutter.AgusDrawTool?> _showDrawToolPicker(
  BuildContext context,
) {
  return showDialog<agus_maps_flutter.AgusDrawTool>(
    context: context,
    builder: (context) => const _DrawToolPickerDialog(),
  );
}

String _drawToolName(agus_maps_flutter.AgusDrawTool tool) {
  return switch (tool) {
    agus_maps_flutter.AgusDrawTool.pin => 'point feature',
    agus_maps_flutter.AgusDrawTool.segment => 'segment feature',
    agus_maps_flutter.AgusDrawTool.line => 'line feature',
    agus_maps_flutter.AgusDrawTool.polygon => 'polygon feature',
    agus_maps_flutter.AgusDrawTool.none => 'map feature',
  };
}

class _LayerNamePromptDialog extends StatefulWidget {
  const _LayerNamePromptDialog({
    required this.initialValue,
    required this.fullscreen,
  });

  final String initialValue;
  final bool fullscreen;

  @override
  State<_LayerNamePromptDialog> createState() => _LayerNamePromptDialogState();
}

class _LayerNamePromptDialogState extends State<_LayerNamePromptDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.fullscreen) {
      return Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Create Drawing Layer'),
            leading: IconButton(
              tooltip: 'Cancel',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close),
            ),
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _LayerNamePromptBody(
                  controller: _controller,
                  autofocus: false,
                  onSubmitted: _submit,
                ),
              ],
            ),
          ),
          bottomNavigationBar: SafeArea(
            minimum: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _submit,
                  child: const Text('Create'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final size = MediaQuery.sizeOf(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final maxHeight = (size.height - viewInsets.bottom - 48)
        .clamp(
          220.0,
          420.0,
        )
        .toDouble();

    return Dialog(
      insetPadding: EdgeInsets.fromLTRB(24, 24, 24, 24 + viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 440, maxHeight: maxHeight),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          children: [
            Text(
              'Create Drawing Layer',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            _LayerNamePromptBody(
              controller: _controller,
              autofocus: true,
              onSubmitted: _submit,
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: _submit,
                    child: const Text('Create'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LayerNamePromptBody extends StatelessWidget {
  const _LayerNamePromptBody({
    required this.controller,
    required this.autofocus,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final bool autofocus;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      autofocus: autofocus,
      textCapitalization: TextCapitalization.words,
      decoration: const InputDecoration(
        labelText: 'Layer name',
        helperText: 'Creates a DuckDB-backed editable drawing layer.',
        border: OutlineInputBorder(),
      ),
      onFieldSubmitted: (_) => onSubmitted(),
    );
  }
}

class _DrawToolPickerDialog extends StatelessWidget {
  const _DrawToolPickerDialog();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final maxHeight = (size.height - 48).clamp(220.0, 420.0).toDouble();
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 420, maxHeight: maxHeight),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
              child: Text(
                'Choose feature type',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            _DrawToolListTile(
              tool: agus_maps_flutter.AgusDrawTool.pin,
              icon: Icons.add_location_alt_outlined,
              label: 'Point',
              description: 'One tapped map location.',
            ),
            _DrawToolListTile(
              tool: agus_maps_flutter.AgusDrawTool.segment,
              icon: Icons.linear_scale,
              label: 'Segment',
              description: 'Two vertices connected by a straight line.',
            ),
            _DrawToolListTile(
              tool: agus_maps_flutter.AgusDrawTool.line,
              icon: Icons.timeline,
              label: 'Line',
              description: 'Two or more vertices forming a path.',
            ),
            _DrawToolListTile(
              tool: agus_maps_flutter.AgusDrawTool.polygon,
              icon: Icons.polyline_outlined,
              label: 'Polygon',
              description: 'Three or more vertices forming a closed area.',
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawToolListTile extends StatelessWidget {
  const _DrawToolListTile({
    required this.tool,
    required this.icon,
    required this.label,
    required this.description,
  });

  final agus_maps_flutter.AgusDrawTool tool;
  final IconData icon;
  final String label;
  final String description;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(description),
      onTap: () => Navigator.of(context).pop(tool),
    );
  }
}

class _MobileDrawSessionCard extends StatelessWidget {
  const _MobileDrawSessionCard({
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
    final drawing = activeTool != agus_maps_flutter.AgusDrawTool.none;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: drawing
            ? colorScheme.primaryContainer.withValues(alpha: 0.72)
            : colorScheme.surfaceContainerHigh.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: drawing ? colorScheme.primary : colorScheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  drawing
                      ? Icons.edit_location_alt
                      : Icons.edit_location_alt_outlined,
                  color: drawing
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        drawing ? 'Drawing mode' : 'Active edit layer',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: drawing
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        activeLayerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: drawing
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!drawing)
                  _MobileDrawToolMenu(
                    enabled: hasEditableLayer,
                    onToolChanged: onToolChanged,
                  ),
              ],
            ),
            if (drawing) ...[
              const SizedBox(height: 10),
              Text(
                'Creating ${_drawToolName(activeTool)}. Tap the map to add vertices. Pan/zoom still works. Use the floating check mark or X to finish.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ] else if (!hasEditableLayer) ...[
              const SizedBox(height: 6),
              Text(
                'Create or choose a layer before adding map features.',
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

class _MobileDrawToolMenu extends StatelessWidget {
  const _MobileDrawToolMenu({
    required this.enabled,
    required this.onToolChanged,
  });

  final bool enabled;
  final ValueChanged<agus_maps_flutter.AgusDrawTool>? onToolChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PopupMenuButton<agus_maps_flutter.AgusDrawTool>(
      tooltip: 'Add feature',
      enabled: enabled && onToolChanged != null,
      onSelected: onToolChanged,
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: agus_maps_flutter.AgusDrawTool.pin,
          child: _MobileDrawToolMenuItem(
            icon: Icons.add_location_alt_outlined,
            label: 'Point',
          ),
        ),
        PopupMenuItem(
          value: agus_maps_flutter.AgusDrawTool.segment,
          child: _MobileDrawToolMenuItem(
            icon: Icons.linear_scale,
            label: 'Segment',
          ),
        ),
        PopupMenuItem(
          value: agus_maps_flutter.AgusDrawTool.line,
          child: _MobileDrawToolMenuItem(
            icon: Icons.timeline,
            label: 'Line',
          ),
        ),
        PopupMenuItem(
          value: agus_maps_flutter.AgusDrawTool.polygon,
          child: _MobileDrawToolMenuItem(
            icon: Icons.polyline_outlined,
            label: 'Polygon',
          ),
        ),
      ],
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: enabled
              ? colorScheme.primary
              : colorScheme.onSurface.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.add_location_alt_outlined,
                color: enabled
                    ? colorScheme.onPrimary
                    : colorScheme.onSurface.withValues(alpha: 0.38),
              ),
              const SizedBox(width: 8),
              Text(
                'Add',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: enabled
                          ? colorScheme.onPrimary
                          : colorScheme.onSurface.withValues(alpha: 0.38),
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileDrawToolMenuItem extends StatelessWidget {
  const _MobileDrawToolMenuItem({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Text(label),
      ],
    );
  }
}

class _MobileLayerCard extends StatelessWidget {
  const _MobileLayerCard({
    required this.layer,
    required this.features,
    required this.active,
    required this.expanded,
    required this.selectedFeatureKey,
    required this.onToggleExpanded,
    required this.onActivateLayer,
    required this.onAddFeature,
    required this.onFeatureSelected,
    required this.onEditFeature,
    required this.onVisibleChanged,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDelete,
  });

  final agus_maps_flutter.AgusLayer layer;
  final List<agus_maps_flutter.AgusLayerFeature> features;
  final bool active;
  final bool expanded;
  final String? selectedFeatureKey;
  final VoidCallback onToggleExpanded;
  final VoidCallback onActivateLayer;
  final VoidCallback onAddFeature;
  final ValueChanged<agus_maps_flutter.AgusLayerFeature> onFeatureSelected;
  final ValueChanged<agus_maps_flutter.AgusLayerFeature>? onEditFeature;
  final ValueChanged<bool> onVisibleChanged;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: active
            ? colorScheme.primaryContainer.withValues(alpha: 0.58)
            : colorScheme.surfaceContainerLow.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: active ? colorScheme.primary : colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onActivateLayer,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: expanded ? 'Hide features' : 'Show features',
                    onPressed: onToggleExpanded,
                    icon: Icon(
                      expanded ? Icons.expand_more : Icons.chevron_right,
                    ),
                  ),
                  Checkbox.adaptive(
                    value: layer.visible,
                    onChanged: (value) => onVisibleChanged(value ?? false),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                layer.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: active
                                      ? colorScheme.onPrimaryContainer
                                      : colorScheme.onSurface,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (active) ...[
                              const SizedBox(width: 6),
                              const _ActiveLayerBadge(),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${features.length} features - z ${layer.zIndex}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: active
                                ? colorScheme.onPrimaryContainer
                                    .withValues(alpha: 0.78)
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<_MobileLayerAction>(
                    tooltip: 'Layer actions',
                    onSelected: (action) {
                      switch (action) {
                        case _MobileLayerAction.addFeature:
                          onAddFeature();
                        case _MobileLayerAction.raise:
                          onMoveUp();
                        case _MobileLayerAction.lower:
                          onMoveDown();
                        case _MobileLayerAction.delete:
                          onDelete();
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: _MobileLayerAction.addFeature,
                        child: _MobileLayerActionItem(
                          icon: Icons.add_location_alt_outlined,
                          label: 'Add feature',
                        ),
                      ),
                      PopupMenuItem(
                        value: _MobileLayerAction.raise,
                        child: _MobileLayerActionItem(
                          icon: Icons.keyboard_arrow_up,
                          label: 'Raise layer',
                        ),
                      ),
                      PopupMenuItem(
                        value: _MobileLayerAction.lower,
                        child: _MobileLayerActionItem(
                          icon: Icons.keyboard_arrow_down,
                          label: 'Lower layer',
                        ),
                      ),
                      PopupMenuItem(
                        value: _MobileLayerAction.delete,
                        child: _MobileLayerActionItem(
                          icon: Icons.delete_outline,
                          label: 'Delete layer',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            Divider(height: 1, color: colorScheme.outlineVariant),
            if (features.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                child: Row(
                  children: [
                    Icon(
                      Icons.add_location_alt_outlined,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'No features yet. Add one to draw it on the map.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: onAddFeature,
                      child: const Text('Add'),
                    ),
                  ],
                ),
              )
            else
              for (final feature in features)
                _MobileFeatureTile(
                  feature: feature,
                  selected: selectedFeatureKey == _featureKey(feature),
                  onSelected: () {
                    onFeatureSelected(feature);
                    onEditFeature?.call(feature);
                  },
                ),
          ],
        ],
      ),
    );
  }
}

enum _MobileLayerAction { addFeature, raise, lower, delete }

class _MobileLayerActionItem extends StatelessWidget {
  const _MobileLayerActionItem({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Text(label),
      ],
    );
  }
}

class _MobileFeatureTile extends StatelessWidget {
  const _MobileFeatureTile({
    required this.feature,
    required this.selected,
    required this.onSelected,
  });

  final agus_maps_flutter.AgusLayerFeature feature;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final title = _featureTitle(feature);

    return InkWell(
      onTap: onSelected,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.secondaryContainer.withValues(alpha: 0.8)
              : Colors.transparent,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 11, 12, 11),
          child: Row(
            children: [
              Icon(
                _featureIcon(feature.geometryKind),
                size: 18,
                color: selected
                    ? colorScheme.onSecondaryContainer
                    : colorScheme.secondary,
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
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: selected
                            ? colorScheme.onSecondaryContainer
                            : colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      _geometryKindLabel(feature.geometryKind),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: selected
                            ? colorScheme.onSecondaryContainer
                                .withValues(alpha: 0.75)
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.open_with,
                size: 18,
                color: selected
                    ? colorScheme.onSecondaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _featureTitle(agus_maps_flutter.AgusLayerFeature feature) {
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
  });

  final agus_maps_flutter.AgusDrawTool activeTool;
  final bool hasEditableLayer;
  final String activeLayerName;

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
            if (activeTool == agus_maps_flutter.AgusDrawTool.none)
              Text(
                hasEditableLayer
                    ? 'Right-click a layer or feature and choose Add Feature... to start drawing.'
                    : 'Create or select a project layer before drawing.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: hasEditableLayer
                      ? colorScheme.onSurfaceVariant
                      : colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              )
            else ...[
              Text(
                'Creating ${_drawToolName(activeTool)}. Use the map check/X controls to finish or cancel before choosing another geometry type.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
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
    return Switch(
      value: value,
      onChanged: onChanged,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

class _CompactIconButton extends StatelessWidget {
  const _CompactIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 16),
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
    required this.active,
    required this.expanded,
    required this.padding,
    required this.selectedFeatureKey,
    required this.onToggleExpanded,
    required this.onFeatureSelected,
    required this.onEditFeature,
    required this.onVisibleChanged,
    required this.onMoveUp,
    required this.onMoveDown,
    this.onDelete,
    this.onActivateLayer,
  });

  final agus_maps_flutter.AgusLayer layer;
  final List<agus_maps_flutter.AgusLayerFeature> features;
  final bool compact;
  final bool active;
  final bool expanded;
  final EdgeInsets padding;
  final String? selectedFeatureKey;
  final VoidCallback onToggleExpanded;
  final ValueChanged<agus_maps_flutter.AgusLayerFeature> onFeatureSelected;
  final ValueChanged<agus_maps_flutter.AgusLayerFeature>? onEditFeature;
  final ValueChanged<bool> onVisibleChanged;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback? onDelete;
  final VoidCallback? onActivateLayer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasChildren = features.isNotEmpty;
    final rowHeight = compact ? 26.0 : 36.0;

    return Column(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: active
                ? colorScheme.primaryContainer.withValues(alpha: 0.55)
                : Colors.transparent,
          ),
          child: InkWell(
            onTap: onActivateLayer,
            child: SizedBox(
              height: rowHeight,
              child: Padding(
                padding: padding,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 3,
                      height: compact ? 18 : 26,
                      color: active ? colorScheme.primary : Colors.transparent,
                    ),
                    const SizedBox(width: 4),
                    if (hasChildren)
                      _CompactIconButton(
                        icon:
                            expanded ? Icons.expand_more : Icons.chevron_right,
                        tooltip: expanded ? 'Collapse layer' : 'Expand layer',
                        onPressed: onToggleExpanded,
                      )
                    else
                      const SizedBox(width: 26),
                    SizedBox(
                      width: 24,
                      child: Checkbox.adaptive(
                        value: layer.visible,
                        onChanged: (value) => onVisibleChanged(value ?? false),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    Icon(
                      _layerIcon(layer.kind),
                      size: compact ? 15 : 20,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 5,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              layer.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: active
                                    ? colorScheme.onPrimaryContainer
                                    : colorScheme.onSurface,
                                fontWeight:
                                    active ? FontWeight.w800 : FontWeight.w600,
                              ),
                            ),
                          ),
                          if (active) ...[
                            const SizedBox(width: 6),
                            const _ActiveLayerBadge(),
                          ],
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 58,
                      child: Text(
                        '${features.length}',
                        textAlign: TextAlign.right,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 34,
                      child: Text(
                        '${layer.zIndex}',
                        textAlign: TextAlign.right,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _CompactIconButton(
                          tooltip: 'Raise layer',
                          icon: Icons.keyboard_arrow_up,
                          onPressed: onMoveUp,
                        ),
                        _CompactIconButton(
                          tooltip: 'Lower layer',
                          icon: Icons.keyboard_arrow_down,
                          onPressed: onMoveDown,
                        ),
                        if (onDelete != null)
                          _CompactIconButton(
                            tooltip: 'Delete layer',
                            icon: Icons.delete_outline,
                            onPressed: onDelete,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (expanded) ...[
          for (final feature in features)
            _FeatureTreeLeaf(
              feature: feature,
              compact: compact,
              selected: selectedFeatureKey == _featureKey(feature),
              padding: EdgeInsets.fromLTRB(
                padding.left + 56,
                compact ? 1 : 0,
                padding.right,
                compact ? 1 : 10,
              ),
              onSelected: () {
                onFeatureSelected(feature);
                onEditFeature?.call(feature);
              },
              onEditFeature: () {
                onFeatureSelected(feature);
                onEditFeature?.call(feature);
              },
            ),
        ],
      ],
    );
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
    required this.compact,
    required this.selected,
    required this.onSelected,
    required this.onEditFeature,
  });

  final agus_maps_flutter.AgusLayerFeature feature;
  final EdgeInsets padding;
  final bool compact;
  final bool selected;
  final VoidCallback onSelected;
  final VoidCallback? onEditFeature;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      onTap: onSelected,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? colorScheme.primaryContainer : Colors.transparent,
        ),
        child: SizedBox(
          height: compact ? 24 : 36,
          child: Padding(
            padding: padding,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  _featureIcon(feature.geometryKind),
                  size: compact ? 13 : 16,
                  color: selected
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.secondary,
                ),
                const SizedBox(width: 7),
                Expanded(
                  flex: 5,
                  child: Text(
                    _featureTitle(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: selected
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurface,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(
                  width: 74,
                  child: Text(
                    _geometryKindLabel(feature.geometryKind),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: selected
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                _CompactIconButton(
                  tooltip: 'Edit feature vertices',
                  icon: Icons.open_with,
                  onPressed: onEditFeature,
                ),
              ],
            ),
          ),
        ),
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

class _ActiveLayerBadge extends StatelessWidget {
  const _ActiveLayerBadge();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primary,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        child: Text(
          'EDIT',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colorScheme.onPrimary,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
        ),
      ),
    );
  }
}

String _geometryKindLabel(agus_maps_flutter.AgusGeometryKind kind) {
  return switch (kind) {
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

String _layerKindLabel(agus_maps_flutter.AgusLayerKind kind) {
  return switch (kind) {
    agus_maps_flutter.AgusLayerKind.nativeMwm => 'Native',
    agus_maps_flutter.AgusLayerKind.userDraw => 'Drawing',
    agus_maps_flutter.AgusLayerKind.comapsSupported => 'CoMaps',
    agus_maps_flutter.AgusLayerKind.duckdbQuery => 'DuckDB',
  };
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kib = bytes / 1024;
  if (kib < 1024) return '${kib.toStringAsFixed(1)} KiB';
  final mib = kib / 1024;
  if (mib < 1024) return '${mib.toStringAsFixed(1)} MiB';
  final gib = mib / 1024;
  return '${gib.toStringAsFixed(1)} GiB';
}

IconData _featureIcon(agus_maps_flutter.AgusGeometryKind kind) {
  return switch (kind) {
    agus_maps_flutter.AgusGeometryKind.point => Icons.circle,
    agus_maps_flutter.AgusGeometryKind.line => Icons.timeline,
    agus_maps_flutter.AgusGeometryKind.segment => Icons.linear_scale,
    agus_maps_flutter.AgusGeometryKind.polygon => Icons.pentagon_outlined,
    agus_maps_flutter.AgusGeometryKind.multipoint => Icons.grain,
    agus_maps_flutter.AgusGeometryKind.multiline => Icons.alt_route,
    agus_maps_flutter.AgusGeometryKind.multipolygon => Icons.polyline_outlined,
    agus_maps_flutter.AgusGeometryKind.collection =>
      Icons.account_tree_outlined,
  };
}

String _featureKey(agus_maps_flutter.AgusLayerFeature feature) {
  return '${feature.layerId}:${feature.featureId}';
}

int _enabledNativeLayerCount(
  agus_maps_flutter.MapLayerState nativeLayerState,
  bool buildings3dEnabled,
) {
  var count = 0;
  if (buildings3dEnabled) count += 1;
  if (nativeLayerState.outdoors) count += 1;
  if (nativeLayerState.isolines) count += 1;
  if (nativeLayerState.subway) count += 1;
  return count;
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
