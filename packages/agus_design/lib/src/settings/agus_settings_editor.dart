import 'package:flutter/material.dart';

import '../components/agus_tree_view.dart';
import '../theme/agus_theme_data.dart';
import 'agus_settings_schema.dart';
import 'agus_setting_widgets.dart';

class AgusSettingsEditor extends StatefulWidget {
  const AgusSettingsEditor({
    required this.schemas,
    this.values = const <String, Object?>{},
    this.onChanged,
    this.initialScope = AgusSettingScope.user,
    super.key,
  });

  final List<AgusSettingSchema> schemas;
  final Map<String, Object?> values;
  final void Function(String id, Object? value)? onChanged;
  final AgusSettingScope initialScope;

  @override
  State<AgusSettingsEditor> createState() => _AgusSettingsEditorState();
}

class _AgusSettingsEditorState extends State<AgusSettingsEditor> {
  late AgusSettingScope scope = widget.initialScope;
  String query = '';
  String? selectedCategory;

  @override
  Widget build(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);
    final categories =
        widget.schemas.map((schema) => schema.category).toSet().toList()
          ..sort();
    final activeCategory =
        selectedCategory ?? (categories.isEmpty ? null : categories.first);
    final filteredSchemas = widget.schemas.where((schema) {
      final categoryMatches =
          activeCategory == null || schema.category == activeCategory;
      return categoryMatches && schema.matchesQuery(query);
    }).toList();

    return Material(
      color: colors.editorBackground,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          final settingsContent = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (compact && categories.isNotEmpty) ...[
                      DropdownButtonFormField<String>(
                        initialValue: activeCategory,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Category',
                        ),
                        items: [
                          for (final category in categories)
                            DropdownMenuItem(
                              value: category,
                              child: Text(category),
                            ),
                        ],
                        onChanged: (id) {
                          if (id != null) {
                            setState(() => selectedCategory = id);
                          }
                        },
                      ),
                      const SizedBox(height: 10),
                    ],
                    TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search, size: 16),
                        hintText: 'Search settings',
                      ),
                      onChanged: (value) => setState(() => query = value),
                    ),
                    const SizedBox(height: 10),
                    AgusSettingScopeSelector(
                      selectedScope: scope,
                      onSelected: (nextScope) =>
                          setState(() => scope = nextScope),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: filteredSchemas.length,
                  itemBuilder: (context, index) {
                    final schema = filteredSchemas[index];
                    final value = widget.values.containsKey(schema.id)
                        ? widget.values[schema.id]
                        : schema.defaultValue;
                    return AgusSettingRow(
                      schema: schema,
                      value: value,
                      modified:
                          widget.values.containsKey(schema.id) &&
                          widget.values[schema.id] != schema.defaultValue,
                      onChanged: widget.onChanged == null
                          ? null
                          : (nextValue) =>
                                widget.onChanged!(schema.id, nextValue),
                    );
                  },
                ),
              ),
            ],
          );

          if (compact) {
            return settingsContent;
          }

          return Row(
            children: [
              SizedBox(
                width: 220,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.sideBarBackground,
                    border: Border(
                      right: BorderSide(color: colors.sideBarBorder),
                    ),
                  ),
                  child: AgusTreeView(
                    selectedId: activeCategory,
                    nodes: [
                      for (final category in categories)
                        AgusTreeNode(
                          id: category,
                          label: category,
                          icon: Icons.tune,
                        ),
                    ],
                    onSelected: (id) => setState(() => selectedCategory = id),
                  ),
                ),
              ),
              Expanded(child: settingsContent),
            ],
          );
        },
      ),
    );
  }
}
