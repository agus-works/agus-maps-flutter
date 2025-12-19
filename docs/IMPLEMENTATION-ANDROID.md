# Android Implementation Plan (MVP)

## Quick Start: Build & Run

### Prerequisites

- Flutter SDK 3.24+ installed
- Android SDK with NDK 27.2.12479018 (or set in `android/build.gradle`)
- A connected Android device or emulator (API 24+)
- ~5GB disk space for CoMaps build artifacts

### Debug Mode (Full debugging, slower)

Debug mode enables hot reload, step-through debugging, and verbose logging for both Flutter and native layers.

```bash
# 1. Bootstrap CoMaps dependencies (first time only)
./scripts/bootstrap_android.sh

# 2. Copy CoMaps data files (first time only)
./scripts/copy_comaps_data.sh

# 3. Run in debug mode
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

```bash
# 1. Bootstrap CoMaps dependencies (first time only)
./scripts/bootstrap_android.sh

# 2. Copy CoMaps data files (first time only) 
./scripts/copy_comaps_data.sh

# 3. Build and run in release mode
cd example
flutter run --release

# Or build an APK for installation
flutter build apk --release
adb install build/app/outputs/flutter-apk/app-release.apk
```

**Release mode characteristics:**
- Flutter: AOT compiled, tree-shaken, minified
- Native: `-O3` optimization, no debug symbols, no assertions
- Performance: Full speed, minimal battery usage
- APK size: ~100MB (stripped, compressed)

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
| `COMAPS_TAG` | `v2025.12.11-2` | CoMaps git tag to checkout |
| `ANDROID_NDK_HOME` | Auto-detected | Path to Android NDK |

---

## Goal
Get the Android example app to:

1. Bundle a Gibraltar map file (`Gibraltar.mwm`) as an example asset.
2. On first launch, **ensure the map exists as a real file on disk** (extract/copy once if missing).
3. Pass the on-disk filesystem path into the native layer (FFI) so the native engine can open it using normal filesystem APIs (and later use `mmap`).
4. Set the initial camera to **Gibraltar** at **zoom 14**.

This matches how Organic Maps / CoMaps typically operate: maps are stored as standalone `.mwm` files on disk and are memory-mapped / paged by the OS for performance.

## Non-Goals (for this MVP)
- Full Drape rendering + Flutter `Texture` integration.
- Search/routing.
- Download manager / storage management.

Those come after we have a repeatable dependency + data workflow and a stable FFI boundary.

## Repository Conventions
- `thirdparty/` contains checked-out external dependencies (e.g., CoMaps engine sources).
- `scripts/` contains all automation that populates `thirdparty/` and applies any patches.
- `patches/comaps/` contains optional patch files that are applied to the CoMaps checkout **only if required**.

## Dependency Setup

### CoMaps engine checkout
We pin and fetch the CoMaps repo into `thirdparty/comaps`.

- Repo: `git@github.com:comaps/comaps.git`
- Default tag: `v2025.12.11-2`
- Override tag by setting env var: `COMAPS_TAG`

Commands:

- `./scripts/bootstrap_android.sh`
  - Clones/updates CoMaps to `thirdparty/comaps` at the desired tag.
  - Applies any patches from `patches/comaps/*.patch`.

Environment variables:
- `COMAPS_TAG` (optional): overrides the tag/commit checked out.

## Map Data (Gibraltar)

### Asset bundling
The example app declares and ships:
- `example/assets/maps/Gibraltar.mwm`

Data source: `https://omaps.webfreak.org/maps/251021/`

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
    
5.  **Data File Bundling** ([scripts/copy_comaps_data.sh](../scripts/copy_comaps_data.sh)):
    -   Script to copy essential CoMaps data files to example app assets.
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
