part of '../../agus_maps_flutter.dart';

/// Default keymap definitions for each platform.
class AgusKeymapDefaults {
  const AgusKeymapDefaults._();

  /// Returns the default keymap entries for a given platform.
  static List<AgusKeymapEntry> forPlatform(AgusKeymapPlatform platform) {
    switch (platform) {
      case AgusKeymapPlatform.macos:
        return _macosDefaults;
      case AgusKeymapPlatform.windows:
        return _windowsDefaults;
      case AgusKeymapPlatform.linux:
        return _linuxDefaults;
      case AgusKeymapPlatform.android:
      case AgusKeymapPlatform.ios:
        return _mobileDefaults;
    }
  }

  static final List<AgusKeymapEntry> _macosDefaults = [
    // Command Bar - Cmd+K
    AgusKeymapEntry(
      command: AgusCommandId.openCommandBar,
      keybinding: const AgusKeybinding(key: 'k', meta: true),
    ),
    // Search - Cmd+F
    AgusKeymapEntry(
      command: AgusCommandId.openSearch,
      keybinding: const AgusKeybinding(key: 'f', meta: true),
    ),
    // Map Navigation
    AgusKeymapEntry(
      command: AgusCommandId.panUp,
      keybinding: const AgusKeybinding(key: 'arrowUp'),
    ),
    AgusKeymapEntry(
      command: AgusCommandId.panDown,
      keybinding: const AgusKeybinding(key: 'arrowDown'),
    ),
    AgusKeymapEntry(
      command: AgusCommandId.panLeft,
      keybinding: const AgusKeybinding(key: 'arrowLeft'),
    ),
    AgusKeymapEntry(
      command: AgusCommandId.panRight,
      keybinding: const AgusKeybinding(key: 'arrowRight'),
    ),
    AgusKeymapEntry(
      command: AgusCommandId.zoomIn,
      keybinding: const AgusKeybinding(key: '=', meta: true),
    ),
    AgusKeymapEntry(
      command: AgusCommandId.zoomOut,
      keybinding: const AgusKeybinding(key: '-', meta: true),
    ),
    AgusKeymapEntry(
      command: AgusCommandId.resetRotation,
      keybinding: const AgusKeybinding(key: 'r', meta: true),
    ),
    AgusKeymapEntry(
      command: AgusCommandId.toggleFullscreen,
      keybinding: const AgusKeybinding(key: 'f', meta: true, control: true),
    ),
    // Layer Management
    AgusKeymapEntry(
      command: AgusCommandId.toggleLayerPanel,
      keybinding: const AgusKeybinding(key: 'l', meta: true, shift: true),
    ),
    AgusKeymapEntry(
      command: AgusCommandId.newDrawingLayer,
      keybinding: const AgusKeybinding(key: 'n', meta: true, shift: true),
    ),
    // Editing - Standard macOS shortcuts
    AgusKeymapEntry(
      command: AgusCommandId.selectAll,
      keybinding: const AgusKeybinding(key: 'a', meta: true),
    ),
    AgusKeymapEntry(
      command: AgusCommandId.deselectAll,
      keybinding: const AgusKeybinding(key: 'a', meta: true, shift: true),
    ),
    AgusKeymapEntry(
      command: AgusCommandId.delete,
      keybinding: const AgusKeybinding(key: 'backspace'),
    ),
    AgusKeymapEntry(
      command: AgusCommandId.undo,
      keybinding: const AgusKeybinding(key: 'z', meta: true),
    ),
    AgusKeymapEntry(
      command: AgusCommandId.redo,
      keybinding: const AgusKeybinding(key: 'z', meta: true, shift: true),
    ),
    AgusKeymapEntry(
      command: AgusCommandId.copy,
      keybinding: const AgusKeybinding(key: 'c', meta: true),
    ),
    AgusKeymapEntry(
      command: AgusCommandId.cut,
      keybinding: const AgusKeybinding(key: 'x', meta: true),
    ),
    AgusKeymapEntry(
      command: AgusCommandId.paste,
      keybinding: const AgusKeybinding(key: 'v', meta: true),
    ),
    AgusKeymapEntry(
      command: AgusCommandId.duplicate,
      keybinding: const AgusKeybinding(key: 'd', meta: true),
    ),
    // Tools
    AgusKeymapEntry(
      command: AgusCommandId.selectTool,
      keybinding: const AgusKeybinding(key: 'v'),
    ),
    AgusKeymapEntry(
      command: AgusCommandId.panTool,
      keybinding: const AgusKeybinding(key: 'h'),
    ),
    AgusKeymapEntry(
      command: AgusCommandId.drawPointTool,
      keybinding: const AgusKeybinding(key: 'p'),
    ),
    AgusKeymapEntry(
      command: AgusCommandId.drawLineTool,
      keybinding: const AgusKeybinding(key: 'l'),
    ),
    AgusKeymapEntry(
      command: AgusCommandId.drawPolygonTool,
      keybinding: const AgusKeybinding(key: 'g'),
    ),
    // Application
    AgusKeymapEntry(
      command: AgusCommandId.showSettings,
      keybinding: const AgusKeybinding(key: ',', meta: true),
    ),
    AgusKeymapEntry(
      command: AgusCommandId.quit,
      keybinding: const AgusKeybinding(key: 'q', meta: true),
    ),
    AgusKeymapEntry(
      command: AgusCommandId.refresh,
      keybinding: const AgusKeybinding(key: 'r', meta: true, shift: true),
    ),
  ];

  static final List<AgusKeymapEntry> _windowsDefaults = [
    // Command Bar - Ctrl+K
    AgusKeymapEntry(
      command: AgusCommandId.openCommandBar,
      keybinding: const AgusKeybinding(key: 'k', control: true),
    ),
    // Search - Ctrl+F
    AgusKeymapEntry(
      command: AgusCommandId.openSearch,
      keybinding: const AgusKeybinding(key: 'f', control: true),
    ),
    // Map Navigation
    AgusKeymapEntry(
      command: AgusCommandId.panUp,
      keybinding: const AgusKeybinding(key: 'arrowUp'),
    ),
    AgusKeymapEntry(
      command: AgusCommandId.panDown,
      keybinding: const AgusKeybinding(key: 'arrowDown'),
    ),
    AgusKeymapEntry(
      command: AgusCommandId.panLeft,
      keybinding: const AgusKeybinding(key: 'arrowLeft'),
    ),
    AgusKeymapEntry(
      command: AgusCommandId.panRight,
      keybinding: const AgusKeybinding(key: 'arrowRight'),
    ),
    AgusKeymapEntry(
      command: AgusCommandId.zoomIn,
      keybinding: const AgusKeybinding(key: '=', control: true),
    ),
    AgusKeymapEntry(
      command: AgusCommandId.zoomOut,
      keybinding: const AgusKeybinding(key: '-', control: true),
    ),
    AgusKeymapEntry(
      command: AgusCommandId.resetRotation,
      keybinding: const AgusKeybinding(key: 'r', control: true),
    ),
    AgusKeymapEntry(
      command: AgusCommandId.toggleFullscreen,
      keybinding: const AgusKeybinding(key: 'f11'),
    ),
    // Layer Management
    AgusKeymapEntry(
      command: AgusCommandId.toggleLayerPanel,
      keybinding: const AgusKeybinding(key: 'l', control: true, shift: true),
    ),
    AgusKeymapEntry(
      command: AgusCommandId.newDrawingLayer,
      keybinding: const AgusKeybinding(key: 'n', control: true, shift: true),
    ),
    // Editing - Standard Windows shortcuts
    AgusKeymapEntry(
      command: AgusCommandId.selectAll,
      keybinding: const AgusKeybinding(key: 'a', control: true),
    ),
    AgusKeymapEntry(
      command: AgusCommandId.deselectAll,
      keybinding: const AgusKeybinding(key: 'a', control: true, shift: true),
    ),
    AgusKeymapEntry(
      command: AgusCommandId.delete,
      keybinding: const AgusKeybinding(key: 'delete'),
    ),
    AgusKeymapEntry(
      command: AgusCommandId.undo,
      keybinding: const AgusKeybinding(key: 'z', control: true),
    ),
    AgusKeymapEntry(
      command: AgusCommandId.redo,
      keybinding: const AgusKeybinding(key: 'y', control: true),
    ),
    AgusKeymapEntry(
      command: AgusCommandId.copy,
      keybinding: const AgusKeybinding(key: 'c', control: true),
    ),
    AgusKeymapEntry(
      command: AgusCommandId.cut,
      keybinding: const AgusKeybinding(key: 'x', control: true),
    ),
    AgusKeymapEntry(
      command: AgusCommandId.paste,
      keybinding: const AgusKeybinding(key: 'v', control: true),
    ),
    AgusKeymapEntry(
      command: AgusCommandId.duplicate,
      keybinding: const AgusKeybinding(key: 'd', control: true),
    ),
    // Tools
    AgusKeymapEntry(
      command: AgusCommandId.selectTool,
      keybinding: const AgusKeybinding(key: 'v'),
    ),
    AgusKeymapEntry(
      command: AgusCommandId.panTool,
      keybinding: const AgusKeybinding(key: 'h'),
    ),
    AgusKeymapEntry(
      command: AgusCommandId.drawPointTool,
      keybinding: const AgusKeybinding(key: 'p'),
    ),
    AgusKeymapEntry(
      command: AgusCommandId.drawLineTool,
      keybinding: const AgusKeybinding(key: 'l'),
    ),
    AgusKeymapEntry(
      command: AgusCommandId.drawPolygonTool,
      keybinding: const AgusKeybinding(key: 'g'),
    ),
    // Application
    AgusKeymapEntry(
      command: AgusCommandId.showSettings,
      keybinding: const AgusKeybinding(key: ',', control: true),
    ),
    AgusKeymapEntry(
      command: AgusCommandId.quit,
      keybinding: const AgusKeybinding(key: 'f4', alt: true),
    ),
    AgusKeymapEntry(
      command: AgusCommandId.refresh,
      keybinding: const AgusKeybinding(key: 'f5'),
    ),
  ];

  static final List<AgusKeymapEntry> _linuxDefaults = [
    // Same as Windows but with some Linux-specific adjustments
    ..._windowsDefaults,
  ];

  static final List<AgusKeymapEntry> _mobileDefaults = [
    // Mobile platforms typically use on-screen controls
    // These are backup keybindings for external keyboards
    AgusKeymapEntry(
      command: AgusCommandId.openSearch,
      keybinding: const AgusKeybinding(key: 'f', meta: true),
    ),
    AgusKeymapEntry(
      command: AgusCommandId.zoomIn,
      keybinding: const AgusKeybinding(key: '=', meta: true),
    ),
    AgusKeymapEntry(
      command: AgusCommandId.zoomOut,
      keybinding: const AgusKeybinding(key: '-', meta: true),
    ),
  ];
}
