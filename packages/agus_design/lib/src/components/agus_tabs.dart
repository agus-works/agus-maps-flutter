import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/agus_theme_data.dart';

/// Visual variant for tab bar appearance.
enum AgusTabVariant {
  /// Large editor-style tabs with icons, dirty state, and preview italics.
  editor,

  /// Compact panel-style tabs with uppercase labels.
  panel,
}

/// Called with the full tab list after a tab has been reordered.
typedef AgusTabReorderCallback = void Function(List<AgusTab> tabs);

/// Immutable data used by [AgusTabBar] to render a tab.
@immutable
class AgusTab {
  /// Creates a tab with customizable states.
  const AgusTab({
    required this.id,
    required this.label,
    this.icon,
    this.dirty = false,
    this.pinned = false,
    this.preview = false,
    this.closable = true,
  });

  /// Stable identifier used for selection, close, scrolling, and reordering.
  final String id;

  /// User-visible text shown in the tab.
  final String label;

  /// Optional leading icon for file type or editor context.
  final IconData? icon;

  /// Whether the tab has unsaved changes.
  final bool dirty;

  /// Whether the tab is pinned and should show the pinned affordance.
  final bool pinned;

  /// Whether the tab is a preview editor and should render italic text.
  final bool preview;

  /// Whether the tab shows a close button when it is not dirty.
  final bool closable;
}

/// A horizontally scrollable tab strip with selection, close, and
/// optional drag reordering.
class AgusTabBar extends StatefulWidget {
  /// Creates a tab bar for the provided [tabs].
  const AgusTabBar({
    required this.tabs,
    required this.selectedId,
    this.variant = AgusTabVariant.editor,
    this.trailing = const <Widget>[],
    this.onSelected,
    this.onClose,
    this.onReorder,
    super.key,
  });

  /// Tabs rendered from left to right.
  final List<AgusTab> tabs;

  /// Identifier of the currently selected tab, or null when nothing is active.
  final String? selectedId;

  /// Visual style variant.
  final AgusTabVariant variant;

  /// Widgets pinned to the trailing edge of the strip (panel variant only).
  final List<Widget> trailing;

  /// Called when a tab is selected.
  final ValueChanged<String>? onSelected;

  /// Called when a tab close button is pressed.
  final ValueChanged<String>? onClose;

  /// Called with a reordered copy of [tabs] after a tab is dragged and dropped.
  ///
  /// Leave this null to disable tab reordering. Only available for editor variant.
  final AgusTabReorderCallback? onReorder;

  @override
  State<AgusTabBar> createState() => _AgusTabBarState();
}

class _AgusTabBarState extends State<AgusTabBar> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _tabKeys = <String, GlobalKey>{};
  OverlayEntry? _dragFeedbackOverlay;

  String? _draggedTabId;
  _TabDropIntent? _dropIntent;
  Offset? _latestDragPosition;

  bool get _isEditorVariant => widget.variant == AgusTabVariant.editor;
  bool get _canReorder => _isEditorVariant && widget.onReorder != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelectedTab());
  }

  @override
  void didUpdateWidget(covariant AgusTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _tabKeys.removeWhere((id, _) => !widget.tabs.any((tab) => tab.id == id));
    if (oldWidget.selectedId != widget.selectedId ||
        !_hasSameTabOrder(oldWidget.tabs, widget.tabs)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelectedTab());
    }
  }

  @override
  void dispose() {
    _hideDragFeedbackOverlay();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);
    final dimensions = AgusThemeData.dimensionsOf(context);

    final backgroundColor = _isEditorVariant
        ? colors.tabInactiveBackground
        : colors.panelBackground;
    final borderColor = _isEditorVariant
        ? colors.tabBorder
        : colors.panelBorder;
    final height = _isEditorVariant
        ? dimensions.editorTabHeight
        : dimensions.panelTabHeight;

    return Material(
      color: backgroundColor,
      child: SizedBox(
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: borderColor)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Listener(
                  onPointerSignal: _handlePointerSignal,
                  child: Scrollbar(
                    controller: _scrollController,
                    interactive: true,
                    notificationPredicate: (notification) =>
                        notification.metrics.axis == Axis.horizontal,
                    radius: const Radius.circular(999),
                    thickness: 3,
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      scrollDirection: Axis.horizontal,
                      physics: _canReorder
                          ? const NeverScrollableScrollPhysics()
                          : const ClampingScrollPhysics(),
                      child: Row(
                        children: [
                          for (final tab in widget.tabs) _buildTab(tab),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (!_isEditorVariant) ...widget.trailing,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTab(AgusTab tab) {
    final tabButton = AgusTabButton(
      tab: tab,
      selected: tab.id == widget.selectedId,
      variant: widget.variant,
      onSelected: widget.onSelected,
      onClose: widget.onClose,
    );
    final keyedTabButton = KeyedSubtree(
      key: _keyForTab(tab.id),
      child: tabButton,
    );

    if (!_canReorder) {
      return keyedTabButton;
    }

    final isDragging = _draggedTabId == tab.id;
    final dropSide = _dropIntent?.targetId == tab.id ? _dropIntent?.side : null;

    return _TabDropIndicator(
      active: dropSide != null && _draggedTabId != tab.id,
      side: dropSide ?? _TabDropSide.before,
      targetId: tab.id,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (details) =>
            _startTabDrag(tab.id, details.globalPosition),
        onHorizontalDragUpdate: (details) =>
            _updateTabDrag(details.globalPosition),
        onHorizontalDragEnd: (_) => _finishTabDrag(),
        onHorizontalDragCancel: _cancelTabDrag,
        child: Opacity(opacity: isDragging ? 0.35 : 1, child: keyedTabButton),
      ),
    );
  }

  GlobalKey _keyForTab(String id) {
    return _tabKeys.putIfAbsent(id, GlobalKey.new);
  }

  bool _hasSameTabOrder(List<AgusTab> oldTabs, List<AgusTab> newTabs) {
    if (oldTabs.length != newTabs.length) {
      return false;
    }

    for (var index = 0; index < oldTabs.length; index++) {
      if (oldTabs[index].id != newTabs[index].id) {
        return false;
      }
    }

    return true;
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scrollController.hasClients) {
      return;
    }

    final delta = event.scrollDelta.dx != 0
        ? event.scrollDelta.dx
        : event.scrollDelta.dy;
    if (delta == 0) {
      return;
    }

    final position = _scrollController.position;
    final nextOffset = (_scrollController.offset + delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if (nextOffset == _scrollController.offset) {
      return;
    }

    _scrollController.jumpTo(nextOffset);
  }

  void _revealSelectedTab() {
    final selectedId = widget.selectedId;
    if (!mounted || selectedId == null) {
      return;
    }

    final tabContext = _tabKeys[selectedId]?.currentContext;
    if (tabContext == null) {
      return;
    }

    Scrollable.ensureVisible(
      tabContext,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
      alignment: 0.5,
    );
  }

  void _startTabDrag(String tabId, Offset globalPosition) {
    _showDragFeedbackOverlay();
    setState(() {
      _draggedTabId = tabId;
      _latestDragPosition = globalPosition;
      _dropIntent = _dropIntentAtPosition(globalPosition);
    });
    _dragFeedbackOverlay?.markNeedsBuild();
  }

  void _updateTabDrag(Offset globalPosition) {
    setState(() {
      _latestDragPosition = globalPosition;
      _dropIntent = _dropIntentAtPosition(globalPosition);
    });
    _dragFeedbackOverlay?.markNeedsBuild();
  }

  void _finishTabDrag() {
    final draggedTabId = _draggedTabId;
    final dropIntent = _dropIntent;
    _cancelTabDrag();

    if (draggedTabId == null || dropIntent == null) {
      return;
    }

    _reorderTab(draggedTabId, dropIntent);
  }

  void _cancelTabDrag() {
    _hideDragFeedbackOverlay();
    setState(() {
      _draggedTabId = null;
      _dropIntent = null;
      _latestDragPosition = null;
    });
  }

  void _reorderTab(String draggedTabId, _TabDropIntent dropIntent) {
    final onReorder = widget.onReorder;
    if (onReorder == null || draggedTabId == dropIntent.targetId) {
      return;
    }

    final oldIndex = widget.tabs.indexWhere((tab) => tab.id == draggedTabId);
    final targetIndex = widget.tabs.indexWhere(
      (tab) => tab.id == dropIntent.targetId,
    );
    if (oldIndex == -1 || targetIndex == -1) {
      return;
    }

    final insertionIndex = dropIntent.side == _TabDropSide.before
        ? targetIndex
        : targetIndex + 1;
    final newIndex = oldIndex < insertionIndex
        ? insertionIndex - 1
        : insertionIndex;
    if (oldIndex == newIndex) {
      return;
    }

    final reorderedTabs = List<AgusTab>.of(widget.tabs);
    final draggedTab = reorderedTabs.removeAt(oldIndex);
    reorderedTabs.insert(newIndex, draggedTab);
    onReorder(List<AgusTab>.unmodifiable(reorderedTabs));
  }

  _TabDropIntent? _dropIntentAtPosition(Offset globalPosition) {
    String? firstTabId;
    String? lastTabId;
    Rect? firstTabRect;
    Rect? lastTabRect;

    for (final tab in widget.tabs) {
      final targetContext = _tabKeys[tab.id]?.currentContext;
      final renderObject = targetContext?.findRenderObject();
      if (renderObject is! RenderBox) {
        continue;
      }

      final tabRect =
          renderObject.localToGlobal(Offset.zero) & renderObject.size;
      firstTabId ??= tab.id;
      firstTabRect ??= tabRect;
      lastTabId = tab.id;
      lastTabRect = tabRect;

      if (tabRect.contains(globalPosition)) {
        final side = globalPosition.dx < tabRect.center.dx
            ? _TabDropSide.before
            : _TabDropSide.after;
        return _TabDropIntent(targetId: tab.id, side: side);
      }
    }

    if (firstTabId == null || firstTabRect == null || lastTabRect == null) {
      return null;
    }

    final withinTabStripHeight =
        globalPosition.dy >= firstTabRect.top &&
        globalPosition.dy <= firstTabRect.bottom;
    if (!withinTabStripHeight) {
      return null;
    }

    if (globalPosition.dx < firstTabRect.left) {
      return _TabDropIntent(targetId: firstTabId, side: _TabDropSide.before);
    }
    if (lastTabId != null && globalPosition.dx > lastTabRect.right) {
      return _TabDropIntent(targetId: lastTabId, side: _TabDropSide.after);
    }

    return null;
  }

  void _showDragFeedbackOverlay() {
    if (_dragFeedbackOverlay != null) {
      return;
    }

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      return;
    }

    _dragFeedbackOverlay = OverlayEntry(
      builder: (overlayContext) {
        final tab = _draggedTab;
        final globalPosition = _latestDragPosition;
        if (tab == null || globalPosition == null) {
          return const SizedBox.shrink();
        }

        final dimensions = AgusThemeData.dimensionsOf(overlayContext);
        final overlayBox = overlay.context.findRenderObject() as RenderBox?;
        final overlayPosition =
            overlayBox?.globalToLocal(globalPosition) ?? globalPosition;

        return Positioned(
          left: overlayPosition.dx + 12,
          top: overlayPosition.dy - dimensions.editorTabHeight / 2,
          child: IgnorePointer(
            child: _TabDragFeedback(
              tab: tab,
              selected: tab.id == widget.selectedId,
              variant: widget.variant,
            ),
          ),
        );
      },
    );
    overlay.insert(_dragFeedbackOverlay!);
  }

  void _hideDragFeedbackOverlay() {
    _dragFeedbackOverlay?.remove();
    _dragFeedbackOverlay = null;
  }

  AgusTab? get _draggedTab {
    final draggedTabId = _draggedTabId;
    if (draggedTabId == null) {
      return null;
    }

    for (final tab in widget.tabs) {
      if (tab.id == draggedTabId) {
        return tab;
      }
    }

    return null;
  }
}

enum _TabDropSide { before, after }

@immutable
class _TabDropIntent {
  const _TabDropIntent({required this.targetId, required this.side});

  final String targetId;
  final _TabDropSide side;
}

class _TabDropIndicator extends StatelessWidget {
  const _TabDropIndicator({
    required this.active,
    required this.side,
    required this.targetId,
    required this.child,
  });

  final bool active;
  final _TabDropSide side;
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
              'agus-editor-tab-drop-$targetId-${side.name}',
            ),
            top: 3,
            bottom: 3,
            left: side == _TabDropSide.before ? -1.5 : null,
            right: side == _TabDropSide.after ? -1.5 : null,
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

class _TabDragFeedback extends StatelessWidget {
  const _TabDragFeedback({
    required this.tab,
    required this.selected,
    required this.variant,
  });

  final AgusTab tab;
  final bool selected;
  final AgusTabVariant variant;

  @override
  Widget build(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);

    return Material(
      key: const ValueKey<String>('agus-editor-tab-drag-feedback'),
      type: MaterialType.transparency,
      child: Opacity(
        opacity: 0.92,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: colors.focusBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Transform.scale(
            scale: 1.02,
            alignment: Alignment.centerLeft,
            child: AgusTabButton(
              tab: tab,
              selected: selected,
              variant: variant,
            ),
          ),
        ),
      ),
    );
  }
}

/// A single tab button used inside [AgusTabBar].
class AgusTabButton extends StatelessWidget {
  /// Creates a tab button for [tab].
  const AgusTabButton({
    required this.tab,
    required this.selected,
    this.variant = AgusTabVariant.editor,
    this.onSelected,
    this.onClose,
    super.key,
  });

  /// Tab data rendered by this button.
  final AgusTab tab;

  /// Whether this button represents the selected tab.
  final bool selected;

  /// Visual style variant.
  final AgusTabVariant variant;

  /// Called when the button body is tapped.
  final ValueChanged<String>? onSelected;

  /// Called when the close affordance is pressed.
  final ValueChanged<String>? onClose;

  @override
  Widget build(BuildContext context) {
    return variant == AgusTabVariant.editor
        ? _buildEditorTab(context)
        : _buildPanelTab(context);
  }

  Widget _buildEditorTab(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);
    final dimensions = AgusThemeData.dimensionsOf(context);
    final foreground = selected
        ? colors.tabActiveForeground
        : colors.tabInactiveForeground;

    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: selected,
        label: tab.label,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 120, maxWidth: 220),
          child: SizedBox(
            height: dimensions.editorTabHeight,
            child: Material(
              color: selected
                  ? colors.tabActiveBackground
                  : colors.tabInactiveBackground,
              child: InkWell(
                hoverColor: colors.hoverBackground,
                onTap: () => onSelected?.call(tab.id),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(color: colors.tabBorder),
                      top: BorderSide(
                        color: selected
                            ? colors.focusBorder
                            : Colors.transparent,
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 10, right: 4),
                    child: Row(
                      children: [
                        if (tab.icon != null) ...[
                          Icon(tab.icon, size: 16, color: foreground),
                          const SizedBox(width: 6),
                        ],
                        if (tab.pinned) ...[
                          Icon(Icons.push_pin, size: 13, color: foreground),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            tab.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: foreground,
                                  fontStyle: tab.preview
                                      ? FontStyle.italic
                                      : FontStyle.normal,
                                ),
                          ),
                        ),
                        if (tab.dirty)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(left: 6, right: 3),
                            decoration: BoxDecoration(
                              color: colors.tabDirtyIndicator,
                              shape: BoxShape.circle,
                            ),
                          )
                        else if (tab.closable)
                          IconButton(
                            tooltip: 'Close ${tab.label}',
                            icon: Icon(
                              Icons.close,
                              color: foreground,
                              size: 14,
                            ),
                            constraints: const BoxConstraints.tightFor(
                              width: 24,
                              height: 24,
                            ),
                            padding: EdgeInsets.zero,
                            splashRadius: 12,
                            onPressed: () => onClose?.call(tab.id),
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
    );
  }

  Widget _buildPanelTab(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);
    final dimensions = AgusThemeData.dimensionsOf(context);
    final foreground = selected
        ? colors.panelTabActiveForeground
        : colors.panelTabInactiveForeground;

    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: selected,
        label: tab.label,
        child: Material(
          color: selected ? colors.editorBackground : Colors.transparent,
          child: InkWell(
            hoverColor: colors.hoverBackground,
            onTap: () => onSelected?.call(tab.id),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: selected ? colors.focusBorder : Colors.transparent,
                    width: 1,
                  ),
                  right: BorderSide(color: colors.panelBorder),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.only(left: 10, right: 6),
                child: SizedBox(
                  height: dimensions.panelTabHeight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (tab.icon != null) ...[
                        Icon(
                          tab.icon,
                          size: dimensions.iconSize,
                          color: foreground,
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        tab.label.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: foreground,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          letterSpacing: 0.2,
                        ),
                      ),
                      if (tab.closable) ...[
                        const SizedBox(width: 4),
                        IconButton(
                          tooltip: 'Close ${tab.label}',
                          icon: const Icon(Icons.close),
                          iconSize: dimensions.iconSize,
                          color: foreground,
                          constraints: BoxConstraints.tightFor(
                            width: dimensions.toolbarButtonSize,
                            height: dimensions.toolbarButtonSize,
                          ),
                          padding: EdgeInsets.zero,
                          onPressed: onClose == null
                              ? null
                              : () => onClose!(tab.id),
                        ),
                      ],
                    ],
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
