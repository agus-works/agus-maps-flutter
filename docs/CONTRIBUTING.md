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
└── docs/                   # Documentation
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

- Flutter SDK 3.x (stable channel)
- Android SDK with NDK r25c+
- CMake 3.18+
- Git (with ability to initialize submodules)
- **macOS** for iOS, macOS, and Android builds
- **Windows** with PowerShell 7+ for Windows and Android builds

> **⚠️ Linux Not Supported:** Linux builds are not yet supported. We are still evaluating which distributions to support and the best development workflow. Contributions from developers with Linux hardware are welcome!

### Initial Setup

We provide **unified bootstrap scripts** that prepare ALL target platforms supported from your build machine in a single command:

| Build Machine | Targets Prepared | Command |
|---------------|------------------|--------|
| **macOS** | Android, iOS, macOS | `./scripts/bootstrap.sh` |
| **Windows** | Android, Windows | `.\scripts\bootstrap.ps1` |

The bootstrap scripts handle:
1. Fetching CoMaps source code at the correct version
2. Applying ALL patches (superset for all platforms)
3. Initializing ALL submodules (required for patches)
4. Building Boost headers
5. Generating and copying CoMaps data files
6. Downloading base MWM samples (World, Gibraltar)
7. Platform-specific setup (XCFrameworks for iOS/macOS, vcpkg for Windows)

**macOS (targets: Android, iOS, macOS):**
```bash
# Clone the repository
git clone https://github.com/bangonkali/agus-maps-flutter.git
cd agus-maps-flutter

# Run unified bootstrap (prepares ALL targets)
./scripts/bootstrap.sh

# Get Flutter dependencies
flutter pub get

# Build and run example
cd example
flutter run -d <device>  # iOS Simulator, Android device, or macOS
```

**Windows PowerShell 7+ (targets: Android, Windows):**
```powershell
# Clone the repository
git clone https://github.com/bangonkali/agus-maps-flutter.git
cd agus-maps-flutter

# Run unified bootstrap (prepares ALL targets)
.\scripts\bootstrap.ps1

# Get Flutter dependencies
flutter pub get

# Build and run example
cd example
flutter run -d <device>  # Windows or Android device
```

### Bootstrap Options

**macOS (`bootstrap.sh`):**
```bash
./scripts/bootstrap.sh                    # Default: download pre-built XCFrameworks
./scripts/bootstrap.sh --build-xcframework  # Build XCFrameworks from source (~30 min each)
./scripts/bootstrap.sh --no-cache          # Disable local caching
```

**Windows (`bootstrap.ps1`):**
```powershell
.\scripts\bootstrap.ps1                   # Default
.\scripts\bootstrap.ps1 -NoCache           # Disable local caching
.\scripts\bootstrap.ps1 -SkipPatches       # Skip patch application (debugging)
.\scripts\bootstrap.ps1 -VcpkgRoot D:\vcpkg # Custom vcpkg location
```

### Bootstrap Architecture

The unified bootstrap scripts share common logic via:
- **Bash**: `scripts/bootstrap_common.sh` (sourced by `bootstrap.sh`)
- **PowerShell**: `scripts/BootstrapCommon.psm1` (imported by `bootstrap.ps1`)

This ensures:
1. Same CoMaps tag is used across all platforms
2. ALL patches are applied (superset for all platforms)
3. ALL submodules are fully initialized (required for patches like gflags)
4. Boost headers are built consistently
5. Data files are copied to example assets
6. XCFrameworks downloaded/built for iOS and macOS (macOS only)
7. vcpkg dependencies installed for Windows (Windows only)

### Local Cache Mechanism (Development Only)

To speed up patch iteration during development, the bootstrap scripts implement local caching:

- **macOS**: After fresh clone, `thirdparty/` is compressed to `.thirdparty.tar.bz2`
- **Windows**: After fresh clone, `thirdparty/` is compressed to `.thirdparty.7z` (requires 7-Zip)

The cache is created **before patches are applied**, allowing you to:
1. Delete the `thirdparty/` folder
2. Re-run bootstrap
3. Quickly restore from cache and re-apply patches

> **Note:** Caching is automatically disabled in CI environments (`$CI=true`) to avoid interfering with CI-specific caching mechanisms.

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

The `thirdparty/comaps` directory contains a patched checkout of CoMaps. Patches are maintained in `patches/comaps/` and applied via:

**Linux/macOS:**
```bash
./scripts/apply_comaps_patches.sh
```

**Windows PowerShell:**
```powershell
.\scripts\apply_comaps_patches.ps1
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
