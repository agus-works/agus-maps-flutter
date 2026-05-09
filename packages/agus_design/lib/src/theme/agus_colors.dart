import 'package:flutter/material.dart';

@immutable
class AgusColors extends ThemeExtension<AgusColors> {
  const AgusColors({
    required this.workbenchBackground,
    required this.titleBarBackground,
    required this.titleBarForeground,
    required this.activityBarBackground,
    required this.activityBarForeground,
    required this.activityBarActiveForeground,
    required this.activityBarBadgeBackground,
    required this.activityBarBadgeForeground,
    required this.sideBarBackground,
    required this.sideBarForeground,
    required this.sideBarTitleForeground,
    required this.sideBarBorder,
    required this.editorBackground,
    required this.editorForeground,
    required this.editorGroupBorder,
    required this.tabActiveBackground,
    required this.tabInactiveBackground,
    required this.tabActiveForeground,
    required this.tabInactiveForeground,
    required this.tabBorder,
    required this.tabDirtyIndicator,
    required this.panelBackground,
    required this.panelBorder,
    required this.panelTabActiveForeground,
    required this.panelTabInactiveForeground,
    required this.statusBarBackground,
    required this.statusBarForeground,
    required this.statusBarItemHoverBackground,
    required this.inputBackground,
    required this.inputForeground,
    required this.inputBorder,
    required this.focusBorder,
    required this.selectionBackground,
    required this.hoverBackground,
    required this.treeIndentGuide,
    required this.scrollbarThumb,
    required this.warningBackground,
    required this.errorBackground,
  });

  static const dark = AgusColors(
    workbenchBackground: Color(0xFF1E1E1E),
    titleBarBackground: Color(0xFF3C3C3C),
    titleBarForeground: Color(0xFFCCCCCC),
    activityBarBackground: Color(0xFF333333),
    activityBarForeground: Color(0xFF858585),
    activityBarActiveForeground: Color(0xFFFFFFFF),
    activityBarBadgeBackground: Color(0xFF007ACC),
    activityBarBadgeForeground: Color(0xFFFFFFFF),
    sideBarBackground: Color(0xFF252526),
    sideBarForeground: Color(0xFFCCCCCC),
    sideBarTitleForeground: Color(0xFFBBBBBB),
    sideBarBorder: Color(0xFF2B2B2B),
    editorBackground: Color(0xFF1E1E1E),
    editorForeground: Color(0xFFD4D4D4),
    editorGroupBorder: Color(0xFF404040),
    tabActiveBackground: Color(0xFF1E1E1E),
    tabInactiveBackground: Color(0xFF2D2D2D),
    tabActiveForeground: Color(0xFFFFFFFF),
    tabInactiveForeground: Color(0xFF969696),
    tabBorder: Color(0xFF252526),
    tabDirtyIndicator: Color(0xFF519ABA),
    panelBackground: Color(0xFF1E1E1E),
    panelBorder: Color(0xFF3C3C3C),
    panelTabActiveForeground: Color(0xFFFFFFFF),
    panelTabInactiveForeground: Color(0xFF969696),
    statusBarBackground: Color(0xFF007ACC),
    statusBarForeground: Color(0xFFFFFFFF),
    statusBarItemHoverBackground: Color(0x33333333),
    inputBackground: Color(0xFF3C3C3C),
    inputForeground: Color(0xFFCCCCCC),
    inputBorder: Color(0xFF3C3C3C),
    focusBorder: Color(0xFF007FD4),
    selectionBackground: Color(0xFF264F78),
    hoverBackground: Color(0xFF2A2D2E),
    treeIndentGuide: Color(0xFF585858),
    scrollbarThumb: Color(0x66797979),
    warningBackground: Color(0xFFCCA700),
    errorBackground: Color(0xFFF14C4C),
  );

  static const light = AgusColors(
    workbenchBackground: Color(0xFFF3F3F3),
    titleBarBackground: Color(0xFFDDDDDD),
    titleBarForeground: Color(0xFF333333),
    activityBarBackground: Color(0xFFF8F8F8),
    activityBarForeground: Color(0xFF616161),
    activityBarActiveForeground: Color(0xFF181818),
    activityBarBadgeBackground: Color(0xFF005FB8),
    activityBarBadgeForeground: Color(0xFFFFFFFF),
    sideBarBackground: Color(0xFFF3F3F3),
    sideBarForeground: Color(0xFF333333),
    sideBarTitleForeground: Color(0xFF555555),
    sideBarBorder: Color(0xFFD7D7D7),
    editorBackground: Color(0xFFFFFFFF),
    editorForeground: Color(0xFF333333),
    editorGroupBorder: Color(0xFFE5E5E5),
    tabActiveBackground: Color(0xFFFFFFFF),
    tabInactiveBackground: Color(0xFFECECEC),
    tabActiveForeground: Color(0xFF1F1F1F),
    tabInactiveForeground: Color(0xFF5F5F5F),
    tabBorder: Color(0xFFD7D7D7),
    tabDirtyIndicator: Color(0xFF005FB8),
    panelBackground: Color(0xFFF8F8F8),
    panelBorder: Color(0xFFD7D7D7),
    panelTabActiveForeground: Color(0xFF1F1F1F),
    panelTabInactiveForeground: Color(0xFF5F5F5F),
    statusBarBackground: Color(0xFF005FB8),
    statusBarForeground: Color(0xFFFFFFFF),
    statusBarItemHoverBackground: Color(0x22000000),
    inputBackground: Color(0xFFFFFFFF),
    inputForeground: Color(0xFF333333),
    inputBorder: Color(0xFFC8C8C8),
    focusBorder: Color(0xFF005FB8),
    selectionBackground: Color(0xFFD6EBFF),
    hoverBackground: Color(0xFFE8E8E8),
    treeIndentGuide: Color(0xFFC4C4C4),
    scrollbarThumb: Color(0x668C8C8C),
    warningBackground: Color(0xFFB58105),
    errorBackground: Color(0xFFC72E0F),
  );

  final Color workbenchBackground;
  final Color titleBarBackground;
  final Color titleBarForeground;
  final Color activityBarBackground;
  final Color activityBarForeground;
  final Color activityBarActiveForeground;
  final Color activityBarBadgeBackground;
  final Color activityBarBadgeForeground;
  final Color sideBarBackground;
  final Color sideBarForeground;
  final Color sideBarTitleForeground;
  final Color sideBarBorder;
  final Color editorBackground;
  final Color editorForeground;
  final Color editorGroupBorder;
  final Color tabActiveBackground;
  final Color tabInactiveBackground;
  final Color tabActiveForeground;
  final Color tabInactiveForeground;
  final Color tabBorder;
  final Color tabDirtyIndicator;
  final Color panelBackground;
  final Color panelBorder;
  final Color panelTabActiveForeground;
  final Color panelTabInactiveForeground;
  final Color statusBarBackground;
  final Color statusBarForeground;
  final Color statusBarItemHoverBackground;
  final Color inputBackground;
  final Color inputForeground;
  final Color inputBorder;
  final Color focusBorder;
  final Color selectionBackground;
  final Color hoverBackground;
  final Color treeIndentGuide;
  final Color scrollbarThumb;
  final Color warningBackground;
  final Color errorBackground;

  @override
  AgusColors copyWith({
    Color? workbenchBackground,
    Color? titleBarBackground,
    Color? titleBarForeground,
    Color? activityBarBackground,
    Color? activityBarForeground,
    Color? activityBarActiveForeground,
    Color? activityBarBadgeBackground,
    Color? activityBarBadgeForeground,
    Color? sideBarBackground,
    Color? sideBarForeground,
    Color? sideBarTitleForeground,
    Color? sideBarBorder,
    Color? editorBackground,
    Color? editorForeground,
    Color? editorGroupBorder,
    Color? tabActiveBackground,
    Color? tabInactiveBackground,
    Color? tabActiveForeground,
    Color? tabInactiveForeground,
    Color? tabBorder,
    Color? tabDirtyIndicator,
    Color? panelBackground,
    Color? panelBorder,
    Color? panelTabActiveForeground,
    Color? panelTabInactiveForeground,
    Color? statusBarBackground,
    Color? statusBarForeground,
    Color? statusBarItemHoverBackground,
    Color? inputBackground,
    Color? inputForeground,
    Color? inputBorder,
    Color? focusBorder,
    Color? selectionBackground,
    Color? hoverBackground,
    Color? treeIndentGuide,
    Color? scrollbarThumb,
    Color? warningBackground,
    Color? errorBackground,
  }) {
    return AgusColors(
      workbenchBackground: workbenchBackground ?? this.workbenchBackground,
      titleBarBackground: titleBarBackground ?? this.titleBarBackground,
      titleBarForeground: titleBarForeground ?? this.titleBarForeground,
      activityBarBackground:
          activityBarBackground ?? this.activityBarBackground,
      activityBarForeground:
          activityBarForeground ?? this.activityBarForeground,
      activityBarActiveForeground:
          activityBarActiveForeground ?? this.activityBarActiveForeground,
      activityBarBadgeBackground:
          activityBarBadgeBackground ?? this.activityBarBadgeBackground,
      activityBarBadgeForeground:
          activityBarBadgeForeground ?? this.activityBarBadgeForeground,
      sideBarBackground: sideBarBackground ?? this.sideBarBackground,
      sideBarForeground: sideBarForeground ?? this.sideBarForeground,
      sideBarTitleForeground:
          sideBarTitleForeground ?? this.sideBarTitleForeground,
      sideBarBorder: sideBarBorder ?? this.sideBarBorder,
      editorBackground: editorBackground ?? this.editorBackground,
      editorForeground: editorForeground ?? this.editorForeground,
      editorGroupBorder: editorGroupBorder ?? this.editorGroupBorder,
      tabActiveBackground: tabActiveBackground ?? this.tabActiveBackground,
      tabInactiveBackground:
          tabInactiveBackground ?? this.tabInactiveBackground,
      tabActiveForeground: tabActiveForeground ?? this.tabActiveForeground,
      tabInactiveForeground:
          tabInactiveForeground ?? this.tabInactiveForeground,
      tabBorder: tabBorder ?? this.tabBorder,
      tabDirtyIndicator: tabDirtyIndicator ?? this.tabDirtyIndicator,
      panelBackground: panelBackground ?? this.panelBackground,
      panelBorder: panelBorder ?? this.panelBorder,
      panelTabActiveForeground:
          panelTabActiveForeground ?? this.panelTabActiveForeground,
      panelTabInactiveForeground:
          panelTabInactiveForeground ?? this.panelTabInactiveForeground,
      statusBarBackground: statusBarBackground ?? this.statusBarBackground,
      statusBarForeground: statusBarForeground ?? this.statusBarForeground,
      statusBarItemHoverBackground:
          statusBarItemHoverBackground ?? this.statusBarItemHoverBackground,
      inputBackground: inputBackground ?? this.inputBackground,
      inputForeground: inputForeground ?? this.inputForeground,
      inputBorder: inputBorder ?? this.inputBorder,
      focusBorder: focusBorder ?? this.focusBorder,
      selectionBackground: selectionBackground ?? this.selectionBackground,
      hoverBackground: hoverBackground ?? this.hoverBackground,
      treeIndentGuide: treeIndentGuide ?? this.treeIndentGuide,
      scrollbarThumb: scrollbarThumb ?? this.scrollbarThumb,
      warningBackground: warningBackground ?? this.warningBackground,
      errorBackground: errorBackground ?? this.errorBackground,
    );
  }

  @override
  AgusColors lerp(ThemeExtension<AgusColors>? other, double t) {
    if (other is! AgusColors) {
      return this;
    }

    return AgusColors(
      workbenchBackground: Color.lerp(
        workbenchBackground,
        other.workbenchBackground,
        t,
      )!,
      titleBarBackground: Color.lerp(
        titleBarBackground,
        other.titleBarBackground,
        t,
      )!,
      titleBarForeground: Color.lerp(
        titleBarForeground,
        other.titleBarForeground,
        t,
      )!,
      activityBarBackground: Color.lerp(
        activityBarBackground,
        other.activityBarBackground,
        t,
      )!,
      activityBarForeground: Color.lerp(
        activityBarForeground,
        other.activityBarForeground,
        t,
      )!,
      activityBarActiveForeground: Color.lerp(
        activityBarActiveForeground,
        other.activityBarActiveForeground,
        t,
      )!,
      activityBarBadgeBackground: Color.lerp(
        activityBarBadgeBackground,
        other.activityBarBadgeBackground,
        t,
      )!,
      activityBarBadgeForeground: Color.lerp(
        activityBarBadgeForeground,
        other.activityBarBadgeForeground,
        t,
      )!,
      sideBarBackground: Color.lerp(
        sideBarBackground,
        other.sideBarBackground,
        t,
      )!,
      sideBarForeground: Color.lerp(
        sideBarForeground,
        other.sideBarForeground,
        t,
      )!,
      sideBarTitleForeground: Color.lerp(
        sideBarTitleForeground,
        other.sideBarTitleForeground,
        t,
      )!,
      sideBarBorder: Color.lerp(sideBarBorder, other.sideBarBorder, t)!,
      editorBackground: Color.lerp(
        editorBackground,
        other.editorBackground,
        t,
      )!,
      editorForeground: Color.lerp(
        editorForeground,
        other.editorForeground,
        t,
      )!,
      editorGroupBorder: Color.lerp(
        editorGroupBorder,
        other.editorGroupBorder,
        t,
      )!,
      tabActiveBackground: Color.lerp(
        tabActiveBackground,
        other.tabActiveBackground,
        t,
      )!,
      tabInactiveBackground: Color.lerp(
        tabInactiveBackground,
        other.tabInactiveBackground,
        t,
      )!,
      tabActiveForeground: Color.lerp(
        tabActiveForeground,
        other.tabActiveForeground,
        t,
      )!,
      tabInactiveForeground: Color.lerp(
        tabInactiveForeground,
        other.tabInactiveForeground,
        t,
      )!,
      tabBorder: Color.lerp(tabBorder, other.tabBorder, t)!,
      tabDirtyIndicator: Color.lerp(
        tabDirtyIndicator,
        other.tabDirtyIndicator,
        t,
      )!,
      panelBackground: Color.lerp(panelBackground, other.panelBackground, t)!,
      panelBorder: Color.lerp(panelBorder, other.panelBorder, t)!,
      panelTabActiveForeground: Color.lerp(
        panelTabActiveForeground,
        other.panelTabActiveForeground,
        t,
      )!,
      panelTabInactiveForeground: Color.lerp(
        panelTabInactiveForeground,
        other.panelTabInactiveForeground,
        t,
      )!,
      statusBarBackground: Color.lerp(
        statusBarBackground,
        other.statusBarBackground,
        t,
      )!,
      statusBarForeground: Color.lerp(
        statusBarForeground,
        other.statusBarForeground,
        t,
      )!,
      statusBarItemHoverBackground: Color.lerp(
        statusBarItemHoverBackground,
        other.statusBarItemHoverBackground,
        t,
      )!,
      inputBackground: Color.lerp(inputBackground, other.inputBackground, t)!,
      inputForeground: Color.lerp(inputForeground, other.inputForeground, t)!,
      inputBorder: Color.lerp(inputBorder, other.inputBorder, t)!,
      focusBorder: Color.lerp(focusBorder, other.focusBorder, t)!,
      selectionBackground: Color.lerp(
        selectionBackground,
        other.selectionBackground,
        t,
      )!,
      hoverBackground: Color.lerp(hoverBackground, other.hoverBackground, t)!,
      treeIndentGuide: Color.lerp(treeIndentGuide, other.treeIndentGuide, t)!,
      scrollbarThumb: Color.lerp(scrollbarThumb, other.scrollbarThumb, t)!,
      warningBackground: Color.lerp(
        warningBackground,
        other.warningBackground,
        t,
      )!,
      errorBackground: Color.lerp(errorBackground, other.errorBackground, t)!,
    );
  }
}
