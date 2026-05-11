part of '../../agus_maps_flutter.dart';

/// A keybinding configuration for a command.
class AgusKeybinding {
  /// Creates a keybinding.
  const AgusKeybinding({
    required this.key,
    this.control = false,
    this.shift = false,
    this.alt = false,
    this.meta = false,
  });

  /// Creates a keybinding from a JSON payload.
  factory AgusKeybinding.fromJson(Map<String, Object?> json) {
    return AgusKeybinding(
      key: json['key'] as String,
      control: json['control'] as bool? ?? false,
      shift: json['shift'] as bool? ?? false,
      alt: json['alt'] as bool? ?? false,
      meta: json['meta'] as bool? ?? false,
    );
  }

  /// The primary key (e.g., 'k', 'arrowUp', 'f1').
  final String key;

  /// Whether Control (Ctrl) is pressed.
  final bool control;

  /// Whether Shift is pressed.
  final bool shift;

  /// Whether Alt (Option on macOS) is pressed.
  final bool alt;

  /// Whether Meta (Cmd on macOS, Win on Windows) is pressed.
  final bool meta;

  /// Converts this keybinding to JSON.
  Map<String, Object?> toJson() {
    return {
      'key': key,
      if (control) 'control': true,
      if (shift) 'shift': true,
      if (alt) 'alt': true,
      if (meta) 'meta': true,
    };
  }

  /// Returns a human-readable label for this keybinding.
  String toLabel({required AgusKeymapPlatform platform}) {
    final parts = <String>[];

    switch (platform) {
      case AgusKeymapPlatform.macos:
        if (control) parts.add('⌃');
        if (alt) parts.add('⌥');
        if (shift) parts.add('⇧');
        if (meta) parts.add('⌘');
      case AgusKeymapPlatform.windows:
      case AgusKeymapPlatform.linux:
        if (control) parts.add('Ctrl');
        if (alt) parts.add('Alt');
        if (shift) parts.add('Shift');
        if (meta) parts.add('Win');
      case AgusKeymapPlatform.android:
      case AgusKeymapPlatform.ios:
        if (control) parts.add('Ctrl');
        if (alt) parts.add('Alt');
        if (shift) parts.add('Shift');
        if (meta) parts.add('Cmd');
    }

    parts.add(_formatKey(key));
    return parts.join(platform == AgusKeymapPlatform.macos ? '' : '+');
  }

  String _formatKey(String key) {
    // Special key formatting
    final specialKeys = {
      'arrowup': '↑',
      'arrowdown': '↓',
      'arrowleft': '←',
      'arrowright': '→',
      'enter': '↵',
      'escape': 'Esc',
      'backspace': '⌫',
      'delete': 'Del',
      'tab': '⇥',
      'space': 'Space',
    };

    final lowerKey = key.toLowerCase();
    return specialKeys[lowerKey] ?? key.toUpperCase();
  }

  /// Creates a unique identifier for conflict detection.
  String toConflictKey() {
    final modifiers = <String>[];
    if (control) modifiers.add('ctrl');
    if (shift) modifiers.add('shift');
    if (alt) modifiers.add('alt');
    if (meta) modifiers.add('meta');
    modifiers.sort();
    return '${modifiers.join('+')}_$key'.toLowerCase();
  }

  @override
  bool operator ==(Object other) {
    return other is AgusKeybinding &&
        other.key == key &&
        other.control == control &&
        other.shift == shift &&
        other.alt == alt &&
        other.meta == meta;
  }

  @override
  int get hashCode => Object.hash(key, control, shift, alt, meta);
}

/// Platform identifiers for keymap resolution.
enum AgusKeymapPlatform {
  /// macOS platform.
  macos('macos'),

  /// Windows platform.
  windows('windows'),

  /// Linux platform.
  linux('linux'),

  /// Android platform.
  android('android'),

  /// iOS platform.
  ios('ios');

  const AgusKeymapPlatform(this.id);

  /// Platform identifier used in JSON and database.
  final String id;

  /// Parses a platform from its identifier.
  static AgusKeymapPlatform fromId(String id) {
    return AgusKeymapPlatform.values.firstWhere(
      (p) => p.id == id,
      orElse: () => throw ArgumentError.value(id, 'id'),
    );
  }

  /// Returns the current platform based on the runtime.
  static AgusKeymapPlatform get current {
    if (Platform.isMacOS) return AgusKeymapPlatform.macos;
    if (Platform.isWindows) return AgusKeymapPlatform.windows;
    if (Platform.isLinux) return AgusKeymapPlatform.linux;
    if (Platform.isAndroid) return AgusKeymapPlatform.android;
    if (Platform.isIOS) return AgusKeymapPlatform.ios;
    return AgusKeymapPlatform.linux; // fallback
  }
}

/// A command-to-keybinding mapping.
class AgusKeymapEntry {
  /// Creates a keymap entry.
  const AgusKeymapEntry({
    required this.command,
    required this.keybinding,
    this.when,
  });

  /// Creates a keymap entry from JSON.
  factory AgusKeymapEntry.fromJson(Map<String, Object?> json) {
    return AgusKeymapEntry(
      command: json['command'] as String,
      keybinding: AgusKeybinding.fromJson(
        json['keybinding'] as Map<String, Object?>,
      ),
      when: json['when'] as String?,
    );
  }

  /// The command identifier.
  final String command;

  /// The keybinding for this command.
  final AgusKeybinding keybinding;

  /// Optional context expression (e.g., 'editorFocus', 'mapFocus').
  final String? when;

  /// Converts this entry to JSON.
  Map<String, Object?> toJson() {
    return {
      'command': command,
      'keybinding': keybinding.toJson(),
      if (when != null) 'when': when,
    };
  }
}

/// A keymap conflict between two entries.
class AgusKeymapConflict {
  /// Creates a conflict record.
  const AgusKeymapConflict({
    required this.keybinding,
    required this.command1,
    required this.command2,
    required this.source1,
    required this.source2,
  });

  /// The conflicting keybinding.
  final AgusKeybinding keybinding;

  /// First command using this keybinding.
  final String command1;

  /// Second command using this keybinding.
  final String command2;

  /// Source of first binding ('default' or 'override').
  final String source1;

  /// Source of second binding ('default' or 'override').
  final String source2;

  /// Returns a human-readable description of the conflict.
  String describe(AgusKeymapPlatform platform) {
    final label = keybinding.toLabel(platform: platform);
    return '$label is bound to both "$command1" ($source1) and "$command2" ($source2)';
  }
}
