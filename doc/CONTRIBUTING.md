# Contributing to Agus Maps Flutter

Thank you for your interest in contributing! This document provides technical details for developers working on the plugin.

## Project Structure

```
agus_maps_flutter/
├── src/                    # Native C++ source code
│   ├── agus_maps_flutter.cpp   # Main FFI implementation
│   ├── agus_maps_flutter.h     # FFI header (used by ffigen)
│   ├── agus_ogl.cpp            # OpenGL ES context management
│   ├── agus_gui_thread.cpp     # JNI-based UI thread dispatch
│   └── CMakeLists.txt          # Native build configuration
├── lib/                    # Dart code
│   ├── agus_maps_flutter.dart  # Public API
│   └── agus_maps_flutter_bindings_generated.dart  # Auto-generated FFI bindings
├── android/                # Android platform integration
├── ios/                    # iOS platform (not yet implemented)
├── linux/                  # Linux platform (not yet implemented)
├── macos/                  # macOS platform (not yet implemented)
├── windows/                # Windows platform (not yet implemented)
├── example/                # Demo Flutter application
├── thirdparty/             # External dependencies (CoMaps engine)
├── patches/                # Patches applied to CoMaps
├── scripts/                # Build and setup automation
└── doc/                   # Documentation
```

## Building and Bundling Native Code

The `pubspec.yaml` specifies FFI plugins as follows:

```yaml
plugin:
  platforms:
    android:
      ffiPlugin: true
      package: app.agus.maps.agus_maps_flutter
      pluginClass: AgusMapsFlutterPlugin
```

This configuration invokes the native build for the various target platforms and bundles the binaries in Flutter applications.

### Platform-Specific Build Systems

| Platform | Build System | Config File |
|----------|-------------|-------------|
| Android | Gradle + NDK | `android/build.gradle` |
| iOS | Xcode + CocoaPods | `ios/agus_maps_flutter.podspec` |
| macOS | Xcode + CocoaPods | `macos/agus_maps_flutter.podspec` |
| Linux | CMake | `linux/CMakeLists.txt` |
| Windows | CMake | `windows/CMakeLists.txt` |

## FFI Bindings

FFI bindings are auto-generated from `src/agus_maps_flutter.h` using `package:ffigen`.

**Regenerate bindings after modifying the header:**

```bash
dart run ffigen --config ffigen.yaml
```

## Development Setup

### Prerequisites

- Flutter SDK 3.38+ (stable channel)
- Android SDK with NDK 27.3+
- CMake 4.2+
- Ninja build system
- Python 3 with the `protobuf` module (`pip install protobuf`)
- Git (with ability to initialize submodules)
- **macOS** for iOS, macOS, and Android builds
- **Windows** with PowerShell 7+ and Git Bash (data generation) for Windows and Android builds
- **Linux** (Ubuntu 22.04+ or equivalent) for Linux and Android builds

> **Important for Contributors:** Do NOT set the `AGUS_MAPS_HOME` environment variable when working on the plugin. The build scripts handle everything automatically by building from source. `AGUS_MAPS_HOME` is only for **consumers** of the published plugin who download the pre-built SDK.

### Initial Setup

We provide **unified build scripts** that handle the entire build process from source via Dart hooks (`tool/build.dart`):

| Build Machine | Target Platforms | Recommended Script |
|---------------|------------------|-------------------|
| **macOS** | Android, iOS, macOS | `./scripts/build_all.sh` |
| **Windows** | Android, Windows | `.\scripts\build_all.ps1` |
| **Linux** | Android, Linux | `./scripts/build_all.sh` |

The `build_all` scripts handle:
1. Bootstrapping CoMaps source (clone, tag checkout, submodules, LFS)
2. Applying patches (superset for all platforms)
3. Building Boost headers
4. Generating and copying CoMaps data files
5. Downloading base MWM samples (World, WorldCoasts, Gibraltar)
6. Building native binaries for the host-supported platforms

**macOS (targets: Android, iOS, macOS):**
```bash
# Clone the repository
git clone https://github.com/agus-works/agus-maps-flutter.git
cd agus-maps-flutter

# Run unified build script (builds ALL targets from source)
./scripts/build_all.sh

# Build and run example
cd example
flutter run -d <device>  # iOS Simulator, Android device, or macOS
```

**Windows PowerShell 7+ (targets: Android, Windows):**
```powershell
# Clone the repository
git clone https://github.com/agus-works/agus-maps-flutter.git
cd agus-maps-flutter

# Run unified build script (builds ALL targets from source)
.\scripts\build_all.ps1

# Build and run example
cd example
flutter run -d <device>  # Windows or Android device
```

**Linux (targets: Android, Linux):**
```bash
# Clone the repository
git clone https://github.com/agus-works/agus-maps-flutter.git
cd agus-maps-flutter

# Install system dependencies (Ubuntu/Debian)
sudo apt-get install build-essential cmake ninja-build clang \
    libgtk-3-dev libepoxy-dev libegl-dev pkg-config

# Run unified build script (builds ALL targets from source)
./scripts/build_all.sh

# Build and run example
cd example
flutter run -d linux
```

### Build Script Usage

The `build_all` scripts are the recommended way to build everything from source:

**macOS/Linux (`build_all.sh`):**
```bash
./scripts/build_all.sh                    # Full build: fetch, patch, build binaries, build apps
```

**Windows (`build_all.ps1`):**
```powershell
.\scripts\build_all.ps1                   # Full build: fetch, patch, build binaries, build apps
```

For targeted native builds, use the Dart build tool directly:

```bash
dart run tool/build.dart --build-binaries --platform <platform>
```

Add `--skip-patches` if you need to debug patch application.

### Build Script Architecture

`build_all` is a thin wrapper around the Dart hooks in `tool/build.dart`. It orchestrates the CoMaps checkout, patch application, Boost headers, data generation, and native builds. Standalone bootstrap/patch scripts are no longer required.

### Rebuilding After Changes

```bash
# If you modified src/agus_maps_flutter.h
dart run ffigen --config ffigen.yaml

# Clean rebuild
cd example
flutter clean
flutter run
```

## CoMaps Patches

The `thirdparty/comaps` directory contains a patched checkout of CoMaps. Patches are maintained in `patches/comaps/` and applied automatically by the Dart build tool (`tool/build.dart`) as part of `build_all` or targeted builds.

To skip patch application (debugging), run:

```bash
dart run tool/build.dart --skip-patches
```

| Patch | Purpose |
|-------|---------|
| `0001-fix-cmake.patch` | CMake fixes for cross-compilation |
| `0002-platform-directory-resources.patch` | Directory-based resource loading |
| `0003-transliteration-directory-resources.patch` | ICU data file loading |
| `0004-fix-android-gl-function-pointers.patch` | GL function pointer resolution |

## Commit Guidelines

This project follows [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` New features
- `fix:` Bug fixes
- `docs:` Documentation changes
- `chore:` Maintenance tasks
- `refactor:` Code refactoring

Example:
```
feat(android): implement touch event forwarding

- Add comaps_touch() FFI function
- Support multitouch gestures
- Convert logical to physical coordinates
```

## Testing

```bash
# Run example app with logging
cd example
flutter run

# Monitor native logs (Android)
adb logcat | grep -E "(CoMaps|AGUS|drape)"
```

## Architecture

See [GUIDE.md](../GUIDE.md) for the full architectural blueprint.

### Detailed Documentation

| Document | Description |
|----------|-------------|
| [API.md](./API.md) | **API Reference** - All existing APIs and roadmap for future additions |
| [ARCHITECTURE-ANDROID.md](./ARCHITECTURE-ANDROID.md) | Deep dive into Android integration, memory/battery efficiency |
| [IMPLEMENTATION-ANDROID.md](./IMPLEMENTATION-ANDROID.md) | Build instructions, debug/release modes |
| [GUIDE.md](../GUIDE.md) | High-level plugin architecture |

### Known Issues

Efficiency and reliability issues are tracked in dedicated files:

| Issue | Platform | Severity | Status |
|-------|----------|----------|--------|
| [ISSUE-debug-logging-release.md](./ISSUE-debug-logging-release.md) | All | Medium | Should Fix |
| [ISSUE-egl-context-recreation.md](./ISSUE-egl-context-recreation.md) | Android | Medium | Should Fix |
| [ISSUE-indexed-stack-memory.md](./ISSUE-indexed-stack-memory.md) | All | Medium | By Design |
| [ISSUE-macos-resize-white-screen.md](./ISSUE-macos-resize-white-screen.md) | macOS | High | ✅ Resolved |
| macOS resize instability (brownish blocks) | macOS | Medium | ✅ Resolved |
| [ISSUE-touch-event-throttling.md](./ISSUE-touch-event-throttling.md) | All | Low | Deferred |
| [ISSUE-dpi-mismatch-surface.md](./ISSUE-dpi-mismatch-surface.md) | Android | Low | Monitor |
| [ISSUE-ffi-string-allocation.md](./ISSUE-ffi-string-allocation.md) | All | Low | Won't Fix |
| [ISSUE-data-extraction-cold-start.md](./ISSUE-data-extraction-cold-start.md) | All | Low | Won't Fix |

## Getting Help

- Open an issue for bugs or feature requests
- Check existing documentation in `/docs`
- Review the GUIDE.md for architectural decisions
