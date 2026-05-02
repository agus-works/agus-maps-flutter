# DuckDB Layers Plan and Progress

Last updated: 2026-05-03

This document is the technical handoff for the DuckDB persistence, analytics, and native layer-rendering work in `agus_maps_flutter`. It is intended to be sufficient context for continuing the implementation later or with another AI coding agent.

## Objective

Add DuckDB as the embedded persistence and analytics layer for user drawings, layer metadata, preset data layers, custom query layers, and geospatial data sources such as GeoParquet. DuckDB-backed layers must render through the native CoMaps/Drape map widget, not through a Flutter overlay, so map interaction, panning, zooming, and visual composition stay consistent with the existing rendering engine.

The rollout order is macOS first, then iOS, Android, Windows, and Linux. macOS was the proving ground because it shares the Apple static framework packaging model with iOS and gives the fastest native iteration loop. iOS packaging now builds successfully; the next major platform target is Android.

## Architecture Principles

- Keep DuckDB private to the plugin/app bundle. Never rely on a user's machine-wide DuckDB installation.
- Mirror the existing CoMaps dependency discipline: pinned refs, deterministic checkout, local patch directories, and explicit CI/release metadata.
- Keep first-party app data in strict plugin-owned tables. Custom user SQL is unrestricted, but renderable query layers must satisfy a strict result contract.
- Use DuckDB Spatial `GEOMETRY` in WGS84/EPSG:4326 as the database geometry representation. Convert to CoMaps Mercator coordinates in native code before Drape rendering.
- Keep native rendering in Drape from the first renderable implementation. Points and lines should use existing user-mark/user-line paths first; filled polygons should use an area primitive/Drape patch only when needed.
- Keep CoMaps behavior unchanged unless a small, isolated rendering patch is required for filled polygon support.
- Keep build outputs reproducible and platform-local: Apple uses static `DuckDB.xcframework`, Android should fold DuckDB into one `libagus_maps_flutter.so`, Windows should use a private DuckDB DLL, and Linux should use a private shared library.

## Key Decisions

- DuckDB core is a root submodule at `thirdparty/duckdb`.
- duckdb-spatial is a separate root submodule at `thirdparty/duckdb-spatial` because `spatial` is out-of-tree.
- DuckDB is pinned to `v1.5.2` (`8a5851971fae891f292c2714d86046ee018e9737`).
- duckdb-spatial is pinned to `dc1996bfd16bd8614fb4ccb5895b3ee0dbd4298e`, the ref used by DuckDB `v1.5.2` release configuration.
- duckdb-spatial nested submodules are initialized at:
  - `thirdparty/duckdb-spatial/duckdb`: `ebf0f8fde4249b6489dd33bec03b041dc4d2fff2`
  - `thirdparty/duckdb-spatial/extension-ci-tools`: `795096d04b009c0d087468439ebb526a5460dfac`
- Required extensions are `core_functions`, `parquet`, `json`, `icu`, `httpfs`, and `spatial`.
- `httpfs` is out-of-tree for DuckDB `v1.5.2`; it is pinned through DuckDB's release config to `duckdb-httpfs` commit `13e18b3c9f3810334f5972b76a3acc247b28e537`.
- The app database path currently used by the first bridge is `writablePath/agus_layers.duckdb`.
- The first bridge scope is lifecycle/health/SQL/migration execution only. It is wired through the macOS and iOS podspecs. Query-result serialization, layer CRUD, backups, and rendering refresh are still pending.

## Current File Map

### Dependency and Build Pins

- `.gitmodules`: root submodule registry for `thirdparty/duckdb` and `thirdparty/duckdb-spatial`.
- `.github/workflows/devops.yml`: exposes `DUCKDB_TAG` and `DUCKDB_SPATIAL_TAG` in CI/release metadata. Full CI build/cache/package steps for DuckDB are still pending.
- `tool/src/config.dart`: default DuckDB and duckdb-spatial refs plus `getDuckdbTag()` and `getDuckdbSpatialTag()`.
- `tool/src/platform_detector.dart`: path helpers for DuckDB, duckdb-spatial, and dependency-specific patch directories.

### Dependency Bootstrap and Patches

- `tool/src/git_operations.dart`: generic git/submodule helpers used by CoMaps and DuckDB dependencies.
- `tool/src/patch_applicator.dart`: generic dependency patch application while preserving CoMaps patch behavior.
- `tool/src/build_runner.dart`: bootstraps DuckDB and duckdb-spatial after CoMaps and before native platform builds.
- `patches/duckdb/README.md`: placeholder and policy for DuckDB patches.
- `patches/duckdb-spatial/README.md`: placeholder and policy for duckdb-spatial patches.

### DuckDB Build

- `tool/duckdb/agus_duckdb_extensions.cmake`: project-owned extension config. It explicitly loads `core_functions`, `parquet`, `json`, `icu`, pinned out-of-tree `httpfs`, and `spatial` from `thirdparty/duckdb-spatial`.
- `tool/src/duckdb_build.dart`: DuckDB build helper. Current implemented Apple outputs are macOS universal static `DuckDB.xcframework` and iOS static `DuckDB.xcframework` with device and simulator slices.
- `macos/agus_maps_flutter.podspec`: now vendors both `CoMaps.xcframework` and `DuckDB.xcframework`, compiles the platform-local `Classes/agus_duckdb_bridge.mm` wrapper for the shared DuckDB bridge implementation, and adds DuckDB header search paths.
- `ios/agus_maps_flutter.podspec`: now vendors both `CoMaps.xcframework` and `DuckDB.xcframework`, compiles the platform-local `Classes/agus_duckdb_bridge.mm` wrapper for the shared DuckDB bridge implementation, and adds DuckDB header search paths for device and simulator XCFramework slices.

### Native Bridge and Dart API

- `src/agus_maps_flutter.h`: public C ABI declarations for the initial DuckDB bridge.
- `src/agus_duckdb_bridge.cpp`: initial DuckDB bridge implementation.
- `lib/agus_maps_flutter_bindings_generated.dart`: regenerated ffigen bindings including DuckDB bridge functions.
- `lib/agus_maps_flutter.dart`: Dart convenience helpers for Apple-platform DuckDB bridge calls.

### Schema Documentation

- `doc/schemas/README.md`: database scope, required extensions, layer kinds, and query render contract.
- `doc/schemas/MIGRATION.md`: migration strategy and backup policy.
- `doc/schemas/migrations/20260502_001_initial_duckdb_layers.sql`: first schema migration.
- `doc/schemas/PLAN-PROGRESS.md`: this handoff document.

## Implemented So Far

### Dependency Foundation

- Added root submodules for DuckDB and duckdb-spatial.
- Added build config defaults and environment-variable accessors for DuckDB pins.
- Generalized submodule checkout and patch application tooling without changing the CoMaps patch model.
- Added empty patch directories for future DuckDB and duckdb-spatial changes.
- Added CI/release metadata visibility for DuckDB and duckdb-spatial refs.

### Extension Configuration

- Added `tool/duckdb/agus_duckdb_extensions.cmake` with the required extension set.
- `spatial` is loaded from the local `thirdparty/duckdb-spatial` source checkout.
- `httpfs` is pinned from the out-of-tree `duckdb-httpfs` repository because it is not present as an in-tree extension in DuckDB `v1.5.2`.

### macOS DuckDB Packaging

- Added `tool/src/duckdb_build.dart` to build DuckDB separately from CoMaps.
- The helper generates DuckDB's merged vcpkg manifest for out-of-tree extension dependencies.
- The helper fetches the DuckDB-generated vcpkg builtin baseline into `VCPKG_ROOT` if a local vcpkg checkout does not already contain it.
- The helper builds macOS `arm64` and `x86_64` slices, merges DuckDB, extension, and vcpkg static archives, then produces a universal `DuckDB.xcframework`.
- `tool/src/build_runner.dart` now calls `buildDuckDBMacOSXCFramework()` from the macOS platform build and copies `DuckDB.xcframework` into `macos/Frameworks` beside CoMaps.

### iOS DuckDB Packaging

- Added `buildDuckDBiOSXCFramework()` to `tool/src/duckdb_build.dart`.
- The iOS helper builds device `arm64`, simulator `arm64`, and simulator `x86_64` DuckDB static archives, merges DuckDB, extension, and vcpkg static archives per slice, then packages a static `DuckDB.xcframework`.
- The simulator archive is created with `lipo` from the `arm64` and `x86_64` simulator builds before `xcodebuild -create-xcframework` packages it beside the device archive.
- The helper generates project-owned vcpkg overlay triplets under `build/duckdb/ios/vcpkg-triplets`:
  - `arm64-ios-agus`
  - `arm64-ios-simulator-agus`
  - `x64-ios-simulator-agus`
- The overlay triplets force `HAVE_PIPE2=0` for vcpkg CMake packages. This fixes curl `8.17.0` mis-detecting `pipe2` on the Xcode `iPhoneSimulator26.4.sdk`, where `pipe2` is not declared.
- iOS CMake builds pass explicit `CMAKE_SYSTEM_NAME=iOS`, `CMAKE_SYSTEM_PROCESSOR`, a generated `CMAKE_PROJECT_TOP_LEVEL_INCLUDES` file that forces the processor cache value early, and `DUCKDB_EXPLICIT_PLATFORM` so DuckDB does not try to execute a cross-compiled platform detector binary on macOS.
- `tool/src/build_runner.dart` now calls `buildDuckDBiOSXCFramework()` from the iOS platform build and copies `DuckDB.xcframework` into `ios/Frameworks` beside CoMaps.
- `ios/agus_maps_flutter.podspec` now vendors `DuckDB.xcframework`, compiles `ios/Classes/agus_duckdb_bridge.mm`, and includes DuckDB headers.

### Apple Native Bridge

The initial bridge in `src/agus_duckdb_bridge.cpp` exposes:

- `agus_duckdb_library_version()`
- `agus_duckdb_last_error()`
- `agus_duckdb_open_app_database(writablePath)`
- `agus_duckdb_close()`
- `agus_duckdb_is_open()`
- `agus_duckdb_load_required_extensions()`
- `agus_duckdb_execute(sql)`
- `agus_duckdb_apply_migration_file(path)`

The bridge currently opens `writablePath/agus_layers.duckdb`, loads required extensions, executes arbitrary SQL, and can execute a migration SQL file. It is guarded by a mutex and maintains a last-error string for Dart callers.

Current limitations:

- The bridge uses `duckdb_open`, not `duckdb_open_ext`, so advanced config options are not wired yet.
- Extension verification currently relies on `LOAD <extension>` success. It does not yet query `duckdb_extensions()` to verify loaded/available status.
- Migrations are not yet embedded or checksummed at runtime. The bridge can execute a SQL file, but a full migration runner remains pending.
- No query result extraction, JSON result encoding, layer CRUD, feature CRUD, checkpoint/backup, or render refresh APIs yet.
- Dart wrappers intentionally throw `UnsupportedError` outside Apple platforms until Android/native builds are wired.

### Dart API

`lib/agus_maps_flutter.dart` now exposes Apple-platform helpers:

- `duckDBLibraryVersion()`
- `duckDBLastError()`
- `openDuckDBAppDatabase(String writablePath)`
- `closeDuckDB()`
- `isDuckDBOpen()`
- `executeDuckDBSql(String sql)`
- `applyDuckDBMigrationFile(String path)`

These are intentionally small bridge helpers, not the final layer-management API.

### Schema Baseline

The first migration creates:

- `agus.schema_migrations`
- `agus.app_metadata`
- `agus.layers`
- `agus.layer_features`
- `agus.query_layers`
- `agus.layer_metadata`
- `agus.layer_render_cache`

The schema includes strict layer kinds, `GEOMETRY` feature storage, JSON properties/style/metadata, bbox columns for viewport filtering, visibility/z-order columns, soft-delete timestamps, and render cache metadata.

## Validation Completed

### Submodule Pins

Validated with direct nested git checks:

```bash
git -C thirdparty/duckdb rev-parse HEAD
git -C thirdparty/duckdb describe --tags --always --dirty
git -C thirdparty/duckdb-spatial rev-parse HEAD
git -C thirdparty/duckdb-spatial describe --tags --always --dirty
git -C thirdparty/duckdb-spatial/duckdb rev-parse HEAD
git -C thirdparty/duckdb-spatial/extension-ci-tools rev-parse HEAD
```

Observed refs:

- DuckDB: `8a5851971fae891f292c2714d86046ee018e9737`, `v1.5.2`
- duckdb-spatial: `dc1996bfd16bd8614fb4ccb5895b3ee0dbd4298e`, described as `v0.9.1-962-gdc1996b`
- spatial nested DuckDB: `ebf0f8fde4249b6489dd33bec03b041dc4d2fff2`
- spatial nested extension-ci-tools: `795096d04b009c0d087468439ebb526a5460dfac`

### macOS DuckDB Build

Validated both macOS slices:

- `arm64` CMake configure passed and linked all required extensions.
- `arm64` build completed.
- `x86_64` CMake configure passed and linked all required extensions.
- `x86_64` build completed.
- Static archives were merged with `libtool`.
- Universal `build/agus-binaries-macos/libagus_duckdb.a` was created with `x86_64 arm64` architectures.
- `build/agus-binaries-macos/DuckDB.xcframework` was created successfully.
- The generated framework was copied to `macos/Frameworks/DuckDB.xcframework` for local macOS builds.

### macOS Runtime Extension Smoke Test

Validated against the built macOS `arm64` DuckDB dylib with Python `ctypes`:

```sql
LOAD core_functions;
LOAD parquet;
LOAD json;
LOAD icu;
LOAD httpfs;
LOAD spatial;
SELECT ST_AsText(ST_Point(1, 2));
```

All required `LOAD` statements returned success and DuckDB reported `v1.5.2`.

### iOS DuckDB Build

Validated through the contributor iOS build:

```bash
env -u AGUS_MAPS_HOME AGUS_MAPS_BUILD_MODE=contributor \
  dart run tool/build.dart --build-binaries --platform ios 2>&1 | tee ./output.log
```

Observed results:

- CoMaps iOS `CoMaps.xcframework` was built successfully.
- DuckDB extension configuration completed with the required extension set.
- DuckDB iOS device `arm64` built successfully.
- DuckDB iOS simulator `arm64` built successfully.
- DuckDB iOS simulator `x86_64` built successfully.
- `build/agus-binaries-ios/DuckDB.xcframework` was created successfully.
- `ios/Frameworks/DuckDB.xcframework` was copied for local CocoaPods integration.
- `pod install` completed for `example/ios`.

Artifact checks:

```bash
find build/agus-binaries-ios/DuckDB.xcframework ios/Frameworks/DuckDB.xcframework \
  -maxdepth 3 -type f -name 'libagus_duckdb.a'

lipo -info \
  build/agus-binaries-ios/DuckDB.xcframework/ios-arm64/libagus_duckdb.a \
  build/agus-binaries-ios/DuckDB.xcframework/ios-arm64_x86_64-simulator/libagus_duckdb.a
```

Observed architectures:

- Device slice: `arm64`
- Simulator slice: `x86_64 arm64`

The rebuilt curl simulator configs under the project-owned triplets record `HAVE_PIPE2:UNINITIALIZED=0` and generate `/* #undef HAVE_PIPE2 */`.

### iOS Simulator App Build

An actual example iOS simulator build was started after the successful iOS `DuckDB.xcframework` packaging. CocoaPods integration progressed far enough to compile/link the plugin target, but the first direct `xcodebuild` run failed at link time with duplicate symbols.

The failing log confirmed two duplicate-symbol groups:

- CoMaps `libcomaps.a` and DuckDB `libagus_duckdb.a` both expose ICU symbols such as `_ubidi_getVisualMap`, `_utrace_data`, and `_umutablecptrie_open`.
- DuckDB's merged static archive contains repeated dependency/loader objects such as `sds.cpp.o`, `bitpacking.cpp.o`, JPEG objects, `strerror_override.c.o`, zstd objects, and both `dummy_static_extension_loader.cpp.o` and `generated_extension_loader.cpp.o`.

The immediate root cause for the hard failure was `-all_load` in `ios/agus_maps_flutter.podspec`. `-all_load` forced every object from every static archive into `agus_maps_flutter.framework`, surfacing duplicates that normal archive selection can otherwise leave unselected. The iOS podspec was changed from `-ObjC -all_load` to `-ObjC`, `pod install` was rerun, and direct simulator `xcodebuild` succeeded for the installed iPhone 17 simulator.

Validated command from the repo root:

```bash
cd example/ios && \
  xcodebuild \
    -workspace Runner.xcworkspace \
    -scheme Runner \
    -configuration Debug \
    -sdk iphonesimulator \
    -destination 'id=B22FD4B7-2890-47C3-B132-883948758375' \
    build 2>&1 | tee ../../output.log
```

Result: `** BUILD SUCCEEDED **`.

Flutter tool validation also passed:

```bash
cd example && \
  flutter build ios --simulator 2>&1 | tee ../output.log
```

Result: Flutter built `build/ios/iphonesimulator/Runner.app` successfully.

The example app now includes an About-tab DuckDB smoke status card. It uses the public Dart bridge helpers to read the linked DuckDB version, open the app-support database, let the native bridge load the required extensions, and execute `SELECT ST_AsText(ST_Point(1, 2));`. Because the example app keeps tabs alive through an `IndexedStack`, the card is built during app startup even when the Map tab is selected.

After adding the card, targeted analysis and Apple builds were rerun:

```bash
cd example && \
  flutter analyze lib/about_tab.dart 2>&1 | tee ../output.log

cd example && \
  flutter build ios --simulator 2>&1 | tee ../output.log

cd example && \
  flutter build macos 2>&1 | tee ../output.log
```

Results: analysis reported only pre-existing `withOpacity` deprecation infos in `about_tab.dart`; both iOS simulator and macOS builds succeeded after the smoke card was added.

The same linker-flag cleanup was applied to `macos/agus_maps_flutter.podspec` to keep Apple podspecs aligned. The Flutter macOS release example build passed:

```bash
cd example && \
  flutter build macos 2>&1 | tee ../output.log
```

Result: Flutter built `build/macos/Build/Products/Release/agus_maps_flutter_example.app` successfully. The macOS log only showed duplicate `-lc++` and missing Metal toolchain Swift search-path warnings, not duplicate symbols.

### May 3 Apple Runtime Symbol and Extension Loader Fixes

The first physical iPhone and Mac smoke run failed in the About tab with:

```text
Failed to lookup symbol 'agus_duckdb_library_version': dlsym(...): symbol not found
```

The C ABI declarations and Dart bindings were correct, but the bridge implementation was not being compiled into the Apple plugin frameworks. `nm -gU` on the built iPhoneOS and macOS plugin frameworks showed `_sum` and `_comaps_init`, but no `_agus_duckdb_*` exports. Grepping the generated Pods projects showed no `agus_duckdb_bridge` source entry.

Fix applied:

- Added `ios/Classes/agus_duckdb_bridge.mm`, which includes `../../src/agus_duckdb_bridge.cpp`.
- Added `macos/Classes/agus_duckdb_bridge.mm`, which includes `../../src/agus_duckdb_bridge.cpp`.
- Removed direct `../src/agus_duckdb_bridge.cpp` entries from both Apple podspec `s.source_files` lists, because CocoaPods was not placing that outside-`Classes` C++ source into the generated Pods projects.
- Reran `pod install` for `example/ios` and `example/macos`.

Validation after the wrapper fix:

- Generated `example/ios/Pods/Pods.xcodeproj/project.pbxproj` and `example/macos/Pods/Pods.xcodeproj/project.pbxproj` both include `agus_duckdb_bridge.mm in Sources`.
- Standalone wrapper compile emitted `_agus_duckdb_library_version` and `_agus_duckdb_open_app_database`.
- `flutter build ios --debug --no-codesign` succeeded and built `build/ios/iphoneos/Runner.app`.
- `flutter build ios --simulator` succeeded and built `build/ios/iphonesimulator/Runner.app`.
- The rebuilt iPhoneOS and simulator plugin frameworks export all `agus_duckdb_*` C ABI symbols.

Once the bridge actually linked DuckDB, macOS surfaced the real static-library conflict: DuckDB's bundled ICU 66.1 symbols collided with CoMaps' bundled ICU 75.1 symbols. The build helper now generates an Apple-only force-include header from DuckDB's vendored `extension/icu/third_party/icu/common/unicode/urename.h`. The generated header prefixes DuckDB's ICU C and C++ symbols with `agus_duckdb_icu_` during DuckDB Apple builds.

Validation for ICU isolation:

- A compile probe against DuckDB `ucase.cpp` emitted `_agus_duckdb_icu_u_isUUppercase` instead of `_u_isUUppercase`.
- Rebuilt macOS `DuckDB.xcframework`; `lipo -info` reports `x86_64 arm64`.
- Rebuilt iOS `DuckDB.xcframework`; device slice reports `arm64`, simulator slice reports `x86_64 arm64`.
- `nm -gU` on both rebuilt Apple DuckDB archives shows `_agus_duckdb_icu_u_isUUppercase` and `_duckdb_library_version`.
- `flutter build macos --debug`, `flutter build ios --debug --no-codesign`, and `flutter build ios --simulator` all succeeded with the prefixed DuckDB frameworks installed.

After that, a macOS `ctypes` smoke test reached DuckDB but failed on `LOAD core_functions` because the generated static extension loader was still being left out by normal archive selection. The bridge now makes a tiny Apple-only reference to DuckDB's generated `duckdb::LinkedExtensions()` symbol. That pulls `generated_extension_loader.cpp.o` and the required static extension objects into the final plugin without reintroducing `-all_load`.

Validation for static extension loading:

- `nm -a` on the macOS plugin now shows `duckdb::LinkedExtensions`, `duckdb::ExtensionHelper::LoadExtension`, and `CoreFunctionsExtension` symbols.
- `nm -a` on the iPhoneOS and simulator plugin frameworks shows the same generated loader path and prefixed ICU symbol.
- macOS runtime smoke via `ctypes` against `example/build/macos/Build/Products/Debug/agus_maps_flutter/agus_maps_flutter.framework` now reports:

```text
version=v1.5.2
open=1
spatial_query=1
is_open=1
```

User validation on May 3 confirmed the About-tab DuckDB smoke status reports spatial query success on both macOS and a physical iPhone 15. This confirms the missing-symbol fix, Apple ICU prefixing, generated static extension loader retention, and required extension loading are working in the real Flutter UI on Apple targets.

### May 3 Android Integration Scoping

The next implementation target is Android. The repository already has the right high-level shape for this: Android should continue shipping one plugin shared library per ABI, `libagus_maps_flutter.so`, and DuckDB should be statically folded into that shared library rather than packaged as a second runtime library.

Relevant Android integration points identified on May 3:

- `android/build.gradle` detects in-repo source builds and points Gradle `externalNativeBuild.cmake.path` at `../src/CMakeLists.txt`.
- External/consumer Android mode already consumes `android/prebuilt/<abi>/libagus_maps_flutter.so` through `jniLibs`, so the release distribution shape should not need a second DuckDB artifact.
- `src/CMakeLists.txt` builds the Android plugin target from `agus_maps_flutter.cpp`, `agus_platform.cpp`, `agus_localization.cpp`, `agus_ogl.cpp`, and `agus_gui_thread.cpp`, then links CoMaps static libraries into the same shared target.
- `tool/src/cmake_build.dart` builds Android ABI outputs into `build/android-<abi>/libagus_maps_flutter.so` and copies them to `build/agus-binaries-android/<abi>/libagus_maps_flutter.so`.
- DuckDB upstream Android CI builds with `ANDROID_ABI=<abi>`, the NDK CMake toolchain, `EXTENSION_STATIC_BUILD=1`, `DUCKDB_PLATFORM=android_<abi>`, and `DUCKDB_CUSTOM_PLATFORM=android_<abi>`.
- DuckDB's platform helper appends `_android` for Android, but explicit `DUCKDB_EXPLICIT_PLATFORM=android_<abi>` is still the safer path because this project is cross-compiling and needs predictable static extension metadata.

Android-specific implementation implications:

- `src/CMakeLists.txt` needs to compile `src/agus_duckdb_bridge.cpp` for Android as part of `agus_maps_flutter`.
- `lib/agus_maps_flutter.dart` should allow `Platform.isAndroid` only after Android native linkage is validated.
- The bridge's generated-loader retention should be extended from Apple to Android so `LOAD core_functions`, `LOAD spatial`, and the rest resolve to statically linked extensions instead of looking for `.duckdb_extension` files.
- DuckDB's bundled ICU should also be prefixed for Android, just like Apple, because CoMaps also brings bundled ICU into the same final shared library.
- The Android DuckDB build helper should produce ABI-specific static archives and any needed vcpkg static libraries before the final plugin CMake build links `libagus_maps_flutter.so`.
- ABI mapping should start with the existing Flutter plugin ABI list: `arm64-v8a`, `armeabi-v7a`, and `x86_64`. Candidate DuckDB/vcpkg mapping is `android_arm64-v8a`, `android_armeabi-v7a`, and `android_x86_64` for DuckDB platform names, with vcpkg triplets likely `arm64-android`, `arm-neon-android`, and `x64-android` unless project-owned overlay triplets prove necessary.
- Android linker validation should include exported `agus_duckdb_*` symbols, generated static extension loader symbols, prefixed `agus_duckdb_icu_*` symbols, and absence of raw DuckDB ICU collisions with CoMaps.

### May 3 Android Implementation Progress

Implementation progress after the Android scoping pass:

- `tool/src/duckdb_build.dart` now has `buildDuckDBAndroidArchives()`, which builds ABI-specific DuckDB static archive bundles before the final Android plugin build.
- Android DuckDB builds reuse the project DuckDB extension config, merged vcpkg manifest generation, required extension list, and DuckDB ICU prefixing strategy already proven on Apple.
- Project-owned Android vcpkg overlay triplets are generated for `arm64-v8a`, `armeabi-v7a`, and `x86_64` so the ABI mapping is explicit and the NDK chainload toolchain is under project control.
- `tool/src/cmake_build.dart` now lets CMake builds receive extra environment values; the Android DuckDB build passes `ANDROID_NDK_HOME`, `ANDROID_NDK_ROOT`, and `ANDROID_NDK` so vcpkg/Android package configuration can find the same NDK used by the plugin build.
- `tool/src/build_runner.dart` now builds the DuckDB Android archive root before each Android plugin ABI and passes `AGUS_DUCKDB_ANDROID_DIR` into `buildAndroidAbi()`.
- `src/CMakeLists.txt` now compiles `agus_duckdb_bridge.cpp` for Android, loads the generated per-ABI DuckDB bundle metadata, adds DuckDB headers, and links the DuckDB/vcpkg static archives into `libagus_maps_flutter.so` with an Android linker group.
- `src/agus_duckdb_bridge.cpp` now retains DuckDB's generated static extension loader on Android, matching the Apple fix that kept `LOAD spatial` from falling back to external `.duckdb_extension` files.
- `lib/agus_maps_flutter.dart` now allows the DuckDB bridge on Android in addition to macOS and iOS.

Current validation target:

1. Run the Android build through `dart run tool/build.dart --build-binaries --platform android` and keep the full output in `android-duckdb-build.log`.
2. If the first build fails during DuckDB/vcpkg Android configuration, inspect the log around the first `error:`/`CMake Error` and adjust only the Android triplet/toolchain variables.
3. After the first successful ABI output, inspect `build/agus-binaries-android/<abi>/libagus_maps_flutter.so` for exported `agus_duckdb_*` symbols, generated loader retention, and prefixed `agus_duckdb_icu_*` symbols.
4. After all ABIs build, run the Android example smoke UI on device/emulator and confirm the About tab reports DuckDB version, database open, and spatial query success.

Validation update after resuming on May 3:

- No terminal process from the previous attempt was still active. The saved `android-duckdb-build.log` had 5,170 lines and ended with `android build complete` plus `=== Build Complete ===`.
- `build/agus-binaries-android/arm64-v8a/libagus_maps_flutter.so`, `build/agus-binaries-android/armeabi-v7a/libagus_maps_flutter.so`, and `build/agus-binaries-android/x86_64/libagus_maps_flutter.so` were all produced.
- Android output sizes are currently large because the debug shared libraries are unstripped and statically include CoMaps plus DuckDB: approximately 1.1 GB for `arm64-v8a`, 954 MB for `armeabi-v7a`, and 1.1 GB for `x86_64`.
- `android-duckdb-symbol-summary.log` confirms each ABI exports all eight bridge symbols: `agus_duckdb_library_version`, `agus_duckdb_last_error`, `agus_duckdb_open_app_database`, `agus_duckdb_close`, `agus_duckdb_is_open`, `agus_duckdb_load_required_extensions`, `agus_duckdb_execute`, and `agus_duckdb_apply_migration_file`.
- The same symbol check confirms each ABI contains DuckDB's generated static extension loader path, including `duckdb::LinkedExtensions()`, `CoreFunctionsExtension`, and `SpatialExtension` symbols.
- The same symbol check confirms each ABI contains the prefixed ICU sample symbol `agus_duckdb_icu_u_isUUppercase`, so the Android DuckDB ICU-prefixing strategy is present in the final plugin shared library.
- `adb devices -l` and `flutter devices` detected a physical Android device, `SM G973F` (`RF8M20SAQSL`, Android 12/API 31, `android-arm64`). The next validation step is a non-resident Flutter launch/install against this device, followed by About-tab smoke verification.
- The first non-resident `flutter run --debug --no-resident -d RF8M20SAQSL` failed during Gradle CMake configuration because Flutter requested unsupported `ANDROID_ABI=x86`. This is outside the documented plugin ABI contract and there is no DuckDB Android bundle at `build/agus-binaries-android-duckdb/x86`.
- Fix in progress: constrain Android source builds to the supported ABI set in both the plugin Gradle file and the example app Gradle file: `arm64-v8a`, `armeabi-v7a`, and `x86_64`.
- Runtime fix: linking DuckDB spatial pulled vcpkg `json-c`, whose `json_object_get`/`json_object_iter_next` symbols collided with CoMaps' Jansson symbols. Android CMake now force-loads CoMaps Jansson before the DuckDB/json-c archive group so `countries.txt` parsing binds to the correct JSON ABI.
- `flutter build apk --debug --target-platform android-arm64` now completes, and the rebuilt Android shared library resolves `json_object_get` next to Jansson's `json_loads`/`json_integer_value` symbols instead of json-c.
- Android device smoke passed on `SM G973F`: the example launches to the Map tab, `countries.txt` parses successfully, the map surface is created, three bundled MWMs register, and the About-tab DuckDB card reports `DuckDB v1.5.2` with `Database open • required extensions loaded • spatial query ok`.
- Release-mode Android source smoke also passed from the example app directory with `flutter run -d RF8M20SAQSL --release`: Gradle built CoMaps from source, produced `build/app/outputs/flutter-apk/app-release.apk` at 435.0 MB, installed it on the same device, and the About-tab DuckDB card reported spatial query success.

If the simulator destination changes, list destinations with:

```bash
cd example/ios && \
  xcodebuild \
    -workspace Runner.xcworkspace \
    -scheme Runner \
    -showdestinations 2>&1 | tee ../../output.log
```

### Code and Tooling Checks

Completed checks:

- `clang++ -std=c++17 -I src -I thirdparty/duckdb/src/include -c src/agus_duckdb_bridge.cpp -o /tmp/agus_duckdb_bridge.o`
- `ruby -c macos/agus_maps_flutter.podspec`
- `ruby -c ios/agus_maps_flutter.podspec`
- `dart run ffigen --config ffigen.yaml`
- `dart format` on edited Dart files
- `dart analyze lib/agus_maps_flutter.dart lib/agus_maps_flutter_bindings_generated.dart tool/src/duckdb_build.dart`
- `git diff --check`
- `dart run tool/build.dart --help`
- VS Code diagnostics on edited bridge, header, Dart, podspec, build helper, CMake config, and docs

Known analyzer output:

- `tool/src/duckdb_build.dart` currently reports `avoid_print` info lints, consistent with the existing build-tool style.
- Broader targeted analysis of build tooling still reports existing script-style `print` info lints and a pre-existing unused helper warning in `tool/src/build_runner.dart`.

## Current Worktree Notes

The submodules are present in the working tree but currently unstaged. Until `.gitmodules` and gitlink entries are staged, `git submodule status thirdparty/duckdb thirdparty/duckdb-spatial` will not know those paths. Use direct `git -C` checks for pin validation before staging.

Generated build outputs under `build/` and framework outputs under `macos/Frameworks/` and `ios/Frameworks/` are ignored. The source changes that matter are the root submodule metadata, tooling, bridge, Dart bindings/API, podspecs, docs, schema files, and the `example/ios/Podfile.lock` plus `example/macos/Podfile.lock` checksum updates caused by the Apple podspec changes.

## Important Build Lessons

- DuckDB's merged vcpkg manifest target assumes `thirdparty/duckdb/build/extension_configuration` exists. The build helper creates it before running `duckdb_merge_vcpkg_manifests`.
- DuckDB's generated vcpkg manifest pins builtin baseline `84bab45d415d22042bd0b9081aea57f362da3f35`. Newer or shallow local vcpkg checkouts may not contain that commit. The build helper fetches it when missing.
- Do not set `CMAKE_SYSTEM_NAME=Darwin` for native macOS DuckDB builds. It causes vcpkg package config version checks, notably PROJ, to think the build is cross-compiled and reject otherwise valid packages.
- `duckdb_static` alone is not enough for packaging the required static extensions. Build the default DuckDB target set so extension archives and the generated static extension loader are produced, then merge all relevant static archives.
- `libtool` emits many harmless `has no symbols` warnings when merging vcpkg archives. The successful `lipo -info` and `xcodebuild -create-xcframework` outputs are the important artifact checks.
- For iOS DuckDB/vcpkg builds, pass `CMAKE_SYSTEM_NAME=iOS`, force `CMAKE_SYSTEM_PROCESSOR` early through `CMAKE_PROJECT_TOP_LEVEL_INCLUDES`, and pass `DUCKDB_EXPLICIT_PLATFORM` for each slice. Without this, PROJ package config can reject the target or DuckDB can try to execute a cross-compiled platform detector binary.
- vcpkg curl `8.17.0` can mis-detect `pipe2` for `arm64-ios-simulator` with the Xcode `iPhoneSimulator26.4.sdk`. The project-owned iOS vcpkg triplets pass `-DHAVE_PIPE2=0`, which makes curl generate `/* #undef HAVE_PIPE2 */` and avoids the simulator compile failure in `socketpair.c`.
- The iOS build currently emits many deployment target warnings from GEOS objects built by vcpkg with Xcode SDK version `26.4` while DuckDB links with deployment target `15.6`. These are warnings, not current blockers; revisit if Xcode treats them as fatal in CI.

## Remaining Plan

### 1. Finish Apple Migration Smoke Validation

- Apply `doc/schemas/migrations/20260502_001_initial_duckdb_layers.sql` through the bridge once migrations are embedded or packaged for runtime access.
- Keep the macOS `ctypes` smoke test as the fast local regression check for lookup, open, static extension loading, and spatial SQL.

### 2. Android Single `.so` Integration

Implementation status and next steps:

1. Extend `tool/src/duckdb_build.dart` with `buildDuckDBAndroidArchives()`.
  - Status: implemented and build-validated.
  - Reuse the existing extension config and vcpkg manifest generation.
  - Build one DuckDB static archive bundle per `BuildConfig.androidAbis` ABI.
  - Use the Android NDK CMake toolchain, `ANDROID_PLATFORM=android-24`, `EXTENSION_STATIC_BUILD=TRUE`, `BUILD_SHELL=OFF`, `BUILD_UNITTESTS=OFF`, `BUILD_BENCHMARKS=OFF`, and `DUCKDB_EXPLICIT_PLATFORM=android_<abi>`.
  - Apply the same DuckDB ICU symbol prefixing used for Apple builds.
  - Project-owned Android vcpkg overlay triplets are now generated up front so ABI mapping and NDK chainloading are explicit.

2. Wire Android DuckDB archives into the final plugin CMake target.
  - Status: implemented and link-validated.
  - Add `agus_duckdb_bridge.cpp` to Android `PLATFORM_SOURCES` in `src/CMakeLists.txt`.
  - Add DuckDB headers to Android include paths.
  - Link the ABI-specific DuckDB archive bundle and vcpkg/extension static libraries into `agus_maps_flutter`.
  - Retain the generated static extension loader without `--whole-archive` on unrelated CoMaps archives.
  - Preserve the existing Android link options for 16 KB page size and CoMaps platform-stub overrides.

3. Update Android build orchestration and distribution shape.
  - Status: implemented and artifact-validated.
  - Call the Android DuckDB archive build before `buildAndroidAbi()` in `tool/src/build_runner.dart`.
  - Pass the per-ABI DuckDB archive/header locations into `buildAndroidAbi()` and then into CMake.
  - Keep final outputs as `build/agus-binaries-android/<abi>/libagus_maps_flutter.so` and `android/prebuilt/<abi>/libagus_maps_flutter.so`; do not add a separate DuckDB `.so`.

4. Enable Dart and example smoke on Android.
  - Status: Dart platform gate implemented; native runtime smoke passed.
  - Allow `Platform.isAndroid` in `_ensureDuckDBBridgeSupported()` after the native symbols are present.
  - Reuse the existing About-tab smoke status; it should report DuckDB version, database open, static extension load, and `ST_Point` success on Android.

5. Validate Android in layers.
  - Status: all-ABI native build, symbol validation, debug/source APK build, release/source APK build, and device runtime smoke completed.
  - Completed: built all configured ABIs: `arm64-v8a`, `armeabi-v7a`, and `x86_64`.
  - Completed: inspected the built `.so` outputs with Android NDK `llvm-nm`; all ABIs export the bridge symbols, retain the generated DuckDB static extension loader, and include prefixed DuckDB ICU symbols.
  - Completed: Android source APK build was constrained to the supported arm64 target for smoke validation, then installed and launched on the detected Android device (`SM G973F`, Android 12/API 31).
  - Completed: unrestricted release-mode example launch from `example/` with `flutter run -d RF8M20SAQSL --release` built and installed `app-release.apk` without requesting unsupported `x86`, and the About-tab DuckDB smoke still reported spatial query success.
  - Completed: About-tab DuckDB smoke status reports `DuckDB v1.5.2`, database open, required extensions loaded, and spatial query success.
  - Completed: Android link-order validation confirms CoMaps Jansson is force-loaded before DuckDB/json-c, preventing the `countries.txt` parser from binding to json-c's incompatible `json_object_get` ABI.
  - Follow-up: add stripping/package-size handling for Android artifacts; the validated release APK is functional but still large at 435.0 MB.

Do not run a full Android all-ABI build casually if it looks like vcpkg/DuckDB will take a long time. First implement the build graph and ask the user before kicking off long all-ABI rebuilds.

### 3. Production Migration Runner

- Replace manual `agus_duckdb_apply_migration_file(path)` use with a real migration runner.
- Keep SQL files in `doc/schemas/migrations/` as source of truth.
- Generate embedded migration text/checksums or load packaged migration assets in a deterministic way.
- Use transactions per migration.
- Record non-null checksums in `agus.schema_migrations`.
- Verify already-applied migration checksums at startup.
- Fail startup/rendering if schema state is unknown.

### 4. Query Result API

- Add native query execution that returns results as JSON or an explicit C ABI row/column structure.
- Keep unrestricted SQL execution available for setup/mutation.
- Add a strict validation function for renderable query layers with required columns `feature_id`, `geometry`, and `properties`.

### 5. Layer CRUD and Backup APIs

- Add native/Dart APIs for layers, features, query layers, metadata, style JSON, visibility, z-order, and min/max zoom.
- Add `CHECKPOINT` + file-copy backup API and UI action.
- Ensure backup reports the generated path and handles open database state safely.

### 6. Native Drape Rendering

- Add a DuckDB-backed layer renderer/provider in native code.
- Initial render path should support points and lines through `df::UserMarksProvider`, `df::UserPointMark`, and `df::UserLineMark`.
- Add viewport listener fan-out so DuckDB rendering can react to viewport changes without replacing existing bearing tracking.
- Query visible features by bbox and zoom, convert WGS84 to Mercator in native code, and throttle refreshes.
- Polygon outlines can use line rendering first. Filled polygons should use a Drape area primitive with an isolated CoMaps patch if necessary.

### 7. Dart Layer API and Reusable UI

- Add public layer models/services under `lib/`.
- Add reusable layer/draw widgets under `lib/src/layers/`.
- Integrate the example app with the reusable widgets.
- Make draw mode visually obvious and ensure it captures pointer events rather than forwarding them to map pan/zoom.
- Support pins, lines, segments, polygons/shapes, vertex editing, cancel/commit, and metadata key/value capture.

### 8. Windows and Linux

- Windows: bundle a private DuckDB runtime artifact with required extensions statically linked where possible.
- Linux: bundle private DuckDB runtime artifacts later, following the same no-system-DuckDB rule.

## Suggested Next Commands

Use these as reference, not as commands to run blindly. Let long builds finish before inspecting output.

```bash
env -u AGUS_MAPS_HOME AGUS_MAPS_BUILD_MODE=contributor \
  dart run tool/build.dart --build-binaries --platform macos 2>&1 | tee ./output.log

env -u AGUS_MAPS_HOME AGUS_MAPS_BUILD_MODE=contributor \
  dart run tool/build.dart --build-binaries --platform ios 2>&1 | tee ./output.log

dart run ffigen --config ffigen.yaml 2>&1 | tee ./output.log

dart format lib tool src 2>&1 | tee ./output.log

git diff --check 2>&1 | tee ./output.log
```

## May 3 Resume Point

Current focus: continue to Android packaging. The source/build/doc work already present in the working tree should not be reverted. The missing-symbol runtime failure was fixed by compiling a platform-local bridge wrapper through CocoaPods. DuckDB's bundled ICU is now prefixed for Apple builds, and the bridge retains DuckDB's generated static extension loader without using `-all_load`.

Validated after the latest fixes: macOS debug build passes, macOS `ctypes` smoke reports `version=v1.5.2`, `open=1`, `spatial_query=1`, and `is_open=1`; iPhoneOS debug no-codesign and iOS simulator builds pass; iPhoneOS and simulator plugin frameworks export all `agus_duckdb_*` C ABI symbols and contain the generated loader and prefixed ICU symbols. User UI validation reports spatial query success on macOS and a physical iPhone 15.

Next action: proceed to Android single-`.so` DuckDB integration, keeping the Apple smoke paths as regression checks.

## Open Questions

No product-level questions are blocking the next step. The active technical question is the Android packaging shape for DuckDB, DuckDB Spatial, `httpfs`, and vcpkg/third-party static libraries inside the plugin's single shared library per ABI.
