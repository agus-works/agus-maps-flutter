import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/agus_theme_data.dart';
import 'agus_input.dart';

typedef AgusCommandAsyncProvider =
    Future<List<AgusCommandGroup>> Function(String query);

@immutable
class AgusCommandMatch {
  const AgusCommandMatch({
    required this.score,
    this.labelIndexes = const <int>{},
  });

  final int score;
  final Set<int> labelIndexes;
}

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
    return match(query) != null;
  }

  AgusCommandMatch? match(String query) {
    final terms = query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty)
        .toList(growable: false);
    if (terms.isEmpty) {
      return const AgusCommandMatch(score: 0);
    }

    final labelLower = label.toLowerCase();
    var score = 0;
    final labelIndexes = <int>{};
    for (final term in terms) {
      final labelSubstringIndex = labelLower.indexOf(term);
      if (labelSubstringIndex >= 0) {
        for (var i = 0; i < term.length; i++) {
          labelIndexes.add(labelSubstringIndex + i);
        }
        score += labelSubstringIndex * 2;
        continue;
      }

      final labelFuzzy = _fuzzyIndexes(labelLower, term);
      if (labelFuzzy != null) {
        labelIndexes.addAll(labelFuzzy);
        score += 40 + _fuzzyGapPenalty(labelFuzzy);
        continue;
      }

      final keywordSubstringIndex = keywords.indexWhere(
        (keyword) => keyword.toLowerCase().contains(term),
      );
      if (keywordSubstringIndex >= 0) {
        score += 90 + keywordSubstringIndex;
        continue;
      }

      final keywordFuzzyIndex = keywords.indexWhere(
        (keyword) => _fuzzyIndexes(keyword.toLowerCase(), term) != null,
      );
      if (keywordFuzzyIndex >= 0) {
        score += 130 + keywordFuzzyIndex;
        continue;
      }

      return null;
    }

    score += label.length;
    if (!enabled) {
      score += 10000;
    }
    return AgusCommandMatch(score: score, labelIndexes: labelIndexes);
  }
}

List<int>? _fuzzyIndexes(String haystack, String needle) {
  if (needle.isEmpty) return const <int>[];
  final indexes = <int>[];
  var searchStart = 0;
  for (final codeUnit in needle.codeUnits) {
    final index = haystack.indexOf(String.fromCharCode(codeUnit), searchStart);
    if (index < 0) return null;
    indexes.add(index);
    searchStart = index + 1;
  }
  return indexes;
}

int _fuzzyGapPenalty(List<int> indexes) {
  if (indexes.length < 2) return 0;
  var penalty = 0;
  for (var i = 1; i < indexes.length; i++) {
    penalty += indexes[i] - indexes[i - 1] - 1;
  }
  return penalty;
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
                  : colors.focusBorder.withValues(alpha: 0.42),
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
    this.asyncProviders = const <AgusCommandAsyncProvider>[],
    super.key,
  });

  final List<AgusCommandGroup> groups;
  final String prompt;
  final String emptyStateLabel;
  final double maxHeight;
  final bool autofocus;
  final VoidCallback? onDismissRequested;
  final ValueChanged<AgusCommandItem>? onItemSelected;
  final List<AgusCommandAsyncProvider> asyncProviders;

  @override
  State<AgusCommandDialog> createState() => _AgusCommandDialogState();
}

class _AgusCommandDialogState extends State<AgusCommandDialog> {
  final TextEditingController _queryController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode(debugLabel: 'AgusCommandDialog');
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _itemKeys = <String, GlobalKey>{};

  int _highlightedIndex = 0;
  int _asyncGeneration = 0;
  List<AgusCommandGroup> _asyncGroups = const <AgusCommandGroup>[];

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
                  child: AgusSearchBox(
                    controller: _queryController,
                    focusNode: _inputFocusNode,
                    autofocus: widget.autofocus,
                    placeholder: widget.prompt,
                    onChanged: _handleQueryChanged,
                    onSubmitted: (_) => _selectHighlighted(),
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
                      : SingleChildScrollView(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
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
                                    query: _queryController.text,
                                    onHover: () => _setHighlightedItem(item.id),
                                    onSelected: () => _select(item),
                                  ),
                              ],
                            ],
                          ),
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
    final seenIds = <String>{};
    return [
      for (final group in [...widget.groups, ..._asyncGroups])
        if (_dedupeRankedItems(_rankedItems(group.items, query), seenIds)
            case final items when items.isNotEmpty)
          AgusCommandGroup(heading: group.heading, items: items),
    ];
  }

  List<AgusCommandItem> _dedupeRankedItems(
    List<AgusCommandItem> items,
    Set<String> seenIds,
  ) {
    return [
      for (final item in items)
        if (seenIds.add(item.id)) item,
    ];
  }

  List<AgusCommandItem> _rankedItems(
    List<AgusCommandItem> items,
    String query,
  ) {
    final ranked = [
      for (final item in items)
        if (item.match(query) case final match?) (item: item, match: match),
    ];
    ranked.sort((a, b) {
      final byScore = a.match.score.compareTo(b.match.score);
      if (byScore != 0) return byScore;
      return a.item.label.compareTo(b.item.label);
    });
    return [for (final rankedItem in ranked) rankedItem.item];
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

  void _handleQueryChanged(String query) {
    setState(() => _highlightedIndex = 0);
    _refreshAsyncGroups(query);
  }

  void _refreshAsyncGroups(String query) {
    final providers = widget.asyncProviders;
    final trimmed = query.trim();
    final generation = ++_asyncGeneration;
    if (providers.isEmpty || trimmed.isEmpty) {
      if (_asyncGroups.isNotEmpty) {
        setState(() => _asyncGroups = const <AgusCommandGroup>[]);
      }
      return;
    }

    Future.wait([for (final provider in providers) provider(trimmed)]).then(
      (groups) {
        if (!mounted || generation != _asyncGeneration) return;
        setState(() {
          _asyncGroups = [
            for (final providerGroups in groups) ...providerGroups,
          ];
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'agus_design',
            context: ErrorDescription(
              'while resolving command async providers',
            ),
          ),
        );
        if (!mounted || generation != _asyncGeneration) return;
        setState(() => _asyncGroups = const <AgusCommandGroup>[]);
      },
    );
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
    this.asyncProviders = const <AgusCommandAsyncProvider>[],
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
  final List<AgusCommandAsyncProvider> asyncProviders;
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
    final hasCommands =
        widget.groups.isNotEmpty || widget.asyncProviders.isNotEmpty;

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
              button: hasCommands,
              label: widget.prompt,
              child: AgusCommandBar(
                prompt: widget.prompt,
                leadingIcon: widget.leadingIcon,
                trailing: effectiveTrailing,
                active: _controller.isOpen,
                enabled: hasCommands,
                onPressed: hasCommands ? _controller.toggle : null,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget? _buildDefaultTrailing(BuildContext context) {
    if (widget.groups.isEmpty && widget.asyncProviders.isEmpty) {
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
                asyncProviders: widget.asyncProviders,
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
    required this.query,
    required this.onSelected,
    required this.onHover,
    super.key,
  });

  final AgusCommandItem item;
  final bool selected;
  final String query;
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
        cursor: widget.item.enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onEnter: (_) {
          widget.onHover();
          setState(() => _hovered = true);
        },
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.item.enabled ? widget.onSelected : null,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(4),
            ),
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
                      child: _CommandHighlightedLabel(
                        label: widget.item.label,
                        match: widget.item.match(widget.query),
                        foreground: foreground,
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

class _CommandHighlightedLabel extends StatelessWidget {
  const _CommandHighlightedLabel({
    required this.label,
    required this.match,
    required this.foreground,
  });

  final String label;
  final AgusCommandMatch? match;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final baseStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: foreground);
    final indexes = match?.labelIndexes ?? const <int>{};
    if (indexes.isEmpty) {
      return Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: baseStyle,
      );
    }

    return Text.rich(
      TextSpan(
        children: [
          for (var i = 0; i < label.length; i++)
            TextSpan(
              text: label[i],
              style: indexes.contains(i)
                  ? baseStyle?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w800,
                      decoration: TextDecoration.underline,
                      decorationColor: foreground.withValues(alpha: 0.7),
                    )
                  : baseStyle,
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
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
