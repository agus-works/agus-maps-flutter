import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/agus_theme_data.dart';

enum AgusTreeSelectionMode { single, multiple }

enum AgusTreeColumnAlignment { start, center, end }

enum AgusTreeVisibilityState { visible, hidden, mixed, locked }

/// Called with the reordered metric columns after a tree header column is
/// dragged and dropped.
typedef AgusTreeColumnReorderCallback =
    void Function(List<AgusTreeColumn> columns);

/// Called when a tree row requests a context menu.
typedef AgusTreeNodeContextMenuCallback =
    void Function(String id, Offset globalPosition);

@immutable
class AgusTreeVisibilityIcons {
  const AgusTreeVisibilityIcons({
    this.visible = Icons.visibility_outlined,
    this.hidden = Icons.visibility_off_outlined,
    this.mixed = Icons.visibility,
    this.locked = Icons.lock_outline,
  });

  final IconData visible;
  final IconData hidden;
  final IconData mixed;
  final IconData locked;

  IconData iconFor(AgusTreeVisibilityState state) {
    return switch (state) {
      AgusTreeVisibilityState.visible => visible,
      AgusTreeVisibilityState.hidden => hidden,
      AgusTreeVisibilityState.mixed => mixed,
      AgusTreeVisibilityState.locked => locked,
    };
  }
}

@immutable
class AgusTreeColumn {
  const AgusTreeColumn({
    required this.id,
    required this.label,
    this.width = 72,
    this.minWidth = 48,
    this.maxWidth = double.infinity,
    this.alignment = AgusTreeColumnAlignment.end,
    this.resizable = true,
  }) : assert(width >= 0),
       assert(minWidth >= 0),
       assert(maxWidth >= minWidth);

  final String id;
  final String label;
  final double width;
  final double minWidth;
  final double maxWidth;
  final AgusTreeColumnAlignment alignment;
  final bool resizable;

  static double clampWidth({
    required double width,
    required double minWidth,
    required double maxWidth,
  }) {
    return width.clamp(minWidth, maxWidth).toDouble();
  }

  AgusTreeColumn copyWith({
    String? id,
    String? label,
    double? width,
    double? minWidth,
    double? maxWidth,
    AgusTreeColumnAlignment? alignment,
    bool? resizable,
  }) {
    return AgusTreeColumn(
      id: id ?? this.id,
      label: label ?? this.label,
      width: width ?? this.width,
      minWidth: minWidth ?? this.minWidth,
      maxWidth: maxWidth ?? this.maxWidth,
      alignment: alignment ?? this.alignment,
      resizable: resizable ?? this.resizable,
    );
  }
}

@immutable
class AgusTreeNode {
  const AgusTreeNode({
    required this.id,
    required this.label,
    this.icon,
    this.children = const <AgusTreeNode>[],
    this.expanded = false,
    this.disabled = false,
    this.badgeLabel,
    this.columnValues = const <String, String>{},
    this.visibility,
    this.renamable = false,
    this.deletable = false,
  });

  final String id;
  final String label;
  final IconData? icon;
  final List<AgusTreeNode> children;
  final bool expanded;
  final bool disabled;
  final String? badgeLabel;
  final Map<String, String> columnValues;
  final AgusTreeVisibilityState? visibility;
  final bool renamable;
  final bool deletable;

  AgusTreeNode copyWith({
    String? id,
    String? label,
    IconData? icon,
    List<AgusTreeNode>? children,
    bool? expanded,
    bool? disabled,
    String? badgeLabel,
    Map<String, String>? columnValues,
    AgusTreeVisibilityState? visibility,
    bool? renamable,
    bool? deletable,
    bool clearBadgeLabel = false,
    bool clearVisibility = false,
  }) {
    return AgusTreeNode(
      id: id ?? this.id,
      label: label ?? this.label,
      icon: icon ?? this.icon,
      children: children ?? this.children,
      expanded: expanded ?? this.expanded,
      disabled: disabled ?? this.disabled,
      badgeLabel: clearBadgeLabel ? null : badgeLabel ?? this.badgeLabel,
      columnValues: columnValues ?? this.columnValues,
      visibility: clearVisibility ? null : visibility ?? this.visibility,
      renamable: renamable ?? this.renamable,
      deletable: deletable ?? this.deletable,
    );
  }
}

class AgusTreeView extends StatefulWidget {
  const AgusTreeView({
    required this.nodes,
    this.selectedId,
    this.selectedIds,
    this.expandedIds,
    this.columns = const <AgusTreeColumn>[],
    this.labelColumnTitle,
    this.labelColumnWidth = 180,
    this.minLabelColumnWidth = 96,
    this.maxLabelColumnWidth = double.infinity,
    this.resizableColumns = true,
    this.selectionMode = AgusTreeSelectionMode.single,
    this.visibilityIcons = const AgusTreeVisibilityIcons(),
    this.onSelected,
    this.onSelectionChanged,
    this.onToggle,
    this.onRename,
    this.onDelete,
    this.onVisibilityChanged,
    this.onContextMenuRequested,
    this.onLabelColumnResize,
    this.onColumnResize,
    this.onColumnReorder,
    super.key,
  }) : assert(labelColumnWidth >= 0),
       assert(minLabelColumnWidth >= 0),
       assert(maxLabelColumnWidth >= minLabelColumnWidth);

  final List<AgusTreeNode> nodes;
  final String? selectedId;
  final Set<String>? selectedIds;
  final Set<String>? expandedIds;
  final List<AgusTreeColumn> columns;
  final String? labelColumnTitle;
  final double labelColumnWidth;
  final double minLabelColumnWidth;
  final double maxLabelColumnWidth;
  final bool resizableColumns;
  final AgusTreeSelectionMode selectionMode;
  final AgusTreeVisibilityIcons visibilityIcons;
  final ValueChanged<String>? onSelected;
  final ValueChanged<Set<String>>? onSelectionChanged;
  final ValueChanged<String>? onToggle;
  final void Function(String id, String label)? onRename;
  final ValueChanged<String>? onDelete;
  final void Function(String id, AgusTreeVisibilityState visibility)?
  onVisibilityChanged;
  final AgusTreeNodeContextMenuCallback? onContextMenuRequested;
  final ValueChanged<double>? onLabelColumnResize;
  final void Function(String columnId, double width)? onColumnResize;

  /// Called with reordered metric columns when a non-label column is dragged.
  ///
  /// The label column is locked outside [columns], so it always remains first.
  final AgusTreeColumnReorderCallback? onColumnReorder;

  @override
  State<AgusTreeView> createState() => _AgusTreeViewState();
}

class _AgusTreeViewState extends State<AgusTreeView> {
  final ScrollController _horizontalController = ScrollController();
  final Map<String, GlobalKey> _columnHeaderKeys = <String, GlobalKey>{};
  OverlayEntry? _columnDragFeedbackOverlay;

  String? _editingId;
  String? _lastRenameTapId;
  DateTime? _lastRenameTapAt;
  TextEditingController? _renameController;
  late double _labelColumnWidth;
  late Map<String, double> _columnWidths;
  String? _draggedColumnId;
  _TreeColumnDropIntent? _columnDropIntent;
  Offset? _latestColumnDragPosition;

  double _horizontalOffset = 0;

  @override
  void initState() {
    super.initState();
    _labelColumnWidth = _clampLabelColumnWidth(widget.labelColumnWidth);
    _columnWidths = _initialColumnWidths();
    _horizontalController.addListener(_handleHorizontalScroll);
  }

  @override
  void didUpdateWidget(covariant AgusTreeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _columnHeaderKeys.removeWhere(
      (id, _) => !widget.columns.any((column) => column.id == id),
    );
    if (oldWidget.labelColumnWidth != widget.labelColumnWidth ||
        oldWidget.minLabelColumnWidth != widget.minLabelColumnWidth ||
        oldWidget.maxLabelColumnWidth != widget.maxLabelColumnWidth) {
      _labelColumnWidth = _clampLabelColumnWidth(
        oldWidget.labelColumnWidth == _labelColumnWidth
            ? widget.labelColumnWidth
            : _labelColumnWidth,
      );
    }
    _columnWidths = _reconciledColumnWidths(oldWidget);
  }

  @override
  void dispose() {
    _hideColumnDragFeedbackOverlay();
    _horizontalController
      ..removeListener(_handleHorizontalScroll)
      ..dispose();
    _renameController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = <_VisibleTreeRow>[];
    for (final node in widget.nodes) {
      _collectRows(node, 0, rows);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columnWidths = [
          for (final column in widget.columns) _widthFor(column),
        ];
        final labelColumnWidth = _effectiveLabelColumnWidth(constraints);
        final scrollableWidth = columnWidths.fold<double>(
          0,
          (sum, width) => sum + width,
        );
        final scrollableViewportWidth = math.max(
          0,
          constraints.maxWidth.isFinite
              ? constraints.maxWidth - labelColumnWidth
              : scrollableWidth,
        );
        final horizontalOffset = _horizontalOffset
            .clamp(0, math.max(0, scrollableWidth - scrollableViewportWidth))
            .toDouble();

        if (!_showsHeader) {
          return _buildLabelOnlyList(rows, constraints);
        }

        final rowList = _buildColumnRowList(
          rows: rows,
          constraints: constraints,
          labelColumnWidth: labelColumnWidth,
          columns: widget.columns,
          columnWidths: columnWidths,
          scrollableWidth: scrollableWidth,
          horizontalOffset: horizontalOffset,
        );

        final tree = Column(
          mainAxisSize: constraints.hasBoundedHeight
              ? MainAxisSize.max
              : MainAxisSize.min,
          children: [
            _TreeHeaderRow(
              label: widget.labelColumnTitle ?? 'Name',
              labelColumnWidth: labelColumnWidth,
              columns: widget.columns,
              columnWidths: columnWidths,
              horizontalController: _horizontalController,
              scrollableWidth: scrollableWidth,
              labelResizable: widget.resizableColumns,
              columnReorderable: widget.onColumnReorder != null,
              draggedColumnId: _draggedColumnId,
              columnDropIntent: _columnDropIntent,
              onLabelResizeDelta: _resizeLabelColumnBy,
              onColumnResizeDelta: _resizeColumnBy,
              keyForColumn: _keyForColumnHeader,
              onColumnDragStart: _startColumnDrag,
              onColumnDragUpdate: _updateColumnDrag,
              onColumnDragEnd: _finishColumnDrag,
              onColumnDragCancel: _cancelColumnDrag,
            ),
            if (constraints.hasBoundedHeight)
              Expanded(child: rowList)
            else
              rowList,
          ],
        );

        return tree;
      },
    );
  }

  Widget _buildLabelOnlyList(
    List<_VisibleTreeRow> rows,
    BoxConstraints constraints,
  ) {
    return ListView.builder(
      padding: EdgeInsets.zero,
      shrinkWrap: !constraints.hasBoundedHeight,
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        return _TreeRowView(
          node: row.node,
          depth: row.depth,
          labelColumnWidth: constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : _labelColumnWidth,
          columns: const <AgusTreeColumn>[],
          columnWidths: const <double>[],
          scrollableWidth: 0,
          horizontalOffset: 0,
          onHorizontalDragDelta: _scrollHorizontallyBy,
          selected: _isSelected(row.node.id),
          expanded: _isExpanded(row.node),
          visibilityIcons: widget.visibilityIcons,
          isEditing: _editingId == row.node.id,
          renameController: _editingId == row.node.id
              ? _renameController
              : null,
          onSelected: _handleSelection,
          onToggle: widget.onToggle,
          onBeginRename: _beginRename,
          onLabelPointerDown: _handleLabelPointerDown,
          onRenameSubmitted: _commitRename,
          onRenameCancelled: _cancelRename,
          onDelete: widget.onDelete,
          onVisibilityChanged: widget.onVisibilityChanged,
          onContextMenuRequested: widget.onContextMenuRequested,
        );
      },
    );
  }

  Widget _buildColumnRowList({
    required List<_VisibleTreeRow> rows,
    required BoxConstraints constraints,
    required double labelColumnWidth,
    required List<AgusTreeColumn> columns,
    required List<double> columnWidths,
    required double scrollableWidth,
    required double horizontalOffset,
  }) {
    return ListView.builder(
      padding: EdgeInsets.zero,
      shrinkWrap: !constraints.hasBoundedHeight,
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        return _TreeRowView(
          node: row.node,
          depth: row.depth,
          labelColumnWidth: labelColumnWidth,
          columns: columns,
          columnWidths: columnWidths,
          scrollableWidth: scrollableWidth,
          horizontalOffset: horizontalOffset,
          onHorizontalDragDelta: _scrollHorizontallyBy,
          selected: _isSelected(row.node.id),
          expanded: _isExpanded(row.node),
          visibilityIcons: widget.visibilityIcons,
          isEditing: _editingId == row.node.id,
          renameController: _editingId == row.node.id
              ? _renameController
              : null,
          onSelected: _handleSelection,
          onToggle: widget.onToggle,
          onBeginRename: _beginRename,
          onLabelPointerDown: _handleLabelPointerDown,
          onRenameSubmitted: _commitRename,
          onRenameCancelled: _cancelRename,
          onDelete: widget.onDelete,
          onVisibilityChanged: widget.onVisibilityChanged,
          onContextMenuRequested: widget.onContextMenuRequested,
        );
      },
    );
  }

  void _collectRows(AgusTreeNode node, int depth, List<_VisibleTreeRow> rows) {
    rows.add(_VisibleTreeRow(node, depth));
    if (!_isExpanded(node)) {
      return;
    }

    for (final child in node.children) {
      _collectRows(child, depth + 1, rows);
    }
  }

  bool _isExpanded(AgusTreeNode node) {
    return widget.expandedIds?.contains(node.id) ?? node.expanded;
  }

  bool _isSelected(String id) {
    if (widget.selectionMode == AgusTreeSelectionMode.multiple) {
      return widget.selectedIds?.contains(id) ?? false;
    }

    return widget.selectedId == id;
  }

  bool get _showsHeader => widget.columns.isNotEmpty;

  void _handleSelection(String id) {
    widget.onSelected?.call(id);
    if (widget.selectionMode == AgusTreeSelectionMode.single) {
      widget.onSelectionChanged?.call(<String>{id});
      return;
    }

    final next = Set<String>.from(widget.selectedIds ?? const <String>{});
    if (!next.add(id)) {
      next.remove(id);
    }
    widget.onSelectionChanged?.call(next);
  }

  void _beginRename(AgusTreeNode node) {
    if (!node.renamable || widget.onRename == null) {
      return;
    }

    _lastRenameTapId = null;
    _lastRenameTapAt = null;
    _renameController?.dispose();
    _renameController = TextEditingController(text: node.label);
    setState(() => _editingId = node.id);
  }

  void _handleLabelPointerDown(AgusTreeNode node) {
    if (!node.renamable || widget.onRename == null) {
      return;
    }

    final now = DateTime.now();
    if (_lastRenameTapId == node.id &&
        _lastRenameTapAt != null &&
        now.difference(_lastRenameTapAt!) <=
            const Duration(milliseconds: 300)) {
      _beginRename(node);
      return;
    }

    _lastRenameTapId = node.id;
    _lastRenameTapAt = now;
  }

  void _commitRename(AgusTreeNode node, String value) {
    final nextLabel = value.trim();
    if (nextLabel.isNotEmpty) {
      widget.onRename?.call(node.id, nextLabel);
    }
    _cancelRename();
  }

  void _cancelRename() {
    _renameController?.dispose();
    _renameController = null;
    if (mounted) {
      setState(() => _editingId = null);
    }
  }

  double _clampLabelColumnWidth(double width) {
    return width
        .clamp(widget.minLabelColumnWidth, widget.maxLabelColumnWidth)
        .toDouble();
  }

  Map<String, double> _initialColumnWidths() {
    return {
      for (final column in widget.columns)
        column.id: AgusTreeColumn.clampWidth(
          width: column.width,
          minWidth: column.minWidth,
          maxWidth: column.maxWidth,
        ),
    };
  }

  Map<String, double> _reconciledColumnWidths(AgusTreeView oldWidget) {
    final oldColumns = {
      for (final column in oldWidget.columns) column.id: column,
    };
    return {
      for (final column in widget.columns)
        column.id: AgusTreeColumn.clampWidth(
          width: oldColumns[column.id]?.width == _columnWidths[column.id]
              ? column.width
              : _columnWidths[column.id] ?? column.width,
          minWidth: column.minWidth,
          maxWidth: column.maxWidth,
        ),
    };
  }

  double _widthFor(AgusTreeColumn column) {
    return AgusTreeColumn.clampWidth(
      width: _columnWidths[column.id] ?? column.width,
      minWidth: column.minWidth,
      maxWidth: column.maxWidth,
    );
  }

  double _effectiveLabelColumnWidth(BoxConstraints constraints) {
    if (!constraints.maxWidth.isFinite) {
      return _labelColumnWidth;
    }

    return math.min(_labelColumnWidth, constraints.maxWidth);
  }

  void _resizeLabelColumnBy(double delta) {
    if (!widget.resizableColumns || delta == 0) {
      return;
    }

    final nextWidth = _clampLabelColumnWidth(_labelColumnWidth + delta);
    if (nextWidth == _labelColumnWidth) {
      return;
    }

    setState(() => _labelColumnWidth = nextWidth);
    widget.onLabelColumnResize?.call(nextWidth);
  }

  void _resizeColumnBy(AgusTreeColumn column, double delta) {
    if (!widget.resizableColumns || !column.resizable || delta == 0) {
      return;
    }

    final nextWidth = AgusTreeColumn.clampWidth(
      width: _widthFor(column) + delta,
      minWidth: column.minWidth,
      maxWidth: column.maxWidth,
    );
    if (nextWidth == _widthFor(column)) {
      return;
    }

    setState(() => _columnWidths[column.id] = nextWidth);
    widget.onColumnResize?.call(column.id, nextWidth);
  }

  GlobalKey _keyForColumnHeader(String columnId) {
    return _columnHeaderKeys.putIfAbsent(columnId, GlobalKey.new);
  }

  void _startColumnDrag(String columnId, Offset globalPosition) {
    _showColumnDragFeedbackOverlay();
    setState(() {
      _draggedColumnId = columnId;
      _latestColumnDragPosition = globalPosition;
      _columnDropIntent = _columnDropIntentAtPosition(globalPosition);
    });
    _columnDragFeedbackOverlay?.markNeedsBuild();
  }

  void _updateColumnDrag(Offset globalPosition) {
    setState(() {
      _latestColumnDragPosition = globalPosition;
      _columnDropIntent = _columnDropIntentAtPosition(globalPosition);
    });
    _columnDragFeedbackOverlay?.markNeedsBuild();
  }

  void _finishColumnDrag() {
    final draggedColumnId = _draggedColumnId;
    final dropIntent = _columnDropIntent;
    _cancelColumnDrag();

    if (draggedColumnId == null || dropIntent == null) {
      return;
    }

    _reorderColumn(draggedColumnId, dropIntent);
  }

  void _cancelColumnDrag() {
    _hideColumnDragFeedbackOverlay();
    setState(() {
      _draggedColumnId = null;
      _columnDropIntent = null;
      _latestColumnDragPosition = null;
    });
  }

  void _reorderColumn(
    String draggedColumnId,
    _TreeColumnDropIntent dropIntent,
  ) {
    final onColumnReorder = widget.onColumnReorder;
    if (onColumnReorder == null || draggedColumnId == dropIntent.targetId) {
      return;
    }

    final oldIndex = widget.columns.indexWhere(
      (column) => column.id == draggedColumnId,
    );
    final targetIndex = widget.columns.indexWhere(
      (column) => column.id == dropIntent.targetId,
    );
    if (oldIndex == -1 || targetIndex == -1) {
      return;
    }

    final insertionIndex = dropIntent.side == _TreeColumnDropSide.before
        ? targetIndex
        : targetIndex + 1;
    final newIndex = oldIndex < insertionIndex
        ? insertionIndex - 1
        : insertionIndex;
    if (oldIndex == newIndex) {
      return;
    }

    final reorderedColumns = List<AgusTreeColumn>.of(widget.columns);
    final draggedColumn = reorderedColumns.removeAt(oldIndex);
    reorderedColumns.insert(newIndex, draggedColumn);
    onColumnReorder(List<AgusTreeColumn>.unmodifiable(reorderedColumns));
  }

  _TreeColumnDropIntent? _columnDropIntentAtPosition(Offset globalPosition) {
    String? firstColumnId;
    String? lastColumnId;
    Rect? firstColumnRect;
    Rect? lastColumnRect;

    for (final column in widget.columns) {
      final targetContext = _columnHeaderKeys[column.id]?.currentContext;
      final renderObject = targetContext?.findRenderObject();
      if (renderObject is! RenderBox) {
        continue;
      }

      final columnRect =
          renderObject.localToGlobal(Offset.zero) & renderObject.size;
      firstColumnId ??= column.id;
      firstColumnRect ??= columnRect;
      lastColumnId = column.id;
      lastColumnRect = columnRect;

      if (columnRect.contains(globalPosition)) {
        final side = globalPosition.dx < columnRect.center.dx
            ? _TreeColumnDropSide.before
            : _TreeColumnDropSide.after;
        return _TreeColumnDropIntent(targetId: column.id, side: side);
      }
    }

    if (firstColumnId == null ||
        firstColumnRect == null ||
        lastColumnRect == null) {
      return null;
    }

    final withinHeaderHeight =
        globalPosition.dy >= firstColumnRect.top &&
        globalPosition.dy <= firstColumnRect.bottom;
    if (!withinHeaderHeight) {
      return null;
    }

    if (globalPosition.dx < firstColumnRect.left) {
      return _TreeColumnDropIntent(
        targetId: firstColumnId,
        side: _TreeColumnDropSide.before,
      );
    }
    if (lastColumnId != null && globalPosition.dx > lastColumnRect.right) {
      return _TreeColumnDropIntent(
        targetId: lastColumnId,
        side: _TreeColumnDropSide.after,
      );
    }

    return null;
  }

  void _showColumnDragFeedbackOverlay() {
    if (_columnDragFeedbackOverlay != null) {
      return;
    }

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      return;
    }

    _columnDragFeedbackOverlay = OverlayEntry(
      builder: (overlayContext) {
        final column = _draggedColumn;
        final globalPosition = _latestColumnDragPosition;
        if (column == null || globalPosition == null) {
          return const SizedBox.shrink();
        }

        final dimensions = AgusThemeData.dimensionsOf(overlayContext);
        final overlayBox = overlay.context.findRenderObject() as RenderBox?;
        final overlayPosition =
            overlayBox?.globalToLocal(globalPosition) ?? globalPosition;

        return Positioned(
          left: overlayPosition.dx + 12,
          top: overlayPosition.dy - dimensions.treeRowHeight / 2,
          child: IgnorePointer(
            child: _TreeColumnDragFeedback(
              column: column,
              width: _widthFor(column),
            ),
          ),
        );
      },
    );
    overlay.insert(_columnDragFeedbackOverlay!);
  }

  void _hideColumnDragFeedbackOverlay() {
    _columnDragFeedbackOverlay?.remove();
    _columnDragFeedbackOverlay = null;
  }

  AgusTreeColumn? get _draggedColumn {
    final draggedColumnId = _draggedColumnId;
    if (draggedColumnId == null) {
      return null;
    }

    for (final column in widget.columns) {
      if (column.id == draggedColumnId) {
        return column;
      }
    }

    return null;
  }

  void _handleHorizontalScroll() {
    if (_horizontalController.offset == _horizontalOffset) {
      return;
    }

    setState(() => _horizontalOffset = _horizontalController.offset);
  }

  void _scrollHorizontallyBy(double delta) {
    if (!_horizontalController.hasClients) {
      return;
    }

    final position = _horizontalController.position;
    final nextOffset = (_horizontalController.offset - delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if (nextOffset == _horizontalController.offset) {
      return;
    }

    _horizontalController.jumpTo(nextOffset);
  }
}

class _VisibleTreeRow {
  const _VisibleTreeRow(this.node, this.depth);

  final AgusTreeNode node;
  final int depth;
}

enum _TreeColumnDropSide { before, after }

@immutable
class _TreeColumnDropIntent {
  const _TreeColumnDropIntent({required this.targetId, required this.side});

  final String targetId;
  final _TreeColumnDropSide side;
}

class _TreeRowView extends StatelessWidget {
  const _TreeRowView({
    required this.node,
    required this.depth,
    required this.labelColumnWidth,
    required this.columns,
    required this.columnWidths,
    required this.scrollableWidth,
    required this.horizontalOffset,
    required this.onHorizontalDragDelta,
    required this.selected,
    required this.expanded,
    required this.visibilityIcons,
    required this.isEditing,
    required this.renameController,
    this.onSelected,
    this.onToggle,
    this.onBeginRename,
    this.onLabelPointerDown,
    this.onRenameSubmitted,
    this.onRenameCancelled,
    this.onDelete,
    this.onVisibilityChanged,
    this.onContextMenuRequested,
  });

  final AgusTreeNode node;
  final int depth;
  final double labelColumnWidth;
  final List<AgusTreeColumn> columns;
  final List<double> columnWidths;
  final double scrollableWidth;
  final double horizontalOffset;
  final ValueChanged<double> onHorizontalDragDelta;
  final bool selected;
  final bool expanded;
  final AgusTreeVisibilityIcons visibilityIcons;
  final bool isEditing;
  final TextEditingController? renameController;
  final ValueChanged<String>? onSelected;
  final ValueChanged<String>? onToggle;
  final ValueChanged<AgusTreeNode>? onBeginRename;
  final ValueChanged<AgusTreeNode>? onLabelPointerDown;
  final void Function(AgusTreeNode node, String value)? onRenameSubmitted;
  final VoidCallback? onRenameCancelled;
  final ValueChanged<String>? onDelete;
  final void Function(String id, AgusTreeVisibilityState visibility)?
  onVisibilityChanged;
  final AgusTreeNodeContextMenuCallback? onContextMenuRequested;

  @override
  Widget build(BuildContext context) {
    return _InteractiveTreeRowView(
      node: node,
      depth: depth,
      labelColumnWidth: labelColumnWidth,
      columns: columns,
      columnWidths: columnWidths,
      scrollableWidth: scrollableWidth,
      horizontalOffset: horizontalOffset,
      onHorizontalDragDelta: onHorizontalDragDelta,
      selected: selected,
      expanded: expanded,
      visibilityIcons: visibilityIcons,
      isEditing: isEditing,
      renameController: renameController,
      onSelected: onSelected,
      onToggle: onToggle,
      onBeginRename: onBeginRename,
      onLabelPointerDown: onLabelPointerDown,
      onRenameSubmitted: onRenameSubmitted,
      onRenameCancelled: onRenameCancelled,
      onDelete: onDelete,
      onVisibilityChanged: onVisibilityChanged,
      onContextMenuRequested: onContextMenuRequested,
    );
  }
}

class _InteractiveTreeRowView extends StatefulWidget {
  const _InteractiveTreeRowView({
    required this.node,
    required this.depth,
    required this.labelColumnWidth,
    required this.columns,
    required this.columnWidths,
    required this.scrollableWidth,
    required this.horizontalOffset,
    required this.onHorizontalDragDelta,
    required this.selected,
    required this.expanded,
    required this.visibilityIcons,
    required this.isEditing,
    required this.renameController,
    this.onSelected,
    this.onToggle,
    this.onBeginRename,
    this.onLabelPointerDown,
    this.onRenameSubmitted,
    this.onRenameCancelled,
    this.onDelete,
    this.onVisibilityChanged,
    this.onContextMenuRequested,
  });

  final AgusTreeNode node;
  final int depth;
  final double labelColumnWidth;
  final List<AgusTreeColumn> columns;
  final List<double> columnWidths;
  final double scrollableWidth;
  final double horizontalOffset;
  final ValueChanged<double> onHorizontalDragDelta;
  final bool selected;
  final bool expanded;
  final AgusTreeVisibilityIcons visibilityIcons;
  final bool isEditing;
  final TextEditingController? renameController;
  final ValueChanged<String>? onSelected;
  final ValueChanged<String>? onToggle;
  final ValueChanged<AgusTreeNode>? onBeginRename;
  final ValueChanged<AgusTreeNode>? onLabelPointerDown;
  final void Function(AgusTreeNode node, String value)? onRenameSubmitted;
  final VoidCallback? onRenameCancelled;
  final ValueChanged<String>? onDelete;
  final void Function(String id, AgusTreeVisibilityState visibility)?
  onVisibilityChanged;
  final AgusTreeNodeContextMenuCallback? onContextMenuRequested;

  @override
  State<_InteractiveTreeRowView> createState() =>
      _InteractiveTreeRowViewState();
}

class _InteractiveTreeRowViewState extends State<_InteractiveTreeRowView> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);
    final dimensions = AgusThemeData.dimensionsOf(context);
    final foreground = widget.node.disabled
        ? colors.sideBarForeground.withValues(alpha: 0.45)
        : colors.sideBarForeground;

    return Semantics(
      button: true,
      selected: widget.selected,
      enabled: !widget.node.disabled,
      label: widget.node.label,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: SizedBox(
          height: dimensions.treeRowHeight,
          child: Material(
            color: widget.selected
                ? colors.selectionBackground
                : _hovered
                ? colors.hoverBackground.withValues(alpha: 0.65)
                : Colors.transparent,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onSecondaryTapDown: widget.onContextMenuRequested == null
                  ? null
                  : (details) => widget.onContextMenuRequested!(
                      widget.node.id,
                      details.globalPosition,
                    ),
              child: InkWell(
                hoverColor: Colors.transparent,
                onTap: widget.node.disabled
                    ? null
                    : () => widget.onSelected?.call(widget.node.id),
                child: Row(
                  children: [
                    SizedBox(
                      width: widget.labelColumnWidth,
                      child: _TreeLabelCell(
                        node: widget.node,
                        depth: widget.depth,
                        expanded: widget.expanded,
                        foreground: foreground,
                        visibilityIcons: widget.visibilityIcons,
                        isEditing: widget.isEditing,
                        renameController: widget.renameController,
                        hovered: _hovered,
                        onToggle: widget.onToggle,
                        onVisibilityChanged: widget.onVisibilityChanged,
                        onLabelPointerDown: widget.onLabelPointerDown,
                        onRenameSubmitted: widget.onRenameSubmitted,
                        onRenameCancelled: widget.onRenameCancelled,
                        onDelete: widget.onDelete,
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onHorizontalDragUpdate: (details) => widget
                            .onHorizontalDragDelta(details.primaryDelta ?? 0),
                        child: ClipRect(
                          child: Transform.translate(
                            offset: Offset(-widget.horizontalOffset, 0),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              widthFactor: 1,
                              child: OverflowBox(
                                alignment: Alignment.centerLeft,
                                minWidth: widget.scrollableWidth,
                                maxWidth: widget.scrollableWidth,
                                child: SizedBox(
                                  width: widget.scrollableWidth,
                                  child: Row(
                                    children: [
                                      for (
                                        var index = 0;
                                        index < widget.columns.length;
                                        index++
                                      )
                                        _TreeMetricCell(
                                          column: widget.columns[index],
                                          width: widget.columnWidths[index],
                                          value:
                                              widget.node.columnValues[widget
                                                  .columns[index]
                                                  .id] ??
                                              '—',
                                          foreground: foreground,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TreeLabelCell extends StatelessWidget {
  const _TreeLabelCell({
    required this.node,
    required this.depth,
    required this.expanded,
    required this.foreground,
    required this.visibilityIcons,
    required this.isEditing,
    required this.renameController,
    required this.hovered,
    this.onToggle,
    this.onVisibilityChanged,
    this.onLabelPointerDown,
    this.onRenameSubmitted,
    this.onRenameCancelled,
    this.onDelete,
  });

  final AgusTreeNode node;
  final int depth;
  final bool expanded;
  final Color foreground;
  final AgusTreeVisibilityIcons visibilityIcons;
  final bool isEditing;
  final TextEditingController? renameController;
  final bool hovered;
  final ValueChanged<String>? onToggle;
  final void Function(String id, AgusTreeVisibilityState visibility)?
  onVisibilityChanged;
  final ValueChanged<AgusTreeNode>? onLabelPointerDown;
  final void Function(AgusTreeNode node, String value)? onRenameSubmitted;
  final VoidCallback? onRenameCancelled;
  final ValueChanged<String>? onDelete;

  @override
  Widget build(BuildContext context) {
    final dimensions = AgusThemeData.dimensionsOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : double.infinity;
        final actionWidth = math.min(32.0, maxWidth);
        final badgeWidth = node.badgeLabel == null
            ? 0.0
            : math.min(32.0, math.max(0.0, maxWidth - actionWidth));
        final iconIndent = 4 + depth * dimensions.treeIndent;
        final toggleX = iconIndent.toDouble();
        final visibilityX = toggleX + 18;
        final fileIconX = visibilityX + 20;
        final rawLabelLeft = fileIconX + (node.icon == null ? 0 : 22);
        final labelRight = actionWidth + badgeWidth;
        final labelLeft = math.min(
          rawLabelLeft,
          math.max(0.0, maxWidth - labelRight),
        );
        final labelWidth = math.max(0.0, maxWidth - labelLeft - labelRight);

        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (node.children.isNotEmpty)
                _PositionedTreeIcon(
                  left: toggleX,
                  maxWidth: maxWidth,
                  width: 16,
                  child: InkWell(
                    onTap: () => onToggle?.call(node.id),
                    child: Icon(
                      expanded
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_right,
                      size: 16,
                      color: foreground,
                    ),
                  ),
                ),
              if (node.visibility != null)
                _PositionedTreeIcon(
                  left: visibilityX,
                  maxWidth: maxWidth,
                  width: 20,
                  child: InkWell(
                    onTap:
                        node.visibility == AgusTreeVisibilityState.locked ||
                            onVisibilityChanged == null
                        ? null
                        : () => onVisibilityChanged!(
                            node.id,
                            _nextVisibility(node.visibility!),
                          ),
                    child: Icon(
                      visibilityIcons.iconFor(node.visibility!),
                      size: 15,
                      color: foreground.withValues(alpha: 0.88),
                    ),
                  ),
                ),
              if (node.icon != null)
                _PositionedTreeIcon(
                  left: fileIconX,
                  maxWidth: maxWidth,
                  width: 16,
                  child: Icon(node.icon, size: 16, color: foreground),
                ),
              if (labelWidth > 0)
                Positioned(
                  left: labelLeft,
                  right: labelRight,
                  top: 0,
                  bottom: 0,
                  child: Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (_) => onLabelPointerDown?.call(node),
                    child: isEditing && renameController != null
                        ? TextField(
                            controller: renameController,
                            autofocus: true,
                            onSubmitted: (value) =>
                                onRenameSubmitted?.call(node, value),
                            onTapOutside: (_) => onRenameCancelled?.call(),
                            decoration: const InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                            ),
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(color: foreground),
                          )
                        : Tooltip(
                            message: node.label,
                            waitDuration: const Duration(milliseconds: 350),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                node.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: foreground),
                              ),
                            ),
                          ),
                  ),
                ),
              if (node.badgeLabel != null && badgeWidth > 0)
                Positioned(
                  right: actionWidth,
                  top: 0,
                  bottom: 0,
                  width: badgeWidth,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Tooltip(
                      message: node.badgeLabel!,
                      waitDuration: const Duration(milliseconds: 350),
                      child: Text(
                        node.badgeLabel!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: foreground.withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                  ),
                ),
              if (actionWidth > 0)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: actionWidth,
                  child: hovered && node.deletable && onDelete != null
                      ? IconButton(
                          tooltip: 'Delete ${node.label}',
                          constraints: const BoxConstraints.tightFor(
                            width: 28,
                            height: 28,
                          ),
                          padding: EdgeInsets.zero,
                          icon: Icon(
                            Icons.delete_outline,
                            size: 16,
                            color: foreground.withValues(alpha: 0.8),
                          ),
                          onPressed: () => onDelete?.call(node.id),
                        )
                      : const SizedBox.shrink(),
                ),
            ],
          ),
        );
      },
    );
  }

  AgusTreeVisibilityState _nextVisibility(AgusTreeVisibilityState state) {
    return switch (state) {
      AgusTreeVisibilityState.visible => AgusTreeVisibilityState.hidden,
      AgusTreeVisibilityState.hidden => AgusTreeVisibilityState.visible,
      AgusTreeVisibilityState.mixed => AgusTreeVisibilityState.visible,
      AgusTreeVisibilityState.locked => AgusTreeVisibilityState.locked,
    };
  }
}

class _TreeMetricCell extends StatelessWidget {
  const _TreeMetricCell({
    required this.column,
    required this.width,
    required this.value,
    required this.foreground,
  });

  final AgusTreeColumn column;
  final double width;
  final String value;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    if (width <= 0) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Align(
          alignment: _alignmentFor(column.alignment),
          child: Tooltip(
            message: value,
            waitDuration: const Duration(milliseconds: 350),
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: foreground.withValues(alpha: 0.76),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PositionedTreeIcon extends StatelessWidget {
  const _PositionedTreeIcon({
    required this.left,
    required this.maxWidth,
    required this.width,
    required this.child,
  });

  final double left;
  final double maxWidth;
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (left >= maxWidth || width <= 0) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: left,
      top: 0,
      bottom: 0,
      width: math.min(width, math.max(0, maxWidth - left)),
      child: Center(child: child),
    );
  }
}

class _TreeHeaderRow extends StatelessWidget {
  const _TreeHeaderRow({
    required this.label,
    required this.labelColumnWidth,
    required this.columns,
    required this.columnWidths,
    required this.horizontalController,
    required this.scrollableWidth,
    required this.labelResizable,
    required this.columnReorderable,
    required this.draggedColumnId,
    required this.columnDropIntent,
    required this.onLabelResizeDelta,
    required this.onColumnResizeDelta,
    required this.keyForColumn,
    required this.onColumnDragStart,
    required this.onColumnDragUpdate,
    required this.onColumnDragEnd,
    required this.onColumnDragCancel,
  });

  final String label;
  final double labelColumnWidth;
  final List<AgusTreeColumn> columns;
  final List<double> columnWidths;
  final ScrollController horizontalController;
  final double scrollableWidth;
  final bool labelResizable;
  final bool columnReorderable;
  final String? draggedColumnId;
  final _TreeColumnDropIntent? columnDropIntent;
  final ValueChanged<double> onLabelResizeDelta;
  final void Function(AgusTreeColumn column, double delta) onColumnResizeDelta;
  final GlobalKey Function(String columnId) keyForColumn;
  final void Function(String columnId, Offset globalPosition) onColumnDragStart;
  final ValueChanged<Offset> onColumnDragUpdate;
  final VoidCallback onColumnDragEnd;
  final VoidCallback onColumnDragCancel;

  @override
  Widget build(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);
    final dimensions = AgusThemeData.dimensionsOf(context);

    return SizedBox(
      height: dimensions.treeRowHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.sideBarBorder)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: labelColumnWidth,
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 42, right: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Tooltip(
                        message: label,
                        waitDuration: const Duration(milliseconds: 350),
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: colors.sideBarForeground.withValues(
                                  alpha: 0.65,
                                ),
                                letterSpacing: 0.4,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ),
                  ),
                  if (labelResizable)
                    _TreeResizeHandle(onResizeDelta: onLabelResizeDelta),
                ],
              ),
            ),
            Expanded(
              child: Scrollbar(
                controller: horizontalController,
                interactive: true,
                notificationPredicate: (notification) =>
                    notification.metrics.axis == Axis.horizontal,
                radius: const Radius.circular(999),
                thickness: 3,
                child: SingleChildScrollView(
                  controller: horizontalController,
                  scrollDirection: Axis.horizontal,
                  physics: const ClampingScrollPhysics(),
                  child: SizedBox(
                    width: scrollableWidth,
                    child: Row(
                      children: [
                        for (var index = 0; index < columns.length; index++)
                          _buildMetricColumn(index),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricColumn(int index) {
    final column = columns[index];
    final cell = _TreeHeaderMetricCell(
      column: column,
      width: columnWidths[index],
      onResizeDelta: onColumnResizeDelta,
    );
    final keyedCell = KeyedSubtree(key: keyForColumn(column.id), child: cell);

    if (!columnReorderable) {
      return keyedCell;
    }

    final dropSide = columnDropIntent?.targetId == column.id
        ? columnDropIntent?.side
        : null;

    return _TreeColumnDropIndicator(
      active: dropSide != null && draggedColumnId != column.id,
      side: dropSide ?? _TreeColumnDropSide.before,
      targetId: column.id,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (details) =>
            onColumnDragStart(column.id, details.globalPosition),
        onHorizontalDragUpdate: (details) =>
            onColumnDragUpdate(details.globalPosition),
        onHorizontalDragEnd: (_) => onColumnDragEnd(),
        onHorizontalDragCancel: onColumnDragCancel,
        child: Opacity(
          opacity: draggedColumnId == column.id ? 0.35 : 1,
          child: keyedCell,
        ),
      ),
    );
  }
}

class _TreeColumnDropIndicator extends StatelessWidget {
  const _TreeColumnDropIndicator({
    required this.active,
    required this.side,
    required this.targetId,
    required this.child,
  });

  final bool active;
  final _TreeColumnDropSide side;
  final String targetId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        if (active)
          Positioned(
            key: ValueKey<String>(
              'agus-tree-column-drop-$targetId-${side.name}',
            ),
            top: 3,
            bottom: 3,
            left: side == _TreeColumnDropSide.before ? -1.5 : null,
            right: side == _TreeColumnDropSide.after ? -1.5 : null,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.focusBorder,
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: colors.focusBorder.withValues(alpha: 0.65),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: const SizedBox(width: 3),
            ),
          ),
      ],
    );
  }
}

class _TreeColumnDragFeedback extends StatelessWidget {
  const _TreeColumnDragFeedback({required this.column, required this.width});

  final AgusTreeColumn column;
  final double width;

  @override
  Widget build(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);
    final dimensions = AgusThemeData.dimensionsOf(context);

    return Material(
      key: const ValueKey<String>('agus-tree-column-drag-feedback'),
      type: MaterialType.transparency,
      child: Opacity(
        opacity: 0.92,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.sideBarBackground,
            border: Border.all(color: colors.focusBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: SizedBox(
            width: width,
            height: dimensions.treeRowHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Align(
                alignment: _alignmentFor(column.alignment),
                child: Text(
                  column.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.sideBarForeground.withValues(alpha: 0.8),
                    letterSpacing: 0.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TreeHeaderMetricCell extends StatelessWidget {
  const _TreeHeaderMetricCell({
    required this.column,
    required this.width,
    required this.onResizeDelta,
  });

  final AgusTreeColumn column;
  final double width;
  final void Function(AgusTreeColumn column, double delta) onResizeDelta;

  @override
  Widget build(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);
    if (width <= 0) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      width: width,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, right: 8),
            child: Align(
              alignment: _alignmentFor(column.alignment),
              child: Text(
                column.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.sideBarForeground.withValues(alpha: 0.65),
                  letterSpacing: 0.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          if (column.resizable)
            _TreeResizeHandle(
              onResizeDelta: (delta) => onResizeDelta(column, delta),
            ),
        ],
      ),
    );
  }
}

class _TreeResizeHandle extends StatefulWidget {
  const _TreeResizeHandle({required this.onResizeDelta});

  final ValueChanged<double> onResizeDelta;

  @override
  State<_TreeResizeHandle> createState() => _TreeResizeHandleState();
}

class _TreeResizeHandleState extends State<_TreeResizeHandle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);

    return Positioned(
      top: 0,
      right: 0,
      bottom: 0,
      width: 8,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragUpdate: (details) {
            widget.onResizeDelta(details.primaryDelta ?? 0);
          },
          child: Align(
            alignment: Alignment.centerRight,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 80),
              width: _hovered ? 2 : 1,
              color: _hovered
                  ? colors.focusBorder
                  : colors.sideBarBorder.withValues(alpha: 0.65),
            ),
          ),
        ),
      ),
    );
  }
}

Alignment _alignmentFor(AgusTreeColumnAlignment alignment) {
  return switch (alignment) {
    AgusTreeColumnAlignment.start => Alignment.centerLeft,
    AgusTreeColumnAlignment.center => Alignment.center,
    AgusTreeColumnAlignment.end => Alignment.centerRight,
  };
}
