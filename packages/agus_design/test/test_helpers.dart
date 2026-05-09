import 'package:agus_design/agus_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const testSettingSchemas = <AgusSettingSchema>[
  AgusSettingSchema(
    id: 'workbench.sideBar.location',
    title: 'Workbench: Side Bar Location',
    description: 'Controls the primary sidebar location.',
    category: 'Workbench',
    type: AgusSettingType.select,
    defaultValue: 'left',
    options: [
      AgusSettingOption(value: 'left', label: 'Left'),
      AgusSettingOption(value: 'right', label: 'Right'),
    ],
  ),
  AgusSettingSchema(
    id: 'workbench.activityBar.visible',
    title: 'Workbench: Activity Bar Visible',
    description: 'Controls Activity Bar visibility.',
    category: 'Workbench',
    type: AgusSettingType.boolean,
    defaultValue: true,
  ),
  AgusSettingSchema(
    id: 'agus.editor.fontSize',
    title: 'Editor: Font Size',
    description: 'Controls the font size used by code editor hosts.',
    category: 'Editor',
    type: AgusSettingType.number,
    defaultValue: 13.0,
    minimum: 8,
    maximum: 32,
  ),
  AgusSettingSchema(
    id: 'agus.webview.localRoot',
    title: 'Webview: Local Root',
    description: 'Directory used for local preview assets.',
    category: 'Webview',
    type: AgusSettingType.folder,
    defaultValue: '',
  ),
  AgusSettingSchema(
    id: 'agus.editor.experimentalData',
    title: 'Editor: Experimental Data',
    description: 'JSON-only data for extension experiments.',
    category: 'Editor',
    type: AgusSettingType.json,
    defaultValue: '{}',
    jsonOnly: true,
  ),
];

Future<void> pumpAgusWidget(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(800, 600),
  ThemeData? theme,
  ThemeData? darkTheme,
  ThemeMode themeMode = ThemeMode.light,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AgusThemeData.dark().toThemeData(),
      darkTheme: darkTheme,
      themeMode: themeMode,
      home: Scaffold(
        body: SizedBox(width: size.width, height: size.height, child: child),
      ),
    ),
  );
}
