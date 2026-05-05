# Android Implementation Plan

This document started as the Android MVP plan. The current Android target has
advanced beyond file extraction: it now uses a Flutter `Texture` backed by
Android `SurfaceProducer`, renders CoMaps through Drape/OpenGL ES, supports
DuckDB-backed project layers, and has specific guardrails for smooth camera
gestures on physical Android devices.

## Quick Start: Build & Run

### Prerequisites

- Flutter SDK 3.24+ installed
- Android SDK with NDK 29.0.14206865 (or set in `android/build.gradle`)
- A connected Android device or emulator (API 24+)
- ~5GB disk space for CoMaps build artifacts

### Debug Mode (Full debugging, slower)

Debug mode enables hot reload, step-through debugging, and verbose logging for both Flutter and native layers.

**macOS:**
```bash
# 1. Bootstrap all dependencies (first time only)
#    This prepares Android, iOS, and macOS targets
dart run tool/build.dart --no-cache

# 2. Run in debug mode
cd example
flutter run --debug

# For verbose native logs, use logcat:
adb logcat -s AgusMapsFlutterNative:D CoMaps:D AgusGuiThread:D
```

**Windows PowerShell:**
```powershell
# 1. Bootstrap all dependencies (first time only)
#    This prepares Android and Windows targets
dart run tool/build.dart --no-cache

# 2. Run in debug mode
cd example
flutter run --debug

# For verbose native logs, use logcat:
adb logcat -s AgusMapsFlutterNative:D CoMaps:D AgusGuiThread:D
```

**Debug mode characteristics:**
- Flutter: Hot reload enabled, Dart DevTools available
- Native: Debug symbols included, assertions enabled, detailed logging
- Performance: Slower due to debug overhead, unoptimized native code
- APK size: ~300MB+ (includes debug symbols)

### Release Mode (High performance, battery efficient)

Release mode produces an optimized build suitable for production use and accurate performance profiling.

**macOS:**
```bash
# 1. Bootstrap all dependencies (first time only)
dart run tool/build.dart --no-cache

# 2. Build and run in release mode
cd example
flutter run --release

# Or build a direct-install APK for the connected device ABI
flutter build apk --release --split-per-abi
adb install build/app/outputs/flutter-apk/app-arm64-v8a-release.apk

# Build an Android App Bundle for store-style ABI delivery
flutter build appbundle --release
```

**Windows PowerShell:**
```powershell
# 1. Bootstrap all dependencies (first time only)
dart run tool/build.dart --no-cache

# 2. Build and run in release mode
cd example
flutter run --release

# Or build a direct-install APK for the connected device ABI
flutter build apk --release --split-per-abi
adb install build/app/outputs/flutter-apk/app-arm64-v8a-release.apk

# Build an Android App Bundle for store-style ABI delivery
flutter build appbundle --release
```

**Release mode characteristics:**
- Flutter: AOT compiled, tree-shaken, minified
- Native: `-O3` optimization, no debug symbols, no assertions
- Performance: Full speed, minimal battery usage
- APK size: native-code heavy; use split-per-ABI APKs or an App Bundle for release distribution. The validated May 3 release outputs were 203.4 MB for `armeabi-v7a`, 231.0 MB for `arm64-v8a`, 237.7 MB for `x86_64`, and 367.3 MB for the App Bundle.

### Profile Mode (For Android Studio Profiler)

Profile mode is optimized but includes profiling hooks for CPU/memory/GPU analysis.

```bash
cd example
flutter run --profile
```

Then in Android Studio:
1. Open **View → Tool Windows → Profiler**
2. Select your device and app process
3. Record CPU, Memory, or Energy traces

### Native-Only Debugging (Advanced)

To debug C++ code in Android Studio:

1. Open the `example/android` folder in Android Studio
2. Set breakpoints in `src/*.cpp` files
3. Run → Debug 'app' with LLDB debugger selected
4. Native breakpoints will hit during execution

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `COMAPS_TAG` | `v2026.04.23-19` | CoMaps git tag to checkout |
| `ANDROID_NDK_HOME` | Auto-detected | Path to Android NDK |

### Standalone Launch (Without Connected Laptop)

Unlike iOS, Android **does allow** debug builds to be launched standalone from the home screen. However, for optimal performance and battery life, use Release mode:

```bash
cd example

# Build and install a Release APK for the device ABI
flutter build apk --release --split-per-abi
adb install build/app/outputs/flutter-apk/app-arm64-v8a-release.apk

# Or build a universal APK only for quick local smoke checks
flutter build apk --release
adb install build/app/outputs/flutter-apk/app-release.apk

# Or run directly
flutter run --release -d <device-id>
```

After installing, you can disconnect the laptop and launch the app from the home screen.

**Note:** Debug builds can also be launched standalone on Android, but they will:
- Run significantly slower (JIT compilation, no tree-shaking)
- Use more battery (debug logging, unoptimized code)
- Have larger APK size (~300MB vs ~100MB)

### Build Configuration: DEBUG/RELEASE Preprocessor Definitions

CoMaps' `base/base.hpp` has a compile-time assertion requiring exactly one of `DEBUG` or `RELEASE`/`NDEBUG` to be defined. This is handled in [src/CMakeLists.txt](../src/CMakeLists.txt):

```cmake
# Debug/Release compile definitions (required by base.hpp)
target_compile_definitions(${PROJECT_NAME} PRIVATE
    $<$<CONFIG:Debug>:DEBUG>
    $<$<CONFIG:Release>:RELEASE>
    $<$<CONFIG:Release>:NDEBUG>
)
```

This ensures:
- **Debug builds:** `DEBUG=1` is defined
- **Release builds:** `RELEASE=1` and `NDEBUG=1` are defined

## Goal

Get the Android example app to:

1. Extract CoMaps resources and map files to app-private storage as real files.
2. Pass filesystem paths into the native layer so CoMaps can open `.mwm` files
   normally.
3. Render the native map through a Flutter `Texture` using Android
   `SurfaceProducer`.
4. Support pan, zoom, rotate, tap selection, routing, map presentation toggles,
   and DuckDB-backed project layers.
5. Keep camera gestures smooth on slower physical devices, including Samsung
   Galaxy S10-class hardware.

This matches how Organic Maps / CoMaps typically operate: maps are stored as
standalone `.mwm` files on disk and are memory-mapped / paged by the OS for
performance.

## Historical MVP Non-Goals

These were non-goals for the original MVP and are now implemented or partially
implemented:

- Full Drape rendering + Flutter `Texture` integration.
- Search/routing.
- Download manager / storage management.

Keep this section only as context when reading older status reports below.

## Current Android Architecture

### Flutter surface

`AgusMap` in `lib/agus_maps_flutter.dart` owns the Flutter-side map surface.

- It creates a native map surface through Pigeon host API
  `createMapSurface`.
- It displays the returned texture id with Flutter `Texture`.
- It forwards touch input through FFI `comaps_touch`.
- It preserves the native surface during mobile keyboard occlusion via
  `AgusMapResizePolicy.stableViewport`.
- It resizes only for real viewport changes such as rotation, split-screen, or
  device-pixel-ratio changes.

### Android host bridge

`android/src/main/java/app/agus/maps/agus_maps_flutter/AgusMapsFlutterPlugin.java`
owns Android platform integration.

- `TextureRegistry.SurfaceProducer` creates the render target consumed by
  Flutter.
- `nativeSetSurface`, `nativeOnSurfaceChanged`, `nativeOnSizeChanged`, and
  `nativeOnSurfaceDestroyed` forward lifecycle and size changes to C++.
- `onFrameReady()` calls `SurfaceProducer.scheduleFrame()` on the main thread so
  Flutter composites newly rendered native frames.
- Data files are extracted into app-private storage before the native engine
  opens map resources.

### Native CoMaps/Drape bridge

`src/agus_maps_flutter.cpp` is the main Android C++ bridge.

- It creates `Framework` after Android paths and a render surface are ready.
- It creates the Drape engine with OpenGL ES 3.
- It registers an active-frame callback so Flutter is notified only when Drape
  renders an active frame.
- It tracks the current viewport for screen/coordinate projection and
  DuckDB-backed layer filtering.
- It exposes FFI for camera movement, touch, routing, place pages, map
  presentation state, and DuckDB rendering.

`src/agus_ogl.cpp` and `src/agus_ogl.hpp` own the Android EGL context factory.

- The draw context renders to the Android window surface provided by
  `SurfaceProducer`.
- The upload context uses a pbuffer surface.
- Surface resets and size changes are routed through the context factory without
  recreating the full Flutter widget tree.

## Android Map Rendering Smoothness

### Problem observed on physical device

On a Samsung Galaxy S10-class device, the map could flicker while pan, zoom, and
rotation gestures were active. After the first mitigation, active gesture
flicker was reduced, but a single delayed flicker could still occur a few
milliseconds to about a second after a smooth camera operation completed.

The delayed flicker matched the DuckDB/Drape viewport refresh path:

1. CoMaps viewport changes arrived during camera movement.
2. The native viewport listener scheduled a DuckDB render-layer refresh.
3. After the camera became idle, the refresh queried DuckDB and rebuilt Drape
   user marks.
4. If the feature set was unchanged, this still caused a visible post-gesture
   invalidation.

### Current rule

Camera gestures must stay render-only. Pan, zoom, and rotation must not run
synchronous DuckDB queries or full Drape user-mark rebuilds on the gesture frame
path.

Project-layer rendering follows these rules:

1. Explicit project-layer mutations refresh immediately:
   - feature commit;
   - layer visibility changes;
   - layer ordering changes;
   - layer deletion or creation.
2. Camera-driven refreshes are debounced until the viewport is idle.
3. The idle refresh compares the newly queried renderable DuckDB feature set
   against the last published set.
4. If the feature set is unchanged, the refresh is a no-op and does not call:
   - `DrapeEngine::UpdateUserMarks`;
   - `DrapeEngine::InvalidateUserMarks`;
   - `WakeRenderer`.
5. If the feature set changed, native user marks are updated incrementally after
   the first publication by reporting created, updated, and removed mark ids.

This keeps normal camera animation smooth while preserving correctness when
moving into an area with different visible project-layer features.

### Relevant implementation points

In `src/agus_maps_flutter.cpp`:

- `SetViewportTracking()` records the current viewport and schedules, rather
  than directly runs, camera-driven DuckDB refreshes.
- `ScheduleDuckDBRenderRefreshAfterViewportIdle()` waits for viewport generation
  stability before refreshing.
- `RefreshDuckDBRenderLayersInternal()` queries visible DuckDB-backed features
  for the current viewport and zoom.
- `AreDuckDBRenderableFeaturesEqual()` skips Drape work when an idle refresh
  returns the same feature set.
- `DuckDBMarksProvider::SetFeatures()` computes created, removed, and updated
  mark ids so only the first publication uses Drape's first-time path.

## Android Debugging and Validation

Use `tee` when collecting logs so the output can be inspected after the run:

```bash
cd example
flutter run -d RF8M20SAQSL --debug 2>&1 | tee ../output.debug-android.log
```

For a build-only native compile check:

```bash
cd example
flutter build apk --debug 2>&1 | tee ../output.android-build.log
```

When investigating flicker, look for:

- repeated `nativeOnSizeChanged` or `nativeOnSurfaceChanged` during gestures;
- `Skipped ... frames!` from Choreographer during map interaction;
- DuckDB layer refresh logs near post-gesture flicker;
- EGL errors from `AgusMapsFlutterNative` or `CoMaps`;
- repeated surface destruction/recreation while the map is visible.

Expected behavior:

- no surface recreation during ordinary pan, zoom, or rotate;
- no synchronous DuckDB refresh while the camera is actively moving;
- no Drape user-mark update after idle if the visible renderable feature set did
  not change;
- explicit layer edits still appear on the map after commit/refresh.

## Repository Conventions
- `thirdparty/` contains checked-out external dependencies (e.g., CoMaps engine sources).
- `tool/build.dart` contains the cross-platform automation that populates `thirdparty/` and applies patches.
- `scripts/` only contains thin wrappers (build_all.*) and utility helpers.
- `patches/comaps/` contains optional patch files that are applied to the CoMaps checkout **only if required**.

## Dependency Setup

### CoMaps engine checkout
We pin and fetch the CoMaps repo into `thirdparty/comaps`.

- Repo: `git@github.com:comaps/comaps.git`
- Default tag: `v2026.04.23-19`
- Override tag by setting env var: `COMAPS_TAG`

Commands:

**All platforms:**
- `dart run tool/build.dart --no-cache`
    - Clones/updates CoMaps to `thirdparty/comaps` at the desired tag.
    - Applies any patches from `patches/comaps/*.patch`.

Environment variables:
- `COMAPS_TAG` (optional): overrides the tag/commit checked out.

## Map Data (Gibraltar)

### Asset bundling
The example app declares and ships:
- `example/assets/maps/Gibraltar.mwm`

Data source: CoMaps CDN servers from the CoMaps source defaults and metaserver, such as `https://cdn-fi-1.comaps.app/` and `https://mapgen-fi-1.comaps.app/`. Runtime region metadata is parsed from the hierarchical CoMaps `countries.txt`; UI browsing keeps folders/groups intact while downloads operate on leaf `.mwm` files.

Android build config sets `.mwm` as **noCompress** so packaging does not compress the file (this reduces CPU overhead during extraction and avoids surprises).

### “Extract once” behavior
On Android, files packaged inside the APK are not normal files you can hand to native `open()`/`mmap()` by path.

So on first run we:
1. Copy `Gibraltar.mwm` from APK assets to an app-private file under `context.filesDir`.
2. Cache it there and reuse it on subsequent launches.

This is implemented as a small Android host bridge (MethodChannel) because it allows efficient streaming copy (without loading the entire `.mwm` into Dart memory).

## FFI Boundary (initial)
We expose a minimal C API that lets Dart:
- create/destroy an engine handle
- load a map by filesystem path
- set initial view (Gibraltar @ zoom 14)

For now, these are stubs that validate the file exists and store the requested view. We will replace internal behavior as we integrate CoMaps.

## Acceptance Criteria
- Example app on Android:
  - bundles `example/assets/maps/Gibraltar.mwm`
  - on first launch copies it to app storage
  - calls native `comaps_load_map_path(extractedPath)`
  - calls native `comaps_set_view(36.1408, -5.3536, 14)`
  - shows success/failure in UI (and logs in native)

## Next Milestones
- Replace stubs with CoMaps engine integration (no upstream modifications if possible; otherwise patch via `patches/comaps/`).
- Add `SurfaceProducer`/Texture rendering pipeline as described in GUIDE.

## Status Report: Phase 2 & 3 (Linker Resolution)

**Date:** 2025-12-17  
**Status:** ✅ APK Builds and Runs - Data Files Extracted - FFI Working

We have successfully resolved all build blockers and the app now runs on device with FFI communication working and CoMaps data files extracted.

### Changes Summary
1.  **CMake Configuration** ([src/CMakeLists.txt](../src/CMakeLists.txt)):
    -   Updated to **C++23** (`CMAKE_CXX_STANDARD 23`) to match CoMaps.
    -   Added `SKIP_TOOLS ON` to avoid building unnecessary CoMaps tools that caused linker issues.
    -   Added `DEBUG`/`RELEASE` compile definitions required by `base.hpp`.
    -   Added `boost` and `libs` include paths.
    -   Added `--allow-multiple-definition` linker flag to allow stub overrides.
    
2.  **FFI Symbol Export** ([src/agus_maps_flutter.h](../src/agus_maps_flutter.h)):
    -   Added `extern "C"` block to prevent C++ name mangling for FFI exports.
    -   Added `__attribute__((visibility("default")))` for symbol visibility.
    -   Added `comaps_init_paths()` FFI function for extracted data files.
    
3.  **Platform Stubs** ([src/agus_platform.cpp](../src/agus_platform.cpp)):
    -   Implemented missing Android platform abstractions to satisfy `libbase.a` and `libplatform.a` dependencies without linking the full Android SDK JNI layer.
    -   **Stubs Added:**
        -   `AndroidThreadAttachToJVM`, `AndroidThreadDetachFromJVM`
        -   `GetAndroidSystemLanguages`
        -   `platform::GetCurrentLocale`
        -   `downloader::CreateNativeHttpThread` (returns nullptr)
        -   `platform::SecureStorage` (no-op)
        -   `platform::HttpClient::RunHttpRequest()` (returns false)
        -   `platform::GetTextByIdFactory` (returns nullptr to avoid assert on missing locale files)
    -   Added `AgusPlatform_InitPaths()` for explicit resource path configuration.
        
4.  **Data File Extraction** ([android/.../AgusMapsFlutterPlugin.java](../android/src/main/java/app/agus/maps/agus_maps_flutter/AgusMapsFlutterPlugin.java)):
    -   Added `extractDataFiles()` method to recursively extract CoMaps data assets.
    -   Data files are extracted from `assets/comaps_data/` to app's files directory.
    -   Added symbol atlas validation before marker reuse:
        -   Requires `symbols/xxhdpi/{light,dark}/symbols.{png,sdf}`
        -   Applies minimum-size checks to reject stale placeholder files
        -   Forces re-extraction if validation fails
    
5.  **Data File Bundling** (handled by `dart run tool/build.dart --no-cache` during bootstrap):
    -   Build tool copies essential CoMaps data files to example app assets.
    -   Files include: classificator.txt, types.txt, categories.txt, drules, etc.
    
6.  **Java/Rendering** ([android/.../AgusMapsFlutterPlugin.java](../android/src/main/java/app/agus/maps/agus_maps_flutter/AgusMapsFlutterPlugin.java)):
    -   Updated to use `TextureRegistry.SurfaceProducer` for modern Flutter API compatibility.
    
7.  **Dart FFI** ([lib/agus_maps_flutter.dart](../lib/agus_maps_flutter.dart)):
    -   Fixed `Pointer<Utf8>` to `Pointer<Char>` cast for FFI string passing.
    -   Added `extractDataFiles()` and `initWithPaths()` methods.
    
8.  **Example App** ([example/lib/main.dart](../example/lib/main.dart)):
    -   Updated to extract data files before initialization.
    -   Uses `initWithPaths()` for proper resource path configuration.

### Verified Behavior (Device Test: Samsung SM-G973F, Android 12)
-   ✅ **APK Size:** ~252MB (includes CoMaps static libraries)
-   ✅ **App Launches:** No native crash on startup
-   ✅ **Asset Extraction:** 
    -   `Gibraltar.mwm` extracted to `/data/user/0/.../files/`
    -   CoMaps data files extracted to `/data/user/0/.../files/comaps_data/`
-   ✅ **FFI Calls Work:** Native logs confirm all calls complete:
    -   `comaps_init_paths` - Platform initialized with resource path
    -   `comaps_load_map_path` - Gibraltar.mwm path received
    -   `comaps_set_view` - Coordinates received (lat=36.1408, lon=-5.3536, zoom=14)
    
### Known Limitations (Current State)
-   ⚠️ **No Rendering:** Framework is deferred until surface is ready.
-   ⚠️ **Framework Not Created:** Full Framework initialization still causes assertions due to missing/incomplete data.

### Immediate Next Steps

1.  **Complete Data File Requirements**:
    -   Identify all required data files for Framework initialization.
    -   May need World.mwm, symbols, fonts, etc.

2.  **Framework Initialization**:
    -   Create Framework when surface is provided.
    -   Debug remaining assertion failures.

3.  **Surface/Texture Rendering**:
    -   The `createMapSurface` method is implemented but not yet connected.
    -   Wire up `AgusOGLContextFactory` to the Drape engine.
    -   Add the `AgusMap` widget to display the texture.

4.  **Touch Handling**:
    -   Implement `comaps_on_touch` FFI.
    -   Pass pointer events from Flutter `Listener` -> Dart FFI -> C++ -> `g_framework->TouchEvent(...)`.
