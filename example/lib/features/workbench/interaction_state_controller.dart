import 'package:flutter/foundation.dart';

/// App interaction mode discriminants.
enum AppInteractionMode {
  /// Default navigation, browsing, and map interactions.
  idle,

  /// Search bar is focused or search results are shown.
  searching,

  /// Drawing a new feature (point, line, segment, polygon).
  drawing,

  /// Editing an existing feature's geometry.
  editingFeature,

  /// Route planning or active navigation mode.
  routing,

  /// Downloading or updating MWM files.
  downloadingMwm,

  /// Switching or focusing on a map layer.
  switchingLayer,

  /// A modal dialog or command input UI is active.
  modalInput,
}

/// Immutable app interaction state snapshot.
@immutable
class AppInteractionState {
  /// Creates an interaction state with the given [mode] and optional metadata.
  const AppInteractionState({
    this.mode = AppInteractionMode.idle,
    this.metadata = const <String, Object?>{},
  });

  /// Current app interaction mode.
  final AppInteractionMode mode;

  /// Optional metadata about the current mode, such as:
  /// - `drawTool`: the active draw tool type (string)
  /// - `featureId`: the feature being edited (int/string)
  /// - `layerId`: the active layer (string)
  /// - `searchQuery`: the active search query (string)
  final Map<String, Object?> metadata;

  /// Returns a new state with updated [mode] and optional [metadata].
  AppInteractionState copyWith({
    AppInteractionMode? mode,
    Map<String, Object?>? metadata,
  }) {
    return AppInteractionState(
      mode: mode ?? this.mode,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Whether the current mode allows navigation commands.
  bool get allowsNavigation =>
      mode == AppInteractionMode.idle ||
      mode == AppInteractionMode.searching ||
      mode == AppInteractionMode.switchingLayer;

  /// Whether the current mode allows starting a new drawing operation.
  bool get allowsDrawing => mode == AppInteractionMode.idle;

  /// Whether the current mode allows editing features.
  bool get allowsFeatureEdit =>
      mode == AppInteractionMode.idle || mode == AppInteractionMode.editingFeature;

  /// Whether the current mode allows routing operations.
  bool get allowsRouting =>
      mode == AppInteractionMode.idle ||
      mode == AppInteractionMode.searching ||
      mode == AppInteractionMode.routing;

  /// Whether the current mode allows MWM download operations.
  bool get allowsMwmDownload =>
      mode == AppInteractionMode.idle ||
      mode == AppInteractionMode.downloadingMwm ||
      mode == AppInteractionMode.searching;

  /// Whether the current mode allows layer switching.
  bool get allowsLayerSwitch =>
      mode == AppInteractionMode.idle ||
      mode == AppInteractionMode.switchingLayer;

  /// Whether the app is in a busy state requiring commit/cancel before other operations.
  bool get isEditing =>
      mode == AppInteractionMode.drawing ||
      mode == AppInteractionMode.editingFeature;

  /// Human-readable reason why an operation is blocked, if any.
  String? disabledReason(String operation) {
    switch (operation) {
      case 'draw':
        if (!allowsDrawing) {
          if (isEditing) {
            return 'A drawing or feature edit is in progress. Commit or cancel it before starting a new drawing.';
          }
          return 'Cannot start drawing in ${mode.name} mode.';
        }
        return null;
      case 'edit':
        if (!allowsFeatureEdit && mode != AppInteractionMode.idle) {
          return 'Cannot edit features in ${mode.name} mode.';
        }
        return null;
      case 'route':
        if (!allowsRouting && mode != AppInteractionMode.idle) {
          return 'Cannot plan routes in ${mode.name} mode.';
        }
        return null;
      default:
        return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppInteractionState &&
          runtimeType == other.runtimeType &&
          mode == other.mode &&
          _mapEquals(metadata, other.metadata);

  @override
  int get hashCode => Object.hash(mode, Object.hashAll(metadata.entries));

  static bool _mapEquals(Map<String, Object?> a, Map<String, Object?> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || a[key] != b[key]) return false;
    }
    return true;
  }
}

/// Controller for global app interaction state.
///
/// Manages high-level interaction modes such as idle, searching, drawing,
/// editing feature, routing, downloading MWM, switching layer, and modal input.
/// Commands and UI interactions query this controller to determine if they
/// are allowed or should be disabled with a clear reason.
class AppInteractionStateController extends ChangeNotifier {
  /// Creates an interaction state controller with optional initial [state].
  AppInteractionStateController({
    AppInteractionState state = const AppInteractionState(),
  }) : _state = state;

  AppInteractionState _state;

  /// Current interaction state.
  AppInteractionState get state => _state;

  /// Current interaction mode.
  AppInteractionMode get mode => _state.mode;

  /// Whether the app is idle (default navigation/browsing).
  bool get isIdle => _state.mode == AppInteractionMode.idle;

  /// Whether the app is in search mode.
  bool get isSearching => _state.mode == AppInteractionMode.searching;

  /// Whether the app is drawing a new feature.
  bool get isDrawing => _state.mode == AppInteractionMode.drawing;

  /// Whether the app is editing an existing feature.
  bool get isEditingFeature => _state.mode == AppInteractionMode.editingFeature;

  /// Whether the app is in routing mode.
  bool get isRouting => _state.mode == AppInteractionMode.routing;

  /// Whether the app is downloading or updating MWM files.
  bool get isDownloadingMwm => _state.mode == AppInteractionMode.downloadingMwm;

  /// Whether the app is switching or focusing on a layer.
  bool get isSwitchingLayer => _state.mode == AppInteractionMode.switchingLayer;

  /// Whether a modal dialog or command input is active.
  bool get isModalInput => _state.mode == AppInteractionMode.modalInput;

  /// Whether the app is in an editing state that requires commit/cancel.
  bool get isEditing => _state.isEditing;

  /// Transitions to idle mode.
  void enterIdle() {
    _setState(const AppInteractionState(mode: AppInteractionMode.idle));
  }

  /// Transitions to search mode.
  void enterSearch({String? query}) {
    _setState(
      AppInteractionState(
        mode: AppInteractionMode.searching,
        metadata: query != null ? {'searchQuery': query} : {},
      ),
    );
  }

  /// Transitions to drawing mode with optional [tool] metadata.
  void enterDrawing({String? tool}) {
    _setState(
      AppInteractionState(
        mode: AppInteractionMode.drawing,
        metadata: tool != null ? {'drawTool': tool} : {},
      ),
    );
  }

  /// Transitions to feature editing mode with optional [featureId].
  void enterEditingFeature({Object? featureId}) {
    _setState(
      AppInteractionState(
        mode: AppInteractionMode.editingFeature,
        metadata: featureId != null ? {'featureId': featureId} : {},
      ),
    );
  }

  /// Transitions to routing mode.
  void enterRouting() {
    _setState(const AppInteractionState(mode: AppInteractionMode.routing));
  }

  /// Transitions to MWM download/update mode.
  void enterDownloadingMwm() {
    _setState(const AppInteractionState(mode: AppInteractionMode.downloadingMwm));
  }

  /// Transitions to layer switching mode with optional [layerId].
  void enterSwitchingLayer({String? layerId}) {
    _setState(
      AppInteractionState(
        mode: AppInteractionMode.switchingLayer,
        metadata: layerId != null ? {'layerId': layerId} : {},
      ),
    );
  }

  /// Transitions to modal input mode.
  void enterModalInput() {
    _setState(const AppInteractionState(mode: AppInteractionMode.modalInput));
  }

  /// Checks if an operation is allowed in the current state.
  bool isOperationAllowed(String operation) {
    switch (operation) {
      case 'draw':
        return _state.allowsDrawing;
      case 'edit':
        return _state.allowsFeatureEdit;
      case 'route':
        return _state.allowsRouting;
      case 'navigate':
        return _state.allowsNavigation;
      case 'downloadMwm':
        return _state.allowsMwmDownload;
      case 'switchLayer':
        return _state.allowsLayerSwitch;
      default:
        return true;
    }
  }

  /// Returns a human-readable reason why an operation is disabled, if any.
  String? disabledReason(String operation) {
    return _state.disabledReason(operation);
  }

  void _setState(AppInteractionState nextState) {
    if (_state == nextState) return;
    _state = nextState;
    notifyListeners();
  }
}
