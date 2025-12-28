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
- Git

### Initial Setup

**Linux/macOS:**
```bash
# Clone the repository
git clone https://github.com/agus-app/agus_maps_flutter.git
cd agus_maps_flutter

# Fetch and patch CoMaps engine
./scripts/bootstrap_android.sh

# Get Flutter dependencies
flutter pub get

# Build and run example
cd example
flutter run
```

**Windows PowerShell:**
```powershell
# Clone the repository
git clone https://github.com/agus-app/agus_maps_flutter.git
cd agus_maps_flutter

# Fetch and patch CoMaps engine
.\scripts\bootstrap_android.ps1

# Get Flutter dependencies
flutter pub get

# Build and run example
cd example
flutter run
```

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

| Issue | Severity | Status |
|-------|----------|--------|
| [ISSUE-debug-logging-release.md](./ISSUE-debug-logging-release.md) | Medium | Should Fix |
| [ISSUE-egl-context-recreation.md](./ISSUE-egl-context-recreation.md) | Medium | Should Fix |
| [ISSUE-indexed-stack-memory.md](./ISSUE-indexed-stack-memory.md) | Medium | By Design |
| [ISSUE-touch-event-throttling.md](./ISSUE-touch-event-throttling.md) | Low | Deferred |
| [ISSUE-dpi-mismatch-surface.md](./ISSUE-dpi-mismatch-surface.md) | Low | Monitor |
| [ISSUE-ffi-string-allocation.md](./ISSUE-ffi-string-allocation.md) | Low | Won't Fix |
| [ISSUE-data-extraction-cold-start.md](./ISSUE-data-extraction-cold-start.md) | Low | Won't Fix |

## Getting Help

- Open an issue for bugs or feature requests
- Check existing documentation in `/docs`
- Review the GUIDE.md for architectural decisions
