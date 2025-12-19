## 0.2.0

### Features
* **Map Download Manager**: New Downloads tab for browsing and downloading MWM files from mirror servers
  - Mirror discovery with automatic latency measurement
  - Snapshot (version) selection with YYMMDD format
  - Fuzzy search for regions using `fuzzywuzzy` package
  - Progress tracking with concurrent download limits (max 3)
  - Human-readable region names (URL decoding, underscore replacement)
  - File size display parsed from mirror directory listings
* **Caching System**: Persist loaded region data to local storage via `shared_preferences`
  - Instant subsequent loads from cache
  - Automatic cache validation against server
  - "cached" badge indicator in UI
* **Disk Space Management**: Real-time disk space detection and safety checks
  - Uses `storage_space` package for accurate Android/iOS detection
  - Blocks downloads if <128MB would remain after download
  - Warns if <1GB would remain after download
* **MWM Registration API**: New `registerSingleMap(path)` FFI function
  - Register individual MWM files by path
  - Bypasses version folder scanning requirement
  - Works with dynamically downloaded maps
* **DPI Scaling**: Proper device pixel ratio handling for crisp rendering on high-DPI displays
* **Tab Navigation**: Stable tab switching using IndexedStack (prevents widget recreation)

### Bug Fixes
* **Disk Space Detection**: Fixed `df -B1` command not working on Android by using `storage_space` package
* **File Size Parsing**: Fixed regex to extract size from HTML `title="13701303 B"` attribute format
* **Snapshot Equality**: Added `==` and `hashCode` to `Snapshot` class for proper DropdownButton matching
* **ANR Prevention**: Heavy regex parsing offloaded to isolate via `compute()`
* **Connectivity Checking**: Use `InternetAddress.lookup()` instead of unreliable `connectivity_plus`

### New Dependencies
* `shared_preferences: ^2.2.0` - Cache storage and MWM metadata persistence
* `http: ^1.1.0` - Mirror service HTTP requests
* `fuzzywuzzy: ^1.1.6` - Fuzzy search for region names (example app)
* `connectivity_plus: ^6.1.4` - Network state monitoring (example app)
* `storage_space: ^1.2.0` - Cross-platform disk space detection (example app)

### New Files
* `lib/mirror_service.dart` - Mirror discovery and MWM download service
* `lib/mwm_storage.dart` - MWM metadata persistence service
* `example/lib/downloads_tab.dart` - Map download manager UI
* `example/lib/downloads_cache.dart` - Downloads caching service
* `example/lib/settings_tab.dart` - Settings tab placeholder

### Documentation
* `docs/IMPL-01-fix-mwm-registration.md` - MWM registration fix documentation
* `docs/IMPL-02-mwm-metadata-storage.md` - Storage implementation guide
* `docs/IMPL-03-mirror-service.md` - Mirror service design document
* `docs/IMPL-04-map-downloads-page.md` - Downloads UI specification

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
