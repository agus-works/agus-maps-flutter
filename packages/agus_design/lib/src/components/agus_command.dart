import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/agus_theme_data.dart';

@immutable
class AgusCommandItem {
  const AgusCommandItem({
    required this.id,
    required this.label,
    this.icon,
    this.keywords = const <String>[],
    this.shortcut,
    this.shortcutLabel,
    this.enabled = true,
    this.onSelected,
  });

  final String id;
  final String label;
  final IconData? icon;
  final List<String> keywords;
  final ShortcutActivator? shortcut;
  final String? shortcutLabel;
  final bool enabled;
  final VoidCallback? onSelected;

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return true;
    }

    return label.toLowerCase().contains(normalized) ||
        keywords.any((keyword) => keyword.toLowerCase().contains(normalized));
  }
}

@immutable
class AgusCommandGroup {
  const AgusCommandGroup({required this.heading, required this.items});

  final String heading;
  final List<AgusCommandItem> items;
}

class AgusCommandController extends ChangeNotifier {
  bool _isOpen = false;

  bool get isOpen => _isOpen;

  void open() {
    if (_isOpen) {
      return;
    }

    _isOpen = true;
    notifyListeners();
  }

  void close() {
    if (!_isOpen) {
      return;
    }

    _isOpen = false;
    notifyListeners();
  }

  void toggle() {
    if (_isOpen) {
      close();
      return;
    }

    open();
  }
}

class AgusCommandShortcutHost extends StatelessWidget {
  const AgusCommandShortcutHost({
    required this.controller,
    required this.groups,
    required this.child,
    this.openShortcut,
    super.key,
  });

  final AgusCommandController controller;
  final List<AgusCommandGroup> groups;
  final Widget child;
  final ShortcutActivator? openShortcut;

  @override
  Widget build(BuildContext context) {
    final items = <String, AgusCommandItem>{
      for (final group in groups)
        for (final item in group.items) item.id: item,
    };

    return Actions(
      actions: <Type, Action<Intent>>{
        _AgusCommandToggleIntent: CallbackAction<_AgusCommandToggleIntent>(
          onInvoke: (_) {
            controller.toggle();
            return null;
          },
        ),
        _AgusCommandCloseIntent: CallbackAction<_AgusCommandCloseIntent>(
          onInvoke: (_) {
            controller.close();
            return null;
          },
        ),
        _AgusCommandRunIntent: CallbackAction<_AgusCommandRunIntent>(
          onInvoke: (intent) {
            final item = items[intent.id];
            if (item == null || !item.enabled) {
              return null;
            }

            item.onSelected?.call();
            controller.close();
            return null;
          },
        ),
      },
      child: Shortcuts(
        shortcuts: <ShortcutActivator, Intent>{
          _effectiveOpenShortcut(context): const _AgusCommandToggleIntent(),
          const SingleActivator(LogicalKeyboardKey.escape):
              const _AgusCommandCloseIntent(),
          for (final item in items.values)
            if (item.shortcut != null)
              item.shortcut!: _AgusCommandRunIntent(item.id),
        },
        child: Focus(autofocus: true, child: child),
      ),
    );
  }

  ShortcutActivator _effectiveOpenShortcut(BuildContext context) {
    return openShortcut ?? defaultOpenShortcutFor(Theme.of(context).platform);
  }

  static ShortcutActivator defaultOpenShortcutFor(TargetPlatform platform) {
    return switch (platform) {
      TargetPlatform.macOS || TargetPlatform.iOS => const SingleActivator(
        LogicalKeyboardKey.keyK,
        meta: true,
      ),
      _ => const SingleActivator(LogicalKeyboardKey.keyK, control: true),
    };
  }

  static String defaultOpenShortcutLabelFor(TargetPlatform platform) {
    return switch (platform) {
      TargetPlatform.macOS || TargetPlatform.iOS => '⌘K',
      _ => 'Ctrl K',
    };
  }
}

class AgusCommandBar extends StatelessWidget {
  const AgusCommandBar({
    this.prompt = 'Search or run a command',
    this.leadingIcon = Icons.search,
    this.trailing,
    this.active = false,
    this.enabled = true,
    this.onPressed,
    super.key,
  });

  final String prompt;
  final IconData leadingIcon;
  final Widget? trailing;
  final bool active;
  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);
    final textStyle = Theme.of(context).textTheme.bodySmall;
    final foreground = enabled
        ? colors.titleBarForeground
        : colors.titleBarForeground.withValues(alpha: 0.45);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: enabled ? onPressed : null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: active
                ? colors.inputBackground
                : colors.inputBackground.withValues(alpha: 0.78),
            border: Border.all(
              color: active
                  ? colors.focusBorder
                  : colors.inputBorder.withValues(alpha: 0.95),
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Icon(leadingIcon, size: 14, color: foreground),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    prompt,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textStyle?.copyWith(
                      color: foreground.withValues(alpha: 0.88),
                    ),
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AgusCommandDialog extends StatefulWidget {
  const AgusCommandDialog({
    required this.groups,
    this.prompt = 'Search or run a command',
    this.emptyStateLabel = 'No matching commands.',
    this.maxHeight = 320,
    this.autofocus = true,
    this.onDismissRequested,
    this.onItemSelected,
    super.key,
  });

  final List<AgusCommandGroup> groups;
  final String prompt;
  final String emptyStateLabel;
  final double maxHeight;
  final bool autofocus;
  final VoidCallback? onDismissRequested;
  final ValueChanged<AgusCommandItem>? onItemSelected;

  @override
  State<AgusCommandDialog> createState() => _AgusCommandDialogState();
}

class _AgusCommandDialogState extends State<AgusCommandDialog> {
  final TextEditingController _queryController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode(debugLabel: 'AgusCommandDialog');
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _itemKeys = <String, GlobalKey>{};

  int _highlightedIndex = 0;

  @override
  void initState() {
    super.initState();
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _inputFocusNode.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _queryController.dispose();
    _inputFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);
    final filteredGroups = _filteredGroups;
    final filteredItems = _filteredItems(filteredGroups);
    final highlightedIndex = _normalizedHighlightedIndex(filteredItems.length);

    return Actions(
      actions: <Type, Action<Intent>>{
        _AgusCommandMoveIntent: CallbackAction<_AgusCommandMoveIntent>(
          onInvoke: (intent) {
            _moveHighlight(intent.delta);
            return null;
          },
        ),
        _AgusCommandSubmitIntent: CallbackAction<_AgusCommandSubmitIntent>(
          onInvoke: (_) {
            _selectHighlighted();
            return null;
          },
        ),
        _AgusCommandCloseIntent: CallbackAction<_AgusCommandCloseIntent>(
          onInvoke: (_) {
            widget.onDismissRequested?.call();
            return null;
          },
        ),
      },
      child: Shortcuts(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.arrowDown): _AgusCommandMoveIntent(
            1,
          ),
          SingleActivator(LogicalKeyboardKey.arrowUp): _AgusCommandMoveIntent(
            -1,
          ),
          SingleActivator(LogicalKeyboardKey.enter): _AgusCommandSubmitIntent(),
          SingleActivator(LogicalKeyboardKey.escape): _AgusCommandCloseIntent(),
        },
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: widget.maxHeight),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.sideBarBackground,
              border: Border.all(
                color: colors.inputBorder.withValues(alpha: 0.9),
              ),
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.32),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.inputBackground,
                      border: Border.all(color: colors.inputBorder),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        children: [
                          Icon(
                            Icons.search,
                            size: 14,
                            color: colors.sideBarForeground.withValues(
                              alpha: 0.72,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _queryController,
                              focusNode: _inputFocusNode,
                              autofocus: widget.autofocus,
                              onChanged: (_) {
                                setState(() => _highlightedIndex = 0);
                              },
                              onSubmitted: (_) => _selectHighlighted(),
                              onTapOutside: (_) =>
                                  widget.onDismissRequested?.call(),
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                hintText: widget.prompt,
                                isDense: true,
                                hintStyle: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: colors.sideBarForeground
                                          .withValues(alpha: 0.5),
                                    ),
                              ),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: colors.sideBarForeground),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Divider(height: 1, thickness: 1, color: colors.sideBarBorder),
                Flexible(
                  child: filteredItems.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Text(
                              widget.emptyStateLabel,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: colors.sideBarForeground.withValues(
                                      alpha: 0.7,
                                    ),
                                  ),
                            ),
                          ),
                        )
                      : ListView(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          shrinkWrap: true,
                          children: [
                            for (final group in filteredGroups) ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  8,
                                  12,
                                  4,
                                ),
                                child: Text(
                                  group.heading.toUpperCase(),
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: colors.sideBarForeground
                                            .withValues(alpha: 0.56),
                                        letterSpacing: 0.6,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ),
                              for (final item in group.items)
                                _AgusCommandItemTile(
                                  key: _keyForItem(item.id),
                                  item: item,
                                  selected:
                                      highlightedIndex >= 0 &&
                                      filteredItems[highlightedIndex].id ==
                                          item.id,
                                  onHover: () => _setHighlightedItem(item.id),
                                  onSelected: () => _select(item),
                                ),
                            ],
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<AgusCommandGroup> get _filteredGroups {
    final query = _queryController.text;
    return [
      for (final group in widget.groups)
        if (group.items.any((item) => item.matches(query)))
          AgusCommandGroup(
            heading: group.heading,
            items: [
              for (final item in group.items)
                if (item.matches(query)) item,
            ],
          ),
    ];
  }

  List<AgusCommandItem> _filteredItems(List<AgusCommandGroup> groups) {
    return [for (final group in groups) ...group.items];
  }

  GlobalKey _keyForItem(String id) {
    return _itemKeys.putIfAbsent(id, GlobalKey.new);
  }

  int _normalizedHighlightedIndex(int itemCount) {
    if (itemCount == 0) {
      return -1;
    }

    if (_highlightedIndex >= itemCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _highlightedIndex = itemCount - 1);
        }
      });
      return itemCount - 1;
    }

    if (_highlightedIndex < 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _highlightedIndex = 0);
        }
      });
      return 0;
    }

    return _highlightedIndex;
  }

  void _moveHighlight(int delta) {
    final items = _filteredItems(_filteredGroups);
    if (items.isEmpty) {
      return;
    }

    final nextIndex = (_highlightedIndex + delta) % items.length;
    setState(() {
      _highlightedIndex = nextIndex < 0 ? items.length - 1 : nextIndex;
    });
    _ensureVisible(items[_highlightedIndex].id);
  }

  void _setHighlightedItem(String id) {
    final items = _filteredItems(_filteredGroups);
    final nextIndex = items.indexWhere((item) => item.id == id);
    if (nextIndex < 0 || nextIndex == _highlightedIndex) {
      return;
    }

    setState(() => _highlightedIndex = nextIndex);
  }

  void _selectHighlighted() {
    final items = _filteredItems(_filteredGroups);
    if (items.isEmpty) {
      return;
    }

    final index = _normalizedHighlightedIndex(items.length);
    if (index >= 0) {
      _select(items[index]);
    }
  }

  void _select(AgusCommandItem item) {
    if (!item.enabled) {
      return;
    }

    widget.onItemSelected?.call(item);
    item.onSelected?.call();
    widget.onDismissRequested?.call();
  }

  void _ensureVisible(String id) {
    final context = _keyForItem(id).currentContext;
    if (context == null) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && context.mounted) {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 80),
          alignment: 0.5,
          curve: Curves.easeOut,
        );
      }
    });
  }
}

class AgusCommandCenter extends StatefulWidget {
  const AgusCommandCenter({
    this.prompt = 'Search or run a command',
    this.leadingIcon = Icons.search,
    this.trailing,
    this.controller,
    this.groups = const <AgusCommandGroup>[],
    this.emptyStateLabel = 'No matching commands.',
    this.openShortcut,
    this.openShortcutLabel,
    this.maxOverlayHeight = 320,
    super.key,
  });

  final String prompt;
  final IconData leadingIcon;
  final Widget? trailing;
  final AgusCommandController? controller;
  final List<AgusCommandGroup> groups;
  final String emptyStateLabel;
  final ShortcutActivator? openShortcut;
  final String? openShortcutLabel;
  final double maxOverlayHeight;

  @override
  State<AgusCommandCenter> createState() => _AgusCommandCenterState();
}

class _AgusCommandCenterState extends State<AgusCommandCenter> {
  final LayerLink _layerLink = LayerLink();
  final OverlayPortalController _portalController = OverlayPortalController();

  AgusCommandController? _internalController;
  double _overlayWidth = 460;

  AgusCommandController get _controller =>
      widget.controller ?? (_internalController ??= AgusCommandController());

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant AgusCommandCenter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) {
      return;
    }

    final oldController = oldWidget.controller ?? _internalController;
    oldController?.removeListener(_handleControllerChanged);
    _controller.addListener(_handleControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    _internalController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effectiveTrailing = widget.trailing ?? _buildDefaultTrailing(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth.isFinite && constraints.maxWidth > 0) {
          _overlayWidth = constraints.maxWidth;
        }

        return CompositedTransformTarget(
          link: _layerLink,
          child: OverlayPortal(
            controller: _portalController,
            overlayChildBuilder: _buildOverlay,
            child: Semantics(
              button: widget.groups.isNotEmpty,
              label: widget.prompt,
              child: AgusCommandBar(
                prompt: widget.prompt,
                leadingIcon: widget.leadingIcon,
                trailing: effectiveTrailing,
                active: _controller.isOpen,
                enabled: widget.groups.isNotEmpty,
                onPressed: widget.groups.isEmpty ? null : _controller.toggle,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget? _buildDefaultTrailing(BuildContext context) {
    if (widget.groups.isEmpty) {
      return null;
    }

    final colors = AgusThemeData.colorsOf(context);
    final label =
        widget.openShortcutLabel ??
        AgusCommandShortcutHost.defaultOpenShortcutLabelFor(
          Theme.of(context).platform,
        );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.titleBarBackground.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colors.titleBarForeground.withValues(alpha: 0.78),
          ),
        ),
      ),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _controller.close,
          ),
        ),
        CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          targetAnchor: Alignment.bottomCenter,
          followerAnchor: Alignment.topCenter,
          offset: const Offset(0, 6),
          child: Material(
            color: Colors.transparent,
            child: SizedBox(
              width: _overlayWidth,
              child: AgusCommandDialog(
                groups: widget.groups,
                prompt: widget.prompt,
                emptyStateLabel: widget.emptyStateLabel,
                maxHeight: widget.maxOverlayHeight,
                onDismissRequested: _controller.close,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _handleControllerChanged() {
    if (_controller.isOpen) {
      _portalController.show();
      setState(() {});
      return;
    }

    _portalController.hide();
    setState(() {});
  }
}

class _AgusCommandItemTile extends StatefulWidget {
  const _AgusCommandItemTile({
    required this.item,
    required this.selected,
    required this.onSelected,
    required this.onHover,
    super.key,
  });

  final AgusCommandItem item;
  final bool selected;
  final VoidCallback onSelected;
  final VoidCallback onHover;

  @override
  State<_AgusCommandItemTile> createState() => _AgusCommandItemTileState();
}

class _AgusCommandItemTileState extends State<_AgusCommandItemTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);
    final foreground = widget.item.enabled
        ? colors.sideBarForeground
        : colors.sideBarForeground.withValues(alpha: 0.42);
    final background = widget.selected
        ? colors.selectionBackground
        : _hovered
        ? colors.hoverBackground
        : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: MouseRegion(
        onEnter: (_) {
          widget.onHover();
          setState(() => _hovered = true);
        },
        onExit: (_) => setState(() => _hovered = false),
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(4),
          child: InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: widget.item.enabled ? widget.onSelected : null,
            child: SizedBox(
              height: 30,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 18,
                      child: widget.item.icon == null
                          ? null
                          : Icon(widget.item.icon, size: 16, color: foreground),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: foreground),
                      ),
                    ),
                    if (widget.item.shortcutLabel != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: Text(
                          widget.item.shortcutLabel!,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: foreground.withValues(alpha: 0.72),
                                letterSpacing: 0.2,
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

class _AgusCommandToggleIntent extends Intent {
  const _AgusCommandToggleIntent();
}

class _AgusCommandCloseIntent extends Intent {
  const _AgusCommandCloseIntent();
}

class _AgusCommandRunIntent extends Intent {
  const _AgusCommandRunIntent(this.id);

  final String id;
}

class _AgusCommandMoveIntent extends Intent {
  const _AgusCommandMoveIntent(this.delta);

  final int delta;
}

class _AgusCommandSubmitIntent extends Intent {
  const _AgusCommandSubmitIntent();
}
