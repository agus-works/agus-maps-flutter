import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/agus_theme_data.dart';

@immutable
class AgusEditorTab {
  const AgusEditorTab({
    required this.id,
    required this.label,
    this.icon,
    this.dirty = false,
    this.pinned = false,
    this.preview = false,
    this.closable = true,
  });

  final String id;
  final String label;
  final IconData? icon;
  final bool dirty;
  final bool pinned;
  final bool preview;
  final bool closable;
}

class AgusEditorTabBar extends StatefulWidget {
  const AgusEditorTabBar({
    required this.tabs,
    required this.selectedId,
    this.onSelected,
    this.onClose,
    super.key,
  });

  final List<AgusEditorTab> tabs;
  final String? selectedId;
  final ValueChanged<String>? onSelected;
  final ValueChanged<String>? onClose;

  @override
  State<AgusEditorTabBar> createState() => _AgusEditorTabBarState();
}

class _AgusEditorTabBarState extends State<AgusEditorTabBar> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _tabKeys = <String, GlobalKey>{};

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
        oldWidget.tabs.length != widget.tabs.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelectedTab());
    }
  }

  @override
  void dispose() {
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
                physics: const ClampingScrollPhysics(),
                child: Row(
                  children: [
                    for (final tab in widget.tabs)
                      AgusEditorTabButton(
                        key: _keyForTab(tab.id),
                        tab: tab,
                        selected: tab.id == widget.selectedId,
                        onSelected: widget.onSelected,
                        onClose: widget.onClose,
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

  GlobalKey _keyForTab(String id) {
    return _tabKeys.putIfAbsent(id, GlobalKey.new);
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
}

class AgusEditorTabButton extends StatelessWidget {
  const AgusEditorTabButton({
    required this.tab,
    required this.selected,
    this.onSelected,
    this.onClose,
    super.key,
  });

  final AgusEditorTab tab;
  final bool selected;
  final ValueChanged<String>? onSelected;
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
