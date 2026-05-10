import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/agus_theme_data.dart';

/// Called with the full tab list after an editor tab has been reordered.
typedef AgusEditorTabReorderCallback = void Function(List<AgusEditorTab> tabs);

/// Immutable data used by [AgusEditorTabBar] to render an editor tab.
@immutable
class AgusEditorTab {
  /// Creates an editor tab with VS Code-like pinned, dirty, preview, and close
  /// states.
  const AgusEditorTab({
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

/// A horizontally scrollable editor tab strip with selection, close, and
/// optional drag reordering.
class AgusEditorTabBar extends StatefulWidget {
  /// Creates an editor tab bar for the provided [tabs].
  const AgusEditorTabBar({
    required this.tabs,
    required this.selectedId,
    this.onSelected,
    this.onClose,
    this.onReorder,
    super.key,
  });

  /// Tabs rendered from left to right.
  final List<AgusEditorTab> tabs;

  /// Identifier of the currently selected tab, or null when nothing is active.
  final String? selectedId;

  /// Called when a tab is selected.
  final ValueChanged<String>? onSelected;

  /// Called when a tab close button is pressed.
  final ValueChanged<String>? onClose;

  /// Called with a reordered copy of [tabs] after a tab is dragged and dropped.
  ///
  /// Leave this null to disable tab reordering.
  final AgusEditorTabReorderCallback? onReorder;

  @override
  State<AgusEditorTabBar> createState() => _AgusEditorTabBarState();
}

class _AgusEditorTabBarState extends State<AgusEditorTabBar> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _tabKeys = <String, GlobalKey>{};
  OverlayEntry? _dragFeedbackOverlay;

  String? _draggedTabId;
  _EditorTabDropIntent? _dropIntent;
  Offset? _latestDragPosition;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelectedTab());
  }

  @override
  void didUpdateWidget(covariant AgusEditorTabBar oldWidget) {
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

    return Material(
      color: colors.tabInactiveBackground,
      child: SizedBox(
        height: dimensions.editorTabHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.tabBorder)),
          ),
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
                physics: widget.onReorder == null
                    ? const ClampingScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                child: Row(
                  children: [for (final tab in widget.tabs) _buildTab(tab)],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTab(AgusEditorTab tab) {
    final tabButton = AgusEditorTabButton(
      tab: tab,
      selected: tab.id == widget.selectedId,
      onSelected: widget.onSelected,
      onClose: widget.onClose,
    );
    final keyedTabButton = KeyedSubtree(
      key: _keyForTab(tab.id),
      child: tabButton,
    );

    if (widget.onReorder == null) {
      return keyedTabButton;
    }

    final isDragging = _draggedTabId == tab.id;
    final dropSide = _dropIntent?.targetId == tab.id ? _dropIntent?.side : null;

    return _EditorTabDropIndicator(
      active: dropSide != null && _draggedTabId != tab.id,
      side: dropSide ?? _EditorTabDropSide.before,
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

  bool _hasSameTabOrder(
    List<AgusEditorTab> oldTabs,
    List<AgusEditorTab> newTabs,
  ) {
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

  void _reorderTab(String draggedTabId, _EditorTabDropIntent dropIntent) {
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

    final insertionIndex = dropIntent.side == _EditorTabDropSide.before
        ? targetIndex
        : targetIndex + 1;
    final newIndex = oldIndex < insertionIndex
        ? insertionIndex - 1
        : insertionIndex;
    if (oldIndex == newIndex) {
      return;
    }

    final reorderedTabs = List<AgusEditorTab>.of(widget.tabs);
    final draggedTab = reorderedTabs.removeAt(oldIndex);
    reorderedTabs.insert(newIndex, draggedTab);
    onReorder(List<AgusEditorTab>.unmodifiable(reorderedTabs));
  }

  _EditorTabDropIntent? _dropIntentAtPosition(Offset globalPosition) {
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
            ? _EditorTabDropSide.before
            : _EditorTabDropSide.after;
        return _EditorTabDropIntent(targetId: tab.id, side: side);
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
      return _EditorTabDropIntent(
        targetId: firstTabId,
        side: _EditorTabDropSide.before,
      );
    }
    if (lastTabId != null && globalPosition.dx > lastTabRect.right) {
      return _EditorTabDropIntent(
        targetId: lastTabId,
        side: _EditorTabDropSide.after,
      );
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
            child: _EditorTabDragFeedback(
              tab: tab,
              selected: tab.id == widget.selectedId,
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

  AgusEditorTab? get _draggedTab {
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

enum _EditorTabDropSide { before, after }

@immutable
class _EditorTabDropIntent {
  const _EditorTabDropIntent({required this.targetId, required this.side});

  final String targetId;
  final _EditorTabDropSide side;
}

class _EditorTabDropIndicator extends StatelessWidget {
  const _EditorTabDropIndicator({
    required this.active,
    required this.side,
    required this.targetId,
    required this.child,
  });

  final bool active;
  final _EditorTabDropSide side;
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
            left: side == _EditorTabDropSide.before ? -1.5 : null,
            right: side == _EditorTabDropSide.after ? -1.5 : null,
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

class _EditorTabDragFeedback extends StatelessWidget {
  const _EditorTabDragFeedback({required this.tab, required this.selected});

  final AgusEditorTab tab;
  final bool selected;

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
            child: AgusEditorTabButton(tab: tab, selected: selected),
          ),
        ),
      ),
    );
  }
}

/// A single editor tab button used inside [AgusEditorTabBar].
class AgusEditorTabButton extends StatelessWidget {
  /// Creates an editor tab button for [tab].
  const AgusEditorTabButton({
    required this.tab,
    required this.selected,
    this.onSelected,
    this.onClose,
    super.key,
  });

  /// Tab data rendered by this button.
  final AgusEditorTab tab;

  /// Whether this button represents the selected tab.
  final bool selected;

  /// Called when the button body is tapped.
  final ValueChanged<String>? onSelected;

  /// Called when the close affordance is pressed.
  final ValueChanged<String>? onClose;

  @override
  Widget build(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);
    final dimensions = AgusThemeData.dimensionsOf(context);
    final foreground = selected
        ? colors.tabActiveForeground
        : colors.tabInactiveForeground;

    return Semantics(
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
                      color: selected ? colors.focusBorder : Colors.transparent,
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
                          icon: Icon(Icons.close, color: foreground, size: 14),
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
    );
  }
}
