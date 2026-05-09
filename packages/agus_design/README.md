# Agus Design

Agus Design is a Flutter package for building VS Code-like workbench applications with native Flutter/Dart surfaces. It starts from an Android/Material baseline on every target platform, then layers VS Code-inspired theme tokens, layout primitives, and desktop-focused components.

The package is intentionally a library first. Apps consume `agus_design`, apply `AgusThemeData.dark().toThemeData()`, and compose the exported workbench widgets into their own shell.

## Current Scope

- Android-locked Material theme foundation with VS Code-like colors and desktop density.
- Workbench shell with title bar, Activity Bar, sidebar, editor area, bottom panel slot, and status bar.
- Resizable split view primitive for desktop pane layouts.
- Activity Bar, title bar, command center, editor tabs, tree view, sidebar sections, status bar, and editor host components.
- Schema-driven settings model, reusable settings row and control widgets, and a responsive settings editor.
- Example app that demonstrates a kitchen-sink workbench surface.
- OSS Widgetbook workspace for cataloging reusable components with knobs and annotated use-cases.

## Quick Start

```dart
import 'package:agus_design/agus_design.dart';
import 'package:flutter/material.dart';

void main() {
	runApp(MaterialApp(
		theme: AgusThemeData.dark().toThemeData(),
		home: const MyWorkbench(),
	));
}
```

## Development

```sh
flutter pub get
dart format .
flutter analyze
flutter test
cd example && flutter run
```

## Widgetbook OSS Workspace

```sh
cd widgetbook
flutter pub get
dart run build_runner build
flutter run
```

See [PLAN.md](PLAN.md) for the full implementation roadmap.
