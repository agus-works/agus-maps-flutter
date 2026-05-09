import 'dart:ui';

import 'package:flutter/material.dart';

@immutable
class AgusDimensions extends ThemeExtension<AgusDimensions> {
  const AgusDimensions({
    required this.titleBarHeight,
    required this.commandCenterHeight,
    required this.activityBarWidth,
    required this.sideBarDefaultWidth,
    required this.sideBarMinWidth,
    required this.secondarySideBarDefaultWidth,
    required this.panelDefaultHeight,
    required this.panelMinHeight,
    required this.statusBarHeight,
    required this.editorTabHeight,
    required this.panelTabHeight,
    required this.treeRowHeight,
    required this.treeIndent,
    required this.iconSize,
    required this.toolbarButtonSize,
    required this.resizeHandleThickness,
    required this.borderRadius,
  });

  static const standard = AgusDimensions(
    titleBarHeight: 35,
    commandCenterHeight: 24,
    activityBarWidth: 48,
    sideBarDefaultWidth: 300,
    sideBarMinWidth: 170,
    secondarySideBarDefaultWidth: 300,
    panelDefaultHeight: 220,
    panelMinHeight: 120,
    statusBarHeight: 22,
    editorTabHeight: 35,
    panelTabHeight: 35,
    treeRowHeight: 22,
    treeIndent: 16,
    iconSize: 16,
    toolbarButtonSize: 28,
    resizeHandleThickness: 8,
    borderRadius: 2,
  );

  final double titleBarHeight;
  final double commandCenterHeight;
  final double activityBarWidth;
  final double sideBarDefaultWidth;
  final double sideBarMinWidth;
  final double secondarySideBarDefaultWidth;
  final double panelDefaultHeight;
  final double panelMinHeight;
  final double statusBarHeight;
  final double editorTabHeight;
  final double panelTabHeight;
  final double treeRowHeight;
  final double treeIndent;
  final double iconSize;
  final double toolbarButtonSize;
  final double resizeHandleThickness;
  final double borderRadius;

  @override
  AgusDimensions copyWith({
    double? titleBarHeight,
    double? commandCenterHeight,
    double? activityBarWidth,
    double? sideBarDefaultWidth,
    double? sideBarMinWidth,
    double? secondarySideBarDefaultWidth,
    double? panelDefaultHeight,
    double? panelMinHeight,
    double? statusBarHeight,
    double? editorTabHeight,
    double? panelTabHeight,
    double? treeRowHeight,
    double? treeIndent,
    double? iconSize,
    double? toolbarButtonSize,
    double? resizeHandleThickness,
    double? borderRadius,
  }) {
    return AgusDimensions(
      titleBarHeight: titleBarHeight ?? this.titleBarHeight,
      commandCenterHeight: commandCenterHeight ?? this.commandCenterHeight,
      activityBarWidth: activityBarWidth ?? this.activityBarWidth,
      sideBarDefaultWidth: sideBarDefaultWidth ?? this.sideBarDefaultWidth,
      sideBarMinWidth: sideBarMinWidth ?? this.sideBarMinWidth,
      secondarySideBarDefaultWidth:
          secondarySideBarDefaultWidth ?? this.secondarySideBarDefaultWidth,
      panelDefaultHeight: panelDefaultHeight ?? this.panelDefaultHeight,
      panelMinHeight: panelMinHeight ?? this.panelMinHeight,
      statusBarHeight: statusBarHeight ?? this.statusBarHeight,
      editorTabHeight: editorTabHeight ?? this.editorTabHeight,
      panelTabHeight: panelTabHeight ?? this.panelTabHeight,
      treeRowHeight: treeRowHeight ?? this.treeRowHeight,
      treeIndent: treeIndent ?? this.treeIndent,
      iconSize: iconSize ?? this.iconSize,
      toolbarButtonSize: toolbarButtonSize ?? this.toolbarButtonSize,
      resizeHandleThickness:
          resizeHandleThickness ?? this.resizeHandleThickness,
      borderRadius: borderRadius ?? this.borderRadius,
    );
  }

  @override
  AgusDimensions lerp(ThemeExtension<AgusDimensions>? other, double t) {
    if (other is! AgusDimensions) {
      return this;
    }

    return AgusDimensions(
      titleBarHeight: lerpDouble(titleBarHeight, other.titleBarHeight, t)!,
      commandCenterHeight: lerpDouble(
        commandCenterHeight,
        other.commandCenterHeight,
        t,
      )!,
      activityBarWidth: lerpDouble(
        activityBarWidth,
        other.activityBarWidth,
        t,
      )!,
      sideBarDefaultWidth: lerpDouble(
        sideBarDefaultWidth,
        other.sideBarDefaultWidth,
        t,
      )!,
      sideBarMinWidth: lerpDouble(sideBarMinWidth, other.sideBarMinWidth, t)!,
      secondarySideBarDefaultWidth: lerpDouble(
        secondarySideBarDefaultWidth,
        other.secondarySideBarDefaultWidth,
        t,
      )!,
      panelDefaultHeight: lerpDouble(
        panelDefaultHeight,
        other.panelDefaultHeight,
        t,
      )!,
      panelMinHeight: lerpDouble(panelMinHeight, other.panelMinHeight, t)!,
      statusBarHeight: lerpDouble(statusBarHeight, other.statusBarHeight, t)!,
      editorTabHeight: lerpDouble(editorTabHeight, other.editorTabHeight, t)!,
      panelTabHeight: lerpDouble(panelTabHeight, other.panelTabHeight, t)!,
      treeRowHeight: lerpDouble(treeRowHeight, other.treeRowHeight, t)!,
      treeIndent: lerpDouble(treeIndent, other.treeIndent, t)!,
      iconSize: lerpDouble(iconSize, other.iconSize, t)!,
      toolbarButtonSize: lerpDouble(
        toolbarButtonSize,
        other.toolbarButtonSize,
        t,
      )!,
      resizeHandleThickness: lerpDouble(
        resizeHandleThickness,
        other.resizeHandleThickness,
        t,
      )!,
      borderRadius: lerpDouble(borderRadius, other.borderRadius, t)!,
    );
  }
}
