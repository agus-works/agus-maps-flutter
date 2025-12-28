# Windows Implementation Plan (MVP)

## Current Status

**Build Status:** ✅ Compiles and links successfully  
**Plugin Registration:** ✅ MethodChannel handler implemented  
**Rendering:** ✅ OpenGL context created, D3D11 texture sharing implemented  
**Surface Bridge:** ✅ Plugin now calls FFI library for surface creation  

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

# 2. Copy CoMaps data files to example assets
.\scripts\copy_comaps_data.sh  # Or manually copy data files
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

### In Progress 🔄

- [ ] Validate D3D11 texture content is correctly rendered
- [ ] Debug OpenGL-to-D3D11 texture copy
- [ ] Frame synchronization timing

### Not Started ❌

- [ ] Touch event handling
- [ ] Camera animation
- [ ] Map pan/zoom gestures

---

## Acceptance Criteria

- [x] Windows example app builds without errors
- [x] Plugin creates native surface and registers Flutter texture
- [ ] App launches and displays Gibraltar map
- [ ] Pan/zoom gestures work correctly
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

2. **Rendering to wrong framebuffer:** OpenGL may be rendering to framebuffer 0 (screen) instead of our offscreen FBO.
   - Verify `MakeCurrent()` binds `m_framebuffer` for draw context
   - Check for CoMaps code that calls `glBindFramebuffer(GL_FRAMEBUFFER, 0)`

3. **Stale data extraction:** Old data files without symbol textures.
   - Delete `Documents\agus_maps_flutter\.comaps_data_extracted` marker file
   - Delete `Documents\agus_maps_flutter\` folder contents
   - Rebuild and run to force fresh extraction

**Debugging:**
- Enable frame logging in `AgusWglContextFactory::CopyToSharedTexture()` to see `hasContent` status
- Check if "Frame N size: WxH hasContent: true" appears in logs
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
