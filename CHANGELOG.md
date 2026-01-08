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

---

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