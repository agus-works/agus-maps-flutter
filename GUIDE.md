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
- View state changes (resize, DPI change)

When idle, CPU and GPU sleep, preserving battery life.

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
- Applying patches
- Building native binaries for all platforms
- Generating assets

> **Important:** Do NOT set `AGUS_MAPS_HOME` when working as a contributor.

#### 2. CI/CD Environment

GitHub Actions builds are detected via `CI=true`. The workflow:
1. Builds binaries from source
2. Copies binaries to `{platform}/prebuilt/` directories
3. Packages everything into `agus-maps-sdk-vX.Y.Z.zip`

#### 3. Plugin Consumers (SDK-based)

For developers using the published plugin:

1. Add dependency: `agus_maps_flutter: ^X.Y.Z`
2. Download `agus-maps-sdk-v0.1.7.zip` from [GitHub Releases](https://github.com/agus-works/agus-maps-flutter/releases)
3. Extract and set environment variable:
   ```bash
   export AGUS_MAPS_HOME=/path/to/agus-maps-sdk-v0.1.7
   ```
4. Copy assets to your Flutter app
5. Build your app

### SDK Structure

```
agus-maps-sdk-vX.Y.Z/
├── android/prebuilt/
│   ├── arm64-v8a/
│   ├── armeabi-v7a/
│   └── x86_64/
├── ios/Frameworks/
│   └── CoMaps.xcframework/
├── macos/Frameworks/
│   └── CoMaps.xcframework/
├── windows/prebuilt/x64/
├── linux/prebuilt/x64/
├── assets/
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
- [doc/RENDER-LOOP.md](doc/RENDER-LOOP.md) - Render loop comparison
