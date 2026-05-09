import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/agus_theme_data.dart';

enum AgusSplitViewPane { first, second }

class AgusSplitView extends StatefulWidget {
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

  final Axis axis;
  final Widget first;
  final Widget second;
  final double initialFirstExtent;
  final AgusSplitViewPane sizedPane;
  final double minFirstExtent;
  final double minSecondExtent;
  final ValueChanged<double>? onFirstExtentChanged;
  final ValueChanged<double>? onSizedExtentChanged;

  @override
  State<AgusSplitView> createState() => _AgusSplitViewState();
}

class _AgusSplitViewState extends State<AgusSplitView> {
  double? sizedExtent;

  @override
  Widget build(BuildContext context) {
    final dimensions = AgusThemeData.dimensionsOf(context);
    final handleExtent = dimensions.resizeHandleThickness;

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
          totalExtent - minOtherExtent - handleExtent,
        );
        final resolvedSizedExtent = (sizedExtent ?? widget.initialFirstExtent)
            .clamp(minSizedExtent, maxSizedExtent)
            .toDouble();
        final handle = _SplitViewHandle(
          axis: widget.axis,
          extent: handleExtent,
          onDragDelta: (delta) => _updateExtent(
            resolvedSizedExtent + _extentDeltaForSizedPane(delta),
          ),
        );

        if (widget.axis == Axis.horizontal) {
          return Row(
            children: _buildHorizontalChildren(resolvedSizedExtent, handle),
          );
        }

        return Column(
          children: _buildVerticalChildren(resolvedSizedExtent, handle),
        );
      },
    );
  }

  List<Widget> _buildHorizontalChildren(double resolvedExtent, Widget handle) {
    if (widget.sizedPane == AgusSplitViewPane.second) {
      return [
        Expanded(child: widget.first),
        handle,
        SizedBox(width: resolvedExtent, child: widget.second),
      ];
    }

    return [
      SizedBox(width: resolvedExtent, child: widget.first),
      handle,
      Expanded(child: widget.second),
    ];
  }

  List<Widget> _buildVerticalChildren(double resolvedExtent, Widget handle) {
    if (widget.sizedPane == AgusSplitViewPane.second) {
      return [
        Expanded(child: widget.first),
        handle,
        SizedBox(height: resolvedExtent, child: widget.second),
      ];
    }

    return [
      SizedBox(height: resolvedExtent, child: widget.first),
      handle,
      Expanded(child: widget.second),
    ];
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
    required this.extent,
    required this.onDragDelta,
  });

  final Axis axis;
  final double extent;
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
    final visualThickness = active ? math.max(2.0, widget.extent / 2) : 1.0;
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
          width: widget.axis == Axis.horizontal ? widget.extent : null,
          height: widget.axis == Axis.vertical ? widget.extent : null,
          child: Center(
            child: SizedBox(
              width: widget.axis == Axis.horizontal
                  ? visualThickness
                  : double.infinity,
              height: widget.axis == Axis.vertical
                  ? visualThickness
                  : double.infinity,
              child: ColoredBox(color: visualColor),
            ),
          ),
        ),
      ),
    );
  }
}
