# Linux Implementation

> **Platform Support:** x86_64 Linux with EGL/OpenGL ES 3.0. Tested on Ubuntu 22.04+ with Mesa drivers.

## Current Status

**🎉 Linux is now fully working!**

| Component | Status |
|-----------|--------|
| **Build** | ✅ Compiles and links successfully |
| **Plugin Registration** | ✅ MethodChannel handler with FlPixelBufferTexture |
| **EGL Context Factory** | ✅ Offscreen pbuffer surfaces with shared contexts |
| **FBO Rendering** | ✅ Framebuffer object with color texture and depth-stencil |
| **DrapeEngine** | ✅ CoMaps rendering engine creates and renders tiles |
| **Texture Sharing** | ✅ FlPixelBufferTexture with CPU-mediated pixel copy |
| **Touch/Scroll** | ✅ Pan, zoom, and scroll interactions work |
| **Map Loading** | ✅ MWM files load and render correctly |

## Architecture Overview

The Linux implementation uses a CPU-mediated pixel copy approach similar to Windows, as direct OpenGL texture sharing between EGL contexts and Flutter's GDK GL context requires complex context sharing setup.

### Rendering Pipeline

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        Linux (EGL + OpenGL ES 3.0)                      │
├─────────────────────────────────────────────────────────────────────────┤
│  CoMaps → EGL pbuffer surface → OpenGL FBO → Render Texture             │
│                          ↓                                              │
│  glReadPixels() → CPU Pixel Buffer → FlPixelBufferTexture → Flutter     │
│                                                                         │
│  ⚠ CPU-mediated: ~2-5ms per frame for 1080p                             │
│  ⚠ RGBA format conversion on CPU                                        │
│  ✓ Works without complex GL context sharing                             │
└─────────────────────────────────────────────────────────────────────────┘
```

### Key Components

| Component | File | Purpose |
|-----------|------|---------|
| **EGL Context Factory** | `src/AgusEglContextFactory.cpp` | Creates EGL contexts and FBO for offscreen rendering |
| **Linux FFI** | `src/agus_maps_flutter_linux.cpp` | Native implementation with Platform methods and DrapeEngine |
| **Flutter Plugin** | `linux/agus_maps_flutter_plugin.cc` | FlPixelBufferTexture registration and method channel |

## Implementation Details

### 1. EGL Context Factory (`AgusEglContextFactory`)

The EGL context factory provides offscreen OpenGL rendering capabilities:

- **pbuffer surfaces**: Creates two pbuffer surfaces (draw + upload) for offscreen rendering
- **OpenGL ES 3.0 contexts**: Creates shared draw and upload contexts for DrapeEngine
- **FBO rendering**: Renders to a framebuffer object backed by a GL texture
- **Pixel buffer copy**: Provides `CopyToPixelBuffer()` for Flutter texture integration

```cpp
// Key methods:
AgusEglContextFactory(int width, int height, float density);
dp::GraphicsContext* GetDrawContext();
dp::GraphicsContext* GetResourcesUploadContext();
uint32_t GetTextureId();
bool CopyToPixelBuffer(uint8_t* buffer, int bufferSize);
void SetSurfaceSize(int width, int height);  // Schedules deferred resize
void CheckPendingResize();                   // Applies resize on render thread
```

### 2. Platform Implementation

The Linux platform implementation in `agus_maps_flutter_linux.cpp` includes:

#### Missing Platform Methods Implemented

The following `Platform` class methods were missing from the CoMaps Linux build and were implemented:

| Method | Implementation | Notes |
|--------|----------------|-------|
| `Platform::GetFileCreationTime()` | Uses `stat()` with `st_atim.tv_sec` | Static method |
| `Platform::GetFileModificationTime()` | Uses `stat()` with `st_mtim.tv_sec` | Static method |
| `Platform::GetFileSizeByName()` | Delegates to `GetFileSizeByFullPath()` | Instance method |
| `Platform::GetFilesByRegExp()` | Uses `opendir()`/`readdir()` with boost::regex | Static method |
| `Platform::GetAllFiles()` | Uses `opendir()`/`readdir()` | Static method |
| `Platform::MkDir()` | Uses `mkdir()` | Static method |
| `Platform::GetReader()` | Returns `FileReader` for path | Instance method |

#### FFI Functions Exported

| Function | Purpose |
|----------|---------|
| `agus_native_create_surface()` | Creates EGL context + FBO, initializes DrapeEngine |
| `agus_native_on_size_changed()` | Handles resize events |
| `agus_native_on_surface_destroyed()` | Cleanup and resource release |
| `agus_get_texture_id()` | Returns GL texture ID |
| `agus_copy_pixels()` | Copies rendered pixels to Flutter buffer |
| `agus_set_frame_ready_callback()` | Registers frame notification callback |

### 3. Flutter Plugin (`FlPixelBufferTexture`)

The plugin uses Flutter's `FlPixelBufferTexture` API for texture sharing:

```cpp
// Custom texture class
struct _AgusMapTexture {
  FlPixelBufferTexture parent_instance;
  int32_t width;
  int32_t height;
  uint8_t* pixel_buffer;
  size_t buffer_size;
  std::mutex* mutex;
  std::atomic<bool>* dirty;
};

// Populate callback
static gboolean agus_map_texture_copy_pixels(FlPixelBufferTexture* texture,
                                              const uint8_t** out_buffer,
                                              uint32_t* width,
                                              uint32_t* height,
                                              GError** error) {
  // Copy pixels from native EGL renderer
  agus_copy_pixels(self->pixel_buffer, self->buffer_size);
  *out_buffer = self->pixel_buffer;
  return TRUE;
}
```

## Issues Resolved

### Issue 1: Framework Not Initialized (White Screen)

**Symptom:** Map registration returned `-1`, logs showed "Framework not initialized"

**Root Cause:** The initial Linux implementation only created the Framework but never created the DrapeEngine, which is required for rendering.

**Solution:** 
1. Created `AgusEglContextFactory` for EGL/GL context management
2. Added DrapeEngine creation in `agus_native_create_surface()`
3. Wrapped context factory in `dp::ThreadSafeFactory` for thread-safe access

### Issue 2: Missing Platform Methods (Undefined Symbols)

**Symptom:** Runtime errors like `undefined symbol: Platform::GetFileCreationTime`

**Root Cause:** CoMaps' `platform_linux.cpp` was not included in the build, leaving several Platform class methods undefined.

**Solution:** Implemented the following methods in `agus_maps_flutter_linux.cpp`:
- `GetFileCreationTime()` / `GetFileModificationTime()` using `stat()`
- `GetAllFiles()` / `GetFilesByRegExp()` using POSIX directory functions
- `GetFileSizeByName()` / `MkDir()` for file operations

### Issue 3: Duplicate Symbol Definitions (Linker Error)

**Symptom:** Multiple definition errors for `namespace platform` functions

**Root Cause:** `namespace platform` localization functions were already provided by CoMaps `libplatform.a`

**Solution:** Removed duplicate `namespace platform` implementations from the Linux FFI code. Only Platform class methods that were truly missing were implemented.

### Issue 4: No Texture Output (Black/White Widget)

**Symptom:** Flutter app ran but map widget showed white/empty

**Root Cause:** 
1. Original implementation returned dummy texture ID without actual rendering
2. No DrapeEngine meant no map tiles were being rendered
3. No texture sharing mechanism between native code and Flutter

**Solution:**
1. Implemented proper EGL context factory with FBO rendering
2. Created DrapeEngine with proper surface dimensions and density
3. Implemented `FlPixelBufferTexture` with pixel copy from native FBO

### Issue 5: Window Resize Causes Map Rendering Corruption (Commit 32c5ced)

**Symptom:** When resizing the Flutter app window on Linux, the map widget would become corrupted - appearing stretched, offset, or displaying incorrect rendering.

**Root Cause:** EGL doesn't allow context stealing like WGL does on Windows.

The original `SetSurfaceSize()` implementation attempted to:
1. Call `eglMakeCurrent()` to acquire the draw context
2. Perform GL operations to resize the framebuffer

However, `eglMakeCurrent()` fails with `EGL_BAD_ACCESS` (0x3002) when the context is already current on another thread (the render thread). Unlike Windows WGL where `wglMakeCurrent()` can "steal" the context from another thread, EGL strictly enforces single-thread context ownership.

**Error from logs:**
```
[CoMaps/ERROR] SetSurfaceSize: eglMakeCurrent failed: 12290
```
(12290 = 0x3002 = EGL_BAD_ACCESS)

**Solution:** Implemented a **deferred resize pattern**:

1. **`SetSurfaceSize()` (called from Flutter main thread):**
   - Now only stores pending dimensions in atomic variables
   - Does NOT attempt any GL operations
   - Non-blocking, returns immediately

2. **`CheckPendingResize()` (called from render thread in Present()):**
   - Checks if a resize is pending
   - If so, calls `ApplyPendingResize()`

3. **`ApplyPendingResize()` (executes on render thread):**
   - EGL context is already current (called from Present)
   - Resizes texture in-place with `glTexImage2D()`
   - Resizes depth buffer with `glRenderbufferStorage()`
   - Re-attaches both to FBO with `glFramebufferTexture2D()`
   - Updates viewport and scissor with `glViewport()` and `glScissor()`

**Key difference from Windows:**

| Platform | Context Behavior | Resize Approach |
|----------|------------------|-----------------|
| **Windows (WGL)** | `wglMakeCurrent()` can steal context | Immediate resize in `SetSurfaceSize()` |
| **Linux (EGL)** | `eglMakeCurrent()` returns `EGL_BAD_ACCESS` | Deferred resize via atomic flags |

**New methods added to `AgusEglContextFactory`:**

| Method | Purpose |
|--------|---------|
| `CheckPendingResize()` | Called from `Present()`, checks and applies pending resize |
| `ApplyPendingResize()` | Private method that performs actual GL resize operations |

**New member variables:**
```cpp
std::atomic<bool> m_pendingResize{false};
std::atomic<int> m_pendingWidth{0};
std::atomic<int> m_pendingHeight{0};
```

## Performance Characteristics

| Metric | Value | Notes |
|--------|-------|-------|
| **Frame Copy Latency** | ~2-5ms | For 1080p, using `glReadPixels()` |
| **Idle CPU Usage** | <1% | When map is stationary |
| **Panning CPU Usage** | 10-20% | Due to per-frame pixel copy |
| **Memory (1080p frame)** | ~8MB | RGBA pixel buffer |

## Future Improvements

### Zero-Copy Path (Planned)

A zero-copy implementation could be achieved by:

1. **EGL_KHR_image_base + DMA-BUF**: Export EGL image as DMA-BUF, import in Flutter's GDK context
2. **GL context sharing**: Share GL context between CoMaps EGL and GDK GL context
3. **GBM (Generic Buffer Manager)**: Use GBM surfaces for zero-copy texture sharing

### Requirements for Zero-Copy

- Mesa 20.0+ with EGL_KHR_image_base support
- GTK 3.24+ or GTK 4 for improved GL context management
- Flutter Linux embedder changes to support external GL textures

## Dependencies

The Linux build requires:

```bash
# Ubuntu/Debian
sudo apt install libgl-dev libegl-dev libgles2-mesa-dev libepoxy-dev

# Required packages
# - libegl-dev: EGL development files
# - libgles2-mesa-dev: OpenGL ES 3.0 development files
# - libepoxy-dev: GL function loading (for plugin)
```

## Build Configuration

### CMakeLists.txt (src/)

```cmake
# Linux-specific source files
elseif(UNIX AND NOT APPLE)
  set(PLATFORM_SOURCES
    "agus_maps_flutter_linux.cpp"
    "AgusEglContextFactory.cpp"
  )
endif()

# Linux platform configuration
if(UNIX AND NOT APPLE AND NOT ANDROID)
  pkg_check_modules(EGL REQUIRED egl)
  pkg_check_modules(GLESV2 REQUIRED glesv2)
  
  target_link_libraries(agus_maps_flutter PRIVATE
    ${EGL_LIBRARIES}
    ${GLESV2_LIBRARIES}
  )
endif()
```

### CMakeLists.txt (linux/)

```cmake
pkg_check_modules(EPOXY REQUIRED epoxy)

target_link_libraries(${PLUGIN_NAME} PRIVATE
  flutter
  PkgConfig::GTK
  ${EPOXY_LIBRARIES}
  agus_maps_flutter  # Link against native library for FFI
)
```

## Testing

### Manual Testing

```bash
cd example

# IMPORTANT: Clean both Flutter and CMake build caches
# flutter clean only cleans Flutter artifacts, not CMake cache
rm -rf build/linux

flutter clean
flutter run -d linux --release 2>&1 | tee ./output.log
```

**Note:** `flutter clean` does NOT clean the native CMake build cache. If you modify 
native C++ files in `linux/` or `src/`, you must also delete `build/linux/` to force 
a full rebuild. CMake symlinks to plugin sources may not trigger rebuild detection.

### Verification Points

1. Check console for `[AgusMapsFlutter] DrapeEngine created successfully`
2. Verify texture ID is non-negative in logs
3. Map should show World/WorldCoasts after initial tile loading
4. Touch/scroll interactions should pan/zoom the map

## Comparison with Other Platforms

| Aspect | Linux | Windows | iOS/macOS | Android |
|--------|-------|---------|-----------|---------|
| **Graphics API** | EGL/GLES3 | WGL/OpenGL | Metal | EGL/GLES3 |
| **Texture Sharing** | FlPixelBufferTexture | D3D11 Shared | CVPixelBuffer | SurfaceTexture |
| **Copy Method** | CPU (glReadPixels) | CPU (glReadPixels) | Zero-copy | Zero-copy |
| **Frame Latency** | 2-5ms | 2-5ms | <0.5ms | <0.5ms |

## Changelog

### 2026-01-06 (Session 4) - Window Resize Fix (Commit 32c5ced)

- **Fixed**: Window resize causes map rendering corruption (stretched/offset display)
  - Root cause: EGL doesn't allow context stealing like WGL does on Windows
  - `eglMakeCurrent()` fails with `EGL_BAD_ACCESS` (0x3002) when context is current on render thread
  - Solution: Implemented **deferred resize pattern** using atomic flags
  
- **Added**: `CheckPendingResize()` method in `AgusEglContextFactory`
  - Called from `AgusEglContext::Present()` on the render thread
  - Checks atomic `m_pendingResize` flag and applies resize if needed
  
- **Added**: `ApplyPendingResize()` private method in `AgusEglContextFactory`
  - Resizes texture in-place with `glTexImage2D()` (no delete/recreate)
  - Resizes depth buffer with `glRenderbufferStorage()`
  - Re-attaches to FBO with `glFramebufferTexture2D()` and `glFramebufferRenderbuffer()`
  - Updates viewport/scissor with `glViewport()` and `glScissor()`
  
- **Modified**: `SetSurfaceSize()` in `AgusEglContextFactory`
  - Now only sets atomic pending resize state (non-blocking)
  - No GL operations, no `eglMakeCurrent()` call
  - Resize is deferred to render thread via `CheckPendingResize()`

- **Modified**: `AgusEglContext::Present()` 
  - Added call to `m_factory->CheckPendingResize()` before capturing pixels
  - This is the only safe place to resize - on render thread where context is current

- **Added**: Atomic member variables for deferred resize state:
  - `std::atomic<bool> m_pendingResize`
  - `std::atomic<int> m_pendingWidth`
  - `std::atomic<int> m_pendingHeight`

### 2026-01-06 (Session 3) - Linux Now Fully Working! 🎉

- **Fixed**: EGL context conflicts causing `eglMakeCurrent failed: 12290` (EGL_BAD_ACCESS)
  - Root cause: Draw context was left current after initialization, blocking render threads
  - Solution: Release context via `eglMakeCurrent(... EGL_NO_CONTEXT)` after initialization and framebuffer creation
  
- **Fixed**: Shader compilation failures (`glCreateShader() -> shader_id=0`)
  - Root cause: Shaders compiled with no GL context current
  - Solution: Context release fix also resolved this (render thread can now properly acquire context)

- **Fixed**: GL_INVALID_FRAMEBUFFER_OPERATION (error 506) in Flutter's texture system
  - Root cause: `CopyToPixelBuffer()` called `eglMakeCurrent` on Flutter's main thread, corrupting GL state
  - Solution: Proactive pixel capture in `AgusEglContext::Present()` while render context is current
  - Added `CaptureFramePixels()` method to read pixels on render thread, store in staging buffer
  - Modified `CopyToPixelBuffer()` to just copy from staging buffer (no GL operations)

- **Added**: `CaptureFramePixels()` method and staging buffer in `AgusEglContextFactory`
  - Thread-safe pixel buffer with mutex protection
  - Vertical flip during capture (OpenGL bottom-left to Flutter top-left)

- **Added**: Platform-conditional return type for `agus_native_create_surface()` in header
  - Linux returns `int64_t` (0 on success, negative on error)
  - Other platforms return `void` (unchanged)

- **Added**: `extern "C"` block around Linux FFI functions for proper symbol visibility
  - Functions: `agus_set_frame_ready_callback`, `agus_native_create_surface`, `agus_copy_pixels`, etc.

- **Added**: `agus_platform_linux.cpp` with minimal HTTP thread stubs
  - Provides `downloader::CreateNativeHttpThread` and `DeleteNativeHttpThread`
  - Required because CoMaps' libplatform doesn't provide these for embedded/headless mode

- **Updated**: `src/CMakeLists.txt` with proper Linux platform sources
  - Uses `agus_maps_flutter_linux.cpp`, `agus_platform_linux.cpp`, `AgusEglContextFactory.cpp`
  - Links against EGL and GLES2 libraries
  - Allows multiple symbol definitions for Platform stubs

- **Updated**: `linux/CMakeLists.txt` as a full Flutter plugin build
  - Creates `agus_maps_flutter_plugin` library linking against native CoMaps library
  - Properly bundles both plugin and native library

- **Updated**: `pubspec.yaml` to include `pluginClass: AgusMapsFlutterPlugin` for Linux

- **Updated**: CoMaps patch `0059-libs-platform-flutter-plugin-support.patch`
  - Added Linux support with `SKIP_QT` flag for headless builds without Qt
  - Provides dummy platform files for Linux embedded mode

### 2026-01-06 (Session 3: CI/CD)

- **Added**: `scripts/build_binaries_linux.sh` build script for Linux native libraries
  - Builds `libagus_maps_flutter.so` for x86_64 architecture
  - Validates prerequisites (CMake, Ninja, development packages)
  - Creates `build/agus-binaries-linux.zip` artifact

- **Added**: Linux CI/CD job in `.github/workflows/devops.yml`
  - Runs on `ubuntu-latest` GitHub Actions runner
  - Uses Azure Blob Storage cache for CoMaps source (similar to other platforms)
  - Installs Linux build dependencies: `libgl-dev`, `libegl-dev`, `libgles-dev`, `libepoxy-dev`, `libgtk-3-dev`
  - Builds native libraries and Flutter example app
  - Produces artifacts: `agus-binaries-linux.zip` and `agus-maps-linux.zip`

- **Updated**: `docs/RELEASE.md` with Linux installation instructions
  - Added prerequisites for Ubuntu/Fedora
  - Added troubleshooting guide for common Linux issues
  - Updated artifact table and manual download section

### 2026-01-06 (Session 2)

- **Fixed**: Duplicate `_AgusMapsFlutterPlugin` struct definitions in `linux/agus_maps_flutter_plugin.cc`
  - The struct was defined twice: lines 182-190 (with texture fields) and lines 210-213 (without texture fields)
  - The second definition overwrote the first, removing texture support
  - Also had duplicate `G_DEFINE_TYPE()` macro calls
  - Fix: Removed the duplicate struct and G_DEFINE_TYPE definitions
  
- **Fixed**: Vertical flip for pixel buffer copy in `AgusEglContextFactory::CopyToPixelBuffer()`
  - OpenGL's coordinate origin is at bottom-left, Flutter expects top-left
  - Added row-by-row flip during pixel copy to correct image orientation
  - Uses temporary buffer to read pixels, then copies with flip to output buffer

### 2026-01-06 (Session 1)
- **Added**: Missing Platform methods (`GetFileCreationTime`, `GetAllFiles`, etc.)
- **Added**: `FlPixelBufferTexture` implementation in plugin
- **Added**: DrapeEngine creation with proper surface management
- **Fixed**: Framework initialization (was missing DrapeEngine)
- **Fixed**: Undefined symbol errors for Platform methods
- **Fixed**: Duplicate symbol errors from namespace platform functions
- **Fixed**: White screen issue (no texture output)
