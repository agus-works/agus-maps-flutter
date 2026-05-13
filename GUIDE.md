# Agus Maps Flutter - Architecture Guide

## Overview

Agus Maps Flutter is a high-performance Flutter plugin that embeds the [CoMaps](https://codeberg.org/comaps/comaps) rendering engine directly into Flutter applications. It delivers **zero-copy GPU rendering** on iOS, macOS, and Android, with optimized CPU-mediated rendering on Windows and Linux.

## Architecture Principles

### 1. Zero-Copy Where Possible

On supported platforms, map data flows directly from disk to GPU without intermediate copies:

| Platform | Rendering Backend | Zero-Copy | Mechanism |
|----------|------------------|-----------|-----------|
| **iOS** | Metal | ✅ Yes | IOSurface + CVPixelBuffer |
| **macOS** | Metal | ✅ Yes | IOSurface + CVPixelBuffer |
| **Android** | OpenGL ES 3.0 | ✅ Yes | SurfaceTexture |
| **Windows** | OpenGL + D3D11 | ❌ No | glReadPixels (~3-6ms/frame) |
| **Linux** | EGL + OpenGL ES 3.0 | ❌ No | FlPixelBufferTexture |

### 2. Memory-Mapped Map Files

The MWM (MapsWithMe) format is memory-mapped via `mmap()`. Only currently-visible tiles are paged into RAM by the OS kernel. This allows rendering 500MB+ country maps on devices with 2GB RAM.

### 3. Event-Driven Rendering

The render loop is "demand-driven" - the engine only renders when:
- User interacts with the map (pan, zoom, rotate)
- Animations are in progress
- Real view state changes (orientation, split-screen/window resize, DPI change)

When idle, CPU and GPU sleep, preserving battery life.

Keyboard and search UI are treated as overlays above a stable map viewport on
mobile platforms. Showing the keyboard must not resize the native map surface;
only overlay controls, result panels, or future camera/content padding should
adapt to keyboard occlusion.

### 4. Asset Integrity and Self-Healing

CoMaps icon rendering depends on `symbols.png` + `symbols.sdf` atlas files.
The build/runtime pipeline now applies two guardrails:

1. **Build-time normalization**
    - `tool/build.dart` copies `comaps_data` and replicates the canonical
       `xxhdpi` atlas to all DPI folders (`6plus`, `mdpi`, `hdpi`, `xhdpi`,
       `xxhdpi`, `xxxhdpi`) for both `light` and `dark`.

2. **Runtime validation before cache reuse**
    - Android, iOS, macOS, Linux, and Windows validate presence + minimum file
       size of `symbols/xxhdpi/{light,dark}/symbols.{png,sdf}` before trusting
       `.comaps_data_extracted`.
    - If atlas files are missing/suspicious (placeholder-sized), extraction is
       forced and stale files are overwritten from bundled `flutter_assets`.

### 5. DuckDB Data Layers

DuckDB is the plugin's embedded persistence and analytics layer for user
drawings, metadata, preset data layers, and custom query-driven geospatial
layers. The dependency model mirrors CoMaps: `DUCKDB_TAG` pins
`thirdparty/duckdb`, `DUCKDB_SPATIAL_TAG` pins `thirdparty/duckdb-spatial`, and
local patches live under `patches/duckdb/` and `patches/duckdb-spatial/`.

The required DuckDB extensions are `core_functions`, `parquet`, `json`, `icu`,
`httpfs`, and `spatial`. Mobile builds statically embed the required extension
set; desktop SDKs bundle private DuckDB artifacts rather than relying on a
machine-wide DuckDB installation.

macOS and iOS contributor builds now produce `DuckDB.xcframework` from the
pinned DuckDB source, `duckdb-spatial`, and the pinned out-of-tree `httpfs`
extension. The build uses DuckDB's merged vcpkg manifest for spatial
dependencies and packages private static Apple framework artifacts for macOS,
iOS device, and iOS simulator slices.

The first macOS native bridge exposes DuckDB version/health checks,
`writablePath/agus_layers.duckdb` app-database open/close, required extension
loading, unrestricted SQL execution, and migration-file execution through Dart
helpers in the public plugin library.

DuckDB layers render through the native CoMaps/Drape path, not a Flutter overlay.
First-party drawing layers use strict plugin-owned tables. User SQL is allowed to
run arbitrary commands, but renderable query layers must return the documented
contract in `doc/schemas/README.md`.

## SDK Distribution Model

### Three Workflows

The plugin supports three distinct workflows:

#### 1. Plugin Contributors (Source Build)

For developers contributing to `agus-maps-flutter`:

```bash
git clone https://github.com/agus-works/agus-maps-flutter.git
cd agus-maps-flutter
./scripts/build_all.sh   # macOS/Linux
# or
.\scripts\build_all.ps1  # Windows
```

The build scripts handle:
- Fetching CoMaps source code
- Initializing pinned DuckDB and duckdb-spatial checkouts
- Applying patches
- Building native binaries for all platforms
- Generating assets

> **Important:** Do NOT set `AGUS_MAPS_HOME` when working as a contributor.

For Apple platform work, prefer targeted contributor builds while iterating:

```bash
env -u AGUS_MAPS_HOME AGUS_MAPS_BUILD_MODE=contributor \
  dart run tool/build.dart --build-binaries --platform ios 2>&1 | tee ./output.log

env -u AGUS_MAPS_HOME AGUS_MAPS_BUILD_MODE=contributor \
  dart run tool/build.dart --build-binaries --platform macos 2>&1 | tee ./output.log
```

The Dart build tool now applies CoMaps patches in deterministic filename order,
fails fast on CMake configure/build errors, removes stale Apple package outputs
before recreating `CoMaps.xcframework`, and builds Metal shaders before running
CocoaPods setup for iOS/macOS.

#### 2. CI/CD Environment

GitHub Actions builds are detected via `CI=true`. The workflow:
1. Builds binaries from source
2. Copies binaries to `{platform}/prebuilt/` directories
3. Packages everything into `agus-maps-sdk-vX.Y.Z.zip`

On Windows CI, CMake Visual Studio generator selection follows the installed
Visual Studio instance with C++ tools. This avoids choosing a newer generator
that CMake advertises before the hosted runner has the matching Visual Studio
version installed.

#### 3. Plugin Consumers (SDK-based)

For developers using the published plugin:

1. Add dependency: `agus_maps_flutter: ^X.Y.Z`
2. Download `agus-maps-sdk-v0.1.7.zip` from [GitHub Releases](https://github.com/agus-works/agus-maps-flutter/releases)
3. Extract and set environment variable:
   ```bash
   export AGUS_MAPS_HOME=/path/to/agus-maps-sdk-v0.1.7
   ```
4. Copy assets from `example/assets/` to your Flutter app
5. Build your app

### SDK Structure

```
agus-maps-sdk-vX.Y.Z/
├── android/prebuilt/
│   ├── arm64-v8a/
│   ├── armeabi-v7a/
│   └── x86_64/
├── ios/Frameworks/
│   ├── CoMaps.xcframework/
│   └── DuckDB.xcframework/        # DuckDB layer runtime
├── macos/Frameworks/
│   ├── CoMaps.xcframework/
│   └── DuckDB.xcframework/        # DuckDB layer runtime
├── windows/prebuilt/x64/
├── linux/prebuilt/x64/
├── example/assets/
│   ├── comaps_data/    # Engine data (styles, fonts, etc.)
│   └── maps/           # ICU data + MWM map files
└── headers/            # C++ headers (optional, for source builds)
```

## Platform Implementations

### iOS and macOS (Metal)

Uses CVPixelBuffer backed by IOSurface for true zero-copy rendering:

1. Allocate CVPixelBuffer with `kCVPixelBufferMetalCompatibilityKey`
2. Create MTLTexture from pixel buffer
3. CoMaps renders to MTLTexture
4. Flutter samples the texture directly

The headless iOS/macOS XCFramework builds keep the native Apple networking and
platform files, but use Monocypher for Ed25519 verification. CoMaps'
`ed25519_apple.mm` imports Xcode-generated `platform-Swift.h`, which is not
available when building the native engine through standalone CMake.

### Android (OpenGL ES)

Uses SurfaceTexture for zero-copy rendering:

1. Flutter creates SurfaceProducer, returns Surface
2. JNI passes Surface to native code as ANativeWindow
3. CoMaps creates EGLSurface from ANativeWindow
4. `eglSwapBuffers` flips to Flutter's texture

### Windows (WGL + D3D11)

CPU-mediated due to OpenGL/D3D11 interop limitations:

1. CoMaps renders to OpenGL FBO via native WGL
2. `glReadPixels` reads frame to CPU buffer (~2-5ms)
3. RGBA→BGRA conversion + Y-flip (~1ms)
4. Copy to D3D11 staging texture
5. Copy to D3D11 shared texture (DXGI handle)
6. Flutter samples shared texture

### Linux (EGL + GTK)

Uses FlPixelBufferTexture with CPU-mediated transfer:

1. CoMaps renders to EGL/OpenGL ES FBO
2. `glReadPixels` reads frame to CPU buffer
3. Flutter's FlPixelBufferTexture consumes the buffer

## FFI Bridge

The Dart-to-C++ interface uses `dart:ffi` with a C-compatible API:

```c
// Lifecycle
ComapsHandle comaps_create(const char* storage_path);
void comaps_destroy(ComapsHandle handle);

// Surface
void comaps_set_surface(ComapsHandle h, void* window, int w, int h);

// Rendering
void comaps_render_frame(ComapsHandle h);

// Input
void comaps_touch(ComapsHandle h, int type, int id, float x, float y);

// Camera
void comaps_set_view(ComapsHandle h, double lat, double lon, int zoom);
```

## Typed Platform Messaging (Pigeon)

All Dart↔native platform messages use Pigeon-generated, strongly typed APIs.
The source definition lives in [pigeons/agus_maps_api.dart](pigeons/agus_maps_api.dart),
with generated outputs placed in platform-specific folders.

### File layout

```
pigeons/
   agus_maps_api.dart
lib/
   src/
      agus_maps_api.g.dart
android/src/main/java/app/agus/maps/agus_maps_flutter/
   AgusMapsApi.java
ios/Classes/
   AgusMapsApi.g.swift
macos/Classes/
   AgusMapsApi.g.swift
windows/
   agus_maps_api.g.h
   agus_maps_api.g.cpp
linux/
   agus_maps_api.g.h
   agus_maps_api.g.cc
```

### Regeneration

From the repository root, run:

```
dart run pigeon \
   --input pigeons/agus_maps_api.dart \
   --dart_out lib/src/agus_maps_api.g.dart \
   --java_out android/src/main/java/app/agus/maps/agus_maps_flutter/AgusMapsApi.java \
   --java_package app.agus.maps.agus_maps_flutter \
   --swift_out ios/Classes/AgusMapsApi.g.swift \
   --cpp_header_out windows/agus_maps_api.g.h \
   --cpp_source_out windows/agus_maps_api.g.cpp \
   --cpp_namespace agus_maps_flutter \
   --gobject_header_out linux/agus_maps_api.g.h \
   --gobject_source_out linux/agus_maps_api.g.cc \
   --gobject_module agus_maps_flutter

dart run pigeon \
   --input pigeons/agus_maps_api.dart \
   --dart_out lib/src/agus_maps_api.g.dart \
   --swift_out macos/Classes/AgusMapsApi.g.swift
```

Generated files are checked into version control and must not be edited by
hand. Update the Pigeon source file and re-run generation instead.

### Place Pages

Tap selection is exposed as a native JSON payload and rendered by Flutter. iOS
and macOS both emit readable `metadataTags` using CoMaps metadata keys from
`feature_meta.hpp`, so the Dart sheet can show the same rich POI details on
Apple platforms: Wikipedia links, phone numbers, IATA codes, elevation,
internet access, and similar OSM metadata.

Flutter remains the single place for display localization. Native code sends raw
type keys and metadata tags; Dart normalizes and localizes them with the copied
CoMaps string resources in `assets/localized_types/`.

### Runtime Map Downloads

Runtime downloads use the CoMaps `countries.txt` hierarchy instead of a flat
list. `MirrorService.getCountriesData()` returns the full tree for UI browsing,
while `getRegions()` returns only leaf regions for callers that need a flat list
of downloadable `.mwm` files.

The example Downloads tab starts from top-level country/region folders, expands
into child folders or leaf files, and resolves group download/delete actions to
their descendant leaves. Search shows flattened fuzzy matches at the root so
direct matches can be downloaded quickly, while matching folder rows still
expand to their normal children in source hierarchy order. A leaf result can
appear both as a direct search result and under its expanded parent folder.

Mirror defaults are aligned with the current CoMaps source list and merged with
metaserver-only hosts from `https://cdn-us-1.comaps.app/servers` before probing.
Legacy Organic Maps mirrors are not used as fallbacks.

## Performance Characteristics

### Memory Usage

| Component | Typical Usage |
|-----------|--------------|
| Dart VM | ~5-10 MB |
| Native Engine | ~15-25 MB |
| GPU Textures | ~20-30 MB |
| Map Data (mmap) | OS-managed paging |
| **Total** | **~40-65 MB** |

### Frame Timing

| Platform | Render Time | Transfer Time | Total |
|----------|-------------|---------------|-------|
| iOS/macOS | ~8-12ms | ~0ms (zero-copy) | ~8-12ms |
| Android | ~8-12ms | ~0ms (zero-copy) | ~8-12ms |
| Windows | ~8-12ms | ~3-6ms | ~11-18ms |
| Linux | ~8-12ms | ~2-4ms | ~10-16ms |

All platforms maintain 60fps on modern hardware.

## Build System

### Detection Priority

Each platform's build system uses this priority:

1. **In-repo detection**: If `.git` and `thirdparty/comaps` exist → build from source
2. **CI detection**: If `CI=true` → use plugin-local `prebuilt/` directory
3. **AGUS_MAPS_HOME**: If set → use SDK binaries
4. **Error**: Clear instructions to download SDK

### Build Files

| Platform | Build File | Build System |
|----------|-----------|--------------|
| Android | `android/build.gradle` | Gradle + NDK |
| iOS | `ios/agus_maps_flutter.podspec` | CocoaPods |
| macOS | `macos/agus_maps_flutter.podspec` | CocoaPods |
| Linux | `linux/CMakeLists.txt` | CMake |
| Windows | `windows/CMakeLists.txt` | CMake |

## Related Documentation

- [README.md](README.md) - Quick start and consumer guide
- [doc/CONTRIBUTING.md](doc/CONTRIBUTING.md) - Contributor setup
- [doc/ARCHITECTURE-ANDROID.md](doc/ARCHITECTURE-ANDROID.md) - Android deep dive
- [doc/IMPLEMENTATION-NATIVE-MESSAGE-PASSING.md](doc/IMPLEMENTATION-NATIVE-MESSAGE-PASSING.md) - Native message passing (Pigeon + FFI) details
- [doc/RENDER-LOOP.md](doc/RENDER-LOOP.md) - Render loop comparison
