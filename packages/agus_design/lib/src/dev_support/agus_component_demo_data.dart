import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../components/agus_command.dart';
import '../components/agus_tree_view.dart';

const agusMetricTreeColumns = <AgusTreeColumn>[
  AgusTreeColumn(id: 'features', label: 'Features', width: 72),
  AgusTreeColumn(id: 'segments', label: 'Segments', width: 84),
  AgusTreeColumn(id: 'vertices', label: 'Vertices', width: 88),
];

const agusAltVisibilityIcons = AgusTreeVisibilityIcons(
  visible: Icons.lightbulb_outline,
  hidden: Icons.lightbulb,
  mixed: Icons.tips_and_updates_outlined,
  locked: Icons.flashlight_off,
);

@immutable
class AgusTreeDemoBundle {
  const AgusTreeDemoBundle({
    required this.nodes,
    required this.expandedIds,
    required this.singleSelectedId,
    required this.multiSelectedIds,
  });

  final List<AgusTreeNode> nodes;
  final Set<String> expandedIds;
  final String singleSelectedId;
  final Set<String> multiSelectedIds;
}

List<AgusCommandGroup> buildAgusWorkbenchCommandGroups({
  required void Function(String id, String label) onSelected,
}) {
  AgusCommandItem item({
    required String id,
    required String label,
    required IconData icon,
    required ShortcutActivator shortcut,
    required String shortcutLabel,
    List<String> keywords = const <String>[],
  }) {
    return AgusCommandItem(
      id: id,
      label: label,
      icon: icon,
      shortcut: shortcut,
      shortcutLabel: shortcutLabel,
      keywords: keywords,
      onSelected: () => onSelected(id, label),
    );
  }

  return [
    AgusCommandGroup(
      heading: 'Navigation',
      items: [
        item(
          id: 'home',
          label: 'Home',
          icon: Icons.home_outlined,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyH, meta: true),
          shortcutLabel: '⌘H',
          keywords: const ['dashboard', 'start', 'overview'],
        ),
        item(
          id: 'inbox',
          label: 'Inbox',
          icon: Icons.inbox_outlined,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyI, meta: true),
          shortcutLabel: '⌘I',
          keywords: const ['messages', 'updates', 'notifications'],
        ),
        item(
          id: 'documents',
          label: 'Documents',
          icon: Icons.description_outlined,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyD, meta: true),
          shortcutLabel: '⌘D',
          keywords: const ['files', 'assets', 'docs'],
        ),
        item(
          id: 'folders',
          label: 'Folders',
          icon: Icons.folder_open_outlined,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyF, meta: true),
          shortcutLabel: '⌘F',
          keywords: const ['collections', 'groups', 'workspace'],
        ),
      ],
    ),
    AgusCommandGroup(
      heading: 'Actions',
      items: [
        item(
          id: 'new-file',
          label: 'New File',
          icon: Icons.note_add_outlined,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyN, meta: true),
          shortcutLabel: '⌘N',
          keywords: const ['create', 'document'],
        ),
        item(
          id: 'new-folder',
          label: 'New Folder',
          icon: Icons.create_new_folder_outlined,
          shortcut: const SingleActivator(
            LogicalKeyboardKey.keyN,
            meta: true,
            shift: true,
          ),
          shortcutLabel: '⇧⌘N',
          keywords: const ['directory', 'group'],
        ),
        item(
          id: 'copy',
          label: 'Copy',
          icon: Icons.content_copy_outlined,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyC, meta: true),
          shortcutLabel: '⌘C',
          keywords: const ['duplicate', 'clone'],
        ),
      ],
    ),
  ];
}

class AgusTreeDemoGenerator {
  const AgusTreeDemoGenerator({this.seed = 11});

  final int seed;

  AgusTreeDemoBundle build({int rootCount = 4}) {
    final random = Random(seed);
    final expandedIds = <String>{};
    final roots = <AgusTreeNode>[];
    final selectedLeafIds = <String>[];
    final safeRootCount = rootCount.clamp(2, _rootLabels.length);

    for (var index = 0; index < safeRootCount; index++) {
      final rootId = 'root-$index';
      final branch = _buildBranch(
        random: random,
        id: rootId,
        label: _rootLabels[index],
        depth: 0,
        maxDepth: 2,
      );
      roots.add(branch.node);
      expandedIds.add(rootId);
      if (branch.node.children.isNotEmpty) {
        expandedIds.add(branch.node.children.first.id);
      }
      selectedLeafIds.addAll(branch.leafIds.take(2));
    }

    final nodes = rebuildAgusTreeDemoMetrics(roots);
    return AgusTreeDemoBundle(
      nodes: nodes,
      expandedIds: expandedIds,
      singleSelectedId: selectedLeafIds.first,
      multiSelectedIds: selectedLeafIds.take(3).toSet(),
    );
  }

  _GeneratedNode _buildBranch({
    required Random random,
    required String id,
    required String label,
    required int depth,
    required int maxDepth,
  }) {
    if (depth >= maxDepth) {
      final metrics = _LeafMetrics(
        features: 1 + random.nextInt(8),
        segments: 8 + random.nextInt(120),
        vertices: 400 + random.nextInt(28000),
      );
      return _GeneratedNode(
        node: AgusTreeNode(
          id: id,
          label: label,
          icon: _leafIcons[random.nextInt(_leafIcons.length)],
          columnValues: _columnValuesFor(metrics),
          visibility: _leafVisibility(random),
          renamable: true,
          deletable: true,
        ),
        leafIds: <String>[id],
      );
    }

    final childCount = 2 + random.nextInt(depth == 0 ? 3 : 4);
    final children = <AgusTreeNode>[];
    final leafIds = <String>[];

    for (var index = 0; index < childCount; index++) {
      final childLabel =
          '${_branchPrefixes[random.nextInt(_branchPrefixes.length)]} '
          '${_branchSuffixes[random.nextInt(_branchSuffixes.length)]}';
      final childId = '$id-$index';
      final child = _buildBranch(
        random: random,
        id: childId,
        label: depth == maxDepth - 1
            ? '$childLabel ${_leafLabels[random.nextInt(_leafLabels.length)]}'
            : childLabel,
        depth: depth + 1,
        maxDepth: maxDepth,
      );
      children.add(child.node);
      leafIds.addAll(child.leafIds);
    }

    return _GeneratedNode(
      node: AgusTreeNode(
        id: id,
        label: label,
        icon: depth == 0 ? Icons.inventory_2_outlined : Icons.folder_outlined,
        children: children,
        visibility: AgusTreeVisibilityState.mixed,
        renamable: true,
        deletable: depth > 0,
      ),
      leafIds: leafIds,
    );
  }

  AgusTreeVisibilityState _leafVisibility(Random random) {
    final roll = random.nextInt(10);
    if (roll <= 4) {
      return AgusTreeVisibilityState.visible;
    }
    if (roll <= 7) {
      return AgusTreeVisibilityState.hidden;
    }
    if (roll == 8) {
      return AgusTreeVisibilityState.mixed;
    }
    return AgusTreeVisibilityState.locked;
  }
}

List<AgusTreeNode> renameAgusTreeDemoNode(
  List<AgusTreeNode> nodes, {
  required String nodeId,
  required String label,
}) {
  return [
    for (final node in nodes)
      if (node.id == nodeId)
        node.copyWith(label: label)
      else
        node.copyWith(
          children: renameAgusTreeDemoNode(
            node.children,
            nodeId: nodeId,
            label: label,
          ),
        ),
  ];
}

List<AgusTreeNode> deleteAgusTreeDemoNode(
  List<AgusTreeNode> nodes, {
  required String nodeId,
}) {
  return rebuildAgusTreeDemoMetrics([
    for (final node in nodes)
      if (node.id != nodeId)
        node.copyWith(
          children: deleteAgusTreeDemoNode(node.children, nodeId: nodeId),
        ),
  ]);
}

List<AgusTreeNode> updateAgusTreeDemoVisibility(
  List<AgusTreeNode> nodes, {
  required String nodeId,
  required AgusTreeVisibilityState visibility,
}) {
  return rebuildAgusTreeDemoMetrics([
    for (final node in nodes)
      if (node.id == nodeId)
        _applyVisibility(node, visibility)
      else
        node.copyWith(
          children: updateAgusTreeDemoVisibility(
            node.children,
            nodeId: nodeId,
            visibility: visibility,
          ),
        ),
  ]);
}

List<AgusTreeNode> rebuildAgusTreeDemoMetrics(List<AgusTreeNode> nodes) {
  return [
    for (final node in nodes)
      if (node.children.isEmpty) node else _rebuildBranch(node),
  ];
}

bool agusTreeDemoContainsNode(List<AgusTreeNode> nodes, String id) {
  for (final node in nodes) {
    if (node.id == id || agusTreeDemoContainsNode(node.children, id)) {
      return true;
    }
  }
  return false;
}

AgusTreeNode _rebuildBranch(AgusTreeNode node) {
  final rebuiltChildren = rebuildAgusTreeDemoMetrics(node.children);
  final featureCount = rebuiltChildren.fold<int>(
    0,
    (sum, child) => sum + _parseMetric(child.columnValues['features']),
  );
  final segmentCount = rebuiltChildren.fold<int>(
    0,
    (sum, child) => sum + _parseMetric(child.columnValues['segments']),
  );
  final vertexCount = rebuiltChildren.fold<int>(
    0,
    (sum, child) => sum + _parseMetric(child.columnValues['vertices']),
  );

  return node.copyWith(
    children: rebuiltChildren,
    columnValues: <String, String>{
      'features': _formatMetric(featureCount),
      'segments': _formatMetric(segmentCount),
      'vertices': _formatMetric(vertexCount),
    },
    visibility: _aggregateVisibility(rebuiltChildren),
  );
}

AgusTreeNode _applyVisibility(
  AgusTreeNode node,
  AgusTreeVisibilityState visibility,
) {
  final nextVisibility = node.visibility == AgusTreeVisibilityState.locked
      ? AgusTreeVisibilityState.locked
      : visibility;
  return node.copyWith(
    visibility: nextVisibility,
    children: [
      for (final child in node.children) _applyVisibility(child, visibility),
    ],
  );
}

AgusTreeVisibilityState? _aggregateVisibility(List<AgusTreeNode> children) {
  final visibilities = children
      .map((child) => child.visibility)
      .whereType<AgusTreeVisibilityState>()
      .toSet();
  if (visibilities.isEmpty) {
    return null;
  }
  if (visibilities.length == 1) {
    return visibilities.first;
  }
  return AgusTreeVisibilityState.mixed;
}

Map<String, String> _columnValuesFor(_LeafMetrics metrics) {
  return <String, String>{
    'features': _formatMetric(metrics.features),
    'segments': _formatMetric(metrics.segments),
    'vertices': _formatMetric(metrics.vertices),
  };
}

String _formatMetric(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    final remaining = digits.length - index;
    buffer.write(digits[index]);
    if (remaining > 1 && remaining % 3 == 1) {
      buffer.write(',');
    }
  }
  return buffer.toString();
}

int _parseMetric(String? value) {
  if (value == null || value.isEmpty) {
    return 0;
  }
  return int.tryParse(value.replaceAll(',', '')) ?? 0;
}

const _rootLabels = <String>[
  'Environment',
  'Characters',
  'Props',
  'Lighting',
  'Effects',
];

const _branchPrefixes = <String>[
  'North',
  'South',
  'Hero',
  'Modular',
  'Spline',
  'Portal',
  'Atlas',
  'Runtime',
  'Studio',
  'Variant',
];

const _branchSuffixes = <String>[
  'Cluster',
  'Collection',
  'Set',
  'Assembly',
  'Pack',
  'Rig',
  'Layer',
  'Group',
];

const _leafLabels = <String>[
  'Facade',
  'Canopy',
  'Anchor',
  'Spline',
  'Trim',
  'Collider',
  'Spawner',
  'Guide',
  'Marker',
  'Emitter',
];

const _leafIcons = <IconData>[
  Icons.polyline_outlined,
  Icons.hexagon_outlined,
  Icons.category_outlined,
  Icons.change_history_outlined,
  Icons.grid_3x3_outlined,
];

@immutable
class _GeneratedNode {
  const _GeneratedNode({required this.node, required this.leafIds});

  final AgusTreeNode node;
  final List<String> leafIds;
}

@immutable
class _LeafMetrics {
  const _LeafMetrics({
    required this.features,
    required this.segments,
    required this.vertices,
  });

  final int features;
  final int segments;
  final int vertices;
}
