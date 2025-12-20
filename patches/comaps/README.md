# CoMaps Patch Files

This directory contains optional patch files (`*.patch`) that may be applied to the CoMaps checkout in `thirdparty/comaps`.

## Active Patches

### 0001-fix-cmake.patch
Fixes CMake configuration issues for cross-compilation.

### 0002-platform-directory-resources.patch
Modifies `platform_android.cpp` to support directory-based resources. When `m_resourcesDir` is a directory (not a ZIP/APK file), it uses `FileReader` instead of `ZipFileReader`. This is required for Flutter plugins that extract data files to the filesystem rather than reading from the APK.

### 0003-transliteration-directory-resources.patch
Modifies `transliteration_loader.cpp` to support directory-based resources for ICU data files.

### 0004-fix-android-gl-function-pointers.patch
Fixes OpenGL ES 3.0 function pointer resolution on Android. On Android, taking the address of GL functions like `::glGenVertexArrays` returns invalid pointers (PLT stub encodings rather than actual function addresses). This patch uses `eglGetProcAddress()` to properly resolve GLES3 function pointers at runtime:
- `glGenVertexArrays`
- `glBindVertexArray`
- `glDeleteVertexArrays`
- `glUnmapBuffer`
- `glMapBufferRange`
- `glFlushMappedBufferRange`
- `glGetStringi`

### 0005-libs-map-framework-cpp.patch
Adds debug logging to `framework.cpp` for tracking initialization sequence during router setup and editor delegate configuration.

### 0006-libs-map-routing_manager-cpp.patch
Adds debug logging to `routing_manager.cpp` for tracking router creation and configuration flow.

### 0007-libs-routing-routing_session-cpp.patch
Adds debug logging to `routing_session.cpp` for tracking session lifecycle events including route removal and reset operations.

### 0008-libs-routing-speed_camera_manager-cpp.patch
Adds debug logging to `speed_camera_manager.cpp` and adds null-check guard for the speed camera clear callback to prevent crashes when the callback is not set.

### 0009-fix-android-gl3stub-include-path.patch
Switches Android OpenGL ES headers from GLES2 + gl3stub.h to native GLES3 headers. Since we target Android API 24+ which has native GLES 3.0 support, we can use `<GLES3/gl3.h>` directly instead of the complex gl3stub dynamic loader path.

### 0010-fix-ios-cmake-missing-files.patch
Fixes iOS CMakeLists.txt by:
- Removing non-existent `http_user_agent_ios.mm` reference that causes CMake configuration to fail
- Adding `http_session_manager.mm` which is needed for iOS networking

### 0011-libs-shaders-metal_program_pool-mm.patch
Fixes Metal shader library loading by searching multiple bundles for `shaders_metal.metallib`. Flutter plugins build the Metal shaders as a standalone library that gets bundled separately from the main app bundle. This patch extends the search path to find the library in either location.

### 0012-active-frame-callback.patch
Adds an efficient active frame callback mechanism to DrapeEngine's FrontendRenderer. This allows embedders (like Flutter plugins) to be notified only when map content actually changed (`isActiveFrame` is true), rather than on every Present() call.

Changes:
- Adds `active_frame_callback.hpp` and `active_frame_callback.cpp` with thread-safe callback registration
- Modifies `frontend_renderer.cpp` to call `NotifyActiveFrame()` when `isActiveFrame` is true
- Updates `CMakeLists.txt` to include the new files

This enables:
1. **Option 3 (Active Frame Detection)**: Only notify Flutter when content changed
2. Combined with **Option 2 (60fps Rate Limiting)** in the plugin code for battery/CPU efficiency

## Policy

- Prefer a clean bridge layer in this repo.
- Only introduce patches if there is no viable clean integration path.
- Keep patches small, scoped, and re-applicable across tags.

## Usage

Applied by:
```bash
./scripts/apply_comaps_patches.sh
```
