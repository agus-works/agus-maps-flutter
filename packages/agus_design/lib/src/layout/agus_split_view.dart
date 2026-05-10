import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/agus_theme_data.dart';

const double _splitViewSeparatorThickness = 1;

/// Identifies which [AgusSplitView] pane owns the fixed, resizable extent.
enum AgusSplitViewPane {
  /// The first child keeps the fixed extent while the second child expands.
  first,

  /// The second child keeps the fixed extent while the first child expands.
  second,
}

/// A two-pane split layout with a thin divider and draggable resize hitbox.
///
/// The visible separator is always one logical pixel thick. The pointer hitbox
/// is intentionally wider and comes from the active Agus dimensions so the
/// separator remains easy to resize on high-density displays.
class AgusSplitView extends StatefulWidget {
  /// Creates a split layout for [first] and [second].
  const AgusSplitView({
    required this.axis,
    required this.first,
    required this.second,
    required this.initialFirstExtent,
    this.sizedPane = AgusSplitViewPane.first,
    this.minFirstExtent = 120,
    this.minSecondExtent = 120,
    this.onFirstExtentChanged,
    this.onSizedExtentChanged,
    super.key,
  });

  /// The direction in which panes are split.
  final Axis axis;

  /// The leading pane for horizontal layouts and the upper pane for vertical
  /// layouts.
  final Widget first;

  /// The trailing pane for horizontal layouts and the lower pane for vertical
  /// layouts.
  final Widget second;

  /// The initial extent of the pane selected by [sizedPane].
  final double initialFirstExtent;

  /// The pane that owns the fixed, user-resizable extent.
  final AgusSplitViewPane sizedPane;

  /// The minimum allowed extent for [first].
  final double minFirstExtent;

  /// The minimum allowed extent for [second].
  final double minSecondExtent;

  /// Called when [first] is the sized pane and its extent changes.
  final ValueChanged<double>? onFirstExtentChanged;

  /// Called whenever the current [sizedPane] extent changes.
  final ValueChanged<double>? onSizedExtentChanged;

  @override
  State<AgusSplitView> createState() => _AgusSplitViewState();
}

class _AgusSplitViewState extends State<AgusSplitView> {
  double? sizedExtent;

  @override
  Widget build(BuildContext context) {
    final dimensions = AgusThemeData.dimensionsOf(context);
    final hitboxExtent = dimensions.resizeHandleThickness;
    const separatorExtent = _splitViewSeparatorThickness;

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalExtent = widget.axis == Axis.horizontal
            ? constraints.maxWidth
            : constraints.maxHeight;
        final minSizedExtent = widget.sizedPane == AgusSplitViewPane.first
            ? widget.minFirstExtent
            : widget.minSecondExtent;
        final minOtherExtent = widget.sizedPane == AgusSplitViewPane.first
            ? widget.minSecondExtent
            : widget.minFirstExtent;
        final maxSizedExtent = math.max(
          minSizedExtent,
          totalExtent - minOtherExtent - separatorExtent,
        );
        final resolvedSizedExtent = (sizedExtent ?? widget.initialFirstExtent)
            .clamp(minSizedExtent, maxSizedExtent)
            .toDouble();
        final handle = _SplitViewHandle(
          axis: widget.axis,
          hitboxExtent: hitboxExtent,
          separatorThickness: separatorExtent,
          onDragDelta: (delta) {
            final nextExtent =
                resolvedSizedExtent + _extentDeltaForSizedPane(delta);
            _updateExtent(
              nextExtent.clamp(minSizedExtent, maxSizedExtent).toDouble(),
            );
          },
        );

        if (widget.axis == Axis.horizontal) {
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Row(
                  children: _buildHorizontalChildren(resolvedSizedExtent),
                ),
              ),
              Positioned(
                left: _handleOffset(
                  totalExtent: totalExtent,
                  resolvedExtent: resolvedSizedExtent,
                  hitboxExtent: hitboxExtent,
                  separatorExtent: separatorExtent,
                ),
                top: 0,
                bottom: 0,
                width: hitboxExtent,
                child: handle,
              ),
            ],
          );
        }

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Column(
                children: _buildVerticalChildren(resolvedSizedExtent),
              ),
            ),
            Positioned(
              top: _handleOffset(
                totalExtent: totalExtent,
                resolvedExtent: resolvedSizedExtent,
                hitboxExtent: hitboxExtent,
                separatorExtent: separatorExtent,
              ),
              left: 0,
              right: 0,
              height: hitboxExtent,
              child: handle,
            ),
          ],
        );
      },
    );
  }

  List<Widget> _buildHorizontalChildren(double resolvedExtent) {
    if (widget.sizedPane == AgusSplitViewPane.second) {
      return [
        Expanded(child: widget.first),
        const SizedBox(width: _splitViewSeparatorThickness),
        SizedBox(width: resolvedExtent, child: widget.second),
      ];
    }

    return [
      SizedBox(width: resolvedExtent, child: widget.first),
      const SizedBox(width: _splitViewSeparatorThickness),
      Expanded(child: widget.second),
    ];
  }

  List<Widget> _buildVerticalChildren(double resolvedExtent) {
    if (widget.sizedPane == AgusSplitViewPane.second) {
      return [
        Expanded(child: widget.first),
        const SizedBox(height: _splitViewSeparatorThickness),
        SizedBox(height: resolvedExtent, child: widget.second),
      ];
    }

    return [
      SizedBox(height: resolvedExtent, child: widget.first),
      const SizedBox(height: _splitViewSeparatorThickness),
      Expanded(child: widget.second),
    ];
  }

  double _handleOffset({
    required double totalExtent,
    required double resolvedExtent,
    required double hitboxExtent,
    required double separatorExtent,
  }) {
    final separatorOffset = widget.sizedPane == AgusSplitViewPane.first
        ? resolvedExtent
        : totalExtent - resolvedExtent - separatorExtent;
    return separatorOffset + separatorExtent / 2 - hitboxExtent / 2;
  }

  double _extentDeltaForSizedPane(Offset delta) {
    final axisDelta = widget.axis == Axis.horizontal ? delta.dx : delta.dy;
    return widget.sizedPane == AgusSplitViewPane.first ? axisDelta : -axisDelta;
  }

  void _updateExtent(double nextExtent) {
    setState(() => sizedExtent = nextExtent);
    if (widget.sizedPane == AgusSplitViewPane.first) {
      widget.onFirstExtentChanged?.call(nextExtent);
    }
    widget.onSizedExtentChanged?.call(nextExtent);
  }
}

class _SplitViewHandle extends StatefulWidget {
  const _SplitViewHandle({
    required this.axis,
    required this.hitboxExtent,
    required this.separatorThickness,
    required this.onDragDelta,
  });

  final Axis axis;
  final double hitboxExtent;
  final double separatorThickness;
  final ValueChanged<Offset> onDragDelta;

  @override
  State<_SplitViewHandle> createState() => _SplitViewHandleState();
}

class _SplitViewHandleState extends State<_SplitViewHandle> {
  bool hovering = false;
  bool dragging = false;

  bool get active => hovering || dragging;

  @override
  Widget build(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);
    final visualColor = active ? colors.focusBorder : colors.editorGroupBorder;

    return MouseRegion(
      cursor: widget.axis == Axis.horizontal
          ? SystemMouseCursors.resizeColumn
          : SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: widget.axis == Axis.horizontal
            ? (_) => setState(() => dragging = true)
            : null,
        onHorizontalDragUpdate: widget.axis == Axis.horizontal
            ? (details) => widget.onDragDelta(details.delta)
            : null,
        onHorizontalDragEnd: widget.axis == Axis.horizontal
            ? (_) => setState(() => dragging = false)
            : null,
        onHorizontalDragCancel: widget.axis == Axis.horizontal
            ? () => setState(() => dragging = false)
            : null,
        onVerticalDragStart: widget.axis == Axis.vertical
            ? (_) => setState(() => dragging = true)
            : null,
        onVerticalDragUpdate: widget.axis == Axis.vertical
            ? (details) => widget.onDragDelta(details.delta)
            : null,
        onVerticalDragEnd: widget.axis == Axis.vertical
            ? (_) => setState(() => dragging = false)
            : null,
        onVerticalDragCancel: widget.axis == Axis.vertical
            ? () => setState(() => dragging = false)
            : null,
        child: SizedBox(
          width: widget.axis == Axis.horizontal ? widget.hitboxExtent : null,
          height: widget.axis == Axis.vertical ? widget.hitboxExtent : null,
          child: Center(
            child: SizedBox(
              width: widget.axis == Axis.horizontal
                  ? widget.separatorThickness
                  : double.infinity,
              height: widget.axis == Axis.vertical
                  ? widget.separatorThickness
                  : double.infinity,
              child: ColoredBox(color: visualColor),
            ),
          ),
        ),
      ),
    );
  }
}
