import 'package:agus_design/agus_design.dart';
import 'package:flutter/material.dart';
import 'package:widgetbook/widgetbook.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart' as widgetbook;

import 'main.directories.g.dart';

void main() {
  runApp(const AgusDesignWidgetbookApp());
}

@widgetbook.App()
class AgusDesignWidgetbookApp extends StatelessWidget {
  const AgusDesignWidgetbookApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Widgetbook.material(
      directories: directories,
      themeMode: ThemeMode.system,
      addons: [
        ViewportAddon(Viewports.all),
        MaterialThemeAddon(
          themes: [
            WidgetbookTheme(
              name: 'Agus Light',
              data: AgusThemeData.light().toThemeData(),
            ),
            WidgetbookTheme(
              name: 'Agus Dark',
              data: AgusThemeData.dark().toThemeData(),
            ),
          ],
        ),
        GridAddon(8),
        TextScaleAddon(initialScale: 1, min: 0.8, max: 1.6, divisions: 4),
        InspectorAddon(),
        AlignmentAddon(),
        // ignore: experimental_member_use
        SemanticsAddon(),
      ],
      header: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          'Agus Design OSS',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
