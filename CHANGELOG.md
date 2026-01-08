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