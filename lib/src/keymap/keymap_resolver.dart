part of '../../agus_maps_flutter.dart';

/// Resolves and manages keymaps from defaults and user overrides.
class AgusKeymapResolver {
  /// Creates a keymap resolver.
  AgusKeymapResolver({
    required this.store,
    required this.platform,
  });

  /// The layer store providing keymap persistence.
  final DuckDBLayerStore store;

  /// The target platform for keymap resolution.
  final AgusKeymapPlatform platform;

  /// Resolves the active keymap by merging defaults and overrides.
  Map<String, AgusKeybinding> resolveKeymap() {
    final defaults = AgusKeymapDefaults.forPlatform(platform);
    final overrides = _loadOverrides();

    final resolved = <String, AgusKeybinding>{};

    // Apply defaults first
    for (final entry in defaults) {
      resolved[entry.command] = entry.keybinding;
    }

    // Apply overrides
    for (final entry in overrides) {
      resolved[entry.command] = entry.keybinding;
    }

    return resolved;
  }

  /// Loads user overrides from the database.
  List<AgusKeymapEntry> _loadOverrides() {
    final settings = store.listKeymapSettings(
      platform: platform.id,
    );

    return settings
        .where((s) => s.isOverride)
        .map((s) => AgusKeymapEntry(
              command: s.command,
              keybinding: AgusKeybinding.fromJson(s.keybindingPayload),
            ))
        .toList();
  }

  /// Detects conflicts in the resolved keymap.
  List<AgusKeymapConflict> detectConflicts() {
    final defaults = AgusKeymapDefaults.forPlatform(platform);
    final overrides = _loadOverrides();

    final allEntries = [...defaults, ...overrides];
    final conflicts = <AgusKeymapConflict>[];

    final keybindingToCommands = <String, List<(String, String)>>{};

    // Build conflict map
    for (final entry in defaults) {
      final key = entry.keybinding.toConflictKey();
      keybindingToCommands.putIfAbsent(key, () => []).add((entry.command, 'default'));
    }

    for (final entry in overrides) {
      final key = entry.keybinding.toConflictKey();
      keybindingToCommands.putIfAbsent(key, () => []).add((entry.command, 'override'));
    }

    // Find conflicts
    for (final MapEntry(key: conflictKey, value: commands) in keybindingToCommands.entries) {
      if (commands.length > 1) {
        // Multiple commands bound to same key
        for (var i = 0; i < commands.length; i++) {
          for (var j = i + 1; j < commands.length; j++) {
            final (cmd1, src1) = commands[i];
            final (cmd2, src2) = commands[j];

            // Find the keybinding
            final entry = allEntries.firstWhere(
              (e) => e.keybinding.toConflictKey() == conflictKey,
            );

            conflicts.add(AgusKeymapConflict(
              keybinding: entry.keybinding,
              command1: cmd1,
              command2: cmd2,
              source1: src1,
              source2: src2,
            ));
          }
        }
      }
    }

    return conflicts;
  }

  /// Saves a keymap override to the database.
  void saveOverride({
    required String command,
    required AgusKeybinding keybinding,
  }) {
    final settingId = '${platform.id}_$command';
    final draft = AgusKeymapSettingDraft(
      settingId: settingId,
      platform: platform.id,
      command: command,
      keybindingPayload: keybinding.toJson(),
      isOverride: true,
      displayName: AgusCommandId.displayName(command),
      description: AgusCommandId.description(command),
      validationSchemaVersion: 1,
    );

    store.upsertKeymapSetting(draft);
  }

  /// Removes a keymap override, restoring the default.
  void removeOverride(String command) {
    final settingId = '${platform.id}_$command';
    store.deleteKeymapSetting(settingId);
  }

  /// Returns the keybinding for a specific command.
  AgusKeybinding? getKeybinding(String command) {
    final keymap = resolveKeymap();
    return keymap[command];
  }

  /// Returns a display label for a command's keybinding.
  String? getKeybindingLabel(String command) {
    final binding = getKeybinding(command);
    return binding?.toLabel(platform: platform);
  }

  /// Initializes default keymaps in the database if not present.
  void initializeDefaults() {
    final defaults = AgusKeymapDefaults.forPlatform(platform);

    for (final entry in defaults) {
      final settingId = '${platform.id}_${entry.command}';
      final existing = store.getKeymapSetting(settingId);

      if (existing == null) {
        final draft = AgusKeymapSettingDraft(
          settingId: settingId,
          platform: platform.id,
          command: entry.command,
          keybindingPayload: entry.keybinding.toJson(),
          isOverride: false,
          displayName: AgusCommandId.displayName(entry.command),
          description: AgusCommandId.description(entry.command),
          validationSchemaVersion: 1,
        );

        store.upsertKeymapSetting(draft);
      }
    }
  }

  /// Exports the current keymap to JSON format.
  Map<String, Object?> exportToJson() {
    final keymap = resolveKeymap();
    final entries = keymap.entries
        .map((e) => AgusKeymapEntry(
              command: e.key,
              keybinding: e.value,
            ))
        .toList();

    return {
      'version': 1,
      'platform': platform.id,
      'keybindings': entries.map((e) => e.toJson()).toList(),
    };
  }

  /// Imports a keymap from JSON format.
  void importFromJson(Map<String, Object?> json) {
    final keybindings = json['keybindings'] as List;

    for (final binding in keybindings) {
      final entry = AgusKeymapEntry.fromJson(binding as Map<String, Object?>);
      saveOverride(
        command: entry.command,
        keybinding: entry.keybinding,
      );
    }
  }
}
