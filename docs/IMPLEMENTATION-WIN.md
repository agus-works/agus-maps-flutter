# Windows Implementation Plan (MVP)

## Quick Start: Build & Run

### Prerequisites

- Flutter SDK 3.24+ installed
- Visual Studio 2022 with C++ Desktop development workload
- Vulkan SDK (automatically installed via vcpkg)
- Windows 10 or later (Vulkan 1.0+ support required)
- ~5GB disk space for CoMaps build artifacts

### Debug Mode (Full debugging, slower)

Debug mode enables hot reload, step-through debugging, and verbose logging for both Flutter and native layers.

```powershell
# 1. Bootstrap CoMaps dependencies (first time only)
./scripts/bootstrap_windows.ps1

# 2. Copy CoMaps data files (first time only)
./scripts/copy_comaps_data.sh  # Or manually copy data files

# 3. Run in debug mode
cd example
flutter run -d windows --debug
```

**Debug mode characteristics:**
- Flutter: Hot reload enabled, Dart DevTools available
- Native: Debug symbols included, assertions enabled, detailed logging
- Performance: Slower due to debug overhead, unoptimized native code
- App size: ~300MB+ (includes debug symbols)

### Release Mode (High performance)

Release mode produces an optimized build suitable for production use.

```powershell
# 1. Bootstrap CoMaps dependencies (first time only)
./scripts/bootstrap_windows.ps1

# 2. Build and run in release mode
cd example
flutter run -d windows --release

# Or build an exe bundle for distribution
flutter build windows --release
```

**Release mode characteristics:**
- Flutter: AOT compiled, tree-shaken, minified
- Native: Optimized, no debug symbols, no assertions
- Performance: Full speed, minimal CPU usage
- App size: ~100MB (stripped, compressed)

---

## Goal

Get the Windows example app to:

1. Bundle a Gibraltar map file (`Gibraltar.mwm`) as an example asset.
2. On first launch, **ensure the map exists as a real file on disk** (extract/copy once if missing).
3. Pass the on-disk filesystem path into the native layer (FFI) so the native engine can open it using normal filesystem APIs (and later use `mmap`).
4. Set the initial camera to **Gibraltar** at **zoom 14**.
5. Render the map using **Vulkan** with **zero-copy texture sharing** via D3D11 interop.

This matches how CoMaps/Organic Maps operates: maps are stored as standalone `.mwm` files on disk and are memory-mapped by the OS for performance.

## Non-Goals (for this MVP)

- Search/routing functionality
- Download manager / storage management
- OpenGL fallback (Vulkan-only for now)

---

## Architecture Overview

### Zero-Copy Texture Sharing (Vulkan + D3D11 Interop)

The Windows implementation uses Flutter's `FlutterDesktopGpuSurfaceDescriptor` with D3D11 shared textures. Vulkan renders to a `VkImage` that is backed by D3D11 memory via `VK_KHR_external_memory_win32`, achieving zero-copy GPU texture sharing.

```
┌─────────────────────────────────────────────────────────────┐
│ Flutter Dart Layer                                          │
│   AgusMap widget → Texture(textureId)                       │
│   AgusMapController → FFI calls                             │
├─────────────────────────────────────────────────────────────┤
│ Flutter Windows Engine (Impeller/Skia)                      │
│   FlutterTextureRegistrar → GPU Surface Descriptor          │
│   Samples D3D11 texture (zero-copy via DXGI shared handle)  │
├─────────────────────────────────────────────────────────────┤
│ agus_maps_flutter_plugin.cpp (Windows version)              │
│   FlutterPlugin + TextureRegistrar                          │
│   D3D11 shared texture with DXGI handle                     │
│   MethodChannel for asset extraction                        │
├─────────────────────────────────────────────────────────────┤
│ AgusVulkanContextFactory.cpp                                │
│   DrawVulkanContext → VkImage from D3D11 shared memory      │
│   UploadVulkanContext → shared VkDevice                     │
│   VK_KHR_external_memory_win32 for D3D11 interop            │
├─────────────────────────────────────────────────────────────┤
│ CoMaps Core (built from source)                             │
│   Framework → DrapeEngine                                   │
│   dp::vulkan::VulkanBaseContext                             │
│   map, drape, drape_frontend, platform, etc.                │
└─────────────────────────────────────────────────────────────┘
```

### Key Implementation Details

| Aspect | iOS/macOS (Metal) | Windows (Vulkan) |
|--------|-------------------|------------------|
| Graphics API | Metal | Vulkan 1.0+ |
| Texture Sharing | CVPixelBuffer + IOSurface | D3D11 + DXGI Shared Handle |
| Zero-Copy Mechanism | CVMetalTextureCache | VK_KHR_external_memory_win32 |
| Flutter Texture | FlutterTexture protocol | FlutterDesktopGpuSurfaceDescriptor |
| Platform Macro | `PLATFORM_MAC=1` | `OMIM_OS_WINDOWS=1` |

### Shared Patterns (same as iOS/macOS)

The following patterns are **identical** across all platforms:

1. **Active Frame Callback** — `df::SetActiveFrameCallback()` for efficient frame signaling
2. **FFI Exports** — Same C API: `comaps_init_paths`, `comaps_set_view`, `comaps_touch`, etc.
3. **Framework Lifecycle** — Deferred initialization, DrapeEngine creation on render thread
4. **Rate Limiting** — 60fps max frame notification rate

---

## File Structure

```
src/
├── agus_maps_flutter.h          # Shared FFI declarations
├── agus_maps_flutter_win.cpp    # Windows FFI implementation (NEW)
├── AgusVulkanContextFactory.hpp # Vulkan context factory header (NEW)
├── AgusVulkanContextFactory.cpp # Vulkan context factory impl (NEW)
├── agus_platform_win.cpp        # Windows platform abstraction (NEW)
├── agus_gui_thread_win.cpp      # Windows GUI thread (NEW)
├── CMakeLists.txt               # Build config (updated for Windows)
windows/
├── CMakeLists.txt               # Flutter plugin build
├── agus_maps_flutter_plugin.cpp # Flutter plugin with texture registrar (NEW)
├── agus_maps_flutter_plugin.h   # Plugin header (NEW)
├── include/
│   └── agus_maps_flutter/
│       └── agus_maps_flutter_plugin_c_api.h
vcpkg.json                       # vcpkg dependencies (NEW)
patches/comaps/
└── 0019-vulkan-windows-surface.patch  # VK_KHR_win32_surface (NEW)
```

---

## Implementation Steps

### Step 1: Create vcpkg.json

Add Vulkan dependencies for Windows:
- `vulkan-headers` — Vulkan API headers
- `vulkan-loader` — Vulkan runtime loader

### Step 2: Create Vulkan Windows Surface Patch

Patch `thirdparty/comaps/libs/drape/vulkan/vulkan_layers.cpp`:
- Add `"VK_KHR_win32_surface"` to `kInstanceExtensions[]` under `#if defined(OMIM_OS_WINDOWS)`

### Step 3: Create AgusVulkanContextFactory

Windows Vulkan context factory extending `dp::vulkan::VulkanContextFactory`:
- Create D3D11 device and shared texture
- Import D3D11 texture into Vulkan via `VK_KHR_external_memory_win32`
- Create `VkImage` backed by shared memory
- Implement `DrawVulkanContext` and `UploadVulkanContext`

### Step 4: Create Windows FFI Implementation

`src/agus_maps_flutter_win.cpp`:
- Implement all FFI exports from `agus_maps_flutter.h`
- Implement Windows-specific surface functions
- Create Framework and DrapeEngine with `dp::ApiVersion::Vulkan`
- Handle frame notification via `df::SetActiveFrameCallback`

### Step 5: Create Windows Platform Abstraction

`src/agus_platform_win.cpp`:
- Initialize CoMaps Platform with Windows paths
- Implement file system operations
- Set up logging to OutputDebugString

### Step 6: Update src/CMakeLists.txt

Add Windows-specific configuration:
- `if(WIN32)` block with Windows source files
- Find and link Vulkan SDK
- Link D3D11, DXGI system libraries
- Add `OMIM_OS_WINDOWS` compile definition

### Step 7: Update windows/CMakeLists.txt

- Link `agus_maps_flutter` shared library
- Bundle Vulkan loader DLL if needed
- Configure proper output paths

---

## Build Configuration

### CMake Flags for Windows

```cmake
-DCMAKE_SYSTEM_NAME=Windows
-DPLATFORM_DESKTOP=ON
-DOMIM_OS_WINDOWS=1
-DSKIP_TESTS=ON
-DSKIP_QT_GUI=ON
-DSKIP_TOOLS=ON
```

### Preprocessor Definitions

```
OMIM_OS_WINDOWS=1
PLATFORM_DESKTOP=1
VK_USE_PLATFORM_WIN32_KHR=1
NOMINMAX
WIN32_LEAN_AND_MEAN
```

### Required Libraries

```cmake
# Vulkan
find_package(Vulkan REQUIRED)
target_link_libraries(... Vulkan::Vulkan)

# Windows system
target_link_libraries(...
  d3d11
  dxgi
  user32
  gdi32
  shell32
)
```

---

## vcpkg Integration

### vcpkg.json

```json
{
  "name": "agus-maps-flutter",
  "version-string": "1.0.0",
  "dependencies": [
    "vulkan-headers",
    "vulkan-loader"
  ]
}
```

### Installation

```powershell
# vcpkg is automatically used by CMake if VCPKG_ROOT is set
# Or manually install:
vcpkg install vulkan-headers vulkan-loader --triplet x64-windows
```

---

## Acceptance Criteria

- [ ] Windows example app builds without errors
- [ ] App launches and displays Gibraltar map
- [ ] Pan/zoom gestures work correctly
- [ ] Map renders at 60fps with minimal CPU usage
- [ ] Release build is under 150MB
- [ ] Bootstrap script works on fresh checkout

---

## Known Issues & Considerations

### Vulkan Driver Support

- Requires Vulkan 1.0+ capable GPU and driver
- Most Windows 10+ systems with discrete or integrated GPUs support Vulkan
- Intel, AMD, and NVIDIA all provide Vulkan drivers

### D3D11 Interop

- Uses `VK_KHR_external_memory_win32` for D3D11 texture sharing
- Requires matching device selection between Vulkan and D3D11
- DXGI adapter enumeration ensures same GPU is used

### Multi-GPU Systems

- Plugin should detect and use the same GPU as Flutter
- DXGI adapter LUID matching between D3D11 and Vulkan

### High DPI Support

- Windows scaling factor affects surface dimensions
- Use `GetDpiForWindow()` or Flutter's reported density

---

## References

- iOS Implementation: [docs/IMPLEMENTATION-IOS.md](IMPLEMENTATION-IOS.md)
- macOS Implementation: [docs/IMPLEMENTATION-MACOS.md](IMPLEMENTATION-MACOS.md)
- Android Implementation: [docs/IMPLEMENTATION-ANDROID.md](IMPLEMENTATION-ANDROID.md)
- Render Loop Details: [docs/RENDER-LOOP.md](RENDER-LOOP.md)
- CoMaps Vulkan code: `thirdparty/comaps/libs/drape/vulkan/`

---

*Last updated: December 2025*
