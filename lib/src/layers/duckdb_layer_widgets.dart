part of '../../agus_maps_flutter.dart';

/// Pointer-capturing overlay for drawing features above [AgusMap].
class DuckDBLayerDrawOverlay extends StatelessWidget {
  /// Creates a draw overlay bound to [controller].
  const DuckDBLayerDrawOverlay({
    super.key,
    required this.controller,
    this.accentColor,
  });

  /// Draw state and persistence controller.
  final DuckDBLayerDrawController controller;

  /// Optional paint color for vertices and geometry previews.
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = accentColor ?? colorScheme.primary;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        if (!controller.isDrawing) {
          return const SizedBox.shrink();
        }

        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) {
            unawaited(controller.handlePointerDown(event.localPosition));
          },
          onPointerMove: (event) {
            unawaited(controller.handlePointerMove(event.localPosition));
          },
          onPointerUp: (_) => controller.handlePointerUp(),
          onPointerCancel: (_) => controller.handlePointerUp(),
          child: CustomPaint(
            painter: _DuckDBDrawPainter(
              tool: controller.tool,
              vertices: controller.vertices,
              selectedVertexIndex: controller.selectedVertexIndex,
              color: color,
              surfaceColor: colorScheme.surface,
            ),
            child: const SizedBox.expand(),
          ),
        );
      },
    );
  }
}

/// Compact drawing toolbar for DuckDB user layers.
class DuckDBLayerDrawToolbar extends StatelessWidget {
  /// Creates a draw toolbar.
  const DuckDBLayerDrawToolbar({
    super.key,
    required this.controller,
    this.axis = Axis.vertical,
    this.onCommitted,
  });

  /// Draw state and persistence controller.
  final DuckDBLayerDrawController controller;

  /// Toolbar layout direction.
  final Axis axis;

  /// Optional callback receiving the committed feature id.
  final ValueChanged<String>? onCommitted;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final buttons = <Widget>[
          _toolButton(context, AgusDrawTool.pin, Icons.place_outlined, 'Pin'),
          _toolButton(
            context,
            AgusDrawTool.segment,
            Icons.linear_scale,
            'Segment',
          ),
          _toolButton(context, AgusDrawTool.line, Icons.timeline, 'Line'),
          _toolButton(
            context,
            AgusDrawTool.polygon,
            Icons.pentagon_outlined,
            'Polygon',
          ),
          const _ToolbarDivider(),
          IconButton(
            tooltip: 'Undo vertex',
            icon: const Icon(Icons.undo),
            onPressed: controller.vertices.isEmpty || controller.isCommitting
                ? null
                : controller.undoLastVertex,
          ),
          IconButton(
            tooltip: 'Commit feature',
            icon: controller.isCommitting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            onPressed: controller.canCommit
                ? () async {
                    try {
                      final featureId = await controller.commit();
                      if (featureId != null) onCommitted?.call(featureId);
                    } catch (error) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                        SnackBar(
                          content: Text('Feature commit failed: $error'),
                        ),
                      );
                    }
                  }
                : null,
          ),
          IconButton(
            tooltip: 'Cancel drawing',
            icon: const Icon(Icons.close),
            onPressed: controller.isDrawing ? controller.cancel : null,
          ),
        ];

        return Material(
          color: colorScheme.surface,
          elevation: 3,
          borderRadius: BorderRadius.circular(8),
          child: axis == Axis.vertical
              ? Column(mainAxisSize: MainAxisSize.min, children: buttons)
              : Row(mainAxisSize: MainAxisSize.min, children: buttons),
        );
      },
    );
  }

  Widget _toolButton(
    BuildContext context,
    AgusDrawTool tool,
    IconData icon,
    String tooltip,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = controller.tool == tool;
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        backgroundColor: selected ? colorScheme.primaryContainer : null,
        foregroundColor: selected ? colorScheme.onPrimaryContainer : null,
      ),
      onPressed:
          controller.isCommitting ? null : () => controller.setTool(tool),
    );
  }
}

/// Metadata capture fields for the next drawn feature.
class DuckDBLayerMetadataForm extends StatefulWidget {
  /// Creates metadata inputs bound to [controller].
  const DuckDBLayerMetadataForm({super.key, required this.controller});

  /// Draw controller receiving metadata updates.
  final DuckDBLayerDrawController controller;

  @override
  State<DuckDBLayerMetadataForm> createState() =>
      _DuckDBLayerMetadataFormState();
}

class _DuckDBLayerMetadataFormState extends State<DuckDBLayerMetadataForm> {
  late final TextEditingController _titleController;
  late final TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.controller.title);
    _noteController = TextEditingController(text: widget.controller.note);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface,
      elevation: 3,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _titleController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Title',
                  prefixIcon: Icon(Icons.label_outline),
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  widget.controller.updateMetadata(title: value);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _noteController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Note',
                  prefixIcon: Icon(Icons.notes_outlined),
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  widget.controller.updateMetadata(note: value);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Layer management panel for DuckDB-backed layers.
class DuckDBLayerPanel extends StatefulWidget {
  /// Creates a panel for visibility, ordering, refresh, and backup actions.
  const DuckDBLayerPanel({
    super.key,
    required this.store,
    this.onRenderingRefresh,
    this.maxHeight = 360,
  });

  /// Store containing the layers to manage.
  final DuckDBLayerStore store;

  /// Optional callback for refreshing native rendering after mutations.
  final AgusLayerCommitCallback? onRenderingRefresh;

  /// Maximum panel height.
  final double maxHeight;

  @override
  State<DuckDBLayerPanel> createState() => _DuckDBLayerPanelState();
}

class _DuckDBLayerPanelState extends State<DuckDBLayerPanel> {
  List<AgusLayer> _layers = const <AgusLayer>[];
  String _message = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _layers = widget.store.listLayers();
    });
  }

  Future<void> _toggleLayer(AgusLayer layer, bool visible) async {
    try {
      widget.store.setLayerVisibility(layer.layerId, visible);
      await widget.onRenderingRefresh?.call();
      _reload();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = 'Layer visibility update failed: $error';
      });
    }
  }

  Future<void> _moveLayer(AgusLayer layer, int delta) async {
    try {
      widget.store.setLayerZIndex(layer.layerId, layer.zIndex + delta);
      await widget.onRenderingRefresh?.call();
      _reload();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = 'Layer order update failed: $error';
      });
    }
  }

  Future<void> _backup() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      final path = await widget.store.backup();
      setState(() {
        _message = 'Backup: $path';
      });
    } catch (error) {
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
    return Material(
      color: colorScheme.surface,
      elevation: 6,
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: widget.maxHeight),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.layers_outlined, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Layers', style: theme.textTheme.titleMedium),
                  ),
                  IconButton(
                    tooltip: 'Refresh layers',
                    icon: const Icon(Icons.refresh),
                    onPressed: _reload,
                  ),
                  IconButton(
                    tooltip: 'Back up database',
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.backup_outlined),
                    onPressed: _busy ? null : _backup,
                  ),
                ],
              ),
              const Divider(height: 16),
              if (_layers.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'No layers',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _layers.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final layer = _layers[index];
                      return _LayerRow(
                        layer: layer,
                        onVisibleChanged: (visible) {
                          unawaited(_toggleLayer(layer, visible));
                        },
                        onMoveUp: () => unawaited(_moveLayer(layer, 1)),
                        onMoveDown: () => unawaited(_moveLayer(layer, -1)),
                      );
                    },
                  ),
                ),
              if (_message.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  _message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LayerRow extends StatelessWidget {
  const _LayerRow({
    required this.layer,
    required this.onVisibleChanged,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final AgusLayer layer;
  final ValueChanged<bool> onVisibleChanged;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Row(
        children: [
          Switch(value: layer.visible, onChanged: onVisibleChanged),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  layer.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge,
                ),
                Text(
                  '${layer.kind.databaseValue} · z ${layer.zIndex}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Move up',
            icon: const Icon(Icons.arrow_upward),
            onPressed: onMoveUp,
          ),
          IconButton(
            tooltip: 'Move down',
            icon: const Icon(Icons.arrow_downward),
            onPressed: onMoveDown,
          ),
        ],
      ),
    );
  }
}

class _ToolbarDivider extends StatelessWidget {
  const _ToolbarDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1);
  }
}

class _DuckDBDrawPainter extends CustomPainter {
  _DuckDBDrawPainter({
    required this.tool,
    required this.vertices,
    required this.selectedVertexIndex,
    required this.color,
    required this.surfaceColor,
  });

  final AgusDrawTool tool;
  final List<AgusDrawPoint> vertices;
  final int? selectedVertexIndex;
  final Color color;
  final Color surfaceColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (vertices.isEmpty) return;

    final path = Path()
      ..moveTo(
        vertices.first.screenPosition.dx,
        vertices.first.screenPosition.dy,
      );
    for (final vertex in vertices.skip(1)) {
      path.lineTo(vertex.screenPosition.dx, vertex.screenPosition.dy);
    }
    if (tool == AgusDrawTool.polygon && vertices.length > 2) {
      path.close();
    }

    if (tool == AgusDrawTool.polygon && vertices.length > 2) {
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: 0.14)
          ..style = PaintingStyle.fill,
      );
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    for (var index = 0; index < vertices.length; index++) {
      final selected = selectedVertexIndex == index;
      final center = vertices[index].screenPosition;
      canvas.drawCircle(
        center,
        selected ? 9 : 7,
        Paint()
          ..color = surfaceColor
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        center,
        selected ? 9 : 7,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 3 : 2,
      );
      canvas.drawCircle(
        center,
        3,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DuckDBDrawPainter oldDelegate) {
    return oldDelegate.tool != tool ||
        oldDelegate.vertices != vertices ||
        oldDelegate.selectedVertexIndex != selectedVertexIndex ||
        oldDelegate.color != color ||
        oldDelegate.surfaceColor != surfaceColor;
  }
}
