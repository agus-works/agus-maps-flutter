# Windows Implementation Plan (MVP)

## Current Status

**Build Status:** ✅ Compiles and links successfully  
**Plugin Registration:** ✅ MethodChannel handler implemented  
**Rendering:** ✅ OpenGL context created, D3D11 texture sharing implemented  
**Surface Bridge:** ✅ Plugin now calls FFI library for surface creation  

## Windows Blank/White Map: Common Root Cause

If the map shows a white/blank widget and logs contain errors like:

- `countries-strings\en.json\localize.json doesn't exist`
- `categories-strings\en.json\localize.json doesn't exist`
- `transit_colors.txt doesn't exist`

then the Windows build is missing required bundled CoMaps assets.

### Why this happens

On desktop, Flutter asset bundling does **not** automatically include files from nested subdirectories when only the parent directory is listed in `pubspec.yaml`. CoMaps stores localization data in nested folders like:

- `assets/comaps_data/countries-strings/en.json/localize.json`
- `assets/comaps_data/categories-strings/en.json/localize.json`

So each locale directory must be explicitly listed in `example/pubspec.yaml`.

### Repair behavior

Windows extraction uses a marker file: `Documents/agus_maps_flutter/.comaps_data_extracted`.
The plugin validates the extracted data directory; if required files are missing, it automatically re-extracts and overwrites from the bundled `flutter_assets`.

## Quick Start: Build & Run

### Prerequisites

- Flutter SDK 3.24+ installed
- Visual Studio 2022 with C++ Desktop development workload  
- vcpkg (installed at `C:\vcpkg` or set `VCPKG_ROOT` environment variable)
- PowerShell 7+ (for bootstrap scripts)
- Windows 10 or later
- ~5GB disk space for CoMaps build artifacts

### First-Time Setup

```powershell
# 1. Fetch CoMaps source and apply patches
.\scripts\fetch_comaps.ps1

# 2. Copy CoMaps data files to example assets (PowerShell 7+)
.\scripts\copy_comaps_data.ps1

# If you prefer bash:
#   ./scripts/copy_comaps_data.sh
```

### Debug Mode

Debug mode enables hot reload, step-through debugging, and verbose logging.

```powershell
cd example
flutter run -d windows --debug
```

### Release Mode

Release mode produces an optimized build suitable for production use.

```powershell
cd example
flutter build windows --release

# Run the built executable
.\build\windows\x64\runner\Release\agus_maps_flutter_example.exe
```

**Build output:**
- `agus_maps_flutter_plugin.dll` (~135KB) - MethodChannel handler
- `agus_maps_flutter.dll` (~10MB) - Native CoMaps FFI library
- `zlib1.dll` (~100KB) - Compression library dependency (from vcpkg)

---

## Goal

Get the Windows example app to:

1. Bundle a Gibraltar map file (`Gibraltar.mwm`) as an example asset.
2. On first launch, **extract the map to Documents/agus_maps_flutter/maps/**.
3. Pass the on-disk filesystem path into the native layer (FFI) so the native engine can open it using normal filesystem APIs.
4. Set the initial camera to **Gibraltar** at **zoom 14**.
5. Render the map using **OpenGL** with **D3D11 texture sharing** for Flutter integration.

## Non-Goals (for this MVP)

- Search/routing functionality
- Download manager / storage management
- Vulkan backend (OpenGL is used for Windows MVP)

---

## Architecture Overview

### Two-DLL Architecture

Windows uses a two-DLL architecture:

1. **agus_maps_flutter_plugin.dll** - Flutter plugin that handles:
   - MethodChannel registration with `agus_maps_flutter` channel
   - Asset extraction (`extractMap`, `extractDataFiles`)
   - Path queries (`getApkPath`)
   - Surface management (`createMapSurface`, `resizeMapSurface`, `destroyMapSurface`)

2. **agus_maps_flutter.dll** - Native FFI library that handles:
   - CoMaps core initialization (`comaps_init_paths`)
   - Map rendering via OpenGL
   - Touch event handling
   - Camera control

### OpenGL + D3D11 Texture Sharing

The Windows implementation uses WGL/OpenGL for CoMaps rendering with D3D11 shared textures for Flutter integration.

```
┌─────────────────────────────────────────────────────────────┐
│ Flutter Dart Layer                                          │
│   AgusMap widget → Texture(textureId)                       │
│   AgusMapController → FFI calls                             │
│   MethodChannel('agus_maps_flutter') → Asset extraction     │
├─────────────────────────────────────────────────────────────┤
│ Flutter Windows Engine (Impeller)                           │
│   FlutterTextureRegistrar → GPU Surface Descriptor          │
│   Samples D3D11 texture (zero-copy via DXGI shared handle)  │
├─────────────────────────────────────────────────────────────┤
│ agus_maps_flutter_plugin.dll                                │
│   AgusMapsFlutterPlugin class                               │
│   MethodChannel handler for extractMap, etc.                │
│   FlutterPlugin registration                                │
├─────────────────────────────────────────────────────────────┤
│ agus_maps_flutter.dll                                       │
│   FFI exports: comaps_init_paths, comaps_set_view, etc.     │
│   AgusWglContextFactory → WGL OpenGL context                │
│   D3D11 shared texture with DXGI handle                     │
├─────────────────────────────────────────────────────────────┤
│ CoMaps Core (built from source)                             │
│   Framework → DrapeEngine                                   │
│   dp::OGLContext via WGL                                    │
│   map, drape, drape_frontend, platform, etc.                │
└─────────────────────────────────────────────────────────────┘
```

### Key Implementation Details

The Windows plugin (`agus_maps_flutter_plugin.dll`) acts as a bridge between Flutter and the FFI library (`agus_maps_flutter.dll`):

1. **Surface Creation Flow:**
   - Dart calls `createMapSurface()` via MethodChannel
   - Plugin loads FFI library (`agus_maps_flutter.dll`) dynamically
   - Plugin calls `agus_native_create_surface()` which creates Framework + DrapeEngine + WGL context
   - Plugin registers D3D11 shared texture with Flutter's `TextureRegistrar`
   - Returns texture ID to Dart for display in `Texture` widget

2. **Texture Sharing:**
   - Native code renders via OpenGL (WGL context)
   - OpenGL framebuffer is copied to D3D11 staging texture
   - D3D11 shared texture is exposed via DXGI shared handle
   - Flutter samples the texture directly (zero-copy)

3. **Frame Synchronization:**
   - Native `agus_set_frame_ready_callback()` notifies plugin of new frames
   - Plugin calls `TextureRegistrar::MarkTextureFrameAvailable()`
   - Flutter schedules next frame to sample the updated texture

| Aspect | iOS/macOS (Metal) | Windows (OpenGL) |
|--------|-------------------|------------------|
| Graphics API | Metal | OpenGL 2.0+ (WGL) |
| Texture Sharing | CVPixelBuffer + IOSurface | D3D11 + DXGI Shared Handle |
| Zero-Copy Mechanism | CVMetalTextureCache | WGL_NV_DX_interop2 |
| Flutter Texture | FlutterTexture protocol | FlutterDesktopGpuSurfaceDescriptor |
| Platform Macro | `PLATFORM_MAC=1` | `OMIM_OS_WINDOWS=1` |
| Plugin Class | AgusMapsFlutterPlugin (Swift) | AgusMapsFlutterPluginCApi (C++) |

---

## File Structure

```
src/
├── agus_maps_flutter.h          # Shared FFI declarations
├── agus_maps_flutter_win.cpp    # Windows FFI implementation
├── AgusWglContextFactory.hpp    # WGL OpenGL context factory header
├── AgusWglContextFactory.cpp    # WGL OpenGL context factory impl
├── agus_platform_win.cpp        # Windows platform abstraction
├── CMakeLists.txt               # Build config (handles Windows)

windows/
├── CMakeLists.txt               # Flutter plugin build
├── agus_maps_flutter_plugin.cpp # MethodChannel handler
├── include/
│   └── agus_maps_flutter/
│       └── agus_maps_flutter_plugin_c_api.h  # C API for Flutter

patches/comaps/
└── *.patch                      # MSVC compatibility patches
```

---

## MethodChannel API

The Windows plugin implements the following MethodChannel methods:

| Method | Arguments | Returns | Description |
|--------|-----------|---------|-------------|
| `extractMap` | `{assetPath: String}` | `String` (path) | Extract map asset to Documents |
| `extractDataFiles` | none | `String` (path) | Extract CoMaps data files |
| `getApkPath` | none | `String` (path) | Return executable directory |
| `createMapSurface` | `{width?, height?}` | `int` (textureId) | Create render surface |
| `resizeMapSurface` | `{width, height}` | `bool` | Resize render surface |
| `destroyMapSurface` | none | `bool` | Destroy render surface |

### File Locations (Windows)

| Purpose | Location |
|---------|----------|
| Flutter Assets | `<exe_dir>/data/flutter_assets/` |
| Extracted Maps | `Documents/agus_maps_flutter/maps/` |
| CoMaps Data | `Documents/agus_maps_flutter/` |
| Extraction Marker | `Documents/agus_maps_flutter/.comaps_data_extracted` |

---

## Build Configuration

### CMake Flags for Windows

```cmake
-DCMAKE_SYSTEM_NAME=Windows
-DOMIM_OS_WINDOWS=1
-DSKIP_TESTS=ON
-DSKIP_QT_GUI=ON
-DSKIP_TOOLS=ON
-DSKIP_QT=ON
```

### Preprocessor Definitions

```
OMIM_OS_WINDOWS=1
NOMINMAX
WIN32_LEAN_AND_MEAN
```

### Required Libraries

```cmake
# Windows system
target_link_libraries(...
  opengl32    # WGL/OpenGL
  d3d11       # Texture sharing
  dxgi        # DXGI shared handles
  dxguid      # DirectX GUIDs
  shell32     # SHGetKnownFolderPath
  ole32       # CoTaskMemFree
)
```

---

## vcpkg Integration

vcpkg is used for additional Windows dependencies. The toolchain is automatically detected if `C:\vcpkg` exists or `VCPKG_ROOT` is set.

### vcpkg.json

```json
{
  "name": "agus-maps-flutter",
  "version-string": "1.0.0",
  "dependencies": []
}
```

---

## Implementation Progress

### Completed ✅

- [x] Windows build compiles and links
- [x] CoMaps patches for MSVC compatibility (30+ patches)
- [x] Plugin MethodChannel registration
- [x] `extractMap` - Copy assets to Documents
- [x] `extractDataFiles` - Extract CoMaps data
- [x] `getApkPath` - Return executable directory
- [x] WGL OpenGL context factory (AgusWglContextFactory)
- [x] CMake integration with vcpkg
- [x] `createMapSurface` - Creates Framework, DrapeEngine, registers D3D11 texture
- [x] `resizeMapSurface` - Updates surface dimensions
- [x] `destroyMapSurface` - Cleans up native resources
- [x] Plugin-to-FFI bridge for surface lifecycle
- [x] D3D11 shared texture with DXGI handle
- [x] Frame callback registration
- [x] SetFramebuffer fix for offscreen FBO binding (nullptr case)
- [x] Touch event handling (pan/zoom via mouse drag)

### In Progress 🔄

- [ ] Scroll wheel zoom support for desktop
- [ ] Additional touch gesture refinements

### Not Started ❌

- [ ] Kinetic scrolling (fling)
- [ ] Map animation smoothness

---

## Acceptance Criteria

- [x] Windows example app builds without errors
- [x] Plugin creates native surface and registers Flutter texture
- [x] App launches and displays Gibraltar map
- [x] Pan/zoom gestures work correctly (mouse drag)
- [ ] Map renders at 60fps with minimal CPU usage
- [ ] Release build is under 150MB

---

## Known Issues & Considerations

### Thread Checker for Embedded Builds

CoMaps uses thread checkers to verify certain classes (like `BookmarkManager`) are accessed from their original thread. In embedded Flutter builds, threading models differ from native apps, causing thread checker assertions to fail.

**Symptom:**
```
(2) ASSERT FAILED
map/bookmark_manager.cpp:263
CHECK(m_threadChecker.CalledOnOriginalThread())
```

**Solution:** The `OMIM_DISABLE_THREAD_CHECKER` compile definition must be set globally for **all CoMaps libraries**, not just agus_maps_flutter. This is done in `src/CMakeLists.txt` before `add_subdirectory` for CoMaps:

```cmake
# In src/CMakeLists.txt, BEFORE add_subdirectory for CoMaps:
add_compile_definitions(OMIM_DISABLE_THREAD_CHECKER)
```

This is supported by patches 0030 and 0031 which modify `thread_checker.cpp` and `thread_checker.hpp` to respect the flag.

**Important:** Setting this only on `agus_maps_flutter` target is NOT sufficient - it must be a global definition so all CoMaps static libraries are compiled with it.

### Crash Dump Handler

Windows builds include automatic crash dump generation for debugging. When the app crashes, a minidump file is written to:

```
Documents\agus_maps_flutter\agus_maps_crash_YYYYMMDD_HHMMSS.dmp
```

This file can be loaded in Visual Studio or WinDbg for post-mortem debugging.

The crash handler is installed automatically when logging is initialized and captures:
- Exception code and address
- Thread information
- Memory state at crash time

### WGL Context Management

Windows uses native WGL for OpenGL context management. Critical considerations:

1. **Context Preservation:** Methods like `GetRendererName()` and `GetRendererVersion()` must not release the current context since the caller expects it to remain current after the call.

2. **Context Restoration:** Methods like `SetSurfaceSize()` and `CopyToSharedTexture()` save and restore the previous context to avoid disrupting the render thread.

3. **MakeCurrent Logging:** Debug builds include logging when `wglMakeCurrent` fails, helping diagnose context issues.

Example of correct context management:
```cpp
void SomeMethod()
{
  // Save current context
  HGLRC prevContext = wglGetCurrentContext();
  HDC prevDC = wglGetCurrentDC();
  
  // Do GL operations
  wglMakeCurrent(m_hdc, m_glrc);
  // ... GL calls ...
  
  // Restore previous context
  if (prevContext != nullptr)
    wglMakeCurrent(prevDC, prevContext);
  else
    wglMakeCurrent(nullptr, nullptr);
}
```

### Native OpenGL vs ANGLE/EGL

The Windows build uses native WGL/OpenGL, NOT ANGLE/EGL. This affects:

- Context checking: Use `wglGetCurrentContext()` instead of `eglGetCurrentContext()`
- Extension loading: Use `wglGetProcAddress()` for GL extensions
- Headers: Include `<windows.h>` and `<GL/gl.h>` instead of EGL headers

The patch `0004-fix-android-gl-function-pointers.patch` handles this by using `#ifdef OMIM_OS_WINDOWS` to select the correct API.

### MSVC Compatibility

CoMaps was originally designed for GCC/Clang. Over 30 patches are required for MSVC compatibility:
- `#pragma once` ordering with symlinks
- Template instantiation differences
- Missing standard library includes
- Boost header workarounds

**MSVC `/bigobj` Flag:**

Unity builds with CoMaps can exceed MSVC's default object file section limit (65,536 sections), causing error `C1128: number of sections exceeded object file format limit`. This is added globally in `thirdparty/comaps/CMakeLists.txt`:

```cmake
if (MSVC)
  add_compile_options(/bigobj)
endif()
```

**Multi-Config Generator Compatibility:**

Visual Studio is a multi-config generator that uses `CMAKE_CONFIGURATION_TYPES` instead of `CMAKE_BUILD_TYPE`. CoMaps' `base/base.hpp` has a static assertion requiring exactly one of `DEBUG` or `RELEASE` to be defined. Use generator expressions:

```cmake
# In src/CMakeLists.txt - handle multi-config generators (Visual Studio)
if (CMAKE_CONFIGURATION_TYPES)
  target_compile_definitions(agus_maps_flutter PRIVATE
    $<$<CONFIG:Debug>:DEBUG>
    $<$<NOT:$<CONFIG:Debug>>:RELEASE>
  )
else()
  # Single-config generators (Ninja, Make)
  if (CMAKE_BUILD_TYPE STREQUAL "Debug")
    target_compile_definitions(agus_maps_flutter PRIVATE DEBUG)
  else()
    target_compile_definitions(agus_maps_flutter PRIVATE RELEASE)
  endif()
endif()
```

### OpenGL Context Creation

Windows requires careful WGL context creation:
- Hidden window for offscreen context
- Pixel format selection for RGBA8
- GL 2.0+ extension loading via wglGetProcAddress

### D3D11 Texture Sharing

For Flutter texture integration:
- Create D3D11 device matching Flutter's GPU
- Use `WGL_NV_DX_interop2` for GL-D3D11 sharing
- Share via DXGI shared handle

**Critical: Dynamic Handle Lookup**

The D3D11 shared texture handle changes whenever the surface is resized. The Flutter `GpuSurfaceTexture` callback must query the **current** handle each time it's invoked, not capture a handle at creation time:

```cpp
// WRONG - captured handle becomes stale on resize:
void* capturedHandle = g_fnGetSharedTextureHandle();
texture_ = std::make_unique<flutter::TextureVariant>(
    flutter::GpuSurfaceTexture(
        kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle,
        [capturedHandle](...) {
            desc.handle = capturedHandle;  // STALE after resize!
        }
    )
);

// CORRECT - query current handle dynamically:
texture_ = std::make_unique<flutter::TextureVariant>(
    flutter::GpuSurfaceTexture(
        kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle,
        [this](...) {
            void* currentHandle = g_fnGetSharedTextureHandle();  // Always current
            desc.handle = currentHandle;
        }
    )
);
```

### Frame Callback Chain

The frame notification system has two callback chains that must both be connected:

1. **DrapeEngine Active Frame Callback:**
   - `df::SetActiveFrameCallback(lambda)` → `notifyFlutterFrameReady()` → `g_frameReadyCallback`
   - Called by DrapeEngine when there's animation or active frame to render

2. **Context Present Callback:**
   - `AgusWglContext::Present()` → `AgusWglContextFactory::OnFrameReady()` → `CopyToSharedTexture()` + `m_frameCallback`
   - Called after each OpenGL frame is rendered

**Critical:** The `m_frameCallback` in `AgusWglContextFactory` must be connected to `notifyFlutterFrameReady()`. This is done when creating the factory:

```cpp
// In agus_native_create_surface():
g_wglFactory = new agus::AgusWglContextFactory(width, height);
g_wglFactory->SetFrameCallback([]() {
    notifyFlutterFrameReady();
});
```

Without this connection, `CopyToSharedTexture()` will copy pixels to the D3D11 texture but Flutter will never be notified to sample the updated texture, resulting in a static (blank) display.

### Tile Loading and View Setting Timing

The `comaps_set_view()` function must use `isAnim=false` when setting the viewport center on Windows. This is a critical difference from iOS/macOS/Android implementations.

**Problem:**
When using animated view changes (`isAnim=true`, the default), the viewport change is queued as an animation. The render loop must:
1. Process the animation event
2. Interpolate the view over multiple frames
3. Eventually trigger `UpdateScene()` which requests tiles

On Windows, the timing between event processing and the render loop can cause tiles to never be requested:
- `SetViewportCenter()` posts a `SetCenterEvent` to the render thread's message queue
- The message is processed AFTER the current frame renders
- With animation enabled, the view change doesn't immediately trigger `modelViewChanged = true`
- The render loop may never call `UpdateScene()` with the new viewport

**Solution:**
```cpp
// In comaps_set_view() - use isAnim=false for synchronous view setting
g_framework->SetViewportCenter(
    m2::PointD(mercator::FromLatLon(lat, lon)),
    zoom,
    false /* isAnim - CRITICAL for Windows */
);
```

With `isAnim=false`:
1. `SetScreen()` directly updates `m_navigator` and returns `true`
2. This causes `breakAnim = true` → `m_modelViewChanged = true`
3. The next render loop iteration sees `modelViewChanged = true`
4. `UpdateScene()` is called, which requests tiles via `ResolveTileKeys()`

**Why iOS/macOS/Android work with animation:**
On these platforms, the render loop is driven by the system's VSync/display link, and the initial screen state may be properly configured before the first frame. Windows uses a custom WGL render loop where the timing differs.

---

## Troubleshooting

### "Could NOT find ZLIB (missing: ZLIB_LIBRARY ZLIB_INCLUDE_DIR)"

**Cause:** CMake is using the wrong vcpkg installation (e.g., Visual Studio's bundled vcpkg instead of your installed C:\vcpkg).

**Solution:**
1. Install zlib via vcpkg: `C:\vcpkg\vcpkg.exe install zlib:x64-windows --classic`
2. The example's `CMakeLists.txt` now forces use of C:\vcpkg if it has zlib installed
3. Clean the build directory: `Remove-Item -Recurse -Force example\build\windows`
4. Rebuild: `flutter build windows --release`

The CMakeLists.txt checks for the actual presence of `zlib.lib` before selecting a vcpkg installation, ensuring it uses a vcpkg that actually has the required packages.

### "MissingPluginException: No implementation found for method extractMap"

**Cause:** Plugin not registered with Flutter.  
**Solution:** Ensure `pubspec.yaml` has `pluginClass: AgusMapsFlutterPluginCApi` under `windows:` platform.

### "Failed to load dynamic library 'agus_maps_flutter.dll': The specified module could not be found" (error code: 126)

**Cause:** Missing DLL dependency (e.g., `zlib1.dll`).  
**Solution:** Ensure `windows/CMakeLists.txt` bundles all runtime dependencies:
```cmake
set(agus_maps_flutter_bundled_libraries
  $<TARGET_FILE:${PLUGIN_NAME}>
  $<TARGET_FILE:agus_maps_flutter>
  "${ZLIB_DLL}"  # From vcpkg
  PARENT_SCOPE
)
```

### Build fails with MAX_PATH exceeded

**Cause:** Symlinks in Flutter's `.plugin_symlinks` create long paths.  
**Solution:** CMakeLists.txt uses `get_filename_component(...REALPATH)` to resolve paths.

### Boost header errors

**Cause:** Boost modular headers need specific include order.  
**Solution:** CoMaps patches add missing includes and fix ordering.

### vcpkg not found after flutter clean

**Cause:** Flutter clean removes CMake cache; vcpkg toolchain must be in example app's CMakeLists.txt.  
**Solution:** Add vcpkg integration before `project()` in `example/windows/CMakeLists.txt`:
```cmake
if(NOT DEFINED CMAKE_TOOLCHAIN_FILE)
  if(EXISTS "C:/vcpkg/scripts/buildsystems/vcpkg.cmake")
    set(CMAKE_TOOLCHAIN_FILE "C:/vcpkg/scripts/buildsystems/vcpkg.cmake" CACHE STRING "")
  endif()
endif()
```

### Map displays as blank or brownish background

**Symptom:** The map widget shows a solid brownish/tan color instead of map content, but no crash occurs.

**Possible Causes:**

1. **Frame callback not connected:** The `AgusWglContextFactory::m_frameCallback` is not set, so `CopyToSharedTexture()` runs but Flutter is never notified.
   - Check logs for "[AgusMapsFlutter] WGL factory frame callback set"
   - Ensure `g_wglFactory->SetFrameCallback()` is called after factory creation

2. **Stale texture handle on resize:** The `GpuSurfaceTexture` callback captures the D3D11 shared handle at creation time, but the handle changes when the surface resizes.
   - Symptoms: Map appears initially then goes blank on window resize; multiple `Shared texture created: ... handle: ...` log entries with different handles
   - Fix: The callback must dynamically query `g_fnGetSharedTextureHandle()` each time, not use a captured value
   - See "Dynamic Handle Lookup" section above for correct implementation

3. **D3D11 flush missing:** After copying pixels to the shared texture, `m_d3dContext->Flush()` must be called to ensure the GPU completes the copy before Flutter samples.
   - Without flush, Flutter may sample stale/incomplete texture data

4. **Map tiles not loaded:** The brownish color IS the map background - tiles may not be loading.
   - Call `comaps_invalidate()` after registering maps to force tile reload
   - Check logs for `comaps_set_view` calls and viewport invalidation
   - **If tiles still don't load:** Call `forceRedraw()` after registering maps - this is necessary when maps are registered AFTER DrapeEngine initialization, as the engine calculates tile coverage before maps are available

5. **DrapeEngine initialized before map registration:** When the DrapeEngine is created, it calculates which tiles to request based on the current viewport. If maps are registered AFTER this calculation, `InvalidateRect` alone may not trigger tile loading.
   - **Solution:** Call `forceRedraw()` after registering all maps. This performs three operations:
     1. `SetMapStyle()` - clears all render groups and forces tile re-request
     2. `InvalidateRendering()` - posts a high-priority `InvalidateMessage` to wake up the FrontendRenderer
     3. `InvalidateRect()` - marks the viewport as needing redraw
   - **Example code:**
     ```dart
     // In _onMapReady() after registering maps:
     agus_maps_flutter.invalidateMap();  // Light refresh
     agus_maps_flutter.forceRedraw();    // Heavy refresh - forces complete tile reload
     ```
   - **Verify:** After calling `forceRedraw()`, logs should show:
     ```
     comaps_force_redraw called - triggering full tile reload
     comaps_force_redraw: SetMapStyle triggered
     comaps_force_redraw: InvalidateRendering triggered
     comaps_force_redraw: InvalidateRect triggered
     ```

6. **Render loop stops after first frame:** The FrontendRenderer may stop rendering if it determines there's nothing to animate or update. This can happen when:
   - Maps are registered after the initial tile coverage calculation
   - The DrapeEngine's message queue isn't processing viewport changes properly
   - **Symptom:** Only "Frame 0" appears in logs, even after user interaction
   - **Solution:** The `comaps_set_view()` function now calls `InvalidateRendering()` in addition to `InvalidateRect()` to ensure the render loop wakes up when the viewport changes

7. **FrontendRenderer suspends due to inactive frames:** CoMaps' `FrontendRenderer` automatically suspends after `kMaxInactiveFrames = 2` consecutive frames with no animation or activity. This is a power-saving optimization but can cause issues when:
   - Tiles are still loading in the background
   - The initial map setup is in progress
   - External events (like map registration) don't trigger "activity"
   
   **Root cause:** In `FrontendRenderer::Routine()`, if `activeFrame` remains false for 2 consecutive frames, the renderer enters a suspended loop waiting for a wake-up message. However, tile loading completion doesn't generate an "active frame" event.
   
   **Solution:** Use `MakeFrameActive()` instead of `InvalidateRendering()` to ensure the render loop continues:
   ```cpp
   // In agus_maps_flutter_win.cpp
   void triggerActiveFrame() {
       if (g_framework) {
           g_framework->GetDrapeEngine()->MakeFrameActive();
       }
   }
   ```
   
   `MakeFrameActive()` adds an `ActiveFrameEvent` user event which sets `activeFrame = true` in the render loop, preventing suspension.
   
   **Initial Frame Counter:** To ensure tiles have time to load during cold start, the WGL context factory can request active frames for the first N renders:
   ```cpp
   // In AgusWglContextFactory.cpp
   void AgusWglContext::Present() {
       // ... existing present logic ...
       if (m_factory && m_factory->m_initialFrameCount > 0) {
           m_factory->m_initialFrameCount--;
           m_factory->RequestActiveFrame();  // Keep render loop alive
       }
   }
   ```

8. **Path separator mismatch for downloaded maps:** Downloaded maps fail to register with "File doesn't exist" errors even though the path is correct.
   - **Symptom:** Log shows `Re-registering downloaded: Philippines_Luzon_South at C:\Users\...\Documents/Philippines_Luzon_South.mwm` (mixed slashes) but error says `File C:\Users\...\Philippines_Luzon_South.mwm doesn't exist` (missing `Documents` folder)
   - **Cause:** Dart's `path_provider` may return paths with forward slashes, which the C++ `base::GetDirectory()` function doesn't handle correctly on Windows
   - **Fix:** Path normalization is now handled at multiple layers:
     - `MwmMetadata` constructor normalizes paths when storing metadata
     - `registerSingleMap()` in Dart normalizes paths before passing to FFI
     - `comaps_register_single_map()` in C++ normalizes paths before using `MakeTemporary()`
   - **Verify:** After fix, paths in logs should show consistent backslashes: `C:\Users\...\Documents\Philippines_Luzon_South.mwm`

9. **Rendering to wrong framebuffer - SetFramebuffer(nullptr) not binding offscreen FBO:**
   - **Symptom:** Map background renders (brownish color) but no map features/tiles appear. Logs show "Tile added to render groups" but `uniqueColors: 1` in frame diagnostics.
   - **Root cause:** CoMaps calls `m_context->SetFramebuffer(nullptr)` to switch to the "default" framebuffer for main rendering (see `frontend_renderer.cpp:1683`). The original Windows implementation treated `nullptr` as "do nothing", leaving the OpenGL framebuffer bound to 0 (screen).
   - **Why tiles still load:** Tile loading happens in `BackendRenderer` and sends `FlushTile` messages to `FrontendRenderer`. The tiles ARE being added to render groups, but when `RenderScene()` draws them, it's rendering to framebuffer 0 (invisible), not our offscreen FBO.
   - **Fix:** `AgusWglContext::SetFramebuffer()` must bind our offscreen FBO when `nullptr` is passed, similar to Qt's implementation:
     ```cpp
     // Before (broken):
     void AgusWglContext::SetFramebuffer(ref_ptr<dp::BaseFramebuffer> framebuffer) {
         // Not used for default framebuffer (empty!)
     }
     
     // After (fixed):
     void AgusWglContext::SetFramebuffer(ref_ptr<dp::BaseFramebuffer> framebuffer) {
         if (framebuffer)
             framebuffer->Bind();  // Bind the provided FBO
         else if (m_isDraw && m_factory)
             glBindFramebuffer(GL_FRAMEBUFFER, m_factory->m_framebuffer);  // Bind our FBO
     }
     ```
   - **Reference:** Qt's `QtRenderOGLContext::SetFramebuffer()` in `qtoglcontext.cpp` shows the correct pattern - it binds `m_backFrame` when framebuffer is nullptr.

10. **Missing OpenGL state initialization - Init() empty:**
   - **Symptom:** Map background renders but tiles/features don't appear, even after fixing SetFramebuffer. Logs show tiles being added to render groups.
   - **Root cause:** CoMaps' `OGLContext::Init()` sets up critical OpenGL state (depth testing, face culling, scissor test) that the rendering code expects. Our `AgusWglContext::Init()` was empty, leaving GL state in an undefined configuration.
   - **Why this matters:** CoMaps' rendering code assumes `GL_SCISSOR_TEST` is enabled (it uses glScissor for viewport clipping). Without proper depth test setup, 3D elements may render incorrectly.
   - **Fix:** Implement `AgusWglContext::Init()` matching `OGLContext::Init()`:
     ```cpp
     void AgusWglContext::Init(dp::ApiVersion apiVersion) {
         // Pixel alignment for texture uploads
         glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
         
         // Depth testing setup
         glClearDepth(1.0);
         glDepthFunc(GL_LEQUAL);
         glDepthMask(GL_TRUE);
         
         // Face culling - important for proper rendering
         glFrontFace(GL_CW);
         glCullFace(GL_BACK);
         glEnable(GL_CULL_FACE);
         
         // Scissor test - CRITICAL: CoMaps expects scissor to be enabled
         glEnable(GL_SCISSOR_TEST);
     }
     ```
   - **Reference:** CoMaps' `OGLContext::Init()` in `drape/oglcontext.cpp` shows the expected initialization.

11. **Stale data extraction:** Old data files without symbol textures.
   - Delete `Documents\agus_maps_flutter\.comaps_data_extracted` marker file
   - Delete `Documents\agus_maps_flutter\` folder contents
   - Rebuild and run to force fresh extraction

**Debugging:**
- Enable frame logging in `AgusWglContextFactory::CopyToSharedTexture()` to see `hasContent` status
- Check if "Frame N size: WxH hasContent: true uniqueColors: N" appears in logs
- If `uniqueColors` is 1, only the background is being rendered (tiles not loaded)
- If `hasContent` is true but display is blank, check texture handle staleness (cause #2)
- If `hasContent` is false, the OpenGL FBO isn't receiving rendered content

### Missing symbol warnings (transit_tram-s, castle-s, etc.)

**Symptom:** Logs show many warnings like:
```
[CoMaps WARN] drape/texture_manager.cpp:445 dp::TextureManager::GetSymbolRegion(): Detected using of unknown symbol  castle-s
```

**Cause:** The `symbols.sdf` file doesn't include definitions for all POI symbols used by the map style.

**Impact:** These warnings are non-fatal - the map will render but some POI icons will be missing or show as blank.

**Note:** The symbol texture files (`symbols.sdf`, `symbols.png`) in `example/assets/comaps_data/symbols/` are pre-generated. Regenerating them requires Qt6 tools from CoMaps build system.

---

## References

- iOS Implementation: [docs/IMPLEMENTATION-IOS.md](IMPLEMENTATION-IOS.md)
- macOS Implementation: [docs/IMPLEMENTATION-MACOS.md](IMPLEMENTATION-MACOS.md)
- Android Implementation: [docs/IMPLEMENTATION-ANDROID.md](IMPLEMENTATION-ANDROID.md)
- Render Loop Details: [docs/RENDER-LOOP.md](RENDER-LOOP.md)
- CoMaps drape code: `thirdparty/comaps/libs/drape/`

---

*Last updated: December 2025*
