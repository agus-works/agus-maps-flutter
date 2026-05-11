# App Interaction State Machine

The app interaction state machine manages high-level interaction modes for the
example app. It helps coordinate complex workflows such as drawing, editing,
routing, and searching, ensuring that conflicting operations are safely guarded
and disabled with clear user feedback.

## Design Goals

1. **Explicit state transitions**: Operations like drawing, editing, and routing
   are tracked in a central controller so commands and UI can query whether they
   are allowed.
2. **Clear disabled reasons**: When a command or operation is blocked, the state
   machine provides a human-readable reason (e.g., "A drawing or feature edit is
   in progress. Commit or cancel it before starting a new drawing.").
3. **Keyboard flow preservation**: The state machine does not interfere with
   keyboard shortcuts, arrow navigation, Enter selection, or Escape cancellation
   in the command bar or other UI elements.
4. **Minimal design-system coupling**: The state machine lives in the example app
   and does not require changes to the core `agus_design` package.

## State Modes

The `AppInteractionMode` enum defines the following interaction modes:

### `idle`
Default navigation, browsing, and map interactions. Most commands are allowed.

### `searching`
Search bar is focused or search results are shown. Allows navigation, routing,
and MWM downloads, but blocks drawing and editing.

### `drawing`
Drawing a new feature (point, line, segment, polygon). Blocks most other
operations until the drawing is committed or cancelled.

**Metadata**: `drawTool` (string) indicating the active tool.

### `editingFeature`
Editing an existing feature's geometry. Allows feature edits but blocks new
drawing operations until committed or cancelled.

**Metadata**: `featureId` (int/string) of the feature being edited.

### `routing`
Route planning or active navigation mode. Allows routing operations and
searching, but blocks drawing and editing.

### `downloadingMwm`
Downloading or updating MWM files. Allows MWM operations but blocks drawing
and editing.

### `switchingLayer`
Switching or focusing on a map layer. Allows navigation and layer operations.

**Metadata**: `layerId` (string) of the active layer.

### `modalInput`
A modal dialog or command input UI is active (e.g., command bar open, alert
dialog shown). This mode is informational and generally does not block operations
unless the dialog itself handles input exclusively.

## State Transitions

State transitions are managed by the `AppInteractionStateController`, which
extends `ChangeNotifier` and notifies listeners when the mode changes.

### Transition methods

- `enterIdle()` → Transitions to idle mode.
- `enterSearch({String? query})` → Transitions to search mode.
- `enterDrawing({String? tool})` → Transitions to drawing mode.
- `enterEditingFeature({Object? featureId})` → Transitions to feature editing mode.
- `enterRouting()` → Transitions to routing mode.
- `enterDownloadingMwm()` → Transitions to MWM download/update mode.
- `enterSwitchingLayer({String? layerId})` → Transitions to layer switching mode.
- `enterModalInput()` → Transitions to modal input mode.

## Command Enablement

Commands in the workbench command bar derive their `enabled` state from the
interaction state controller. For example:

```dart
AgusCommandItem(
  id: 'draw-polygon',
  label: 'Draw Polygon Feature',
  icon: Icons.polyline_outlined,
  enabled: _interactionStateController.isOperationAllowed('draw'),
  onSelected: () {
    _interactionStateController.enterDrawing(tool: 'polygon');
    _setDuckDBDrawTool(agus_maps_flutter.AgusDrawTool.polygon);
  },
)
```

If a command is disabled, the state machine provides a reason via
`disabledReason(operation)`, which can be shown in a tooltip or alert.

## Example Integration

### Initialize the controller

```dart
class _MyAppState extends State<MyApp> {
  late final AppInteractionStateController _interactionStateController;

  @override
  void initState() {
    super.initState();
    _interactionStateController = AppInteractionStateController();
  }

  @override
  void dispose() {
    _interactionStateController.dispose();
    super.dispose();
  }
}
```

### Wire state transitions

```dart
void _setDuckDBDrawTool(agus_maps_flutter.AgusDrawTool tool) {
  final controller = _duckDBDrawController;
  if (controller == null) {
    return;
  }

  if (tool == agus_maps_flutter.AgusDrawTool.none) {
    // Exiting drawing mode
    controller.cancel();
    _interactionStateController.enterIdle();
  } else if (!controller.isEditing) {
    // Starting a new drawing
    _interactionStateController.enterDrawing(tool: tool.name);
    controller.startDrawing(_activeDuckDBLayerId, tool);
  } else {
    // Commit or cancel existing drawing before switching
    _showPendingDrawingDialog(
      onCommit: () async {
        await controller.commit();
        _interactionStateController.enterIdle();
        controller.startDrawing(_activeDuckDBLayerId, tool);
        _interactionStateController.enterDrawing(tool: tool.name);
      },
      onCancel: () {
        controller.cancel();
        _interactionStateController.enterIdle();
        controller.startDrawing(_activeDuckDBLayerId, tool);
        _interactionStateController.enterDrawing(tool: tool.name);
      },
    );
  }
}
```

### Query operation permissions

```dart
AgusCommandItem drawCommand({
  required agus_maps_flutter.AgusDrawTool tool,
  required String label,
  required IconData icon,
}) {
  final enabled = _duckDBLayerStore != null &&
      _interactionStateController.isOperationAllowed('draw');

  return AgusCommandItem(
    id: 'draw-${tool.name}',
    label: label,
    icon: icon,
    enabled: enabled,
    onSelected: () {
      if (!enabled) {
        final reason = _interactionStateController.disabledReason('draw');
        if (reason != null) {
          _showMessage(reason);
        }
        return;
      }
      _setDuckDBDrawTool(tool);
    },
  );
}
```

## Operation Permissions

The `AppInteractionState` class provides permission queries:

- `allowsNavigation` → `true` for idle, searching, switchingLayer modes.
- `allowsDrawing` → `true` only for idle mode.
- `allowsFeatureEdit` → `true` for idle and editingFeature modes.
- `allowsRouting` → `true` for idle, searching, and routing modes.
- `allowsMwmDownload` → `true` for idle, downloadingMwm, and searching modes.
- `allowsLayerSwitch` → `true` for idle and switchingLayer modes.
- `isEditing` → `true` for drawing and editingFeature modes (requires commit/cancel).

## Design System Notes

The state machine is implemented entirely in the example app and does not modify
the `agus_design` package. If a design-system-level change is needed (e.g.,
adding a `disabledReason` field to `AgusCommandItem`), it should be proposed
separately and implemented as a minimal, safe extension.

For now, disabled commands are guarded at the app level by checking
`_interactionStateController.isOperationAllowed(operation)` before executing the
command's `onSelected` callback.

## Testing

The state machine and command enablement logic are tested in:

- `example/test/features/interaction_state_controller_test.dart` — Unit tests for
  state transitions, permission queries, and disabled reasons.

Run tests with:

```bash
dart run melos run test --scope=agus_maps_flutter_example
```

## Future Enhancements

- Add `disabledReason` or `disabledTooltip` to `AgusCommandItem` in the design
  system for better UI feedback.
- Expand state machine to track sub-modes (e.g., drawing.vertex vs drawing.drag).
- Persist state across app restarts for workflows like routing or active downloads.
