import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Primary Activity Bar destinations in the desktop workbench.
enum WorkbenchActivity {
  explorer,
  mapPresentation,
  search,
  favorites,
  downloads,
  settings,
  about,
}

/// Editor Area tabs.
enum WorkbenchEditorTab {
  blank,
  map,
}

/// Bottom Panel tabs.
enum WorkbenchPanelTab {
  pointOfInterest,
  debugConsole,
}

/// Secondary Side Bar tabs.
enum WorkbenchSecondarySideBarTab {
  properties,
  inspector,
}

/// Immutable desktop layout state for VS Code-style workbench surfaces.
@immutable
class WorkbenchLayoutState {
  /// Creates layout state for Activity Bar, Side Bars, Editor Area, and Panel.
  const WorkbenchLayoutState({
    this.activeActivity = WorkbenchActivity.explorer,
    this.primarySideBarVisible = true,
    this.secondarySideBarVisible = true,
    this.panelVisible = true,
    this.activeEditorTab = WorkbenchEditorTab.map,
    this.activePanelTab = WorkbenchPanelTab.pointOfInterest,
    this.activeSecondarySideBarTab = WorkbenchSecondarySideBarTab.properties,
    this.editorTabOrder = const [
      WorkbenchEditorTab.blank,
      WorkbenchEditorTab.map,
    ],
    this.panelTabOrder = const [
      WorkbenchPanelTab.pointOfInterest,
      WorkbenchPanelTab.debugConsole,
    ],
    this.secondarySideBarTabOrder = const [
      WorkbenchSecondarySideBarTab.properties,
      WorkbenchSecondarySideBarTab.inspector,
    ],
    this.primarySideBarWidth = 340,
    this.secondarySideBarWidth = 320,
    this.panelHeight = 260,
  });

  /// Active Activity Bar item.
  final WorkbenchActivity activeActivity;

  /// Whether the Primary Side Bar is visible.
  final bool primarySideBarVisible;

  /// Whether the Secondary Side Bar is visible.
  final bool secondarySideBarVisible;

  /// Whether the bottom Panel is visible.
  final bool panelVisible;

  /// Active Editor Area tab.
  final WorkbenchEditorTab activeEditorTab;

  /// Active bottom Panel tab.
  final WorkbenchPanelTab activePanelTab;

  /// Active Secondary Side Bar tab.
  final WorkbenchSecondarySideBarTab activeSecondarySideBarTab;

  /// Current visual order for Editor Area tabs.
  final List<WorkbenchEditorTab> editorTabOrder;

  /// Current visual order for bottom Panel tabs.
  final List<WorkbenchPanelTab> panelTabOrder;

  /// Current visual order for Secondary Side Bar tabs.
  final List<WorkbenchSecondarySideBarTab> secondarySideBarTabOrder;

  /// Width of the Primary Side Bar in logical pixels.
  final double primarySideBarWidth;

  /// Width of the Secondary Side Bar in logical pixels.
  final double secondarySideBarWidth;

  /// Height of the bottom Panel in logical pixels.
  final double panelHeight;

  /// Creates a modified copy.
  WorkbenchLayoutState copyWith({
    WorkbenchActivity? activeActivity,
    bool? primarySideBarVisible,
    bool? secondarySideBarVisible,
    bool? panelVisible,
    WorkbenchEditorTab? activeEditorTab,
    WorkbenchPanelTab? activePanelTab,
    WorkbenchSecondarySideBarTab? activeSecondarySideBarTab,
    List<WorkbenchEditorTab>? editorTabOrder,
    List<WorkbenchPanelTab>? panelTabOrder,
    List<WorkbenchSecondarySideBarTab>? secondarySideBarTabOrder,
    double? primarySideBarWidth,
    double? secondarySideBarWidth,
    double? panelHeight,
  }) {
    return WorkbenchLayoutState(
      activeActivity: activeActivity ?? this.activeActivity,
      primarySideBarVisible:
          primarySideBarVisible ?? this.primarySideBarVisible,
      secondarySideBarVisible:
          secondarySideBarVisible ?? this.secondarySideBarVisible,
      panelVisible: panelVisible ?? this.panelVisible,
      activeEditorTab: activeEditorTab ?? this.activeEditorTab,
      activePanelTab: activePanelTab ?? this.activePanelTab,
      activeSecondarySideBarTab:
          activeSecondarySideBarTab ?? this.activeSecondarySideBarTab,
      editorTabOrder: editorTabOrder ?? this.editorTabOrder,
      panelTabOrder: panelTabOrder ?? this.panelTabOrder,
      secondarySideBarTabOrder:
          secondarySideBarTabOrder ?? this.secondarySideBarTabOrder,
      primarySideBarWidth: primarySideBarWidth ?? this.primarySideBarWidth,
      secondarySideBarWidth:
          secondarySideBarWidth ?? this.secondarySideBarWidth,
      panelHeight: panelHeight ?? this.panelHeight,
    );
  }
}

/// Global workbench state manager for desktop panes and tabs.
class WorkbenchController extends ChangeNotifier {
  /// Creates a controller with optional initial [state].
  WorkbenchController({
    WorkbenchLayoutState state = const WorkbenchLayoutState(),
  }) : _state = state;

  static const double _minSideBarWidth = 240;
  static const double _maxSideBarWidth = 560;
  static const double _minPanelHeight = 160;
  static const double _maxPanelHeight = 520;

  WorkbenchLayoutState _state;

  /// Current immutable layout state.
  WorkbenchLayoutState get state => _state;

  /// Selects an activity, toggling the Primary Side Bar when reselected.
  void selectActivity(WorkbenchActivity activity) {
    if (_state.activeActivity == activity && _state.primarySideBarVisible) {
      _setState(_state.copyWith(primarySideBarVisible: false));
      return;
    }

    _setState(
      _state.copyWith(
        activeActivity: activity,
        primarySideBarVisible: true,
      ),
    );
  }

  /// Selects an Editor Area tab.
  void selectEditorTab(WorkbenchEditorTab tab) {
    _setState(_state.copyWith(activeEditorTab: tab));
  }

  /// Reorders Editor Area tabs while preserving all known tabs exactly once.
  void reorderEditorTabs(List<WorkbenchEditorTab> tabs) {
    _setState(
      _state.copyWith(
        editorTabOrder: _normalizedOrder(tabs, WorkbenchEditorTab.values),
      ),
    );
  }

  /// Selects a bottom Panel tab and ensures the Panel is visible.
  void selectPanelTab(WorkbenchPanelTab tab) {
    _setState(_state.copyWith(activePanelTab: tab, panelVisible: true));
  }

  /// Reorders bottom Panel tabs while preserving all known tabs exactly once.
  void reorderPanelTabs(List<WorkbenchPanelTab> tabs) {
    _setState(
      _state.copyWith(
        panelTabOrder: _normalizedOrder(tabs, WorkbenchPanelTab.values),
      ),
    );
  }

  /// Selects a Secondary Side Bar tab and ensures the side bar is visible.
  void selectSecondarySideBarTab(WorkbenchSecondarySideBarTab tab) {
    _setState(
      _state.copyWith(
        activeSecondarySideBarTab: tab,
        secondarySideBarVisible: true,
      ),
    );
  }

  /// Reorders Secondary Side Bar tabs while preserving all known tabs once.
  void reorderSecondarySideBarTabs(List<WorkbenchSecondarySideBarTab> tabs) {
    _setState(
      _state.copyWith(
        secondarySideBarTabOrder: _normalizedOrder(
          tabs,
          WorkbenchSecondarySideBarTab.values,
        ),
      ),
    );
  }

  /// Toggles the Primary Side Bar.
  void togglePrimarySideBar() {
    _setState(
      _state.copyWith(primarySideBarVisible: !_state.primarySideBarVisible),
    );
  }

  /// Toggles the Secondary Side Bar.
  void toggleSecondarySideBar() {
    _setState(
      _state.copyWith(
        secondarySideBarVisible: !_state.secondarySideBarVisible,
      ),
    );
  }

  /// Toggles the bottom Panel.
  void togglePanel() {
    _setState(_state.copyWith(panelVisible: !_state.panelVisible));
  }

  /// Resizes the Primary Side Bar by [delta].
  void resizePrimarySideBar(double delta) {
    _setState(
      _state.copyWith(
        primarySideBarWidth: _clamp(
          _state.primarySideBarWidth + delta,
          _minSideBarWidth,
          _maxSideBarWidth,
        ),
      ),
    );
  }

  /// Resizes the Secondary Side Bar by [delta].
  void resizeSecondarySideBar(double delta) {
    _setState(
      _state.copyWith(
        secondarySideBarWidth: _clamp(
          _state.secondarySideBarWidth + delta,
          _minSideBarWidth,
          _maxSideBarWidth,
        ),
      ),
    );
  }

  /// Resizes the bottom Panel by [delta].
  void resizePanel(double delta) {
    _setState(
      _state.copyWith(
        panelHeight: _clamp(
          _state.panelHeight + delta,
          _minPanelHeight,
          _maxPanelHeight,
        ),
      ),
    );
  }

  void _setState(WorkbenchLayoutState nextState) {
    _state = nextState;
    notifyListeners();
  }

  static double _clamp(double value, double min, double max) {
    return math.max(min, math.min(max, value));
  }

  static List<T> _normalizedOrder<T>(List<T> nextOrder, List<T> defaultOrder) {
    final nextItems = <T>[];
    for (final item in nextOrder) {
      if (defaultOrder.contains(item) && !nextItems.contains(item)) {
        nextItems.add(item);
      }
    }
    for (final item in defaultOrder) {
      if (!nextItems.contains(item)) {
        nextItems.add(item);
      }
    }
    return List.unmodifiable(nextItems);
  }
}
