# User Story: Editable and Platform-Aware Keymaps

## As a power user
I want to customize keyboard shortcuts for all commands, so that I can match my preferred workflow and muscle memory.

## Background
Different users have different keyboard habits from VSCode, Vim, IDEs, or other tools. Fixed shortcuts frustrate users who expect different conventions. Platform-specific defaults (Cmd on macOS, Ctrl on Windows) are essential for native feel, but users must be able to override any default.

## Acceptance Criteria

### Platform-Specific Defaults
- ✅ **macOS defaults**:
  - Cmd+K: Open command bar
  - Cmd+F: Open search
  - Cmd+Z: Undo, Cmd+Shift+Z: Redo
  - Cmd+=: Zoom in, Cmd+-: Zoom out
  - Cmd+Q: Quit, Cmd+,: Settings
- ✅ **Windows/Linux defaults**:
  - Ctrl+K: Open command bar
  - Ctrl+F: Open search
  - Ctrl+Z: Undo, Ctrl+Y: Redo (Windows convention)
  - Ctrl+=: Zoom in, Ctrl+-: Zoom out
  - F11: Toggle fullscreen
  - Alt+F4: Quit (Windows)
- ✅ **Mobile defaults**:
  - Minimal defaults for external keyboard support
  - Touch interaction remains primary

### Command Registry
- ✅ Central `AgusCommandId` enum with dot-notation identifiers
  - Example: `map.zoom.in`, `commandbar.open`, `layer.toggle.panel`
- ✅ Each command has:
  - Unique identifier
  - Display name for UI
  - Description for tooltips and help

### Command Categories
- ✅ Map Navigation: pan, zoom, rotation, fullscreen
- ✅ Search & Command Bar: open search, open command bar
- ✅ Layer Management: toggle panel, new layer, toggle visibility
- ✅ Selection & Editing: select, delete, undo, redo, copy, paste
- ✅ Tool Selection: select tool, pan tool, drawing tools
- ✅ Application: settings, about, quit, refresh

### Keybinding Model
- ✅ `AgusKeybinding` represents a keyboard shortcut:
  - `key`: Primary key (e.g., 'k', 'arrowUp', 'escape')
  - `control`: Ctrl modifier (boolean)
  - `shift`: Shift modifier (boolean)
  - `alt`: Alt/Option modifier (boolean)
  - `meta`: Cmd on macOS, Win on Windows (boolean)
- ✅ Platform-aware labels:
  - macOS: `⌘K` (uses symbols)
  - Windows/Linux: `Ctrl+K` (uses text)

### Keymap Resolver
- ✅ `AgusKeymapResolver` manages keymap resolution and persistence
- ✅ Responsibilities:
  - Merge default and user-override keymaps
  - Load/save overrides via DuckDB
  - Detect and report conflicts
  - Export/import keymaps as JSON
  - Initialize defaults on first run

### Database Persistence
- ✅ Keymaps stored in `agus.keymap_settings` table
- ✅ Schema:
  - `setting_id`: Unique identifier (e.g., `macos_commandbar.open`)
  - `platform`: Target platform (`macos`, `windows`, `linux`, `android`, `ios`)
  - `command`: Command identifier
  - `keybinding_payload`: JSON with key, control, shift, alt, meta
  - `is_override`: True for user customizations, false for defaults
  - `display_name`, `description`: Optional human-readable metadata
  - `validation_schema_version`: Schema version for migrations

### Conflict Detection
- ✅ Conflicts occur when multiple commands share the same keybinding
- ✅ Detection algorithm:
  1. Build map of keybindings to commands
  2. Identify keybindings with multiple commands
  3. Create `AgusKeymapConflict` records
- ✅ Conflict resolution:
  - User overrides take precedence
  - Conflicts between defaults fixed in code
  - Conflicts involving overrides reported to user
- ✅ Example conflict report:
  - `⌘K is bound to both "commandbar.open" (default) and "layer.toggle.panel" (override)`

### JSON Import/Export
- ✅ Keymaps can be exported as JSON following `doc/schemas/keymap.schema.json`
- ✅ Example JSON:
```json
{
  "version": 1,
  "platform": "macos",
  "keybindings": [
    {
      "command": "commandbar.open",
      "keybinding": {
        "key": "k",
        "meta": true
      }
    }
  ]
}
```
- ✅ Users can:
  1. Export current keymaps: `resolver.exportToJson()`
  2. Edit JSON in external editor
  3. Import modified keymaps: `resolver.importFromJson(json)`
  4. Validate against schema

### Programmatic API
- ✅ `resolver.saveOverride(command, keybinding)`: Override a single keybinding
- ✅ `resolver.removeOverride(command)`: Restore default
- ✅ `resolver.resolveKeymap()`: Get merged keymap (defaults + overrides)
- ✅ `resolver.detectConflicts()`: Find conflicting keybindings
- ✅ `resolver.initializeDefaults()`: Initialize defaults on first run

### OS Shortcut Avoidance
- ✅ Defaults avoid common OS-level shortcuts:
  - Ctrl/Cmd+C/V/X (copy/paste/cut)
  - Ctrl/Cmd+A (select all)
  - Ctrl/Cmd+Tab (window switching)
  - Ctrl/Cmd+W (close window)
  - macOS: ⌘H (hide), ⌘M (minimize), ⌘Space (Spotlight)
  - Windows: Win+D (show desktop), Win+L (lock), Alt+Tab (task switcher)

### Command Bar Integration
- ✅ Command bar displays shortcut labels next to commands
- ✅ Example: `getKeybindingLabel(AgusCommandId.openSearch)` → `"⌘F"` (macOS) or `"Ctrl+F"` (Windows)
- ✅ Labels update when keymaps change

## Implementation References

### Components
- **Command IDs**: `lib/src/keymap/keymap_commands.dart`
- **Keybinding Models**: `lib/src/keymap/keymap_models.dart`
  - `AgusKeybinding`, `AgusKeymapEntry`, `AgusKeymapConflict`
- **Platform Defaults**: `lib/src/keymap/keymap_defaults.dart`
  - `AgusKeymapDefaults`, `AgusKeymapPlatform`
- **Resolver API**: `lib/src/keymap/keymap_resolver.dart`
  - `AgusKeymapResolver`

### Database Schema
- Table: `agus.keymap_settings`
- Columns: `setting_id`, `platform`, `command`, `keybinding_payload`, `is_override`, `display_name`, `description`, `validation_schema_version`, `created_at`, `updated_at`
- Schema: `doc/schemas/README.md`

### JSON Schema
- Schema: `doc/schemas/keymap.schema.json`
- Validates: version, platform, keybindings array, command IDs, keybinding structure

## Testing Approach
- Unit tests: `test/keymap_test.dart`
- Test coverage:
  - Keybinding parsing and serialization
  - Platform-specific label formatting
  - Conflict detection algorithm
  - Default keymap validation
  - Override persistence
  - JSON import/export
  - Conflict key generation
- Manual: Override a keybinding, verify command bar label updates
- Manual: Create conflict, verify detection and reporting
- Manual: Export/import keymaps, verify round-trip consistency

## Documentation
- Architecture: `doc/KEYMAP-ARCHITECTURE.md`
- JSON schema: `doc/schemas/keymap.schema.json`
- Database schema: `doc/schemas/README.md`
- Command bar integration: `doc/COMMAND-BAR.md`

## Future Enhancements
1. **Context-aware keybindings**: Support `when` clause evaluation
2. **Chord sequences**: Multi-step shortcuts (e.g., `Ctrl+K Ctrl+S`)
3. **Keymap themes**: Predefined sets (VSCode-like, Vim-like, etc.)
4. **Visual conflict resolution UI**: Guided workflow
5. **Shortcut recording**: Press keys to capture binding interactively
6. **Global vs. local scope**: Different keymaps for different app contexts

## Related Features
- Command-driven drawing and interaction state safety
- Reusable Agus design components
- Status telemetry copy with notifications
