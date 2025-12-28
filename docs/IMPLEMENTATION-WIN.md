# Windows Implementation Plan (MVP)

## Current Status

**Build Status:** ✅ Compiles and links successfully  
**Plugin Registration:** ✅ MethodChannel handler implemented  
**Rendering:** 🔄 WIP - OpenGL context created, texture sharing in progress  

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

### In Progress 🔄

- [ ] `createMapSurface` - Create render texture (returns placeholder)
- [ ] `resizeMapSurface` - Resize texture
- [ ] `destroyMapSurface` - Cleanup texture
- [ ] D3D11/OpenGL texture interop for Flutter
- [ ] Frame rendering loop integration

### Not Started ❌

- [ ] Touch event handling
- [ ] Camera animation
- [ ] Map pan/zoom gestures

---

## Acceptance Criteria

- [x] Windows example app builds without errors
- [ ] App launches and displays Gibraltar map
- [ ] Pan/zoom gestures work correctly
- [ ] Map renders at 60fps with minimal CPU usage
- [ ] Release build is under 150MB

---

## Known Issues & Considerations

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

---

## Troubleshooting

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

---

## References

- iOS Implementation: [docs/IMPLEMENTATION-IOS.md](IMPLEMENTATION-IOS.md)
- macOS Implementation: [docs/IMPLEMENTATION-MACOS.md](IMPLEMENTATION-MACOS.md)
- Android Implementation: [docs/IMPLEMENTATION-ANDROID.md](IMPLEMENTATION-ANDROID.md)
- Render Loop Details: [docs/RENDER-LOOP.md](RENDER-LOOP.md)
- CoMaps drape code: `thirdparty/comaps/libs/drape/`

---

*Last updated: December 2025*
