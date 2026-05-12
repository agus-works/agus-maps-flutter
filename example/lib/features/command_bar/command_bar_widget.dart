import 'package:flutter/material.dart';
import 'package:agus_maps_flutter/agus_maps_flutter.dart';

/// A command palette widget that displays available commands with their keyboard shortcuts.
class CommandBar extends StatefulWidget {
  const CommandBar({
    super.key,
    required this.resolver,
    required this.onCommandExecuted,
  });

  final AgusKeymapResolver resolver;
  final void Function(String commandId) onCommandExecuted;

  @override
  State<CommandBar> createState() => _CommandBarState();
}

class _CommandBarState extends State<CommandBar> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  Map<String, AgusKeybinding>? _keymap;

  static final _availableCommands = [
    AgusCommandId.openSearch,
    AgusCommandId.focusSearch,
    AgusCommandId.toggleLayerPanel,
    AgusCommandId.newDrawingLayer,
    AgusCommandId.toggleCurrentLayer,
    AgusCommandId.selectAll,
    AgusCommandId.deselectAll,
    AgusCommandId.delete,
    AgusCommandId.undo,
    AgusCommandId.redo,
    AgusCommandId.copy,
    AgusCommandId.cut,
    AgusCommandId.paste,
    AgusCommandId.duplicate,
    AgusCommandId.selectTool,
    AgusCommandId.panTool,
    AgusCommandId.drawPointTool,
    AgusCommandId.drawLineTool,
    AgusCommandId.drawPolygonTool,
    AgusCommandId.zoomIn,
    AgusCommandId.zoomOut,
    AgusCommandId.resetRotation,
    AgusCommandId.toggleFullscreen,
    AgusCommandId.showAbout,
    AgusCommandId.showSettings,
    AgusCommandId.refresh,
  ];

  @override
  void initState() {
    super.initState();
    _loadKeymap();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadKeymap() async {
    final keymap = widget.resolver.resolveKeymap();
    setState(() => _keymap = keymap);
  }

  List<String> get _filteredCommands {
    if (_searchQuery.isEmpty) return _availableCommands;

    return _availableCommands.where((cmd) {
      final displayName = AgusCommandId.displayName(cmd).toLowerCase();
      final description = AgusCommandId.description(cmd).toLowerCase();
      return displayName.contains(_searchQuery) ||
          description.contains(_searchQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 500),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search commands...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _keymap == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: _filteredCommands.length,
                      itemBuilder: (context, index) {
                        final commandId = _filteredCommands[index];
                        final binding = _keymap![commandId];
                        final label = binding?.toLabel(
                          platform: AgusKeymapPlatform.current,
                        );

                        return ListTile(
                          title: Text(AgusCommandId.displayName(commandId)),
                          subtitle: Text(
                            AgusCommandId.description(commandId),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          trailing: label != null
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color:
                                          Theme.of(context).colorScheme.outline,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    label,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          fontFamily: 'monospace',
                                        ),
                                  ),
                                )
                              : null,
                          onTap: () {
                            widget.onCommandExecuted(commandId);
                            Navigator.of(context).pop();
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows the command bar dialog.
Future<void> showCommandBar({
  required BuildContext context,
  required AgusKeymapResolver resolver,
  required void Function(String commandId) onCommandExecuted,
}) {
  return showDialog(
    context: context,
    builder: (context) => CommandBar(
      resolver: resolver,
      onCommandExecuted: onCommandExecuted,
    ),
  );
}
