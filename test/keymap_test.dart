import 'package:flutter_test/flutter_test.dart';
import 'package:agus_maps_flutter/agus_maps_flutter.dart';

void main() {
  group('AgusKeybinding', () {
    test('creates keybinding with modifiers', () {
      const binding = AgusKeybinding(
        key: 'k',
        meta: true,
        shift: true,
      );

      expect(binding.key, 'k');
      expect(binding.meta, true);
      expect(binding.shift, true);
      expect(binding.control, false);
      expect(binding.alt, false);
    });

    test('parses keybinding from JSON', () {
      final json = {
        'key': 'f',
        'control': true,
        'shift': true,
      };

      final binding = AgusKeybinding.fromJson(json);

      expect(binding.key, 'f');
      expect(binding.control, true);
      expect(binding.shift, true);
      expect(binding.meta, false);
      expect(binding.alt, false);
    });

    test('converts keybinding to JSON', () {
      const binding = AgusKeybinding(
        key: 'z',
        meta: true,
      );

      final json = binding.toJson();

      expect(json['key'], 'z');
      expect(json['meta'], true);
      expect(json.containsKey('control'), false);
      expect(json.containsKey('shift'), false);
    });

    test('generates macOS label with symbols', () {
      const binding = AgusKeybinding(
        key: 'k',
        meta: true,
        shift: true,
      );

      final label = binding.toLabel(platform: AgusKeymapPlatform.macos);

      expect(label, '⇧⌘K');
    });

    test('generates Windows label with text', () {
      const binding = AgusKeybinding(
        key: 'k',
        control: true,
        shift: true,
      );

      final label = binding.toLabel(platform: AgusKeymapPlatform.windows);

      expect(label, 'Ctrl+Shift+K');
    });

    test('formats special keys', () {
      const arrowUp = AgusKeybinding(key: 'arrowUp');
      expect(
        arrowUp.toLabel(platform: AgusKeymapPlatform.macos),
        '↑',
      );

      const escape = AgusKeybinding(key: 'escape');
      expect(
        escape.toLabel(platform: AgusKeymapPlatform.windows),
        'Esc',
      );

      const enter = AgusKeybinding(key: 'enter');
      expect(
        enter.toLabel(platform: AgusKeymapPlatform.macos),
        '↵',
      );
    });

    test('generates conflict key for comparison', () {
      const binding1 = AgusKeybinding(key: 'k', meta: true);
      const binding2 = AgusKeybinding(key: 'K', meta: true);

      expect(binding1.toConflictKey(), binding2.toConflictKey());
    });

    test('generates unique conflict keys for different bindings', () {
      const binding1 = AgusKeybinding(key: 'k', meta: true);
      const binding2 = AgusKeybinding(key: 'k', control: true);

      expect(binding1.toConflictKey(), isNot(binding2.toConflictKey()));
    });

    test('equality comparison', () {
      const binding1 = AgusKeybinding(key: 'k', meta: true);
      const binding2 = AgusKeybinding(key: 'k', meta: true);
      const binding3 = AgusKeybinding(key: 'k', control: true);

      expect(binding1, binding2);
      expect(binding1, isNot(binding3));
    });
  });

  group('AgusKeymapPlatform', () {
    test('parses platform from ID', () {
      expect(AgusKeymapPlatform.fromId('macos'), AgusKeymapPlatform.macos);
      expect(AgusKeymapPlatform.fromId('windows'), AgusKeymapPlatform.windows);
      expect(AgusKeymapPlatform.fromId('linux'), AgusKeymapPlatform.linux);
    });

    test('throws on invalid platform ID', () {
      expect(
        () => AgusKeymapPlatform.fromId('invalid'),
        throwsArgumentError,
      );
    });
  });

  group('AgusKeymapEntry', () {
    test('creates entry with command and keybinding', () {
      const entry = AgusKeymapEntry(
        command: AgusCommandId.openCommandBar,
        keybinding: AgusKeybinding(key: 'k', meta: true),
      );

      expect(entry.command, AgusCommandId.openCommandBar);
      expect(entry.keybinding.key, 'k');
      expect(entry.keybinding.meta, true);
    });

    test('parses entry from JSON', () {
      final json = {
        'command': 'map.zoom.in',
        'keybinding': {
          'key': '=',
          'meta': true,
        },
        'when': 'mapFocus',
      };

      final entry = AgusKeymapEntry.fromJson(json);

      expect(entry.command, 'map.zoom.in');
      expect(entry.keybinding.key, '=');
      expect(entry.keybinding.meta, true);
      expect(entry.when, 'mapFocus');
    });

    test('converts entry to JSON', () {
      const entry = AgusKeymapEntry(
        command: 'map.zoom.out',
        keybinding: AgusKeybinding(key: '-', control: true),
        when: 'editorFocus',
      );

      final json = entry.toJson();
      final keybindingJson = json['keybinding'] as Map<String, Object?>;

      expect(json['command'], 'map.zoom.out');
      expect(keybindingJson['key'], '-');
      expect(keybindingJson['control'], true);
      expect(json['when'], 'editorFocus');
    });
  });

  group('AgusCommandId', () {
    test('provides display names for commands', () {
      expect(AgusCommandId.displayName(AgusCommandId.openCommandBar),
          'Open Command Bar');
      expect(AgusCommandId.displayName(AgusCommandId.zoomIn), 'Zoom In');
      expect(AgusCommandId.displayName(AgusCommandId.undo), 'Undo');
    });

    test('provides descriptions for commands', () {
      expect(
        AgusCommandId.description(AgusCommandId.openCommandBar),
        'Open the command bar',
      );
      expect(
        AgusCommandId.description(AgusCommandId.zoomIn),
        'Zoom in on the map',
      );
    });

    test('returns command ID for unknown commands', () {
      expect(AgusCommandId.displayName('unknown.command'), 'unknown.command');
      expect(AgusCommandId.description('unknown.command'), '');
    });
  });

  group('AgusKeymapDefaults', () {
    test('provides macOS defaults', () {
      final defaults = AgusKeymapDefaults.forPlatform(AgusKeymapPlatform.macos);

      expect(defaults, isNotEmpty);

      // Check command bar binding (Cmd+K)
      final cmdBar = defaults.firstWhere(
        (e) => e.command == AgusCommandId.openCommandBar,
      );
      expect(cmdBar.keybinding.key, 'k');
      expect(cmdBar.keybinding.meta, true);

      // Check undo (Cmd+Z)
      final undo = defaults.firstWhere(
        (e) => e.command == AgusCommandId.undo,
      );
      expect(undo.keybinding.key, 'z');
      expect(undo.keybinding.meta, true);
    });

    test('provides Windows defaults', () {
      final defaults =
          AgusKeymapDefaults.forPlatform(AgusKeymapPlatform.windows);

      expect(defaults, isNotEmpty);

      // Check command bar binding (Ctrl+K)
      final cmdBar = defaults.firstWhere(
        (e) => e.command == AgusCommandId.openCommandBar,
      );
      expect(cmdBar.keybinding.key, 'k');
      expect(cmdBar.keybinding.control, true);

      // Check redo (Ctrl+Y, Windows convention)
      final redo = defaults.firstWhere(
        (e) => e.command == AgusCommandId.redo,
      );
      expect(redo.keybinding.key, 'y');
      expect(redo.keybinding.control, true);
    });

    test('provides Linux defaults', () {
      final defaults = AgusKeymapDefaults.forPlatform(AgusKeymapPlatform.linux);

      expect(defaults, isNotEmpty);
    });

    test('provides mobile defaults', () {
      final androidDefaults =
          AgusKeymapDefaults.forPlatform(AgusKeymapPlatform.android);
      final iosDefaults =
          AgusKeymapDefaults.forPlatform(AgusKeymapPlatform.ios);

      // Mobile has minimal defaults
      expect(androidDefaults, isNotEmpty);
      expect(iosDefaults, isNotEmpty);
    });

    test('macOS defaults avoid common OS shortcuts', () {
      final defaults = AgusKeymapDefaults.forPlatform(AgusKeymapPlatform.macos);

      // Should not override Tab, Cmd+Tab, Cmd+W, etc.
      final cmds = defaults.map((e) => e.keybinding).toList();

      // No Cmd+W (close window)
      expect(
        cmds.any((kb) => kb.key == 'w' && kb.meta && !kb.control && !kb.shift),
        false,
      );

      // No Cmd+Tab (app switcher)
      expect(
        cmds.any((kb) => kb.key == 'tab' && kb.meta),
        false,
      );
    });

    test('Windows defaults avoid common OS shortcuts', () {
      final defaults =
          AgusKeymapDefaults.forPlatform(AgusKeymapPlatform.windows);

      final cmds = defaults.map((e) => e.keybinding).toList();

      // No Alt+Tab (task switcher)
      expect(
        cmds.any((kb) => kb.key == 'tab' && kb.alt),
        false,
      );

      // No Ctrl+W (close tab/window)
      expect(
        cmds.any((kb) => kb.key == 'w' && kb.control && !kb.shift),
        false,
      );
    });

    test('defaults have no internal conflicts', () {
      for (final platform in AgusKeymapPlatform.values) {
        final defaults = AgusKeymapDefaults.forPlatform(platform);
        final keybindingKeys = <String>{};

        for (final entry in defaults) {
          final key = entry.keybinding.toConflictKey();
          expect(
            keybindingKeys.contains(key),
            false,
            reason: 'Duplicate keybinding $key in $platform defaults',
          );
          keybindingKeys.add(key);
        }
      }
    });
  });

  group('AgusKeymapConflict', () {
    test('describes conflict with human-readable message', () {
      final conflict = AgusKeymapConflict(
        keybinding: const AgusKeybinding(key: 'k', meta: true),
        command1: AgusCommandId.openCommandBar,
        command2: AgusCommandId.toggleLayerPanel,
        source1: 'default',
        source2: 'override',
      );

      final description = conflict.describe(AgusKeymapPlatform.macos);

      expect(description, contains('⌘K'));
      expect(description, contains(AgusCommandId.openCommandBar));
      expect(description, contains(AgusCommandId.toggleLayerPanel));
      expect(description, contains('default'));
      expect(description, contains('override'));
    });
  });
}
