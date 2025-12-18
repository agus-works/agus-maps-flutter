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

## Policy

- Prefer a clean bridge layer in this repo.
- Only introduce patches if there is no viable clean integration path.
- Keep patches small, scoped, and re-applicable across tags.

## Usage

Applied by:
```bash
./scripts/apply_comaps_patches.sh
```
