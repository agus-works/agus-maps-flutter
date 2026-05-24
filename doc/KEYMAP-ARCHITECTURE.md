# Keymap Architecture

This document describes the keyboard shortcut system for Agus Maps Flutter.

## Overview

The keymap architecture provides:

- **Platform-specific defaults**: Native shortcuts for macOS, Windows, Linux, Android, and iOS
- **User customization**: Override any default shortcut via persistent storage
- **Conflict detection**: Identify and report conflicting keybindings
- **Command registry**: Centralized command IDs with human-readable labels
- **JSON schema**: Validated keymap definitions for import/export

## Architecture Components

### 1. Command IDs (`AgusCommandId`)

Central registry of all application commands. Each command has:
- Unique dot-notation identifier (e.g., `map.zoom.in`)
- Display name for UI presentation
- Description for tooltips and help

**Command Categories:**
- **Map Navigation**: pan, zoom, rotation, fullscreen
- **Search & Command Bar**: open search, open command bar
- **Layer Management**: toggle panel, new layer, toggle visibility
- **Selection & Editing**: select, delete, undo, redo, copy, paste
- **Tool Selection**: select tool, pan tool, drawing tools
- **Application**: settings, about, quit, refresh

### 2. Keybinding Models (`AgusKeybinding`, `AgusKeymapEntry`)

**AgusKeybinding** represents a keyboard shortcut:
```dart
const AgusKeybinding(
  key: 'k',        // Primary key
  meta: true,      // Cmd on macOS, Win on Windows
  control: false,  // Ctrl modifier
  shift: false,    // Shift modifier
  alt: false,      // Alt/Option modifier
)
```

**Platform-aware labels:**
- macOS: `⌘K` (uses symbols)
- Windows/Linux: `Ctrl+K` (uses text)

**Conflict detection:**
- Each keybinding generates a unique conflict key
- Used to detect multiple commands bound to the same shortcut

### 3. Platform Defaults (`AgusKeymapDefaults`)

Provides sensible defaults for each platform:

**macOS defaults:**
- Cmd+K: Open command bar
- Cmd+F: Open search
- Cmd+Z: Undo
- Cmd+Shift+Z: Redo
- Cmd+=: Zoom in
- Cmd+-: Zoom out

**Windows/Linux defaults:**
- Ctrl+K: Open command bar
- Ctrl+F: Open search
- Ctrl+Z: Undo
- Ctrl+Y: Redo (Windows convention)
- Ctrl+=: Zoom in
- Ctrl+-: Zoom out
- F11: Toggle fullscreen

**Mobile defaults:**
- Minimal defaults for external keyboard support
- Primary interaction is touch-based

### 4. Keymap Resolver (`AgusKeymapResolver`)

Manages keymap resolution and persistence:

**Key responsibilities:**
- Merge default and user-override keymaps
- Load/save overrides via DuckDB
- Detect and report conflicts
- Export/import keymaps as JSON
- Initialize defaults on first run

**Usage example:**
```dart
final resolver = AgusKeymapResolver(
  store: duckdbStore,
  platform: AgusKeymapPlatform.current,
);

// Initialize defaults
await resolver.initializeDefaults();

// Get resolved keymap
final keymap = await resolver.resolveKeymap();

// Override a keybinding
await resolver.saveOverride(
  command: AgusCommandId.openCommandBar,
  keybinding: const AgusKeybinding(key: 'p', meta: true, shift: true),
);

// Detect conflicts
final conflicts = await resolver.detectConflicts();
for (final conflict in conflicts) {
  print(conflict.describe(AgusKeymapPlatform.current));
}
```

## Database Schema

Keymaps are persisted in `agus.keymap_settings`:

```sql
CREATE TABLE agus.keymap_settings (
  setting_id TEXT PRIMARY KEY,
  platform TEXT NOT NULL,
  command TEXT NOT NULL,
  keybinding_payload JSON NOT NULL,
  is_override BOOLEAN NOT NULL DEFAULT FALSE,
  display_name TEXT,
  description TEXT,
  validation_schema_version INTEGER NOT NULL DEFAULT 1,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

**Field semantics:**
- `setting_id`: Unique identifier (typically `{platform}_{command}`)
- `platform`: Target platform (`macos`, `windows`, `linux`, `android`, `ios`)
- `command`: Command identifier from `AgusCommandId`
- `keybinding_payload`: JSON object with `key`, `control`, `shift`, `alt`, `meta` fields
- `is_override`: `true` for user customizations, `false` for defaults
- `validation_schema_version`: Schema version for migration compatibility

## JSON Schema

Keymaps can be exported and imported as JSON following `doc/schemas/keymap.schema.json`:

**Example:**
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
    },
    {
      "command": "map.zoom.in",
      "keybinding": {
        "key": "=",
        "meta": true
      }
    }
  ]
}
```

## Conflict Detection

Conflicts occur when multiple commands share the same keybinding.

**Detection algorithm:**
1. Build a map of keybindings to commands
2. Identify keybindings with multiple commands
3. Create `AgusKeymapConflict` records with:
   - Conflicting keybinding
   - Both command IDs
   - Source of each binding (default vs. override)

**Conflict resolution:**
- User overrides always take precedence
- Conflicts between defaults should be fixed in code
- Conflicts involving overrides should be reported to the user

**Example conflict report:**
```
⌘K is bound to both "commandbar.open" (default) and "layer.toggle.panel" (override)
```

## Editing Keymaps

### Via UI (Future)

A settings panel will allow users to:
1. Browse all commands and current bindings
2. Click a keybinding to edit
3. Press a new key combination
4. See immediate conflict warnings
5. Save or cancel the change

### Via JSON Import/Export

Users can:
1. Export current keymaps: `resolver.exportToJson()`
2. Edit JSON in external editor
3. Import modified keymaps: `resolver.importFromJson(json)`
4. Validate against `doc/schemas/keymap.schema.json`

### Via Direct API

Programmatic access:
```dart
// Override a single keybinding
await resolver.saveOverride(
  command: 'map.zoom.in',
  keybinding: const AgusKeybinding(key: '+', meta: true),
);

// Remove an override (restore default)
await resolver.removeOverride('map.zoom.in');
```

## Integration with Flutter Shortcuts/Actions

The keymap system integrates with Flutter's `Shortcuts` and `Actions` widgets.

**Example wiring (future implementation):**

```dart
class KeymapShortcuts extends StatefulWidget {
  final Widget child;
  final AgusKeymapResolver resolver;

  const KeymapShortcuts({
    required this.child,
    required this.resolver,
  });

  @override
  State<KeymapShortcuts> createState() => _KeymapShortcutsState();
}

class _KeymapShortcutsState extends State<KeymapShortcuts> {
  Map<String, AgusKeybinding>? _keymap;

  @override
  void initState() {
    super.initState();
    _loadKeymap();
  }

  Future<void> _loadKeymap() async {
    final keymap = await widget.resolver.resolveKeymap();
    setState(() => _keymap = keymap);
  }

  @override
  Widget build(BuildContext context) {
    if (_keymap == null) return widget.child;

    // Convert AgusKeybinding to Flutter ShortcutActivator
    final shortcuts = <ShortcutActivator, Intent>{};
    for (final entry in _keymap!.entries) {
      final binding = entry.value;
      final activator = _toShortcutActivator(binding);
      final intent = _commandToIntent(entry.key);
      shortcuts[activator] = intent;
    }

    return Shortcuts(
      shortcuts: shortcuts,
      child: Actions(
        actions: _buildActions(),
        child: widget.child,
      ),
    );
  }

  ShortcutActivator _toShortcutActivator(AgusKeybinding binding) {
    return SingleActivator(
      _parseLogicalKey(binding.key),
      control: binding.control,
      shift: binding.shift,
      alt: binding.alt,
      meta: binding.meta,
    );
  }

  LogicalKeyboardKey _parseLogicalKey(String key) {
    // Map string keys to Flutter LogicalKeyboardKey
    // ...
  }

  Intent _commandToIntent(String command) {
    // Map command IDs to Intent subclasses
    // ...
  }

  Map<Type, Action<Intent>> _buildActions() {
    // Map Intent types to Action implementations
    // ...
  }
}
```

## Command Bar Integration

The command bar displays shortcut labels next to commands:

```dart
final label = await resolver.getKeybindingLabel(AgusCommandId.openSearch);
// Returns: "⌘F" on macOS, "Ctrl+F" on Windows/Linux

ListTile(
  title: Text('Open Search'),
  trailing: Text(label ?? ''),
  onTap: () => executeCommand(AgusCommandId.openSearch),
)
```

## Platform Conventions

The keymap system respects platform conventions:

### macOS
- Primary modifier: `⌘ Command`
- Undo: `⌘Z`, Redo: `⌘⇧Z`
- Quit: `⌘Q`
- Settings: `⌘,`
- Find/Search: `⌘F`
- Symbols in labels: `⌘⇧K`

The example macOS app also exposes these through the native platform menu. The
`Agus Suite` app menu uses platform-provided About, Services, Hide, Show All,
and Quit items, so `Cmd+Q` terminates through AppKit instead of a custom Dart
exit handler. The `Edit > Find` item opens the map search flow, and
`Agus Suite > Settings...` opens the settings dialog.

### Windows
- Primary modifier: `Ctrl`
- Undo: `Ctrl+Z`, Redo: `Ctrl+Y`
- Quit: `Alt+F4`
- Fullscreen: `F11`
- Text labels: `Ctrl+Shift+K`

### Linux
- Similar to Windows with minor variations
- Window managers may intercept some shortcuts

### Mobile (Android/iOS)
- External keyboard support only
- Minimal defaults (most interaction is touch-based)

## Avoiding OS Shortcut Conflicts

The defaults avoid common OS-level shortcuts:

**Avoided on all platforms:**
- `Ctrl/Cmd+C/V/X` (copy/paste/cut) - used for editing
- `Ctrl/Cmd+A` (select all) - used for feature selection
- `Ctrl/Cmd+Z/Y` (undo/redo) - used for editing
- `Ctrl/Cmd+Tab` (window switching) - reserved by OS
- `Ctrl/Cmd+W` (close window) - reserved by OS

**Avoided on macOS:**
- `⌘H` (hide window) - OS reserved
- `⌘M` (minimize) - OS reserved
- `⌘Space` (Spotlight) - OS reserved

**Avoided on Windows:**
- `Win+D` (show desktop) - OS reserved
- `Win+L` (lock screen) - OS reserved
- `Alt+Tab` (task switcher) - OS reserved

## Testing

See `test/keymap_test.dart` for comprehensive tests covering:

- Keybinding parsing and serialization
- Platform-specific label formatting
- Conflict detection algorithm
- Default keymap validation
- Override persistence
- JSON import/export
- Conflict key generation

## Future Enhancements

1. **Context-aware keybindings**: Support `when` clause evaluation
2. **Chord sequences**: Multi-step shortcuts (e.g., `Ctrl+K Ctrl+S`)
3. **Keymap themes**: Predefined keymap sets (VSCode-like, Vim-like, etc.)
4. **Visual conflict resolution UI**: Guided conflict resolution workflow
5. **Shortcut recording**: Press keys to capture binding interactively
6. **Global vs. local scope**: Different keymaps for different app contexts

## References

- JSON Schema: `doc/schemas/keymap.schema.json`
- Command IDs: `lib/src/keymap/keymap_commands.dart`
- Platform Defaults: `lib/src/keymap/keymap_defaults.dart`
- Resolver API: `lib/src/keymap/keymap_resolver.dart`
- Database Schema: `agus.keymap_settings` table
