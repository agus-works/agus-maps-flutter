import 'package:flutter/material.dart';

import '../theme/agus_theme_data.dart';
import 'agus_settings_schema.dart';

class AgusSettingScopeSelector extends StatelessWidget {
  const AgusSettingScopeSelector({
    required this.selectedScope,
    required this.onSelected,
    super.key,
  });

  final AgusSettingScope selectedScope;
  final ValueChanged<AgusSettingScope> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final scope in const [
          AgusSettingScope.user,
          AgusSettingScope.workspace,
        ])
          InkWell(
            onTap: () => onSelected(scope),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scope == selectedScope
                    ? colors.selectionBackground
                    : colors.inputBackground,
                border: Border.all(
                  color: scope == selectedScope
                      ? colors.focusBorder
                      : colors.inputBorder,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                child: Text(scope.label),
              ),
            ),
          ),
      ],
    );
  }
}

class AgusSettingRow extends StatelessWidget {
  const AgusSettingRow({
    required this.schema,
    required this.value,
    required this.modified,
    this.onChanged,
    super.key,
  });

  final AgusSettingSchema schema;
  final Object? value;
  final bool modified;
  final ValueChanged<Object?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = AgusThemeData.colorsOf(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: modified ? colors.focusBorder : Colors.transparent,
            width: 3,
          ),
          bottom: BorderSide(color: colors.editorGroupBorder),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    schema.title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (modified)
                  TextButton(
                    onPressed: onChanged == null
                        ? null
                        : () => onChanged!(schema.defaultValue),
                    child: const Text('Reset'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              schema.description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.editorForeground.withValues(alpha: 0.78),
              ),
            ),
            const SizedBox(height: 10),
            AgusSettingControl(
              schema: schema,
              value: value,
              onChanged: onChanged,
            ),
            const SizedBox(height: 6),
            Text(
              schema.id,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colors.editorForeground.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AgusSettingControl extends StatelessWidget {
  const AgusSettingControl({
    required this.schema,
    required this.value,
    this.onChanged,
    super.key,
  });

  final AgusSettingSchema schema;
  final Object? value;
  final ValueChanged<Object?>? onChanged;

  @override
  Widget build(BuildContext context) {
    if (schema.jsonOnly || schema.type == AgusSettingType.json) {
      return TextButton.icon(
        onPressed: null,
        icon: const Icon(Icons.data_object, size: 16),
        label: const Text('Edit in JSON'),
      );
    }

    return switch (schema.type) {
      AgusSettingType.boolean => Switch(
        value: _booleanValue(value),
        onChanged: onChanged == null ? null : (next) => onChanged!(next),
      ),
      AgusSettingType.select || AgusSettingType.radio => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260),
        child: DropdownButton<Object>(
          value: _optionValue(schema, value),
          isExpanded: true,
          items: [
            for (final option in schema.options)
              DropdownMenuItem<Object>(
                value: option.value,
                child: Text(option.label),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
      AgusSettingType.number => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 180),
        child: TextFormField(
          initialValue: value?.toString() ?? '',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onFieldSubmitted: (text) {
            final parsed = double.tryParse(text);
            if (parsed == null) {
              return;
            }
            final clamped = parsed.clamp(
              schema.minimum ?? double.negativeInfinity,
              schema.maximum ?? double.infinity,
            );
            onChanged?.call(clamped);
          },
        ),
      ),
      AgusSettingType.array || AgusSettingType.object => TextFormField(
        initialValue: value?.toString() ?? '',
        minLines: 2,
        maxLines: 4,
        onFieldSubmitted: onChanged,
      ),
      AgusSettingType.file || AgusSettingType.folder => LayoutBuilder(
        builder: (context, constraints) {
          final field = TextFormField(
            initialValue: value?.toString() ?? '',
            onFieldSubmitted: onChanged,
          );
          final browseButton = OutlinedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.folder_open, size: 16),
            label: const Text('Browse'),
          );

          if (constraints.maxWidth < 260) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [field, const SizedBox(height: 8), browseButton],
            );
          }

          return Row(
            children: [
              Expanded(child: field),
              const SizedBox(width: 8),
              browseButton,
            ],
          );
        },
      ),
      AgusSettingType.color || AgusSettingType.string => TextFormField(
        initialValue: value?.toString() ?? '',
        onFieldSubmitted: onChanged,
      ),
      AgusSettingType.json => const SizedBox.shrink(),
    };
  }

  Object? _optionValue(AgusSettingSchema schema, Object? value) {
    if (schema.options.any((option) => option.value == value)) {
      return value;
    }
    if (schema.options.any((option) => option.value == schema.defaultValue)) {
      return schema.defaultValue;
    }
    return schema.options.isEmpty ? null : schema.options.first.value;
  }

  bool _booleanValue(Object? value) {
    if (value is bool) {
      return value;
    }
    return schema.defaultValue == true;
  }
}
