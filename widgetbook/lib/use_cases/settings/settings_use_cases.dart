import 'package:agus_design/agus_design.dart';
import 'package:flutter/material.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import '../../src/catalog_data.dart';

@widgetbook.UseCase(
  name: 'Scope selector',
  type: AgusSettingScopeSelector,
  path: '[Settings]/editor',
)
Widget buildAgusSettingScopeSelectorUseCase(BuildContext context) {
  final scope = context.knobs.object.segmented<AgusSettingScope>(
    label: 'Scope',
    initialOption: AgusSettingScope.user,
    options: const [AgusSettingScope.user, AgusSettingScope.workspace],
    labelBuilder: (value) => value.label,
  );

  return previewFrame(
    context,
    width: 280,
    child: AgusSettingScopeSelector(selectedScope: scope, onSelected: (_) {}),
  );
}

@widgetbook.UseCase(
  name: 'Field variants',
  type: AgusSettingControl,
  path: '[Settings]/editor',
)
Widget buildAgusSettingControlUseCase(BuildContext context) {
  final kind = context.knobs.object.segmented<AgusSettingPreviewKind>(
    label: 'Field type',
    initialOption: AgusSettingPreviewKind.select,
    options: AgusSettingPreviewKind.values,
    labelBuilder: (value) => value.label,
  );
  final enabled = context.knobs.boolean(label: 'Enabled', initialValue: true);

  return previewFrame(
    context,
    width: 420,
    child: AgusSettingControl(
      schema: buildSettingSchemaPreview(kind),
      value: buildSettingValuePreview(kind),
      onChanged: enabled ? (_) {} : null,
    ),
  );
}

@widgetbook.UseCase(
  name: 'Setting row',
  type: AgusSettingRow,
  path: '[Settings]/editor',
)
Widget buildAgusSettingRowUseCase(BuildContext context) {
  final kind = context.knobs.object.segmented<AgusSettingPreviewKind>(
    label: 'Row type',
    initialOption: AgusSettingPreviewKind.number,
    options: AgusSettingPreviewKind.values,
    labelBuilder: (value) => value.label,
  );
  final modified = context.knobs.boolean(label: 'Modified', initialValue: true);

  return previewFrame(
    context,
    width: 560,
    child: AgusSettingRow(
      schema: buildSettingSchemaPreview(kind),
      value: buildSettingValuePreview(kind),
      modified: modified,
      onChanged: (_) {},
    ),
  );
}

@widgetbook.UseCase(
  name: 'Responsive settings editor',
  type: AgusSettingsEditor,
  path: '[Settings]/editor',
)
Widget buildAgusSettingsEditorUseCase(BuildContext context) {
  final width = context.knobs.int.slider(
    label: 'Editor width',
    initialValue: 920,
    min: 320,
    max: 1080,
    divisions: 19,
  );
  final initialScope = context.knobs.object.segmented<AgusSettingScope>(
    label: 'Initial scope',
    initialOption: AgusSettingScope.user,
    options: const [AgusSettingScope.user, AgusSettingScope.workspace],
    labelBuilder: (value) => value.label,
  );
  final showModifiedValues = context.knobs.boolean(
    label: 'Show modified values',
    initialValue: true,
  );

  return previewFrame(
    context,
    width: width.toDouble(),
    height: 620,
    padding: EdgeInsets.zero,
    child: SettingsEditorPreview(
      key: ValueKey('$width-$initialScope-$showModifiedValues'),
      schemas: sampleSettingSchemas,
      initialValues: buildSampleSettingValues(
        showModifiedValues: showModifiedValues,
      ),
      initialScope: initialScope,
    ),
  );
}
