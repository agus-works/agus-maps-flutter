# User Story: Reusable Agus Design Components and Widgetbook Coverage

## As a UI developer
I want a comprehensive design system with reusable components and interactive documentation, so that I can build consistent, high-quality UIs without reinventing primitives.

## Background
Map applications require many specialized UI components: command bars, status bars, notifications, layer panels, property editors, drawing toolbars, etc. Without a shared design system, teams duplicate code, create inconsistent UIs, and waste time on one-off implementations. A design system with interactive Widgetbook coverage provides:
- Single source of truth for visual primitives
- Component reuse across plugin and examples
- Interactive component states for design review
- Fast iteration without rebuilding full app

## Acceptance Criteria

### Design System Package
- ✅ **Package**: `packages/agus_design`
- ✅ **Isolation**: No dependencies on `agus_maps_flutter`, DuckDB, CoMaps, native binaries, or map assets
- ✅ **Scope**: Reusable Flutter UI components, tokens, themes, layouts
- ✅ **Export**: `package:agus_design/agus_design.dart` as public API

### Core Design Components
- ✅ **Workbench Layouts**:
  - `VSCodeWorkbench`: VS Code-style layout with title bar, sidebar, editor area, panels, status bar
  - Configurable activity bar, side bar, editor tabs, panel sections
- ✅ **Command System**:
  - `AgusCommandCenter`: Command bar with fuzzy filtering, keyboard navigation, highlighted matches
  - `AgusCommandItem`: Command data model with label, icon, keywords, enabled state, onSelected callback
  - `AgusCommandGroup`: Command grouping with labels
  - `AgusCommandAsyncProvider`: Async command feeds (e.g., native search results, MWM maps)
- ✅ **Status Bar**:
  - `AgusStatusBar`: Bottom status bar with left/center/right sections
  - `AgusStatusBarItem`: Clickable status items with icons, labels, tooltips
  - `MapTelemetryStatusBarBuilder`: Map-specific telemetry items (zoom, bearing, coordinates)
  - Copy-to-clipboard support with double-click/long-press gestures
- ✅ **Notifications**:
  - `AgusNotificationManager`: Centralized notification controller
  - `AgusNotificationToast`: VS Code-style toast notifications with auto-dismiss
- ✅ **Layer UI**:
  - `DuckDBLayerDrawController`: Drawing state machine (exported from plugin, not design package)
  - `DuckDBLayerDrawToolbar`: Icon controls for draw tools, undo, commit, cancel
  - `DuckDBLayerMetadataForm`: Title/note capture for features
  - `DuckDBLayerPanel`: Visibility and z-order controls for layers
- ✅ **Theme System**:
  - `AgusThemeData`: Theme tokens for colors, dimensions, typography
  - Dark/light mode support
  - Extension methods for theme access

### Widgetbook Integration
- ✅ **Location**: `widgetbook/` at repository root
- ✅ **Scope**: Catalogs `packages/agus_design` components only
- ✅ **Isolation**: No `agus_maps_flutter`, DuckDB, CoMaps, or native dependencies
- ✅ **Use Cases**: `widgetbook/lib/use_cases/` for component states
- ✅ **Generation**: `widgetbook/lib/main.directories.g.dart` auto-generated
- ✅ **Platform**: Runs on Chrome (web) for fast iteration

### Widgetbook Workflow
1. Add/update components in `packages/agus_design/lib`
2. Add Widgetbook use cases under `widgetbook/lib/use_cases`
3. Regenerate directories: `dart run melos run generate --no-select`
4. Run Widgetbook: `dart run melos run widgetbook --no-select`
5. Inspect component states in browser
6. Commit regenerated `widgetbook/lib/main.directories.g.dart`

### Melos Scripts
- ✅ `dart run melos run design:analyze`: Fast analysis of `agus_design` package
- ✅ `dart run melos run design:test`: Fast tests of `agus_design` package
- ✅ `dart run melos run widgetbook`: Run Widgetbook catalog on Chrome
- ✅ `dart run melos run generate`: Regenerate Widgetbook directories

### Component Coverage
- ✅ Command bar: Multiple states (empty, filtered, selected, disabled commands)
- ✅ Status bar: Telemetry items, clipboard gestures, notifications
- ✅ Notifications: Success, error, info, warning toasts
- ✅ Workbench layouts: Activity bar, sidebar, editor tabs, panels
- ✅ Drawing toolbar: Tool selection, undo, commit, cancel states
- ✅ Layer panel: Visibility toggles, z-order controls, backup actions
- ✅ Metadata form: Title/note inputs, validation states

### Design Tokens
- ✅ Colors: Primary, accent, background, surface, error, success, text, borders
- ✅ Dimensions: Spacing, border radius, icon sizes, font sizes
- ✅ Typography: Font families, weights, sizes, line heights
- ✅ Shadows: Elevation levels for overlays, dialogs, panels

### Testing
- ✅ Component tests: `packages/agus_design/test/components/`
- ✅ Example: `agus_status_bar_telemetry_test.dart` (15 tests)
- ✅ Analysis: No issues in design package
- ✅ Fast iteration: Tests run in <5s, analysis in <3s

### Documentation
- ✅ Widgetbook quick guide: `doc/WIDGETBOOK.md`
- ✅ Status telemetry: `IMPLEMENTATION_STATUS_TELEMETRY.md`
- ✅ Command bar: `doc/COMMAND-BAR.md`
- ✅ Package README: `packages/agus_design/README.md`

## Implementation References

### Package Structure
```
packages/agus_design/
├── lib/
│   ├── agus_design.dart           # Public API export
│   ├── src/
│   │   ├── components/            # Reusable components
│   │   │   ├── agus_command_center.dart
│   │   │   ├── agus_status_bar.dart
│   │   │   ├── agus_status_bar_telemetry.dart
│   │   │   ├── agus_notification_manager.dart
│   │   │   └── ...
│   │   ├── theme/                 # Theme tokens
│   │   ├── layouts/               # Layout primitives
│   │   └── ...
├── test/                          # Component tests
├── example/                       # Package-level examples
└── pubspec.yaml
```

### Widgetbook Structure
```
widgetbook/
├── lib/
│   ├── main.dart                  # Widgetbook app entry
│   ├── main.directories.g.dart    # Auto-generated directories
│   └── use_cases/                 # Component use cases
│       ├── command_center_use_cases.dart
│       ├── status_bar_use_cases.dart
│       └── ...
└── pubspec.yaml
```

### Key Dependencies
- `agus_design`: Only Flutter SDK + minimal pub.dev packages
- `widgetbook`: Only `agus_design` + `widgetbook` package
- No native binaries, no DuckDB, no CoMaps

## Testing Approach
- Unit tests: `dart run melos run design:test`
- Analysis: `dart run melos run design:analyze`
- Widgetbook: `dart run melos run widgetbook`, manual inspection
- Visual regression: Future enhancement with screenshot comparison

## Usage Example

Consuming app imports design system:
```dart
import 'package:agus_design/agus_design.dart';

// Use theme
final theme = AgusThemeData.dark();

// Use command bar
AgusCommandCenter(
  commands: [
    AgusCommandGroup(
      label: 'Navigation',
      commands: [
        AgusCommandItem(
          id: 'search',
          label: 'Search Map',
          icon: Icons.search,
          keywords: ['find', 'locate'],
          enabled: true,
          onSelected: () => _openSearch(),
        ),
      ],
    ),
  ],
)

// Use status bar
AgusStatusBar(
  leftItems: [...],
  rightItems: _buildMapTelemetryItems(),
)
```

## Benefits
- ✅ **Consistency**: Single source of truth for visual primitives
- ✅ **Reusability**: Components used across plugin, examples, external apps
- ✅ **Speed**: Fast iteration with Widgetbook, no full app rebuild
- ✅ **Quality**: Comprehensive tests, static analysis, design review
- ✅ **Isolation**: Design system stays independent of map/native concerns

## Future Enhancements
1. **Visual regression testing**: Screenshot comparison in CI
2. **Accessibility audit**: WCAG 2.1 compliance checks
3. **Theme builder**: Interactive theme customization tool
4. **Component variants**: More size/style/state options
5. **Animation library**: Shared motion design primitives
6. **Icon library**: Custom icon set with SVG sources

## Related Features
- Status telemetry copy with notifications
- Command-driven drawing and interaction state safety
- Editable/platform keymaps
- Layer/feature focus centers and active selection
