# Dart Hooks Implementation

This document describes the Dart hooks and build tool implementation that replaces shell scripts for build orchestration.

## Overview

Starting with v0.1.14, the plugin uses a Dart-based build system that provides:

1. **Automated SDK download** via Dart hooks during `flutter pub get` (consumer workflow)
2. **Unified build tool** (`tool/build.dart`) for contributors building from source
3. **Cross-platform compatibility** without platform-specific shell scripts
4. **Better maintainability** with modular Dart code instead of shell scripts

## Architecture

### Consumer Workflow (Plugin Users)

**Hook System**: `hook/build.dart`
- Runs automatically during `flutter pub get`
- Detects consumer mode (default)
- Downloads SDK from GitHub Releases
- Extracts and installs binaries to plugin directories
- Falls back to `AGUS_MAPS_HOME` if download fails

**Usage**:
```bash
# Consumer workflow - automatic via flutter pub get
flutter pub get
# Hook automatically downloads SDK v0.1.14 from GitHub Releases
```

### Contributor Workflow (Building from Source)

**Build Tool**: `tool/build.dart`
- Must be explicitly invoked by contributors
- Detects contributor mode (when `AGUS_MAPS_BUILD_MODE=contributor` or in-repo)
- Orchestrates CoMaps bootstrap, patch application, and native builds

**Usage**:
```bash
# Bootstrap CoMaps (clone, checkout, patches, boost, data)
dart run tool/build.dart --no-cache

# Build native binaries for all platforms
dart run tool/build.dart --build-binaries

# Build specific platforms
dart run tool/build.dart --build-binaries --platform android --platform ios

# Skip patches (for testing)
dart run tool/build.dart --skip-patches
```

## Build Tool Structure

The build tool is organized into modular components in `tool/src/`:

### Core Modules

- **`build_runner.dart`** - Main orchestration logic, coordinates all build steps
- **`config.dart`** - Build configuration, constants, and mode detection
- **`platform_detector.dart`** - OS detection and platform-specific paths

### Build Operations

- **`git_operations.dart`** - CoMaps git clone, checkout, submodules
- **`patch_applicator.dart`** - Apply CoMaps patches
- **`process_runner.dart`** - Execute external processes (CMake, Python scripts)
- **`file_operations.dart`** - Cross-platform file system operations
- **`archive_manager.dart`** - ZIP/TAR archive operations

### Platform Builds

- **`cmake_build.dart`** - CMake build orchestration for all platforms:
  - `buildAndroidAbi()` - Android ABI-specific builds
  - `buildiOSXCFramework()` - iOS XCFramework (device + simulator)
  - `buildMacOSXCFramework()` - macOS XCFramework (universal)
  - `buildWindowsLibrary()` - Windows DLL build
  - `buildLinuxLibrary()` - Linux shared library build

### SDK Management

- **`sdk_downloader.dart`** - Download SDK from GitHub Releases:
  - HTTP download with progress
  - Local caching
  - ZIP extraction
  - Installation to plugin directories

## Scripts Replaced by Dart Implementation

The following legacy scripts were removed and replaced by the Dart build tool:

### Bootstrap Scripts (Replaced)

| Script | Replaced By | Notes |
|--------|-------------|-------|
| `scripts/bootstrap.sh` | `dart run tool/build.dart --no-cache` | Bootstrap CoMaps (clone, checkout, patches, boost, data) |
| `scripts/bootstrap.ps1` | `dart run tool/build.dart --no-cache` | Windows version of bootstrap |
| `scripts/bootstrap_common.sh` | `tool/src/build_runner.dart` | Logic moved to Dart modules |
| `scripts/BootstrapCommon.psm1` | `tool/src/build_runner.dart` | PowerShell module logic moved to Dart |

### Platform Build Scripts (Replaced)

| Script | Replaced By | Notes |
|--------|-------------|-------|
| `scripts/build_binaries_android.sh` | `dart run tool/build.dart --build-binaries --platform android` | Android native library builds |
| `scripts/build_binaries_android.ps1` | `dart run tool/build.dart --build-binaries --platform android` | Windows version |
| `scripts/build_binaries_ios.sh` | `dart run tool/build.dart --build-binaries --platform ios` | iOS XCFramework build |
| `scripts/build_binaries_macos.sh` | `dart run tool/build.dart --build-binaries --platform macos` | macOS XCFramework build |
| `scripts/build_binaries_windows.ps1` | `dart run tool/build.dart --build-binaries --platform windows` | Windows DLL build |
| `scripts/build_binaries_linux.sh` | `dart run tool/build.dart --build-binaries --platform linux` | Linux shared library build |

## Optional Wrapper Scripts (Still Present)

The following wrappers remain in the repository for convenience:

- `scripts/build_all.sh` / `scripts/build_all.ps1`
  - **Status**: Thin wrappers around `tool/build.dart` for local builds
  - **Recommended**: Use `dart run tool/build.dart --build-binaries` directly when scripting

- `scripts/bundle_headers.sh`
  - **Status**: Still used in CI/CD workflows
  - **Reason**: Utility script for packaging headers separately

## CI/CD Migration

The GitHub Actions workflow (`.github/workflows/devops.yml`) has been updated to use the Dart build tool:

### Changes Made

**After**:
```yaml
- name: Get Flutter Dependencies
  run: flutter pub get

- name: Bootstrap CoMaps
  env:
    COMAPS_TAG: ${{ env.COMAPS_TAG }}
    AGUS_MAPS_BUILD_MODE: contributor
  run: dart run tool/build.dart --no-cache

- name: Build iOS XCFramework
  env:
    COMAPS_TAG: ${{ env.COMAPS_TAG }}
    AGUS_MAPS_BUILD_MODE: contributor
  run: dart run tool/build.dart --build-binaries --platform ios
```

### All Platforms Updated

- ✅ macOS job (iOS/macOS builds)
- ✅ Android job
- ✅ Windows job
- ✅ Linux job

## Dependencies Added

The following packages were added to `pubspec.yaml` to support the Dart build system:

```yaml
dependencies:
  hooks: ^1.0.0           # Dart hooks API for build automation
  archive: ^3.4.0         # Archive operations (ZIP extraction/creation)
  yaml: ^3.1.2            # YAML parsing for pubspec.yaml
  path: ^1.9.1            # Cross-platform path operations

dev_dependencies:
  args: ^2.5.0            # Command-line argument parsing (already existed)
```

## Build Mode Detection

The build tool automatically detects the build mode:

### Consumer Mode (Default)
- **Trigger**: `AGUS_MAPS_BUILD_MODE` not set or set to `consumer`
- **Behavior**: Downloads pre-built SDK from GitHub Releases
- **Hook**: `hook/build.dart` handles SDK download during `flutter pub get`

### Contributor Mode
- **Trigger**: `AGUS_MAPS_BUILD_MODE=contributor` OR in-repo (`.git` and `thirdparty/comaps` exist)
- **Behavior**: Builds from source using `tool/build.dart`
- **Requires**: CoMaps source code in `thirdparty/comaps`

**Environment Variable**:
```bash
export AGUS_MAPS_BUILD_MODE=contributor  # Force contributor mode
```

## Migration Checklist

For contributors migrating from shell scripts to Dart build tool:

- [ ] Install Dart SDK (if not already installed)
- [ ] Run `flutter pub get` to install build dependencies
- [ ] Use `dart run tool/build.dart --no-cache` for bootstrap
- [ ] Use `dart run tool/build.dart --build-binaries --platform <platform>` for native builds
- [ ] Update CI/CD workflows (already done in v0.1.14)
- [ ] Update documentation references to shell scripts

## Future Enhancements

Potential improvements for future versions:

1. **Bundle Headers Migration**: Migrate `bundle_headers.sh` to Dart tool
2. **MWM Download Integration**: Keep base MWM downloads fully handled by the Dart tool
3. **Patch Management**: Consider migrating patch validation/regeneration to Dart
4. **Incremental Builds**: Add support for incremental builds in Dart tool
5. **Build Caching**: Implement more sophisticated caching in Dart tool
6. **Parallel Builds**: Add parallel platform builds in Dart tool

## Troubleshooting

### Hook Not Running

If the hook doesn't run during `flutter pub get`:

1. Verify `hooks` package is installed: `flutter pub get`
2. Check hook file exists: `hook/build.dart`
3. Verify `pubspec.yaml` doesn't explicitly disable hooks
4. Check Dart SDK version: Requires Dart SDK >= 3.6.0

### Build Tool Not Found

If `dart run tool/build.dart` fails:

1. Verify you're in the plugin root directory
2. Run `flutter pub get` to install dependencies
3. Check Dart SDK version: `dart --version`
4. Verify `tool/build.dart` exists and is executable

### Environment Variables

Required environment variables for contributor mode:

- `AGUS_MAPS_BUILD_MODE=contributor` - Force contributor mode
- `COMAPS_TAG=v2026.01.08-11` - CoMaps version tag (optional, defaults in config)

Platform-specific variables (auto-detected in most cases):

- `ANDROID_HOME` / `ANDROID_SDK_ROOT` - Android SDK path
- `NDK_HOME` / `ANDROID_NDK_HOME` - Android NDK path
- `VCPKG_ROOT` - vcpkg path (Windows)
- `CMAKE` - CMake path (optional, auto-detected)

## References

- [Dart Hooks Documentation](https://pub.dev/packages/hooks)
- [CHANGELOG.md](../CHANGELOG.md) - v0.1.14 entry
- [RELEASE.md](./RELEASE.md) - Release and installation guide
- [IMPLEMENTATION-CI-CD.md](./IMPLEMENTATION-CI-CD.md) - CI/CD implementation details
