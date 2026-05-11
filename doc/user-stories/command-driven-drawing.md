# User Story: Command-Driven Drawing and Interaction State Safety

## As a map editor
I want drawing and editing operations to be safely coordinated through commands, so that I never lose work or enter conflicting states.

## Background
Complex map applications support many interaction modes: browsing, searching, drawing, editing, routing, downloading. Without explicit state management, users can accidentally start conflicting operations (e.g., drawing while editing, routing while drawing), lose uncommitted work, or trigger undefined behavior.

## Acceptance Criteria

### Explicit State Transitions
- ✅ Central `AppInteractionStateController` tracks current mode
- ✅ Supported modes:
  - `idle`: Default navigation and browsing
  - `searching`: Search bar focused or results visible
  - `drawing`: Drawing a new feature (point/line/segment/polygon)
  - `editingFeature`: Editing existing feature geometry
  - `routing`: Route planning or active navigation
  - `downloadingMwm`: Downloading/updating MWM maps
  - `switchingLayer`: Switching or focusing on a layer
  - `modalInput`: Modal dialog or command input active

### Command Enablement Guards
- ✅ Drawing commands disabled during search, routing, or downloads
- ✅ Edit commands disabled during drawing
- ✅ New drawing commands disabled when another drawing is in progress
- ✅ Command bar queries `isOperationAllowed(operation)` before enabling commands
- ✅ Disabled commands show human-readable reason via `disabledReason(operation)`

### State-Aware Command Bar
- ✅ Command items derive `enabled` state from interaction controller
- ✅ Attempting disabled command shows tooltip or alert with reason
- ✅ Example: "A drawing or feature edit is in progress. Commit or cancel it before starting a new drawing."

### Drawing/Editing Workflow
- ✅ Drawing command: Checks if allowed, enters `drawing` mode, starts tool
- ✅ Commit drawing: Persists feature, exits to `idle`
- ✅ Cancel drawing: Discards changes, exits to `idle`
- ✅ Switch tool during drawing: Prompts to commit or cancel first
- ✅ Feature edit: Enters `editingFeature` mode, loads geometry
- ✅ Commit edit: Updates feature, exits to `idle`

### Keyboard Flow Preservation
- ✅ State machine does not interfere with keyboard shortcuts
- ✅ Command bar arrow navigation works regardless of interaction mode
- ✅ Enter selection and Escape cancellation preserved
- ✅ Modal dialogs use `modalInput` mode for informational tracking only

### Design System Separation
- ✅ State machine lives in example app, not `agus_design` package
- ✅ Commands query app-level controller for enablement
- ✅ No invasive changes to core design components

## Implementation References

### State Controller
- Class: `AppInteractionStateController` (example app)
- Extends: `ChangeNotifier`
- Methods:
  - `enterIdle()`, `enterDrawing()`, `enterEditingFeature()`, etc.
  - `isOperationAllowed(operation)`
  - `disabledReason(operation)`

### Interaction Modes
- Enum: `AppInteractionMode`
- Modes: `idle`, `searching`, `drawing`, `editingFeature`, `routing`, `downloadingMwm`, `switchingLayer`, `modalInput`

### Permission Queries
- `allowsNavigation`: True for idle, searching, switchingLayer
- `allowsDrawing`: True only for idle
- `allowsFeatureEdit`: True for idle and editingFeature
- `allowsRouting`: True for idle, searching, routing
- `allowsMwmDownload`: True for idle, downloadingMwm, searching
- `allowsLayerSwitch`: True for idle and switchingLayer
- `isEditing`: True for drawing and editingFeature (requires commit/cancel)

### Command Integration Example
```dart
AgusCommandItem(
  id: 'draw-polygon',
  label: 'Draw Polygon Feature',
  icon: Icons.polyline_outlined,
  enabled: _interactionStateController.isOperationAllowed('draw'),
  onSelected: () {
    if (!enabled) {
      _showMessage(_interactionStateController.disabledReason('draw'));
      return;
    }
    _interactionStateController.enterDrawing(tool: 'polygon');
    _setDuckDBDrawTool(AgusDrawTool.polygon);
  },
)
```

## Testing Approach
- Unit tests: `example/test/features/interaction_state_controller_test.dart`
- Test coverage:
  - State transitions
  - Permission queries
  - Disabled reason messages
  - Conflict detection
- Manual: Attempt to draw while editing, verify guard message
- Manual: Start drawing, switch tool, verify commit/cancel prompt

## Documentation
- Architecture: `doc/INTERACTION-STATE-MACHINE.md`
- Command bar: `doc/COMMAND-BAR.md`
- Drawing controller: `lib/src/layers/duckdb_draw_controller.dart`

## Related Features
- Layer/feature focus centers and active selection
- Reusable Agus design components
- Editable/platform keymaps
