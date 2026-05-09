# Widgetbook Quick Guide

Widgetbook lives at `widgetbook/` and catalogs `packages/agus_design`. It is intentionally isolated from `agus_maps_flutter`, DuckDB, CoMaps, native binaries, and map assets.

## Setup

From the repository root:

```bash
flutter pub get
dart run melos bootstrap
dart run melos run generate --no-select
```

## Run Widgetbook

```bash
dart run melos run widgetbook --no-select
```

Equivalent direct command:

```bash
cd widgetbook
flutter run -d chrome
```

## Fast design checks

```bash
dart run melos run design:analyze --no-select
dart run melos run design:test --no-select
```

## Adding new use cases

1. Add or update components in `packages/agus_design/lib`.
2. Add Widgetbook use cases under `widgetbook/lib/use_cases`.
3. Regenerate directories with `dart run melos run generate --no-select`.
4. Run Widgetbook and inspect the component states.

Commit the regenerated `widgetbook/lib/main.directories.g.dart` when use cases change.

Keep Widgetbook dependencies limited to `agus_design` unless a future map-specific catalog explicitly needs `agus_maps_flutter`.
