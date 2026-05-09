# Melos Monorepo

`agus-maps-flutter` is a Melos-managed Pub Workspace. The native map plugin remains at the repository root so existing CoMaps, DuckDB, platform, hook, and CI paths continue to work. The copied design system lives in `packages/agus_design` and can be developed quickly without building native map dependencies.

## Workspace layout

```text
agus-maps-flutter/
├── pubspec.yaml                  # workspace root and root plugin package
├── example/                      # map example app, depends on agus_design
├── packages/
│   └── agus_design/              # copied design system package
├── tool/
│   └── skin_generator_tool/      # workspace tool package
└── widgetbook/                   # single Widgetbook app for agus_design
```

Workspace packages:

| Package | Path | Purpose |
| --- | --- | --- |
| `agus_maps_flutter` | `.` | Root Flutter plugin and native map integration |
| `agus_maps_flutter_example` | `example` | Example app that consumes the plugin and design system |
| `agus_design` | `packages/agus_design` | Fast, isolated Flutter design system |
| `agus_design_example` | `packages/agus_design/example` | Lightweight design package example app |
| `agus_design_widgetbook` | `widgetbook` | Widgetbook catalog for design components |
| `skin_generator_tool` | `tool/skin_generator_tool` | Dart skin generation tooling |

## Commands

Run commands from the repository root unless noted.

```bash
flutter pub get
dart run melos bootstrap
dart run melos list --long
```

The root `pubspec.lock` is the workspace lockfile and should be committed. Child workspace lockfiles are removed.

Fast design-only checks:

```bash
dart run melos run design:analyze --no-select
dart run melos run design:test --no-select
dart run melos run generate --no-select
```

Workspace checks with a clean analyzer/test baseline:

```bash
dart run melos run analyze --no-select
dart run melos run test --no-select
```

The root native plugin package and `skin_generator_tool` currently have existing analyzer info/warning output from build orchestration code. They are excluded from the default `analyze` script so design and example iteration stays signal-rich.

Map example builds still run from `example/` after the workspace has been bootstrapped:

```bash
cd example
flutter run -d <device>
```

## Design isolation

`packages/agus_design` intentionally has no dependency on `agus_maps_flutter`, DuckDB, CoMaps, generated map assets, or native plugin binaries. Widgetbook depends on `agus_design` only. This keeps design iteration fast while allowing `example/` to inherit the same package when the map example builds.

## Current doc inventory

```text
doc/API.md
doc/ARCHITECTURE-ANDROID.md
doc/ARCHIVING.md
doc/BUILD-CONFIGURATION.md
doc/COMAPS-ASSETS.md
doc/CONTRIBUTING.md
doc/COPYING.md
doc/DART-HOOKS.md
doc/IMPLEMENTATION-ANDROID.md
doc/IMPLEMENTATION-CI-CD.md
doc/IMPLEMENTATION-IOS.md
doc/IMPLEMENTATION-LINUX.md
doc/IMPLEMENTATION-LOCALISATION.md
doc/IMPLEMENTATION-MACOS.md
doc/IMPLEMENTATION-MELOS-MONOREPO.md
doc/IMPLEMENTATION-NATIVE-MESSAGE-PASSING.md
doc/IMPLEMENTATION-NAVIGATION.md
doc/IMPLEMENTATION-SEARCH.md
doc/IMPLEMENTATION-SKIN-GENERATOR-DART.md
doc/IMPLEMENTATION-WIN-IMPROVEMENT.md
doc/IMPLEMENTATION-WIN-OVERLAY.md
doc/IMPLEMENTATION-WIN.md
doc/MAP-WIDGET-PARTS.md
doc/MONOREPO.md
doc/PATCHING-GUIDE.md
doc/PLAN-SWIFT-PM.md
doc/PLAN-WASM.md
doc/RELEASE.md
doc/RENDER-LOOP.md
doc/UI-LAYOUT.md
doc/WIDGETBOOK.md
doc/IMPL-01-fix-mwm-registration.md
doc/IMPL-02-mwm-metadata-storage.md
doc/IMPL-03-mirror-service.md
doc/IMPL-04-map-downloads-page.md
doc/IMPL-05-place-page-drawer.md
doc/issues/ISSUE-LOCALISATION.md
doc/issues/ISSUE-arena-allocator-ffi.md
doc/issues/ISSUE-data-extraction-cold-start.md
doc/issues/ISSUE-debug-logging-release.md
doc/issues/ISSUE-dpi-mismatch-surface.md
doc/issues/ISSUE-egl-context-recreation.md
doc/issues/ISSUE-event-stream-lifecycle.md
doc/issues/ISSUE-ffi-string-allocation.md
doc/issues/ISSUE-indexed-stack-memory.md
doc/issues/ISSUE-jni-reflection-overhead.md
doc/issues/ISSUE-linux-pixel-buffer-copy.md
doc/issues/ISSUE-macos-resize-white-screen.md
doc/issues/ISSUE-pigeon-async-overhead.md
doc/issues/ISSUE-placepage-deep-copy.md
doc/issues/ISSUE-touch-event-throttling.md
doc/issues/ISSUE-windows-symbol-loading.md
doc/layouts/PROGRESS.md
doc/layouts/README.md
doc/layouts/desktop/README.md
doc/layouts/mobile-landscape/README.md
doc/layouts/mobile-portrait/README.md
doc/layouts/tablet/README.md
doc/schemas/LAYERS.md
doc/schemas/MANUAL-TESTING.md
doc/schemas/MIGRATION.md
doc/schemas/PLAN-PROGRESS.md
doc/schemas/README.md
doc/schemas/migrations/20260502_001_initial_duckdb_layers.sql
doc/schemas/migrations/20260505_001_remove_layer_child_foreign_keys.sql
```
