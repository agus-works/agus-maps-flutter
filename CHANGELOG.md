## 0.1.22

### macOS/iOS Rendering

* **Fixed Stalled Rendering**: Resolved a critical issue where the map would freeze during pan/zoom operations after the first few seconds of interaction. The fix ensures that Flutter is notified immediately whenever a new frame is presented by the Metal engine, bypassing a previous optimization that was causing missed frames during interactive gestures. This restores smooth, continuous map updates on both macOS and iOS.
* **Documentation**: Updated implementation documentation for macOS and iOS to reflect the improved frame notification logic.

## 0.1.21

### Map View

* **Initial viewport ordering**: Restored v0.1.17 behavior by applying the initial `setView` before `onMapReady` to avoid delayed/blank initial renders for consumers.

### macOS

* **Metal context build fix**: Restored missing `DrawMetalContext` members and removed stale legacy-branch references to unblock macOS builds.

## 0.1.20

### macOS/iOS Rendering

* **SDK shader validation**: CI now fails if `shaders_metal.metallib` is missing, preventing release of iOS/macOS SDK artifacts that would render blank.

## 0.1.19

### macOS/iOS Rendering

* **Regression isolation toggle**: Added a legacy Metal `Present()` path toggle to help diagnose broken initial rendering on macOS/iOS SDK consumers introduced after v0.1.14.
* **Documentation note**: Documented the regression investigation and the diagnostic toggle location in macOS implementation notes.

## 0.1.18

### Map View

* **Initial Viewport Fix**: Delayed initial map view setup to ensure `onMapReady` is called first and map registration completes, preventing race conditions during startup.

### Documentation

* **Cached headers troubleshooting**: Updated README and RELEASE.md with instructions for clearing cached headers on iOS/macOS to resolve potential build issues.

* **Project management guides**: Added `doc/ARCHIVING.md` and `doc/COPYING.md` to provide standardized guidelines for archiving and copying the project directory.

## 0.1.17

### Map Rendering & UX

* **Dynamic visual scaling**: Added a `density` parameter to `createMapSurface` and `resizeMapSurface`, enabling DPI-aware visual scaling without surface recreation. `AgusMap` now combines device pixel ratio with a user scale, and the example app includes a persistent map label scale slider.

* **Windows pixel conversion**: Rounded physical pixel dimensions on Windows and improved diagnostics/texture filtering for clearer rendering.

### Platform Fixes

* **macOS shutdown stability**: Fixed quit hangs and Cmd+Q aborts by making Metal context cleanup non-blocking and safer during teardown.

### Build System & Tooling

* **Windows data generation compatibility**: Desktop data generation now uses Git Bash on Windows and avoids multiprocessing in `libkomwm.py` via a dedicated patch.

* **Map downloader enhancements**: Added force re-download and cache handling flags to `tool/map_downloader.dart`.

* **Data tooling cleanup**: Removed symbol texture download logic from the data generation pipeline.

* **Script cleanup**: Retired legacy bootstrap/patch validation scripts in favor of Dart hooks and `build_all` scripts.

### CI/CD

* **Windows-focused builds**: CI now enables CoMaps builds on Windows only and streamlines Python setup/submodule LFS handling.

* **LFS reliability**: Added `git lfs pull` for nested submodules and improved logging during initialization.

### Dependencies

* **Tooling updates**: `archive` 4.0.7, `ffigen` 20.1.1, `flutter_lints` 6.0.0; CI Flutter updated to 3.38.7.

### Documentation

* **Windows assets guidance**: Documented extracted asset locations on Windows.

* **CoMaps tag refresh**: Updated docs and scripts to `COMAPS_TAG` v2026.01.08-11.

* **Docs cleanup**: Updated documentation to replace removed shell/PowerShell script references with `tool/build.dart` usage.

### Maintenance

* **Example lockfiles**: Removed `path_provider_foundation` from iOS/macOS example Podfile locks.

## 0.1.16

### Windows Rendering

* **Zero-copy pipeline**: Implemented WGL_NV_DX_interop with DXGI shared handles for GPU-only frame transfer (CPU fallback retained). Includes adapter matching, interop FBO setup, renderbuffer fallback, draw/read buffer setup, and RGBA→BGRA swizzle in the CPU path.

* **Diagnostics overlay**: Added native OpenGL overlay for runtime visibility of renderer/transfer path and keyed mutex state, with environment toggle and custom lines API.

* **Active frame notifications**: CoMaps render loop now calls the active-frame callback when a frame is rendered, ensuring Flutter is notified of live frames.

### Build System

* **Windows runtime dependencies**: Build tooling now copies `zlib1.dll` from vcpkg into the output directory and improves vcpkg manifest path handling.

* **Clean build helper**: Added `clean-build.ps1` to simplify Windows clean builds.

### Documentation

* **Windows architecture updates**: Added/expanded Windows implementation docs for zero-copy rendering, overlay diagnostics, and render loop behavior.

## 0.1.15

### Map Mirrors & Downloads

* **CoMaps CDN discovery**: `MirrorService` now targets CoMaps CDN servers and probes snapshots via `countries.txt` (no directory listings), with a new `discoverMirrors()` that reports availability and latency.

* **Shared mirror utilities**: Added `lib/src/mirror_utils.dart` to parse `countries.txt` JSON, model regions/snapshots, and share mirror discovery logic between runtime and tools.

* **Map downloader tooling**: New `tool/map_downloader.dart` (mirror discovery, snapshot probing, JSON reports, list modes) and `tool/check_mirrors.dart` diagnostics for metaserver and CDN health checks.

### Example App

* **Mirror selector UI**: Downloads tab now surfaces mirror status/latency, allows switching mirrors, and refreshes mirror discovery in the background.

* **Download paths & cleanup**: Downloads now store maps under `Documents/agus_maps_flutter/maps`; cache validation probes `countries.txt`, and startup cleanup checks both root and maps directories for partial downloads.

* **Map deletion flow**: Added per-map delete actions for non-bundled downloads, backed by new `MwmStorage.deleteMap()` APIs and UI confirmation.

### Build System & CI

* **Thirdparty caching**: Build runner can cache `thirdparty/` into `.thirdparty-<tag>.tar.gz` and restore it on bootstrap; tar.gz create/extract support added to the archive manager.

* **Boost headers handling**: Build tooling now prefers Boost modular headers and falls back to `b2 headers` when needed; CI verifies flat headers for plugin compilation.

* **CI asset downloads**: CI and build scripts now use the Dart map downloader for consistent asset retrieval (with optional JSON reports) and validate/copy ICU data.

* **iOS/macOS source hiding**: CI temporarily hides CoMaps source during iOS/macOS example builds and extracts bundled headers for plugin compilation, then restores sources post-build.

* **Windows vcpkg baseline**: Added `builtin-baseline` to `vcpkg.json` and CI ensures the baseline commit is available in the cached vcpkg clone.

### Build Tooling

* **CMake/NDK detection**: CMake discovery now prefers SDK-installed CMake on Windows; Android NDK detection honors `ANDROID_NDK_HOME` and falls back to the newest installed version with clearer errors.

* **Process diagnostics**: Process runner adds verbose command logging and prints captured stdout/stderr on failures.

### Documentation

* **CoMaps CDN guidance**: README and mirror service docs now describe CoMaps CDN servers, metaserver discovery, and updated download examples.

## 0.1.14

### Build System Overhaul

* **Dart Build Tool Migration**: Replaced shell scripts (`.sh`, `.ps1`) with a unified Dart build tool (`tool/build.dart`) for all platforms. This provides better cross-platform compatibility, easier maintenance, and consistent behavior across macOS, Linux, and Windows.

* **Dart Hooks Infrastructure**: Implemented Dart hooks system (`hook/build.dart`) to automatically download and install the SDK during `flutter pub get` for plugin consumers. This eliminates the manual download step for typical consumers.

  - **Consumer Workflow**: The hook automatically downloads the SDK from GitHub Releases during `flutter pub get`
  - **Contributor Workflow**: Contributors use `dart run tool/build.dart --build-binaries` to build from source
  - **Fallback Support**: The `AGUS_MAPS_HOME` environment variable remains supported as a fallback

* **Modular Build System**: Created `tool/src/` with modular Dart components:
  - `build_runner.dart` - Main build orchestration
  - `cmake_build.dart` - CMake build logic for all platforms
  - `sdk_downloader.dart` - SDK download and installation
  - `platform_detector.dart` - OS and platform detection
  - `file_operations.dart` - Cross-platform file operations
  - `process_runner.dart` - External process execution
  - `git_operations.dart` - Git operations (clone, checkout, submodules)
  - `patch_applicator.dart` - CoMaps patch application
  - `archive_manager.dart` - Archive operations
  - `config.dart` - Build configuration and constants

### Bug Fixes

* **iOS XCFramework Generation**: Fixed a critical issue where iOS XCFramework creation failed due to naming conflicts when merging static libraries from device and simulator builds. Both builds were creating `libcomaps.a` in the same directory, causing overwrites. The fix creates separate temporary directories (`temp/iphoneos/` and `temp/iphonesimulator/`) for each architecture's merged library.

* **Windows Visual Studio Generator**: On Windows, the build tool now uses Visual Studio 17 2022 generator instead of Ninja to avoid GCC/MinGW-w64 compatibility issues with ICU compilation. ICU has known issues with newer GCC versions (e.g., 15.2.0), so using MSVC via Visual Studio generator is more reliable.

* **Windows Multi-Config Builds**: Fixed handling of Visual Studio multi-configuration builds where `CMAKE_BUILD_TYPE` is ignored during configure and output DLLs are placed in `buildDir/Release/` or `buildDir/Debug/` subdirectories. The build tool now correctly uses the `--config` flag and searches appropriate output directories.

* **Windows Path Handling**: Improved path handling in the `copyPath` function with proper normalization using `path.absolute()` and `path.normalize()`. Added error handling to skip files that can't be copied (symlinks, missing files) instead of failing the entire copy operation.

* **Windows Data Generation**: The Dart build tool now only runs `generate_desktop_ui_strings.py` directly on Windows and skips bash scripts (`generate_drules.sh`, `generate_categories.sh`), matching the behavior of the original PowerShell implementation.

* **Windows zlib1.dll Runtime Dependency**: Added CI step to copy `zlib1.dll` runtime dependency for Windows builds, ensuring the DLL is available at runtime.

* **CoMaps Data Generation Environment**: Added `OMIM_PATH` and `DATA_PATH` environment variables to data generation scripts (`generate_drules.sh`, `generate_categories.sh`), which are required by CoMaps tools to locate sources and output directories correctly.

### CI/CD Improvements

* **Workflow Modernization**: Updated `.github/workflows/devops.yml` to use `dart run tool/build.dart` instead of shell scripts for:
  - CoMaps bootstrap (`dart run tool/build.dart --no-cache`)
  - Platform-specific native builds (`dart run tool/build.dart --build-binaries --platform <platform>`)

* **MWM Download Steps**: Added explicit MWM file download steps to CI workflow for iOS, macOS, and Android example app builds. Downloads `World.mwm`, `WorldCoasts.mwm`, and `Gibraltar.mwm` from CoMaps CDN servers (with Organic Maps mirrors as fallback) to ensure map assets are available for example apps.

* **Symbol Texture Downloading**: Implemented automatic download of symbol textures from Organic Maps for various resolutions and themes (`.sdf` and `.png` files).

* **CocoaPods Automation**: Improved Metal shader compilation handling for macOS/iOS builds, ensuring shaders are correctly processed and linked. Added CocoaPods setup automation after building native binaries.

### Documentation

* **Early-Stage Notice**: Added early-stage development notice to README to set appropriate expectations for users.

* **Dart Hooks Documentation**: Added comprehensive `doc/DART-HOOKS.md` documenting the new build system architecture, migration from shell scripts, build mode detection, and troubleshooting.

### Dependencies

* **New Build Dependencies**: Added the following packages to support the Dart build system:
  - `hooks: ^1.0.0` - Dart hooks API for build automation
  - `archive: ^3.4.0` - Archive operations (ZIP extraction/creation)
  - `yaml: ^3.1.2` - YAML parsing for pubspec.yaml
  - `path: ^1.9.1` - Cross-platform path operations

### Migration

No action required for consumers upgrading from `0.1.13`. The Dart hooks system provides a smoother experience:

- **First-time setup**: Simply run `flutter pub get` - the SDK will be downloaded automatically
- **Existing `AGUS_MAPS_HOME` users**: Your existing setup continues to work; the environment variable takes precedence over auto-download
- **Contributors**: Use `dart run tool/build.dart --build-binaries` instead of shell scripts

## 0.1.13

### Documentation

* **Comprehensive API Reference**: Added `doc/API.md` with complete documentation of all existing APIs and a roadmap for future API additions. Includes detailed implementation patterns for FFI and MethodChannel APIs, code review checklists, and CoMaps framework reference.

* **Enhanced README**: Significantly improved setup instructions with detailed platform-specific configuration for iOS, macOS, and Android minimum versions. Added a new "Quick Test" section with a compact example app to verify plugin setup.

* **API Reference Links**: Updated README and CONTRIBUTING.md to include links to the new API reference documentation. Moved Features section to the example app README for better organization.

### Linux Build System

* **Simplified Binary Distribution**: Removed the separate `libagus.so` dependency from Linux builds. All CoMaps functionality is now statically linked into `libagus_maps_flutter.so`, reducing deployment complexity and eliminating potential library loading issues.

* **Streamlined CMakeLists.txt**: Updated `linux/CMakeLists.txt` to check only for `libagus_maps_flutter.so` during prebuilt detection, reflecting the consolidated library architecture.

### Migration

No action required for consumers upgrading from `0.1.12`. The Linux build changes are fully backward compatible—existing `AGUS_MAPS_HOME` setups will continue to work with the new single-library architecture.

## 0.1.12

### Bug Fixes

* **Missing Metal Shaders in Release Binaries**: Fixed a critical packaging issue where `shaders_metal.metallib` was omitted from the `agus-binaries-ios.zip` and `agus-binaries-macos.zip` release artifacts. This caused runtime crashes on iOS and macOS (specifically `CHECK(libPath != nil) shaders_metal.metallib not found in any bundle!`). The CI/CD workflow and local build scripts now correctly package the `Resources` directory containing the compiled shaders.

* **Development Pod Resource Copying**: Updated the `podspec` development helper script (used when the plugin is a local path dependency) to copy `Resources` (shaders) from `AGUS_MAPS_HOME` in addition to headers. This ensures that local example apps and development workflows correctly include the necessary Metal shaders.

## 0.1.11

### Bug Fixes

* **iOS Release build failure** (critical): Fixed missing `GCC_PREPROCESSOR_DEFINITIONS` configuration overrides for Debug/Release builds in the iOS podspec. Without these, CoMaps' `base/base.hpp` triggers a static assertion: `Either Debug or Release should be defined, but not both`. This affected pub.dev consumers building for iOS in Release mode. The fix adds `DEBUG=1` for Debug builds and `RELEASE=1 NDEBUG=1` for Release/Profile builds, matching the macOS podspec.

### Documentation

* **New Build Configuration Guide**: Added `doc/BUILD-CONFIGURATION.md` to comprehensively document build configurations (Debug/Release/Profile), preprocessor definitions, and platform-specific build details.
* **Release Guide Update**: Updated `doc/RELEASE.md` to reflect the deprecation of individual binary downloads. It now focuses on the Unified Binary Package and provides detailed instructions for installing pre-built Example Apps on all platforms.

### Release & Distribution

* **Deprecated Individual Binary Downloads**: The release workflow now only distributes the unified `agus-maps-sdk`. Individual platform zip files (e.g., `agus-binaries-ios.zip`) are no longer generated to streamline distribution.
* **Release Artifacts Cleanup**: The `devops.yml` workflow was updated to stop uploading deprecated artifacts.


## 0.1.10

### iOS and macOS Build System Improvements

* **Development Pod header support**: Added automatic header copying at `pod install` time for Development Pods (path dependency) on both iOS and macOS. When using the plugin as a development dependency (e.g., `path: ../agus_maps_flutter`), headers are now copied from `AGUS_MAPS_HOME` during pod installation, fixing "file not found" errors for CoMaps headers like `boost/regex.hpp`.

* **SDK source tracking**: Introduced a marker file (`.sdk_source`) in the `ios/Headers/` and `macos/Headers/` directories to track which SDK the headers were copied from. The build system now detects when `AGUS_MAPS_HOME` changes and automatically refreshes headers, ensuring consumers always have the correct headers for their configured SDK version.

* **Header copying in `prepare_command`**: Both iOS and macOS podspec `prepare_command` blocks now copy headers from `AGUS_MAPS_HOME/headers` to `Headers/comaps/` alongside the XCFramework. This ensures pub.dev consumers have all necessary headers for compilation.

* **Prioritized header search paths** (macOS): Reordered `HEADER_SEARCH_PATHS` in the macOS podspec to prioritize downloaded headers (`Headers/comaps/`) over in-repo thirdparty paths. This ensures consumers using the SDK binaries get consistent header resolution without interference from missing in-repo sources.

### Repository Maintenance

* **Updated `.gitignore`**: Added `macos/Headers/` and `ios/Headers/` to ignore downloaded headers, keeping the repository clean when using SDK binaries.

### Technical Details

* **Development Pod vs. Published Pod behavior**:
  - **Published pods** (from pub.dev): `prepare_command` runs during `pod install`, copying frameworks and headers
  - **Development pods** (path dependency): `prepare_command` is skipped; new Ruby code at the top of the podspec handles header copying

* **Header refresh triggers**:
  1. `Headers/comaps/` directory missing
  2. `.sdk_source` marker file missing
  3. `.sdk_source` contains a different path than current `AGUS_MAPS_HOME`

### Migration

No breaking changes. Consumers using `AGUS_MAPS_HOME` will benefit from automatic header management on both iOS and macOS. If you encounter stale headers after changing SDK versions, delete `ios/Headers/` or `macos/Headers/` and run `pod install` again.


## 0.1.9

### Build System Improvements

* **Streamlined Android prebuilt binary integration**: Refactored `android/build.gradle` to provide a cleaner separation between in-repo development mode and external consumer mode. External consumers now exclusively use pre-built binaries via `jniLibs.srcDirs`, while in-repo contributors continue to build from source via CMake.

* **Enhanced AGUS_MAPS_HOME detection**: When `AGUS_MAPS_HOME` environment variable is set and points to a valid directory, the build system now explicitly forces external consumer mode. This prevents accidental source builds when consumers have the SDK properly configured.

* **Disabled CMake for external consumers**: The `externalNativeBuild` block in `android/build.gradle` is now conditionally applied only for in-repo builds. External consumers no longer trigger CMake configuration, eliminating unnecessary build overhead and potential configuration errors.

* **Simplified prebuilt library lookup**: Removed complex multi-tier fallback logic in favor of a straightforward approach:
  1. Check `AGUS_MAPS_HOME` environment variable
  2. Use `jniLibs.srcDirs` to point to the prebuilt libraries
  3. Provide clear error messages if binaries are not found
  
  This eliminates the plugin-local `prebuilt/` directory fallback for non-CI builds, making the consumer workflow more explicit and predictable.

### Bug Fixes

* **Asset extraction verification**: Enhanced the asset extraction check in `AgusMapsFlutterPlugin.java` to verify that essential files (e.g., `unicode_blocks.txt`) exist before skipping re-extraction. This prevents runtime errors caused by incomplete or corrupted asset extractions.

  The plugin now checks:
  - Marker file (`.comaps_data_extracted`) indicating prior extraction
  - Essential asset file (`fonts/unicode_blocks.txt`) to confirm completeness
  
  If either check fails, assets are re-extracted automatically.

### Error Message Improvements

* **Clearer setup instructions**: Error messages when `AGUS_MAPS_HOME` is missing or invalid now provide more actionable guidance:
  - For consumers: Step-by-step instructions to download, extract, configure, and use the SDK
  - For contributors: Direct reference to build scripts (`build_all.sh` / `build_all.ps1`)
  - Distinguished between AGUS_MAPS_HOME path issues vs. missing binaries entirely

### Technical Details

* **Build mode detection logic**: The build system now evaluates build mode in this order:
  1. **AGUS_MAPS_HOME override**: If set and valid, force external consumer mode
  2. **In-repo check**: If `.git` and `thirdparty/comaps` exist AND AGUS_MAPS_HOME is not set, use in-repo development mode
  3. **External consumer**: Otherwise, require AGUS_MAPS_HOME with valid prebuilt binaries

* **jniLibs.srcDirs approach**: Instead of using CMake arguments to configure prebuilt paths, the Gradle build now directly adds the prebuilt directory to `sourceSets.main.jniLibs.srcDirs`. This is the standard Android approach for including pre-compiled native libraries and avoids CMake entirely for consumers.

### Migration

No breaking changes. Consumers using `AGUS_MAPS_HOME` correctly will see improved build performance (no CMake overhead) and clearer error messages. Ensure your `AGUS_MAPS_HOME` points to a valid SDK directory with the following structure:

```
agus-maps-sdk-v0.1.9/
├── android/prebuilt/{arm64-v8a,armeabi-v7a,x86_64}/
├── ios/Frameworks/CoMaps.xcframework/
├── macos/Frameworks/CoMaps.xcframework/
├── windows/prebuilt/x64/
├── linux/prebuilt/x64/
└── assets/
    ├── comaps_data/
    └── ...
```

### Cross-Platform Impact

* **Android only**: All changes are scoped to Android Gradle configuration and Java plugin code
* **No changes to iOS/macOS/Linux/Windows**: Build systems for other platforms remain unchanged

## 0.1.8

### Bug Fixes

* **Android Gradle syntax error**: Fixed a missing closing brace in `android/build.gradle` inside the external CMake configuration block. The malformed `else { ... }` caused Gradle to report `Unexpected input: '{'` at the `android {` line during CI. The block is now correctly closed and parses under AGP 8.x.

* **NDK handling aligned with v0.1.6**: Retained `ndkVersion = android.ndkVersion` to match prior successful builds. No changes to NDK behavior versus `0.1.6`; the consuming app continues to define the NDK version used.

### CI Stability

* **GitHub Actions (Android)**: With the Gradle file corrected, CI can evaluate the project and proceed to build native libraries and example artifacts without early failure. NDK behavior remains unchanged from `0.1.6`. No workflow changes are required.

### Cross‑platform Impact

* **No changes to iOS/macOS/Linux/Windows**: The fix is scoped to Android Gradle configuration only. Other platforms and their build systems (CocoaPods/CMake) remain unchanged and continue to work as in `0.1.7`.

### Migration

No action required for consumers upgrading from `0.1.7`. NDK behavior is unchanged compared to `0.1.6`.

## 0.1.7

### Breaking Changes

* **Mandatory `AGUS_MAPS_HOME` for consumers**: Plugin consumers must now set the `AGUS_MAPS_HOME` environment variable pointing to the extracted SDK directory. The fallback to extracting binaries into the app root directory has been removed.

* **SDK Package Renamed**: The release artifact is now named `agus-maps-sdk-vX.Y.Z.zip` (previously `agus-maps-binaries-vX.Y.Z.zip`) to better reflect that it contains the complete SDK with binaries, assets, and optional headers.

### New Features

* **CI Environment Detection**: All build systems (Gradle, CMake, CocoaPods) now detect CI environments via the `CI` environment variable. This allows CI workflows to use plugin-local `prebuilt/` directories without requiring `AGUS_MAPS_HOME`.

* **Standardized Error Messages**: All platforms now display consistent, actionable error messages when binaries are not found, clearly distinguishing between consumer and contributor workflows.

### Build System Improvements

* **Android `build.gradle`**: Fixed a bug with orphaned if-block in prebuilt detection logic. Added CI detection to allow plugin-local prebuilt directories only in CI or when binaries actually exist.

* **iOS/macOS podspecs**: Enhanced `prepare_command` with CI detection. CI builds now proceed with a placeholder, allowing the workflow to copy frameworks before the actual build step.

* **Linux/Windows CMakeLists**: Added `IS_CI` detection alongside `IS_IN_REPO` for cleaner workflow separation.

### Documentation

* **Rewrote `GUIDE.md`**: Replaced historical architecture document with current implementation details. Now covers the three workflow types (contributor, CI, consumer) and actual platform implementations.

* **Updated `README.md`**: Refined consumer installation instructions with platform-specific commands for setting `AGUS_MAPS_HOME`. Added Windows CMD example alongside PowerShell.

* **Updated `CONTRIBUTING.md`**: Added explicit warning that contributors should NOT set `AGUS_MAPS_HOME` - the build scripts handle everything automatically.

### Migration Guide

If upgrading from v0.1.6:

1. Download `agus-maps-sdk-v0.1.7.zip` from [GitHub Releases](https://github.com/agus-works/agus-maps-flutter/releases)
2. Extract to a permanent location (e.g., `~/agus-sdk/agus-maps-sdk-v0.1.7`)
3. Set `AGUS_MAPS_HOME` environment variable:
   ```bash
   # macOS/Linux (add to ~/.bashrc or ~/.zshrc)
   export AGUS_MAPS_HOME=/path/to/agus-maps-sdk-v0.1.7
   
   # Windows PowerShell (add to profile or set system env var)
   $env:AGUS_MAPS_HOME = "C:\path\to\agus-maps-sdk-v0.1.7"
   ```
4. Copy assets from SDK to your Flutter app's `assets/` folder
5. Rebuild with `flutter clean && flutter build`

## 0.1.6

### Bug Fixes

* **Fixed Windows CI archive creation step**: Resolved a CI failure where the "Create Windows Binaries Archive" step was using bash-style commands (`rm -f`, `zip`) but running in PowerShell by default. PowerShell interpreted `rm -f` as `Remove-Item` with an ambiguous `-f` parameter. Changed to native PowerShell commands (`Remove-Item`, `Compress-Archive`) with explicit `shell: pwsh` for consistency with other Windows steps.

## 0.1.5

### Bug Fixes

* **Fixed Windows binaries path in unified package**: Resolved an issue where Windows binaries in `agus-maps-binaries-vX.Y.Z.zip` were incorrectly placed at `windows/prebuilt/agus-binaries-windows/x64/` instead of `windows/prebuilt/x64/`. This caused Windows consumers to get "file not found" errors when using the unified binary package.

### New Features

* **Auto-download XCFramework for iOS/macOS**: Pub.dev consumers no longer need to manually place iOS/macOS frameworks. The CocoaPods `prepare_command` now automatically downloads the XCFramework from GitHub releases when not found locally. This solves the issue where pub-cache installed plugins couldn't find frameworks extracted to the consumer app's directory (different directory trees).

  **Important:** Consumers still need to download and extract the unified binary package to their app root for **assets** (`assets/comaps_data/`, `assets/maps/`). Only the XCFramework download is automated.

### Build System Improvements

* **Updated podspec versions**: iOS and macOS podspecs now correctly specify version `0.1.5` (previously `0.0.1`).

* **Improved iOS/macOS podspec documentation**: Added detailed comments explaining the three-tier framework resolution: (1) local existence check, (2) relative path search for vendored plugins, (3) auto-download from GitHub releases.

* **Improved Android build.gradle documentation**: Added clarifying comments about how `rootDir` resolves in Flutter Android builds to help future maintainers understand the prebuilt binary search logic.

### CI/CD Improvements

* **Consistent archive creation for Windows**: Added a dedicated "Create Windows Binaries Archive" step in CI workflow (similar to Android and Linux) that creates the zip with content at root level, ensuring the correct `windows/prebuilt/x64/` structure in the unified package.

* **Removed duplicate release artifact**: Removed the redundant non-versioned `agus-maps-binaries.zip` from releases. Only the versioned `agus-maps-binaries-vX.Y.Z.zip` is now uploaded, avoiding confusion and reducing release artifact size.

* **Individual iOS/macOS binary zips in releases**: Added `agus-binaries-ios.zip` and `agus-binaries-macos.zip` to GitHub releases for CocoaPods auto-download functionality.

## 0.1.4

### Bug Fixes

* **Fixed Android CI build failure**: Resolved an issue where in-repo builds (CI, local development) incorrectly used pre-built binary mode instead of building from source. This caused compilation failures with "file not found" errors for CoMaps headers (`base/task_loop.hpp`, `platform/platform.hpp`, etc.) because the headers directory was not set.

### Build System Changes

* **Prioritize source builds for in-repo development**: Changed Android Gradle build logic to always build from source when running in-repo (when `.git` and `thirdparty/comaps` exist), regardless of whether `android/prebuilt/` contains binaries. This ensures CI builds and local development always use the source code.
* **Clearer error for external consumers**: External consumers (Flutter apps using this plugin as a dependency) now receive a clear `GradleException` with download instructions if pre-built binaries are missing, instead of a generic warning.

## 0.1.3

### Breaking Changes

* **Removed auto-download behavior**: All build systems (CMake, Gradle, CocoaPods) no longer auto-download binaries during build. Consumers must manually download and extract the unified package before building.
* **Removed `download_libs.sh`**: The auto-download script has been removed to ensure a single, consistent, deterministic workflow for all consumers.

### Consumer Workflow Changes

The workflow is now fully manual and deterministic:

1. Add `agus_maps_flutter: ^0.1.3` to your `pubspec.yaml`
2. Download `agus-maps-binaries-v0.1.3.zip` from [GitHub Releases](https://github.com/agus-works/agus-maps-flutter/releases)
3. Extract directly to your Flutter app root directory
4. Add assets to your `pubspec.yaml`:
   ```yaml
   flutter:
     assets:
       - assets/comaps_data/
       - assets/maps/
   ```
5. Run `flutter build`

> **⚠️ Upgrading from 0.1.2:** When upgrading the plugin version, you must also manually download and extract the new binaries package. The build system will NOT auto-download - it only detects pre-existing binaries.

### Unified Package Structure

After extracting `agus-maps-binaries-vX.Y.Z.zip` to your app root (`my_app/`):

```
my_app/
├── android/prebuilt/{arm64-v8a,armeabi-v7a,x86_64}/   ← Native libraries
├── ios/Frameworks/CoMaps.xcframework/                 ← iOS framework
├── macos/Frameworks/CoMaps.xcframework/               ← macOS framework
├── windows/prebuilt/x64/                              ← Windows DLLs
├── linux/prebuilt/x64/                                ← Linux shared libs
├── assets/comaps_data/                                ← Engine data files
├── assets/maps/                                       ← Map files location
├── headers/                                           ← (Optional) C++ headers
├── lib/                                               ← Your app code
└── pubspec.yaml
```

### Build System Improvements

* **Detection-only build systems**: All platforms (CMake, Gradle, CocoaPods) now only detect pre-built binaries. Clear error messages with download instructions are shown when binaries are missing.
* **No network during build**: Build process is fully deterministic with no implicit downloads.
* **Consistent archive format**: All platform binaries use consistent archive structure without wrapper folders.
* **Linux architecture naming**: Standardized Linux binaries to use `x64` folder naming (consistent with Windows).
* **Multi-location binary search**: CMake (Linux/Windows) and Gradle (Android) now search multiple locations for pre-built binaries:
  - Plugin-local directory (for CI builds or vendored plugins)
  - Project root directory (for consumers extracting unified package)
* **Linux CMakeLists.txt**: Complete rewrite with prebuilt detection, IMPORTED targets, and clear FATAL_ERROR messages for missing binaries.
* **Windows CMakeLists.txt**: Enhanced detection logic matching the Linux implementation.

### CI/CD Improvements

* **Explicit archive creation**: CI now creates all platform archives with consistent structure (content at root, no wrapper folders).
* **Removed archive creation from build scripts**: Build scripts now only produce output directories; CI handles archive creation for consistency.
* **Linux archive creation**: Added explicit archive creation step in CI for Linux binaries with x64 folder naming.

### Documentation

* Updated `README.md` with simplified 5-step Quick Start guide and upgrade instructions.
* Updated `CHANGELOG.md` with detailed migration notes.
* Updated `doc/RELEASE.md` with manual setup workflow and platform detection details.
* Updated `doc/IMPLEMENTATION-IOS.md` with manual binary setup instructions.
* Updated `doc/IMPLEMENTATION-MACOS.md` with manual binary setup instructions.
* Updated `doc/IMPLEMENTATION-CI-CD.md` with consumer workflow notes.
* Updated iOS/macOS podspec comments to reflect manual setup requirement.

## 0.1.2

### Release Packaging Improvements

* **Unified binary package**: Introduced `agus-maps-binaries-vX.Y.Z.zip` containing all platform binaries, assets, and headers in a single download.
* **Versioned artifact filenames**: All release artifacts now include the version tag (e.g., `agus-maps-android-vX.Y.Z.apk`).
* **Streamlined release artifacts**: Removed individual platform binary zips from releases - they are now consolidated in the unified package.
* **Headers included**: C++ headers are now bundled in the unified package for developers who need to build from source.

### Documentation

* Updated `doc/RELEASE.md` with comprehensive installation guide for the unified binary package.

## 0.1.1

* CI/CD improvements for multi-platform builds.
* Azure Blob Storage caching for CoMaps source.
* Build workflow optimizations.

## 0.1.0

* Initial release of Agus Maps Flutter.
* Zero-copy rendering architecture.
* Offline maps support via CoMaps engine.
* Experimental support for linux, macos, windows, ios and android targets.
* This is an experimental release, do not use on production apps.