# Linux Implementation

> **Platform Support:** x86_64 Linux with EGL/OpenGL ES 3.0. Tested on Ubuntu 22.04+ with Mesa drivers.

## Current Status

**🎉 Linux is now fully working!**

| Component | Status |
|-----------|--------|
| **Build** | ✅ Compiles and links successfully |
| **Plugin Registration** | ✅ MethodChannel handler with FlPixelBufferTexture |
| **EGL Context Factory** | ✅ Deferred initialization avoids Flutter EGL conflicts |
| **FBO Rendering** | ✅ Framebuffer object with color texture and depth-stencil |
| **DrapeEngine** | ✅ CoMaps rendering engine creates and renders tiles |
| **Texture Sharing** | ✅ FlPixelBufferTexture with CPU-mediated pixel copy |
| **Touch/Scroll** | ✅ Pan, zoom, and scroll interactions work |
| **Map Loading** | ✅ MWM files load and render correctly |

### Important: Clean Rebuild Required

**CMake does not detect changes to symlinked plugin sources.** After modifying native C++ code, you MUST perform a clean rebuild:

```bash
cd example

# CRITICAL: Remove CMake build cache (flutter clean doesn't do this!)
rm -rf build/linux

# Then clean Flutter and rebuild
flutter clean
flutter run -d linux --release 2>&1 | tee ./output.log
```

**How to verify you have the latest code:**
- Look for: `Using default EGL display` (new code) 
- NOT: `Using MESA surfaceless platform` (old code, surfaceless is now only a fallback)

## Environment Compatibility

The Linux implementation is designed to work across multiple environments:

| Environment | EGL Display | Surface Type | Rendering | Status |
|-------------|-------------|--------------|-----------|--------|
| **Bare metal + NVIDIA GPU** | Default | pbuffer | Hardware accelerated | ✅ Expected to work |
| **Bare metal + AMD GPU** | Default | pbuffer | Hardware accelerated | ✅ Expected to work |
| **Bare metal + Intel GPU** | Default | pbuffer | Hardware accelerated | ✅ Expected to work |
| **Bare metal + llvmpipe (no GPU)** | Default | pbuffer | Software rendered | ✅ Expected to work |
| **WSL2 + llvmpipe** | Default | pbuffer | Software rendered | ✅ Tested |
| **WSL2 + GPU passthrough** | Default | pbuffer | Hardware accelerated | ✅ Expected to work |
| **Headless server** | Default or Surfaceless | pbuffer or surfaceless | Software | ✅ Expected to work |
| **Docker container** | Default or Surfaceless | pbuffer or surfaceless | Software | ✅ Expected to work |

### Display Selection Strategy

The implementation uses a prioritized display selection strategy:

1. **Try default EGL display first** (`eglGetDisplay(EGL_DEFAULT_DISPLAY)`)
   - Works with hardware GPUs (NVIDIA, AMD, Intel)
   - Works with software rendering (llvmpipe, softpipe)
   - Most widely compatible option

2. **Fall back to surfaceless platform** (only if default fails)
   - Uses `EGL_PLATFORM_SURFACELESS_MESA` via `eglGetPlatformDisplayEXT()`
   - Designed for headless/embedded systems
   - Does not require a display server (X11/Wayland)

### Why Default Display is Preferred

On WSL2 and some VM environments, the MESA surfaceless platform advertises support but doesn't work reliably with llvmpipe software rendering. The default display with pbuffer surfaces provides better compatibility:

- llvmpipe supports pbuffer surfaces for offscreen rendering
- pbuffer surfaces are more widely tested and supported
- Surfaceless platform has edge cases with `eglMakeCurrent` returning `EGL_BAD_ACCESS`

### GPU Access on WSL2

If you want hardware acceleration on WSL2 (instead of llvmpipe software rendering), add your user to the `render` group:

```bash
sudo usermod -aG render $USER
# Log out and back in for changes to take effect
```

This grants access to `/dev/dri/renderD128` for GPU passthrough.

## Architecture Overview

The Linux implementation uses a CPU-mediated pixel copy approach similar to Windows, as direct OpenGL texture sharing between EGL contexts and Flutter's GDK GL context requires complex context sharing setup.

### Rendering Pipeline

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        Linux (EGL + OpenGL ES 3.0)                      │
├─────────────────────────────────────────────────────────────────────────┤
│  CoMaps → EGL context (pbuffer surface) → OpenGL FBO → Color Texture    │
│                          ↓                                              │
│  glReadPixels() → CPU Staging Buffer → FlPixelBufferTexture → Flutter   │
│                                                                         │
│  ⚠ CPU-mediated copy: NOT zero-copy like Android/iOS/macOS             │
│  ⚠ ~2-5ms per frame for 1080p (glReadPixels latency)                   │
│  ⚠ Vertical flip during copy (OpenGL bottom-left → Flutter top-left)   │
│  ✓ Works on bare metal Linux, WSL2, and headless servers               │
│  ✓ Compatible with hardware GPUs (NVIDIA/AMD/Intel) and software       │
│    rendering (llvmpipe)                                                 │
│  ✓ Surfaceless context fallback for systems without pbuffer support     │
└─────────────────────────────────────────────────────────────────────────┘
```

### Why Not Zero-Copy on Linux?

Unlike Android (SurfaceTexture), iOS/macOS (CVPixelBuffer + IOSurface), and even Windows (D3D11 shared textures), **Linux has no standardized zero-copy path between separate EGL contexts and Flutter's texture system**.

Flutter's Linux embedder uses `FlPixelBufferTexture`, which expects CPU pixel data:

| Platform | Texture Sharing | Copy Type | Latency |
|----------|-----------------|-----------|----------|
| Android | `SurfaceTexture` (native handle) | Zero-copy | <0.5ms |
| iOS/macOS | `CVPixelBuffer` + `IOSurface` | Zero-copy | <0.5ms |
| Windows | D3D11 Shared Texture* | CPU copy | 2-5ms |
| **Linux** | `FlPixelBufferTexture` | CPU copy | 2-5ms |

*Windows uses `glReadPixels` → D3D11 upload, similar latency to Linux.

Potential future zero-copy paths for Linux:
- DMA-BUF export via `EGL_MESA_image_dma_buf_export` → Flutter GDK import
- Shared EGL/GDK GL context (complex, requires Flutter embedder changes)
- Wayland buffer sharing via `wl_buffer`

### Key Components

| Component | File | Purpose |
|-----------|------|---------|
| **EGL Context Factory** | `src/AgusEglContextFactory.cpp` | Creates EGL contexts and FBO for offscreen rendering |
| **Linux FFI** | `src/agus_maps_flutter_linux.cpp` | Native implementation with Platform methods and DrapeEngine |
| **Flutter Plugin** | `linux/agus_maps_flutter_plugin.cc` | FlPixelBufferTexture registration and method channel |

## Implementation Details

### 1. EGL Context Factory (`AgusEglContextFactory`)

The EGL context factory provides offscreen OpenGL rendering capabilities:

- **Default display preferred**: Uses `eglGetDisplay(EGL_DEFAULT_DISPLAY)` for maximum compatibility
- **Surfaceless context fallback**: Uses `EGL_KHR_surfaceless_context` only if default display fails
- **pbuffer surfaces**: Creates pbuffer surfaces for offscreen rendering on default display
- **OpenGL ES 3.0 contexts**: Creates shared draw and upload contexts for DrapeEngine
- **FBO rendering**: Renders to a framebuffer object backed by a GL texture
- **Pixel buffer copy**: Provides `CopyToPixelBuffer()` for Flutter texture integration
- **Deferred initialization**: Framebuffer creation deferred to render thread to avoid Flutter EGL context conflicts

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

### Issue 6: EGL Context Creation Fails on WSL2/Headless Systems

**Symptom:** Map surface creation fails with error message:
```
[CoMaps/ERROR] src/AgusEglContextFactory.cpp:291 InitializeEGL(): Failed to make draw context current
[CoMaps/ERROR] src/AgusEglContextFactory.cpp:168 AgusEglContextFactory(): Failed to initialize EGL
[AgusMapsFlutter] ERROR: Failed to create EGL context factory
```

**Root Cause:** On WSL2 with WSLg or headless Linux systems, `eglGetDisplay(EGL_DEFAULT_DISPLAY)` returns a display backed by software rendering (e.g., `llvmpipe`) or a surfaceless/GBM Mesa implementation. These displays may not properly support pbuffer surfaces for OpenGL ES 3.0 rendering.

The original implementation required pbuffer surfaces (`EGL_SURFACE_TYPE, EGL_PBUFFER_BIT`) in the EGL config, but this requirement can fail on:
- WSL2 with WSLg (uses Mesa surfaceless or GBM backend)
- Headless servers without X11/Wayland
- Systems with only software rendering (llvmpipe)
- Virtual machines without GPU passthrough

**Solution:** Implemented `EGL_KHR_surfaceless_context` support with automatic fallback:

1. **Detect EGL extensions at startup:**
   - Check for `EGL_EXT_platform_base` (client extension)
   - Check for `EGL_MESA_platform_surfaceless` (client extension)
   - Check for `EGL_KHR_surfaceless_context` (display extension)

2. **Use surfaceless platform if available:**
   ```cpp
   auto eglGetPlatformDisplayEXT = (PFNEGLGETPLATFORMDISPLAYEXTPROC)
       eglGetProcAddress("eglGetPlatformDisplayEXT");
   m_display = eglGetPlatformDisplayEXT(EGL_PLATFORM_SURFACELESS_MESA, 
                                         EGL_DEFAULT_DISPLAY, nullptr);
   ```

3. **Skip pbuffer surfaces in surfaceless mode:**
   - Use `EGL_SURFACE_TYPE = 0` (not pbuffer) in surfaceless mode config
   - Use `EGL_NO_SURFACE` for `eglMakeCurrent()` calls
   - FBO rendering still works (renders to texture, not surface)

4. **Automatic fallback chain:**
   - Try surfaceless platform → Try pbuffer surfaces → Fallback to surfaceless context

**Key changes:**

| Component | Change |
|-----------|--------|
| `InitializeEGL()` | Added extension detection and multi-platform support |
| `AgusEglContext::MakeCurrent()` | Uses `EGL_NO_SURFACE` in surfaceless mode |
| Config selection | Uses `EGL_SURFACE_TYPE = 0` in surfaceless mode (required!) |
| Error handling | Added `EglErrorString()` helper for detailed error messages |

**New member variable:**
```cpp
bool m_useSurfaceless = false;  // EGL_KHR_surfaceless_context mode
```

**Environment compatibility matrix:**

| Environment | EGL Display | Surface Mode | Notes |
|-------------|-------------|--------------|-------|
| Native Linux + GPU | Default | pbuffer | Hardware accelerated |
| WSL2 + WSLg | Surfaceless MESA | surfaceless | Software rendered via llvmpipe |
| Headless server | Surfaceless MESA | surfaceless | No display required |
| VM without GPU | Default/Surfaceless | surfaceless fallback | Software rendered |

### Issue 7: eglChooseConfig Returns 0 Configs on MESA Surfaceless Platform

**Symptom:** EGL initializes successfully but config selection fails:
```
[CoMaps/INFO] src/AgusEglContextFactory.cpp:266 InitializeEGL(): EGL client extensions - platform_base: 1 surfaceless: 1
[CoMaps/INFO] src/AgusEglContextFactory.cpp:279 InitializeEGL(): Using MESA surfaceless platform
[CoMaps/INFO] src/AgusEglContextFactory.cpp:305 InitializeEGL(): EGL initialized: 1 . 5
[CoMaps/INFO] src/AgusEglContextFactory.cpp:309 InitializeEGL(): EGL_KHR_surfaceless_context: 1
[CoMaps/ERROR] src/AgusEglContextFactory.cpp:357 InitializeEGL(): eglChooseConfig failed: EGL_SUCCESS numConfigs: 0
```

**Root Cause:** When using `EGL_PLATFORM_SURFACELESS_MESA`, the surfaceless platform **requires** `EGL_SURFACE_TYPE = 0` to be explicitly set in the config attributes. Simply omitting `EGL_SURFACE_TYPE` is not sufficient - the EGL implementation may default to requiring some surface type, which surfaceless platforms cannot provide.

The initial fix (Session 5) only removed the `EGL_SURFACE_TYPE` attribute when in surfaceless mode, but this caused `eglChooseConfig` to return 0 matching configs because:
1. MESA surfaceless implementation provides configs with `EGL_SURFACE_TYPE = 0` only
2. Without explicitly requesting `EGL_SURFACE_TYPE = 0`, the EGL implementation may filter out these configs
3. No configs match, so the initialization fails

**Solution:** Explicitly set `EGL_SURFACE_TYPE = 0` for surfaceless mode and implement progressive config relaxation:

```cpp
// Surface type: pbuffer for regular, 0 for surfaceless (must be explicit!)
configAttribs[idx++] = EGL_SURFACE_TYPE;
configAttribs[idx++] = m_useSurfaceless ? 0 : EGL_PBUFFER_BIT;
```

Additionally, implemented a fallback mechanism that tries progressively more relaxed config requirements:

1. **Full config**: 8-bit RGBA, 24-bit depth, 8-bit stencil
2. **Reduced depth**: 8-bit RGBA, 16-bit depth, 8-bit stencil  
3. **Minimal depth/stencil**: 8-bit RGBA, 16-bit depth, no stencil
4. **No depth/stencil**: 8-bit RGBA only
5. **Last resort**: Only `EGL_RENDERABLE_TYPE = EGL_OPENGL_ES3_BIT`

**Key code change:**
```cpp
struct ConfigAttempt {
  const char* description;
  EGLint surfaceType;
  EGLint depthSize;
  EGLint stencilSize;
};

ConfigAttempt attempts[] = {
  { "full (depth24/stencil8)", m_useSurfaceless ? 0 : EGL_PBUFFER_BIT, 24, 8 },
  { "reduced depth (depth16/stencil8)", m_useSurfaceless ? 0 : EGL_PBUFFER_BIT, 16, 8 },
  { "minimal (depth16/stencil0)", m_useSurfaceless ? 0 : EGL_PBUFFER_BIT, 16, 0 },
  { "no depth/stencil", m_useSurfaceless ? 0 : EGL_PBUFFER_BIT, 0, 0 },
};

for (const auto& attempt : attempts) {
  // Try config, break on success
}
```

**Why this matters:**
- Software renderers (llvmpipe) may not support high depth buffer precision
- Some embedded/VM environments have limited GPU capabilities
- Progressive fallback ensures maximum compatibility while preferring best quality

### Issue 8: eglMakeCurrent Fails with EGL_BAD_ACCESS on MESA Surfaceless

**Symptom:** After successfully selecting an EGL config, `eglMakeCurrent` fails:
```
[CoMaps/INFO] src/AgusEglContextFactory.cpp:363 InitializeEGL(): EGL config selected with full (depth24/stencil8) - numConfigs: 1
[CoMaps/INFO] src/AgusEglContextFactory.cpp:438 InitializeEGL(): Using surfaceless mode: 1
[CoMaps/ERROR] src/AgusEglContextFactory.cpp:475 InitializeEGL(): Failed to make draw context current: EGL_BAD_ACCESS surfaceless: 1
```

Also seen in logs:
```
libEGL warning: failed to open /dev/dri/renderD128: Permission denied
```

**Root Cause:** On WSL2 with WSLg, the `EGL_PLATFORM_SURFACELESS_MESA` was being preferred, but:
1. Without GPU passthrough permissions (`/dev/dri/renderD128` access denied), Mesa falls back to llvmpipe (software rendering)
2. llvmpipe's surfaceless implementation has known issues with `eglMakeCurrent` returning `EGL_BAD_ACCESS`
3. The surfaceless platform is designed for headless servers, not for desktop environments where a regular display is available

**Solution:** Changed the initialization order to prefer default display with pbuffer surfaces:

1. **Try default display first** (works reliably with llvmpipe software rendering)
2. **Fall back to surfaceless platform** only if default display fails

```cpp
// Strategy: Try default display first (more reliable), then surfaceless as fallback
// Default display with pbuffer works better on most systems including WSL2 with llvmpipe

// First, try the default display
m_display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
if (m_display != EGL_NO_DISPLAY)
{
  LOG(LINFO, ("Using default EGL display"));
  m_useSurfaceless = false;
}
else if (hasPlatformBase && hasSurfaceless)
{
  // Fallback to surfaceless platform if default display failed
  // ... surfaceless initialization ...
}
```

**Why default display works better:**
- Default display on WSL2 uses Mesa's EGL implementation with llvmpipe
- llvmpipe supports pbuffer surfaces for offscreen rendering
- pbuffer surfaces are more widely supported than surfaceless contexts
- Surfaceless platform is a specialized mode that may not work with all drivers

**Alternative fix (for GPU access):**
If you want to use hardware acceleration on WSL2, add your user to the `render` group:
```bash
sudo usermod -aG render $USER
# Log out and back in for changes to take effect
```

### Issue 9: Map Files Not Found (Path Mismatch)

**Symptom:** Framework initialization succeeds but maps fail to load:
```
[CoMaps/WARN] platform/local_country_file_utils.cpp:272 FindAllLocalMapsAndCleanup(): Can't find any: World Reason: File World.mwm doesn't exist in the scope r
w:  $HOME/.local/share/agus_maps_flutter/
r:  $HOME/.local/share/agus_maps_flutter/
s:
```

Yet the extraction logs show the files exist:
```
[AgusMapsFlutter] Map already exists at: $HOME/.local/share/agus_maps_flutter/maps/World.mwm
```

**Root Cause:** Path mismatch between extraction and framework search:
- **Extraction**: Maps were being extracted to `<data_dir>/maps/World.mwm` (with `maps/` subdirectory)
- **Framework**: Searches in `<data_dir>/World.mwm` (directly in root, no subdirectory)

The CoMaps `Platform` class searches for `.mwm` files directly in the configured resource/writable paths. The Linux `extract_map()` function was creating a `maps/` subdirectory that doesn't exist on other platforms (iOS/macOS extract directly to documents directory).

**Solution:** Changed `extract_map()` to extract directly to the data directory without the `maps/` subdirectory:

```cpp
// Before (incorrect):
fs::path maps_dir = data_dir_path / "maps";
fs::create_directories(maps_dir);
fs::path dest_path = maps_dir / filename;

// After (correct):
// Extract directly to data_dir (NOT to maps/ subdirectory)
// This matches iOS/macOS behavior and how CoMaps Platform searches for files
fs::create_directories(data_dir_path);
fs::path dest_path = data_dir_path / filename;
```

**Cross-platform consistency:**

| Platform | Extraction Path | Notes |
|----------|-----------------|-------|
| iOS | `~/Documents/World.mwm` | Direct to documents |
| macOS | `~/Documents/World.mwm` | Direct to documents |
| Linux | `~/.local/share/app/World.mwm` | Direct to data dir (fixed) |
| Windows | `%APPDATA%\app\World.mwm` | Direct to app data |
| Android | Internal storage root | Direct extraction |

**Cleanup:** Users who have already run the app may have maps in the old `maps/` subdirectory. To fix:
```bash
# Move files from maps/ subdirectory to parent
cd ~/.local/share/agus_maps_flutter
mv maps/*.mwm .
rmdir maps
```

Or simply clear the data directory and let the app re-extract:
```bash
rm -rf ~/.local/share/agus_maps_flutter
```

### Issue 10: EGL_BAD_ACCESS During Plugin Initialization (Complete Deferred Init)

**Symptom:** Even after fixing display selection priority, `eglMakeCurrent` still fails:
```
[CoMaps/INFO] src/AgusEglContextFactory.cpp:275 InitializeEGL(): Using default EGL display
[CoMaps/INFO] src/AgusEglContextFactory.cpp:367 InitializeEGL(): EGL config selected with full (depth24/stencil8) - numConfigs: 1
[CoMaps/ERROR] src/AgusEglContextFactory.cpp:508 CreateFramebuffer(): Failed to make context current in CreateFramebuffer: EGL_BAD_ACCESS surfaceless: 0
```

> **⚠️ CMake Cache Issue:** If you still see "Using MESA surfaceless platform" in your logs after updating the code, the build cache is stale. CMake doesn't detect changes to symlinked plugin sources. Run `rm -rf build/linux && flutter clean` before rebuilding.

Or with surfaceless mode:
```
[CoMaps/INFO] src/AgusEglContextFactory.cpp:286 InitializeEGL(): Using MESA surfaceless platform
[CoMaps/INFO] src/AgusEglContextFactory.cpp:487 InitializeEGL(): EGL contexts created successfully (GL init deferred)
[CoMaps/ERROR] src/AgusEglContextFactory.cpp:508 CreateFramebuffer(): Failed to make context current in CreateFramebuffer: EGL_BAD_ACCESS surfaceless: 1
```

**Root Cause:** The `AgusEglContextFactory` constructor calls `CreateFramebuffer()`, which runs on the **main thread** where Flutter's Linux embedder has its own EGL context current. Even though we deferred `GLFunctions::Init()` to `CreateFramebuffer()`, the constructor still runs on the main thread, causing the same conflict.

Unlike Windows (`wglMakeCurrent` can "steal" context from other threads), EGL strictly enforces that a context can only be current on one thread at a time. When Flutter's context is current on the main thread and we try to make our context current, `EGL_BAD_ACCESS` is returned.

**Solution:** Complete deferred initialization - defer BOTH GL function init AND framebuffer creation to the first `GetDrawContext()` call, which happens on the render thread:

1. **Constructor** - Only creates EGL display, config, contexts, and surfaces (no `eglMakeCurrent`)
2. **GetDrawContext()** (called on render thread) - Creates framebuffer and initializes GL functions

```cpp
// Constructor - no framebuffer creation
AgusEglContextFactory::AgusEglContextFactory(...)
{
  if (!InitializeEGL()) { return; }
  
  // Do NOT create framebuffer here - runs on main thread
  m_framebufferDeferred = true;
  m_initialized = true;  // Valid for DrapeEngine creation
}

// GetDrawContext() - called on render thread
dp::GraphicsContext* AgusEglContextFactory::GetDrawContext()
{
  // Deferred framebuffer creation
  if (m_framebufferDeferred && m_framebuffer == 0)
  {
    if (!CreateFramebuffer(m_width, m_height))
    {
      m_initialized = false;
      return nullptr;
    }
    m_framebufferDeferred = false;
  }
  // ... create context wrapper ...
}
```

**Thread timeline with complete deferral:**
```
Main Thread (Plugin Init):
  ├─ Flutter has EGL context current
  ├─ agus_maps_flutter plugin registers
  ├─ AgusEglContextFactory constructor:
  │   ├─ InitializeEGL() creates display, config, contexts (no MakeCurrent) ✓
  │   ├─ Sets m_framebufferDeferred = true
  │   └─ Returns success
  └─ DrapeEngine can be created (factory is valid)

Render Thread (First Frame):
  ├─ GetDrawContext() called
  ├─ Detects m_framebufferDeferred = true
  ├─ CreateFramebuffer():
  │   ├─ eglMakeCurrent() succeeds (no conflict) ✓
  │   ├─ GLFunctions::Init() succeeds ✓
  │   └─ FBO created ✓
  └─ Returns draw context, rendering begins
```

**New member variable:**
```cpp
bool m_framebufferDeferred = false;  // Framebuffer creation deferred until GetDrawContext()
```

**Additional fix - Display selection order:**
Changed to prefer default display (pbuffer) over surfaceless:
- MESA surfaceless platform with llvmpipe has issues even on render thread
- Default display with pbuffer surfaces works reliably with software rendering
- Surfaceless only used as last-resort fallback if default display fails

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

# CRITICAL: Always clean CMake cache when modifying native C++ code!
# flutter clean does NOT clean native build cache.
# CMake symlinks to plugin sources don't trigger rebuild detection.
rm -rf build/linux

flutter clean
flutter run -d linux --release 2>&1 | tee ./output.log
```

### Verifying the Build

After building, check the logs to verify you're running the latest code:

**Expected (correct):**
```
[CoMaps/INFO] src/AgusEglContextFactory.cpp:XXX InitializeEGL(): Using default EGL display
[CoMaps/INFO] src/AgusEglContextFactory.cpp:XXX AgusEglContextFactory(): EGL context factory created successfully (framebuffer deferred)
```

**Stale cache (needs rm -rf build/linux):**
```
[CoMaps/INFO] src/AgusEglContextFactory.cpp:286 InitializeEGL(): Using MESA surfaceless platform
```

The "Using MESA surfaceless platform" message as the **first choice** indicates old code. In the current implementation, default display is tried first, and surfaceless is only used as a fallback.

### WSL2-Specific Notes

On WSL2 without GPU passthrough, you'll see:
```
libEGL warning: failed to open /dev/dri/renderD128: Permission denied
```

This is **expected and harmless** - Mesa falls back to llvmpipe (software rendering). The default EGL display with pbuffer surfaces works correctly with llvmpipe.

To enable GPU passthrough (optional):
```bash
sudo usermod -aG render $USER
# Log out and back in
```

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

### 2026-01-07 (Session 8) - Documentation and Texture Sharing Clarification

- **Documentation**: Updated IMPLEMENTATION-LINUX.md with:
  - Clear explanation that Linux uses CPU-mediated copy (NOT zero-copy)
  - Comparison table with other platforms' texture sharing mechanisms
  - CMake cache rebuild requirements and verification steps
  - WSL2-specific troubleshooting notes
  - Explanation of why zero-copy isn't possible with current Flutter Linux embedder

- **Documentation**: Updated README.md with:
  - Linux status clarification (CPU-mediated ~2-5ms latency)
  - Platform support table notes about Windows/Linux texture sharing

### 2026-01-07 (Session 7) - Map Path Fix and Complete Deferred EGL Initialization

- **Fixed**: Map files not found due to path mismatch (Issue 9)
  - **Root cause**: Linux `extract_map()` extracted to `<data_dir>/maps/` subdirectory, but CoMaps Platform searches directly in `<data_dir>/`
  - **Symptom**: `FindAllLocalMapsAndCleanup(): Can't find any: World` despite files existing
  - **Solution**: Changed extraction to place files directly in data directory (matches iOS/macOS behavior)
  - **File changed**: `linux/agus_maps_flutter_plugin.cc` - `extract_map()` function

- **Fixed**: `EGL_BAD_ACCESS` during plugin initialization even with default display (Issue 10)
  - **Root cause**: Flutter's Linux embedder has EGL context current on main thread during plugin init
  - **Symptom**: `eglMakeCurrent` fails because Flutter's context is active on the same display
  - **Solution**: Complete deferred initialization - both GL functions AND framebuffer creation deferred to render thread
  - **Files changed**: 
    - `src/AgusEglContextFactory.cpp` - Deferred framebuffer to `GetDrawContext()`, prefer default display over surfaceless
    - `src/AgusEglContextFactory.hpp` - Added `m_framebufferDeferred` member

- **Changed**: Display selection order back to default-first
  - MESA surfaceless platform with llvmpipe doesn't work reliably
  - Default display with pbuffer surfaces works correctly with software rendering
  - Surfaceless only used as last resort fallback

- **Updated**: Documentation with Issues 9 and 10 details

### 2026-01-07 (Session 6) - EGL Config Selection and Display Priority Fix

- **Fixed**: `eglChooseConfig` returns 0 configs on MESA surfaceless platform (Issue 7)
  - **Root cause**: MESA surfaceless platform requires `EGL_SURFACE_TYPE = 0` explicitly set
  - **Symptom**: `eglChooseConfig failed: EGL_SUCCESS numConfigs: 0` even though EGL initialized
  - **Solution**: Explicitly set surface type based on mode (`0` for surfaceless, `EGL_PBUFFER_BIT` otherwise)

- **Added**: Progressive config fallback mechanism for maximum compatibility
  1. Full config: depth24/stencil8
  2. Reduced depth: depth16/stencil8
  3. Minimal: depth16/no stencil
  4. No depth/stencil
  5. Last resort: only renderable type (minimal requirements)

- **Fixed**: Compilation error - `LWARN` macro doesn't exist, should be `LWARNING`

- **Fixed**: `eglMakeCurrent` fails with `EGL_BAD_ACCESS` on MESA surfaceless platform (Issue 8)
  - **Root cause**: On WSL2, surfaceless platform with llvmpipe doesn't work reliably
  - **Symptom**: `Failed to make draw context current: EGL_BAD_ACCESS surfaceless: 1`
  - **Also seen**: `libEGL warning: failed to open /dev/dri/renderD128: Permission denied`
  - **Solution**: Changed initialization order to prefer default display with pbuffer surfaces
  - Default display works reliably with llvmpipe software rendering
  - Surfaceless platform only used as fallback if default display fails

### 2026-01-07 (Session 5) - Surfaceless EGL Context Support for WSL2/Headless

- **Fixed**: `eglMakeCurrent` fails with `EGL_BAD_ACCESS` or similar errors on WSL2/headless Linux
  - **Root cause**: On WSL2 with WSLg or headless systems, `eglGetDisplay(EGL_DEFAULT_DISPLAY)` returns a GBM or software-rendered display (e.g., `llvmpipe`) that may not properly support pbuffer surfaces with GLES3
  - **Symptom**: Logs showed `[CoMaps/ERROR] src/AgusEglContextFactory.cpp:291 InitializeEGL(): Failed to make draw context current` during surface creation
  
- **Solution**: Implemented EGL surfaceless context support (`EGL_KHR_surfaceless_context`)
  - **Primary approach**: Use `EGL_MESA_platform_surfaceless` via `eglGetPlatformDisplayEXT()` for offscreen rendering
  - **Fallback**: If surfaceless platform unavailable, try pbuffer surfaces with default display
  - **Second fallback**: If pbuffer creation fails but `EGL_KHR_surfaceless_context` is available, fall back to surfaceless mode

- **New helper functions added**:
  - `EglErrorString()`: Converts EGL error codes to human-readable strings for better debugging
  - `HasEglExtension()`: Checks for EGL extension support on both client and display level

- **Modified `InitializeEGL()` method**:
  1. First checks for `EGL_EXT_platform_base` and `EGL_MESA_platform_surfaceless` client extensions
  2. If available, uses `eglGetPlatformDisplayEXT(EGL_PLATFORM_SURFACELESS_MESA, ...)` for the display
  3. Falls back to `eglGetDisplay(EGL_DEFAULT_DISPLAY)` if surfaceless platform not available
  4. Checks `EGL_KHR_surfaceless_context` support on the initialized display
  5. Skips pbuffer surface creation when using surfaceless mode
  6. Uses `EGL_NO_SURFACE` for `eglMakeCurrent()` in surfaceless mode

- **Modified `AgusEglContext` class**:
  - Added `m_surfaceless` flag to track surfaceless mode
  - `MakeCurrent()` now uses `EGL_NO_SURFACE` for both read and draw surfaces in surfaceless mode
  
- **Modified other methods for surfaceless compatibility**:
  - `CreateFramebuffer()`: Uses correct surface based on `m_useSurfaceless` flag
  - `CleanupFramebuffer()`: Uses correct surface based on `m_useSurfaceless` flag
  - `GetDrawContext()` / `GetResourcesUploadContext()`: Pass surfaceless flag to context wrapper

- **New member variable in `AgusEglContextFactory`**:
  - `bool m_useSurfaceless`: Tracks whether surfaceless mode is active

- **Added EGL extension headers and defines**:
  - Included `<EGL/eglext.h>` for extension function types
  - Added `EGL_PLATFORM_SURFACELESS_MESA` (0x31DD) and `EGL_PLATFORM_GBM_MESA` (0x31D7) defines

- **Environment compatibility**:
  | Environment | Primary Approach | Fallback |
  |-------------|------------------|----------|
  | WSL2 + WSLg | Surfaceless (MESA) | pbuffer → surfaceless |
  | Native X11/Wayland | pbuffer surfaces | surfaceless if pbuffer fails |
  | Headless (no display) | Surfaceless (MESA) | N/A |
  | llvmpipe (software) | Surfaceless | pbuffer if extensions missing |

### 2026-01-06 (Session 3: CI/CD)

- **Added**: `dart run tool/build.dart --build-binaries --platform linux` to build Linux native libraries
  - Builds `libagus_maps_flutter.so` for x86_64 architecture
  - Validates prerequisites (CMake, Ninja, development packages)
  - Creates `build/agus-binaries-linux.zip` artifact

- **Added**: Linux CI/CD job in `.github/workflows/devops.yml`
  - Runs on `ubuntu-latest` GitHub Actions runner
  - Uses Azure Blob Storage cache for CoMaps source (similar to other platforms)
  - Installs Linux build dependencies: `libgl-dev`, `libegl-dev`, `libgles-dev`, `libepoxy-dev`, `libgtk-3-dev`
  - Builds native libraries and Flutter example app
  - Produces artifacts: `agus-binaries-linux.zip` and `agus-maps-linux.zip`

- **Updated**: `doc/RELEASE.md` with Linux installation instructions
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
