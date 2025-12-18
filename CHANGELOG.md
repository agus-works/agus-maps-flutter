## 0.1.0

### Features
* **Android Support**: Full CoMaps Framework integration for Android platform
* **Native Rendering**: OpenGL ES 3.0 hardware-accelerated map rendering via Flutter texture
* **JNI Bridge**: Complete JNI layer for Framework initialization and lifecycle management
* **Asset Extraction**: Automatic extraction of CoMaps data files (fonts, styles, symbols) to device storage
* **GuiThread Integration**: JNI-based GuiThread for proper main thread task dispatch on Android

### Bug Fixes
* **GL Function Pointers**: Fixed SIGSEGV crash on Android caused by improper OpenGL ES 3.0 function pointer resolution. Now uses `eglGetProcAddress()` to properly resolve GLES3 functions at runtime (glGenVertexArrays, glBindVertexArray, glDeleteVertexArrays, glUnmapBuffer, glMapBufferRange, glFlushMappedBufferRange, glGetStringi)
* **Directory-based Resources**: Fixed Platform and Transliteration loaders to support directory-based resources instead of requiring ZIP/APK files
* **EGL Context Management**: Proper EGL context creation with shared contexts for multi-threaded rendering

### CoMaps Patches
* `0001-fix-cmake.patch` - CMake configuration fixes for cross-compilation
* `0002-platform-directory-resources.patch` - Directory-based resource loading for platform_android.cpp
* `0003-transliteration-directory-resources.patch` - Directory-based ICU data file loading
* `0004-fix-android-gl-function-pointers.patch` - Android GL function pointer resolution via eglGetProcAddress

### Assets
* Added CoMaps data files: fonts, styles (default/outdoors/vehicle), symbols for all DPI densities
* Added World.mwm and WorldCoasts.mwm base map files
* Added ICU data file (icudt75l.dat) for transliteration support

## 0.0.1

* Initial project scaffolding
