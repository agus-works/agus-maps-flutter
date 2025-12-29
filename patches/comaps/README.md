# CoMaps Patch Files

This directory contains patch files (`*.patch`) that are applied to the CoMaps checkout in `thirdparty/comaps`.

## Important Notes

### Submodule Requirements
Some patches target files within git submodules (e.g., `3party/gflags/CMakeLists.txt`). 
For these patches to apply correctly, **ALL submodules must be fully initialized**.

The bootstrap and fetch scripts ensure this by using:
```bash
git submodule update --init --recursive
```

**Do NOT use `--depth 1`** with submodule initialization as it may cause patches to fail.

### Patch Application Behavior
The patch application scripts (`apply_comaps_patches.sh` / `apply_comaps_patches.ps1`) will:
1. Reset the CoMaps working tree to HEAD
2. Reset all submodules to their recorded commits
3. Apply patches in sorted order (0001, 0002, etc.)
4. **Skip patches** whose target files don't exist (e.g., if a submodule wasn't initialized)
5. Continue on non-fatal failures and report a summary

This means patches for uninitialized submodules won't cause the entire process to fail.

---

## Patch Catalog

### 0002-platform-directory-resources.patch

**File Modified:** `libs/platform/platform_android.cpp`

**Category:** Android Platform / Resource Loading

**Purpose:** Modifies the Android platform reader to support directory-based resources in addition to ZIP/APK-based resources.

**What it does:**
- Adds a check in `Platform::GetReader()` for the 'r' (resources) scope
- If `m_resourcesDir` is a directory (not a ZIP file), uses `FileReader` to read files directly from the filesystem
- If `m_resourcesDir` is a ZIP file (APK), uses the original `ZipFileReader` logic

**Why it's needed:**
Flutter plugins extract map data files to the filesystem rather than reading directly from the APK's assets. The original CoMaps code assumes resources are always inside a ZIP archive (the APK), which fails when resources are stored as loose files on disk.

**Without this patch:**
- `Platform::GetReader()` would fail to find resource files when `m_resourcesDir` points to an extracted directory
- Map classification data, style files, and other resources would fail to load
- The map would not render correctly or crash on startup

---

### 0003-transliteration-directory-resources.patch

**File Modified:** `libs/indexer/transliteration_loader.cpp`

**Category:** Android Platform / ICU Transliteration

**Purpose:** Extends ICU data file loading to support directory-based resources on Android.

**What it does:**
- Checks if the ICU data file (`icudt75l.dat`) already exists in the writable directory
- If `ResourcesDir` is a directory (not ZIP), checks for the ICU file there directly
- If `ResourcesDir` is a ZIP (APK), extracts the ICU file as before
- Adds debug logging for ICU file location discovery

**Why it's needed:**
The ICU library needs its data file for transliteration support. When resources are pre-extracted to a directory (as in Flutter plugins), the code should read directly from that location instead of attempting ZIP extraction.

**Without this patch:**
- ICU transliteration initialization would fail when resources are directory-based
- Search functionality that relies on transliteration (e.g., converting between scripts) would not work
- The app might crash or silently fail to provide proper search results

---

### 0004-fix-android-gl-function-pointers.patch

**File Modified:** `libs/drape/gl_functions.cpp`

**Category:** Android/Windows OpenGL / Critical Bug Fix

**Purpose:** Fixes OpenGL ES 3.0 function pointer resolution on Android and improves Windows WGL support.

**What it does:**
1. **Android:** Uses `eglGetProcAddress()` instead of direct symbol references for GLES3 functions:
   - `glGenVertexArrays`, `glBindVertexArray`, `glDeleteVertexArrays`
   - `glUnmapBuffer`, `glMapBufferRange`, `glFlushMappedBufferRange`
   - `glGetStringi`
2. **Windows:** Improves WGL extension loading with OES/EXT/ARB suffix fallbacks
3. Adds shader debugging infrastructure with environment variable controls (`AGUS_VERBOSE_SHADER`, `AGUS_DUMP_SHADERS`)
4. Adds `glGetShaderSource` function pointer for shader debugging
5. Adds comprehensive error handling and logging for shader compilation
6. Stores shader sources for debugging purposes

**Why it's needed:**
On Android, taking the address of GL symbols like `::glGenVertexArrays` returns PLT stub addresses rather than actual function pointers. These invalid pointers cause crashes or undefined behavior when called. The `eglGetProcAddress()` function properly resolves runtime function pointers.

**Without this patch:**
- Vertex Array Object (VAO) functions would crash or silently fail on Android
- Map rendering would be completely broken or crash immediately
- Shader compilation errors would be harder to diagnose

---

### 0005-libs-map-framework-cpp.patch

**File Modified:** `libs/map/framework.cpp`

**Category:** Debug Logging

**Purpose:** Adds debug logging to track Framework initialization sequence.

**What it does:**
- Adds `LOG(LDEBUG, ...)` calls around `SetRouterImpl`, `UpdateMinBuildingsTapZoom`, and `editor.SetDelegate`
- Helps trace initialization flow during debugging

**Why it's needed:**
Framework initialization involves many components. When debugging startup issues (especially on embedded platforms), knowing exactly where initialization stalls is critical.

**Without this patch:**
- Initialization failures would be harder to diagnose
- No visibility into which component causes hangs or crashes during startup

**Status:** Debug/Development patch - could potentially be removed in production builds.

---

### 0006-libs-map-routing_manager-cpp.patch

**File Modified:** `libs/map/routing_manager.cpp`

**Category:** Debug Logging

**Purpose:** Adds debug logging to track router creation and configuration.

**What it does:**
- Adds logging around `AbsentRegionsFinder` creation
- Logs router type and `IndexRouter` creation steps
- Tracks routing settings and router assignment

**Why it's needed:**
Routing initialization is complex and involves multiple factories. Debug logging helps identify exactly where issues occur.

**Without this patch:**
- Router initialization failures would be opaque
- Difficult to debug routing setup issues on embedded platforms

**Status:** Debug/Development patch - could potentially be removed in production builds.

---

### 0007-libs-routing-routing_session-cpp.patch

**File Modified:** `libs/routing/routing_session.cpp`

**Category:** Debug Logging

**Purpose:** Adds debug logging to track routing session lifecycle.

**What it does:**
- Logs `RemoveRoute()` operations step by step
- Logs `Reset()` sequence including route removal and state clearing
- Logs `SetRouter()` flow including thread checks and reset operations

**Why it's needed:**
Session state changes need visibility for debugging routing-related crashes or hangs.

**Without this patch:**
- Routing session state transitions would be invisible
- Hard to diagnose crashes during route clearing or session reset

**Status:** Debug/Development patch - could potentially be removed in production builds.

---

### 0008-libs-routing-speed_camera_manager-cpp.patch

**File Modified:** `libs/routing/speed_camera_manager.cpp`

**Category:** Null Safety / Crash Prevention

**Purpose:** Adds null-check guard for the speed camera clear callback and debug logging.

**What it does:**
- Wraps `m_speedCamClearCallback()` invocation in a null check
- Adds debug logging for reset operations
- Prevents crash when callback is not set

**Why it's needed:**
In embedded contexts, the speed camera clear callback might not be registered. Calling an unset `std::function` causes undefined behavior (typically a crash).

**Without this patch:**
- App would crash when `SpeedCameraManager::Reset()` is called without a registered callback
- Crash during routing session cleanup

---

### 0009-fix-android-gl3stub-include-path.patch

**File Modified:** `libs/drape/gl_includes.hpp`

**Category:** Android OpenGL / Build Configuration

**Purpose:** Switches from GLES2 + gl3stub.h to native GLES3 headers.

**What it does:**
- Replaces `#include <GLES2/gl2.h>` and `#include <GLES2/gl2ext.h>` with GLES3 equivalents
- Removes the `gl3stub.h` include that was used for dynamic GLES3 loading
- Keeps `<GLES2/gl2ext.h>` for `GL_TEXTURE_EXTERNAL_OES` and other extensions

**Why it's needed:**
The project targets Android API 24+ which has native GLES 3.0 support. Using native headers is cleaner and avoids the complexity of the gl3stub dynamic loader approach.

**Without this patch:**
- Build would fail looking for the `gl3stub.h` file in the CoMaps Android SDK path
- Would need to maintain the complex gl3stub loading mechanism

---

### 0010-fix-ios-cmake-missing-files.patch

**File Modified:** `CMakeLists.txt`

**Category:** Build System / Multi-Platform Support

**Purpose:** Comprehensive CMake fixes for cross-platform builds, especially iOS/Flutter integration.

**What it does:**
1. Uses `CMAKE_CURRENT_SOURCE_DIR` instead of `CMAKE_SOURCE_DIR` for subdirectory builds
2. Adds `/bigobj` for MSVC to handle unity builds
3. Adds multi-config generator support (Visual Studio, Xcode) with generator expressions
4. Adds `SKIP_QT` option to skip Qt dependencies
5. Fixes Boost modular header include paths
6. Adds `SKIP_TOOLS` option to skip generator tools
7. Adds `SKIP_ANDROID_JNI` option for Flutter Android builds
8. Makes Python protobuf check conditional on Qt builds

**Why it's needed:**
When CoMaps is used as a subdirectory of another project (like a Flutter plugin), many CMake assumptions break. This patch makes the build system flexible enough for embedded use.

**Without this patch:**
- CMake configuration would fail when CoMaps is a subdirectory
- Qt dependencies would be required even when not needed
- Windows builds would fail with "too many sections" errors
- Xcode/Visual Studio multi-config builds would break

---

### 0011-3party-icu-CMakeLists-txt.patch

**File Modified:** `3party/icu/CMakeLists.txt`

**Category:** Build System / ICU Library

**Purpose:** Adds missing ICU source file to the build.

**What it does:**
- Adds `icu/icu4c/source/common/ures_cnv.cpp` to the icuuc library sources

**Why it's needed:**
This file is required for ICU resource bundle conversion functionality. Without it, certain ICU operations fail at link time.

**Without this patch:**
- Linker errors for missing ICU symbols
- ICU functionality would be incomplete

---

### 0012-active-frame-callback.patch

**Files Modified:** 
- `libs/drape_frontend/CMakeLists.txt`
- `libs/drape_frontend/active_frame_callback.cpp` (new file)
- `libs/drape_frontend/active_frame_callback.hpp` (new file)

**Category:** Flutter Integration / Rendering Efficiency

**Purpose:** Adds an efficient active frame callback mechanism for Flutter texture notification.

**What it does:**
- Creates new files for thread-safe callback registration
- Exposes `SetActiveFrameCallback()` and `NotifyActiveFrame()` functions
- Called from `FrontendRenderer::RenderFrame()` only when `isActiveFrame` is true

**Why it's needed:**
Flutter plugins need to know when the map texture has new content to display. Without this, the plugin would need to poll or assume every frame has changes, wasting CPU/GPU resources.

**Without this patch:**
- Flutter would need to mark texture dirty on every frame (inefficient)
- No clean way to know when map content actually changed
- Higher battery consumption and CPU usage

---

### 0015-libs-platform-platform_mac-mm.patch

**File Modified:** `libs/platform/platform_mac.mm`

**Category:** macOS Platform / Missing Functions

**Purpose:** Adds missing platform function implementations for macOS.

**What it does:**
- Adds `#include` for required headers (`platform_unix_impl.hpp`, `coding/file_reader.hpp`, etc.)
- Implements `Platform::MkDir()`
- Implements `Platform::GetFilesByRegExp()` and `Platform::GetAllFiles()`
- Implements `Platform::GetFileSizeByName()` and `Platform::GetReader()`
- Implements `Platform::VideoMemoryLimit()` and `Platform::PreCachingDepth()`
- Implements `Platform::GetMemoryInfo()` using Mach APIs
- Implements `Platform::Version()` and `Platform::SetupMeasurementSystem()`
- Adds global `GetPlatform()` function

**Why it's needed:**
When building for macOS without the full app context, certain platform functions are missing. This patch provides the complete implementation.

**Without this patch:**
- Linker errors for missing Platform functions on macOS
- macOS build would fail

---

### 0016-libs-search-CMakeLists-txt.patch

**File Modified:** `libs/search/CMakeLists.txt`

**Category:** Build System / Test Configuration

**Purpose:** Makes search test subdirectories conditional on `SKIP_TESTS`.

**What it does:**
- Changes `if(PLATFORM_DESKTOP)` to `if(PLATFORM_DESKTOP AND NOT SKIP_TESTS)`
- Prevents building search quality tools when tests are skipped

**Why it's needed:**
When building as a library (not a full application), test/quality tools aren't needed and may have additional dependencies.

**Without this patch:**
- Unnecessary test code would be compiled
- Potential build failures from test dependencies

---

### 0017-libs-shaders-metal_program_pool-mm.patch

**File Modified:** `libs/shaders/metal_program_pool.mm`

**Category:** macOS/iOS Metal / Resource Loading

**Purpose:** Extends Metal shader library search to multiple bundle locations.

**What it does:**
- Searches main bundle first
- Searches all loaded bundles
- Searches all frameworks
- Searches nested `.bundle` directories within frameworks
- On macOS, searches `Contents/Frameworks` directory for plugin frameworks
- Adds extensive logging for debugging library location

**Why it's needed:**
Flutter plugins package Metal shaders separately from the main app. The shader library might be in a framework bundle, a resource bundle inside a framework, or the plugin's own bundle.

**Without this patch:**
- Metal shader library would not be found in Flutter plugin builds
- Map rendering would fail on iOS/macOS with Metal

---

### 0018-fix-shutdown-threads-null-safety.patch

**File Modified:** `libs/platform/platform.cpp`

**Category:** Null Safety / Crash Prevention

**Purpose:** Adds null checks to `Platform::ShutdownThreads()` to prevent crashes.

**What it does:**
- Returns early if any thread pointer is null
- Returns early if threads are already shut down
- Checks each thread before calling `ShutdownAndJoin()`

**Why it's needed:**
During app termination, static destruction order can cause `Platform` to be destroyed after some threads. Double-shutdown or null pointer access would cause crashes.

**Without this patch:**
- Crash during app shutdown when threads are already destroyed
- Crash from double-shutdown attempts
- Undefined behavior from null pointer access

---

### 0019-vulkan-windows-surface.patch

**File Modified:** `libs/drape/vulkan/vulkan_layers.cpp`

**Category:** Windows Vulkan Support

**Purpose:** Adds Windows-specific Vulkan extensions.

**What it does:**
- Adds instance extensions: `VK_KHR_win32_surface`, `VK_EXT_debug_utils`, `VK_KHR_get_physical_device_properties2`, `VK_KHR_external_memory_capabilities`
- Adds device extensions: `VK_KHR_external_memory`, `VK_KHR_external_memory_win32`

**Why it's needed:**
Windows requires specific Vulkan extensions for window surface creation and memory sharing.

**Without this patch:**
- Vulkan rendering would fail on Windows
- No window surface could be created

---

### 0022-3party-freetype-CMakeLists-txt.patch

**File Modified:** `3party/freetype/CMakeLists.txt`

**Category:** Build System / Installation Rules

**Purpose:** Disables FreeType installation rules.

**What it does:**
- Sets `SKIP_INSTALL_ALL ON` before adding FreeType subdirectory

**Why it's needed:**
When building as a static library for bundling, FreeType's install rules conflict with the parent project's install configuration.

**Without this patch:**
- CMake install rules from FreeType would pollute the parent project
- Potential conflicts during installation

---

### 0024-3party-jansson-jansson_config-h.patch

**File Modified:** `3party/jansson/jansson_config.h`

**Category:** Windows MSVC Compatibility

**Purpose:** Disables GCC atomic builtins for MSVC.

**What it does:**
- Wraps `JSON_HAVE_ATOMIC_BUILTINS` and `JSON_HAVE_SYNC_BUILTINS` definitions in `#ifdef _MSC_VER` check
- Sets both to 0 for MSVC, uses original values for other compilers

**Why it's needed:**
MSVC doesn't have GCC's `__atomic` or `__sync` builtins. Jansson needs to use alternative thread-safety mechanisms on Windows.

**Without this patch:**
- Compilation errors on MSVC about undefined `__atomic_*` functions
- Build would fail on Windows

---

### 0025-3party-opening_hours-rules_evaluation-cpp.patch

**File Modified:** `3party/opening_hours/rules_evaluation.cpp`

**Category:** Windows POSIX Compatibility

**Purpose:** Provides `localtime_r` implementation for Windows.

**What it does:**
- Adds conditional `localtime_r` wrapper using `localtime_s` on Windows
- Uses the same function signature as POSIX `localtime_r`

**Why it's needed:**
Windows doesn't have POSIX `localtime_r`. Windows provides `localtime_s` with reversed argument order.

**Without this patch:**
- Compilation error on Windows: `localtime_r` not found
- Opening hours parsing would not compile

---

### 0026-3party-protobuf-CMakeLists-txt.patch

**File Modified:** `3party/protobuf/CMakeLists.txt`

**Category:** Windows Build / Macro Conflicts

**Purpose:** Prevents Windows GDI header macro conflicts with protobuf.

**What it does:**
- Adds `NOGDI` compile definition for Windows builds
- This prevents `wingdi.h` from defining `ERROR` as 0

**Why it's needed:**
Windows `wingdi.h` defines `#define ERROR 0`, which conflicts with protobuf's `GOOGLE_LOG(ERROR)` macro.

**Without this patch:**
- Protobuf compilation fails on Windows with macro redefinition errors
- Build errors about `ERROR` being defined as `0`

---

### 0028-libs-base-logging-cpp.patch

**File Modified:** `libs/base/logging.cpp`

**Category:** Windows C Runtime Safety

**Purpose:** Fixes `std::toupper` call with unsigned char cast.

**What it does:**
- Casts character to `unsigned char` before passing to `std::toupper`

**Why it's needed:**
On Windows MSVC, `std::toupper(char)` can trigger an assertion failure if the character value is negative (e.g., non-ASCII characters). Casting to `unsigned char` ensures defined behavior.

**Without this patch:**
- Debug assertion failure on Windows with non-ASCII log level strings
- Potential crash in debug builds

---

### 0029-libs-base-string_utils-hpp.patch

**File Modified:** `libs/base/string_utils.hpp`

**Category:** Windows C Runtime Bug Fix

**Purpose:** Fixes `_strtoi64` and `_strtoui64` parameter passing on Windows.

**What it does:**
- Changes `&stop` to `stop` in `_strtoi64` and `_strtoui64` calls
- The `stop` parameter is already a pointer, taking its address gives wrong type

**Why it's needed:**
The original code passes `char***` where `char**` is expected, causing undefined behavior on Windows.

**Without this patch:**
- Integer parsing would fail or produce garbage results on Windows
- Potential crashes from type confusion

---

### 0030-libs-base-thread_checker-cpp.patch

**File Modified:** `libs/base/thread_checker.cpp`

**Category:** Embedded Build Support / Thread Safety

**Purpose:** Allows disabling thread checking for embedded builds.

**What it does:**
- Adds `#ifdef OMIM_DISABLE_THREAD_CHECKER` conditional compilation
- When defined, `CalledOnOriginalThread()` always returns true
- Constructor becomes empty

**Why it's needed:**
Embedded applications (like Flutter plugins) have different threading models. Objects created on one thread may be legitimately accessed from another (e.g., platform thread to render thread).

**Without this patch:**
- Thread checker assertions would fire in legitimate embedded usage patterns
- Crashes in debug builds from thread checker failures

---

### 0031-libs-base-thread_checker-hpp.patch

**File Modified:** `libs/base/thread_checker.hpp`

**Category:** Embedded Build Support / Thread Safety

**Purpose:** Header counterpart to thread checker disable mechanism.

**What it does:**
- When `OMIM_DISABLE_THREAD_CHECKER` is defined:
  - Removes `m_id` member variable
  - `CHECK_THREAD_CHECKER` becomes no-op
  - `DECLARE_AND_CHECK_THREAD_CHECKER` becomes no-op
- Adds documentation explaining the mechanism

**Why it's needed:**
Must match the implementation in the .cpp file. Header changes allow the compiler to optimize away thread checker storage.

**Without this patch:**
- Mismatched definitions between header and implementation
- Thread checker wouldn't be fully disabled

---

### 0032-libs-base-timer-cpp.patch

**File Modified:** `libs/base/timer.cpp`

**Category:** Windows C Runtime Safety

**Purpose:** Fixes `std::isdigit` call with unsigned char cast.

**What it does:**
- Casts character to `unsigned char` before `std::isdigit` call in timestamp parsing

**Why it's needed:**
Same as 0028 - Windows MSVC debug runtime asserts on negative character values.

**Without this patch:**
- Debug assertion failure when parsing timestamps with certain characters
- Crash in debug builds

---

### 0033-libs-drape-drape_tests-gl_functions-cpp.patch

**File Modified:** `libs/drape/drape_tests/gl_functions.cpp`

**Category:** Test Code / API Compatibility

**Purpose:** Updates mock `glShaderSource` to match new signature with debug name parameter.

**What it does:**
- Adds `std::string const & debugName` parameter to mock function
- Ignores the parameter in the mock implementation

**Why it's needed:**
Patch 0004 added a `debugName` parameter to `GLFunctions::glShaderSource`. Test mocks must match the new signature.

**Without this patch:**
- Test compilation fails due to signature mismatch
- Drape tests would not build

---

### 0034-libs-drape-dynamic_texture-hpp.patch

**File Modified:** `libs/drape/dynamic_texture.hpp`

**Category:** Windows Macro Conflicts

**Purpose:** Undefines Windows `FindResource` macro.

**What it does:**
- Adds `#undef FindResource` after includes

**Why it's needed:**
Windows `WinBase.h` defines `FindResource` as `FindResourceW` or `FindResourceA`. This conflicts with `dp::Texture::FindResource` method.

**Without this patch:**
- Compilation error: `FindResource` method gets macro-expanded
- drape library won't compile on Windows

---

### 0035-libs-drape-framebuffer-hpp.patch

**File Modified:** `libs/drape/framebuffer.hpp`

**Category:** Windows Macro Conflicts

**Purpose:** Undefines Windows `FindResource` macro (same as 0034).

**What it does:**
- Adds `#undef FindResource` after includes

**Why it's needed:**
Same as 0034 - framebuffer.hpp also uses code that conflicts with the Windows macro.

**Without this patch:**
- Same compilation errors as 0034 but in different header

---

### 0036-libs-drape-gl_functions-hpp.patch

**File Modified:** `libs/drape/gl_functions.hpp`

**Category:** API Change / Shader Debugging

**Purpose:** Adds optional `debugName` parameter to `glShaderSource` declaration.

**What it does:**
- Adds `std::string const & debugName = {}` parameter with default value

**Why it's needed:**
Header must match implementation changed in patch 0004. Default parameter maintains backward compatibility.

**Without this patch:**
- Header/implementation mismatch
- Existing code calling `glShaderSource` would fail to compile

---

### 0037-libs-drape-shader-cpp.patch

**File Modified:** `libs/drape/shader.cpp`

**Category:** Error Handling / Robustness

**Purpose:** Improves shader compilation error handling and adds retry logic.

**What it does:**
- Passes shader name to `glShaderSource` for debugging
- Adds retry logic if compilation fails with "src_len=" error (indicates upload glitch)
- Changes fatal `CHECK` to `LOG(LERROR)` to allow app to continue for diagnostics

**Why it's needed:**
Shader compilation can fail transiently on some drivers. Fatal crashes prevent diagnosis. Retry logic can recover from transient failures.

**Without this patch:**
- App crashes on any shader compilation error
- No retry for transient driver issues
- Harder to diagnose shader problems

---

### 0038-libs-drape-texture-hpp.patch

**File Modified:** `libs/drape/texture.hpp`

**Category:** Windows Macro Conflicts

**Purpose:** Undefines Windows `FindResource` macro (same as 0034, 0035).

**What it does:**
- Adds `#undef FindResource` after includes

**Why it's needed:**
Same Windows macro conflict issue in the texture header.

**Without this patch:**
- Same compilation errors in texture-related code

---

### 0039-libs-drape-tm_read_resources-hpp.patch

**File Modified:** `libs/drape/tm_read_resources.hpp`

**Category:** Windows Compatibility / Line Endings

**Purpose:** Handles Windows line endings in pattern list files.

**What it does:**
- Strips trailing `\r` from lines (Windows CRLF handling)
- Skips empty tokens from multiple spaces

**Why it's needed:**
Pattern files may have Windows line endings. `std::getline` leaves `\r` at end of lines on non-Windows systems reading Windows files.

**Without this patch:**
- Pattern parsing fails with Windows-format files
- `\r` characters would be part of pattern data

---

### 0040-libs-drape-vertex_array_buffer-cpp.patch

**File Modified:** `libs/drape/vertex_array_buffer.cpp`

**Category:** Error Handling / Robustness

**Purpose:** Handles missing vertex attribute locations gracefully.

**What it does:**
- Checks if `attributeLocation == -1` (attribute optimized out by shader compiler)
- Logs error instead of asserting
- Continues to next attribute instead of crashing

**Why it's needed:**
Shader compilers may optimize out unused attributes. The original assert crashes on valid shader optimizations.

**Without this patch:**
- Crash when shader compiler optimizes out an attribute
- Cannot use shaders with optimized attributes

---

### 0041-libs-drape_frontend-frontend_renderer-cpp.patch

**File Modified:** `libs/drape_frontend/frontend_renderer.cpp`

**Category:** Flutter Integration

**Purpose:** Calls the active frame callback mechanism from patch 0012.

**What it does:**
- Includes `active_frame_callback.hpp`
- Calls `NotifyActiveFrame()` when `isActiveFrame` is true

**Why it's needed:**
This is the actual integration point for the callback mechanism created in patch 0012.

**Without this patch:**
- Active frame callback would never be invoked
- Patch 0012 would be useless

---

### 0042-libs-indexer-categories_holder-cpp.patch

**File Modified:** `libs/indexer/categories_holder.cpp`

**Category:** Windows C Runtime Safety

**Purpose:** Fixes `std::isdigit` call with unsigned char cast.

**What it does:**
- Casts `name.m_name.front()` to `unsigned char` before `std::isdigit`

**Why it's needed:**
Same Windows MSVC debug runtime issue as patches 0028, 0032.

**Without this patch:**
- Debug assertion failure when processing category names

---

### 0043-libs-indexer-editable_map_object-cpp.patch

**File Modified:** `libs/indexer/editable_map_object.cpp`

**Category:** Windows C Runtime Safety

**Purpose:** Fixes `std::isalnum` and `std::isdigit` calls with unsigned char casts.

**What it does:**
- Creates local lambda `isAlnum` with proper casting
- Casts characters to `unsigned char` in phone validation

**Why it's needed:**
Same Windows MSVC debug runtime issue for character classification functions.

**Without this patch:**
- Debug assertion failures when validating flats/phone numbers

---

### 0044-libs-indexer-search_string_utils-cpp.patch

**File Modified:** `libs/indexer/search_string_utils.cpp`

**Category:** Windows C Runtime Safety

**Purpose:** Fixes `std::isdigit` call with unsigned char cast.

**What it does:**
- Creates local lambda `isDigit` with proper casting for UniString elements

**Why it's needed:**
Same Windows MSVC debug runtime issue.

**Without this patch:**
- Debug assertion failure in search token processing

---

### 0045-libs-platform-local_country_file_utils-cpp.patch

**File Modified:** `libs/platform/local_country_file_utils.cpp`

**Category:** Windows C Runtime Safety

**Purpose:** Fixes `isdigit` call with unsigned char cast.

**What it does:**
- Casts character to `unsigned char` in `ParseVersion`

**Why it's needed:**
Same Windows MSVC debug runtime issue.

**Without this patch:**
- Debug assertion failure when parsing map version strings

---

### 0046-libs-platform-platform_win-cpp.patch

**File Modified:** `libs/platform/platform_win.cpp`

**Category:** Windows Build / Name Resolution

**Purpose:** Fixes `bind` to use `std::bind` explicitly.

**What it does:**
- Changes `bind(&CloseHandle, hFile)` to `std::bind(&CloseHandle, hFile)`

**Why it's needed:**
Without the `std::` prefix, the compiler might find wrong `bind` overloads depending on includes and namespace usage.

**Without this patch:**
- Potential compilation errors or wrong function binding

---

### 0047-libs-routing-lanes-lanes_parser-cpp.patch

**File Modified:** `libs/routing/lanes/lanes_parser.cpp`

**Category:** Windows C Runtime Safety

**Purpose:** Fixes `std::isspace` and `std::tolower` calls with unsigned char casts.

**What it does:**
- Casts characters to `unsigned char` in lambda for `std::views::filter` and `std::views::transform`

**Why it's needed:**
Same Windows MSVC debug runtime issue for character classification.

**Without this patch:**
- Debug assertion failure when parsing lane information

---

### 0048-libs-routing-routing_quality-api-google-google_api-cpp.patch

**File Modified:** `libs/routing/routing_quality/api/google/google_api.cpp`

**Category:** Windows POSIX Compatibility

**Purpose:** Provides portable UTC offset calculation.

**What it does:**
- Creates `GetUTCOffsetHours()` function that works on Windows and POSIX
- On Windows, uses `_get_timezone()` instead of `tm_gmtoff`
- Properly accounts for DST

**Why it's needed:**
Windows `struct tm` doesn't have `tm_gmtoff` member. Need platform-specific code.

**Without this patch:**
- Compilation error on Windows: `tm_gmtoff` not a member of `tm`

---

### 0049-libs-search-latlon_match-cpp.patch

**File Modified:** `libs/search/latlon_match.cpp`

**Category:** Windows C Runtime Safety

**Purpose:** Fixes `isdigit` call with unsigned char cast.

**What it does:**
- Casts character to `unsigned char` in coordinate parsing

**Why it's needed:**
Same Windows MSVC debug runtime issue.

**Without this patch:**
- Debug assertion failure when parsing latitude/longitude

---

### 0050-libs-search-processor-cpp.patch

**File Modified:** `libs/search/processor.cpp`

**Category:** Windows C Runtime Safety

**Purpose:** Fixes `isdigit` calls with unsigned char casts.

**What it does:**
- Casts characters to `unsigned char` in multiple functions
- Creates local `isDigit` lambda for `std::all_of`

**Why it's needed:**
Same Windows MSVC debug runtime issue.

**Without this patch:**
- Debug assertion failures in search processing

---

### 0051-libs-search-search_quality-samples_generation_tool-samples_generation_tool-cpp.patch

**File Modified:** `libs/search/search_quality/samples_generation_tool/samples_generation_tool.cpp`

**Category:** Windows C Runtime Safety

**Purpose:** Fixes `isdigit` call with unsigned char cast.

**What it does:**
- Casts character to `unsigned char` in house number modification

**Why it's needed:**
Same Windows MSVC debug runtime issue.

**Without this patch:**
- Debug assertion failure in samples generation tool

---

### 0052-libs-shaders-gl_program_pool-cpp.patch

**File Modified:** `libs/shaders/gl_program_pool.cpp`

**Category:** Windows OpenGL / Shader Version

**Purpose:** Uses correct GLSL version string for Windows.

**What it does:**
- Changes condition from `OMIM_OS_DESKTOP` to `OMIM_OS_DESKTOP && !OMIM_OS_WINDOWS`
- Windows (with ANGLE) uses GLES3 shader version, not GL3

**Why it's needed:**
Windows builds using ANGLE (EGL/GLES emulation) need GLES shader version strings, not desktop GL version strings.

**Without this patch:**
- Shader compilation fails on Windows with wrong GLSL version
- Map rendering broken on Windows

---

### 0053-libs-transit-transit_schedule-cpp.patch

**File Modified:** `libs/transit/transit_schedule.cpp`

**Category:** Windows POSIX Compatibility

**Purpose:** Provides `localtime_r` implementation for Windows.

**What it does:**
- Same pattern as patch 0025: wrapper using `localtime_s`

**Why it's needed:**
Same as patch 0025 - transit schedule needs thread-safe time conversion.

**Without this patch:**
- Compilation error on Windows in transit module

---

### 0054-3party-opening_hours-CMakeLists-txt.patch

**File Modified:** `3party/opening_hours/CMakeLists.txt`

**Category:** Windows Build / Unity Build

**Purpose:** Adds `/bigobj` compiler flag for MSVC.

**What it does:**
- Adds `target_compile_options(${PROJECT_NAME} PRIVATE /bigobj)` for MSVC

**Why it's needed:**
Unity builds combine many source files, exceeding MSVC's default object section limit.

**Without this patch:**
- Build error: "file too big" or "too many sections" on Windows

---

### 0059-win-platform-cmake.patch

**File Modified:** `libs/platform/CMakeLists.txt`

**Category:** Build System / Platform Configuration

**Purpose:** Comprehensive platform CMake configuration for Flutter plugin builds.

**What it does:**
1. Fixes iOS to use `http_session_manager.mm` instead of non-existent `http_user_agent_ios.mm`
2. Adds `SKIP_ANDROID_JNI` configuration for Flutter Android (uses external platform implementation)
3. Adds `SKIP_QT` configuration for macOS without Qt
4. Adds `SKIP_QT` configuration for Windows without Qt
5. Makes Qt linking conditional on `NOT SKIP_QT`

**Why it's needed:**
Flutter plugins need platform implementations without Qt and without JNI (using FFI instead).

**Without this patch:**
- Cannot build platform library for Flutter integration
- Wrong source files selected for iOS
- Unnecessary Qt dependencies

---

### 0060-3party-gflags-skip-install.patch

**File Modified:** `3party/gflags/CMakeLists.txt`

**Category:** Build System / CMake Install Rules

**Purpose:** Skips gflags install configuration when using generator expressions.

**What it does:**
- Checks for `CMAKE_SKIP_INSTALL_RULES` and generator expressions in `CMAKE_INSTALL_PREFIX`
- Skips `file(RELATIVE_PATH ...)` and configure_file calls that fail with generator expressions

**Why it's needed:**
Flutter Windows builds use generator expressions in install prefix (`$<TARGET_FILE_DIR:...>`). CMake's `file(RELATIVE_PATH)` doesn't support generator expressions.

**Without this patch:**
- CMake configuration fails on Flutter Windows builds
- Error about invalid characters in path

---

### 0061-3party-protobuf-stubs-time.patch

**Files Modified:**
- `3party/protobuf/protobuf/src/google/protobuf/stubs/time.cc`
- `3party/protobuf/protobuf/src/google/protobuf/stubs/time.h`

**Category:** Windows Macro Conflicts

**Purpose:** Undefines Windows `GetCurrentTime` macro.

**What it does:**
- Adds `#undef GetCurrentTime` in both header and source

**Why it's needed:**
Windows `winbase.h` defines `GetCurrentTime` as a macro. Protobuf has a `GetCurrentTime` function that conflicts.

**Without this patch:**
- Protobuf compilation fails with macro expansion errors

---

### 0062-libs-platform-gui_thread_win-cpp.patch

**File Modified:** `libs/platform/gui_thread_win.cpp` (new file)

**Category:** Windows Platform / GUI Thread

**Purpose:** Provides Windows implementation of `GuiThread` for task execution.

**What it does:**
- Creates a message-only window for receiving task messages
- Implements `GuiThread::Push()` using Windows message queue
- Uses custom `WM_GUI_TASK` message for task dispatch

**Why it's needed:**
The platform library needs a `GuiThread` implementation for Windows without Qt. This uses native Windows message passing.

**Without this patch:**
- Linker error: missing `GuiThread::Push` on Windows
- Cannot post tasks to GUI thread

---

### 0063-3party-boost-qvm-quat_traits-hpp.patch

**File Modified:** `3party/boost/libs/qvm/include/boost/qvm/quat_traits.hpp`

**Category:** Compiler Compatibility / Template Syntax

**Purpose:** Fixes template keyword usage in boost::qvm.

**What it does:**
- Removes unnecessary `template` keyword before `write_element_idx`

**Why it's needed:**
Some compilers reject the `template` keyword in this context when not in a dependent scope.

**Without this patch:**
- Compilation errors with certain compilers in quaternion code

---

### 0064-3party-boost-gil-algorithm-hpp.patch

**File Modified:** `3party/boost/libs/gil/include/boost/gil/algorithm.hpp`

**Category:** Compiler Compatibility / Template Syntax

**Purpose:** Fixes template keyword usage in boost::gil.

**What it does:**
- Removes unnecessary `template` keyword before `apply`

**Why it's needed:**
Same as patch 0063 - template keyword syntax issue.

**Without this patch:**
- Compilation errors in image processing code

---

### 0065-3party-jansson-hashtable_seed-undef-long.patch

**File Modified:** `3party/jansson/jansson/src/hashtable_seed.c`

**Category:** Windows Unity Build / Macro Conflicts

**Purpose:** Undefines `Long` and `ULong` macros before Windows headers.

**What it does:**
- Adds `#undef Long` and `#undef ULong` before `#include <windows.h>`

**Why it's needed:**
In Unity builds, `dtoa.c` defines `#define Long int`. This leaks to `hashtable_seed.c` which includes Windows headers. Windows SDK headers have struct members named `Long` which become invalid with the macro.

**Without this patch:**
- Unity build fails: "DWORD followed by int is illegal"
- Windows header parsing errors

---

### 0066-3party-jansson-dtoa-undef-long-end.patch

**File Modified:** `3party/jansson/jansson/src/dtoa.c`

**Category:** Windows Unity Build / Macro Conflicts

**Purpose:** Undefines `Long` macro at end of dtoa.c.

**What it does:**
- Adds `#undef Long` at the end of dtoa.c

**Why it's needed:**
`dtoa.c` defines `Long` at line 229. In Unity builds, this macro leaks to subsequent files. Adding the undef at file end prevents leakage.

**Without this patch:**
- Unity build errors in files compiled after dtoa.c
- Windows header conflicts with `Long` macro

---

### 0067-3party-jansson-disable-unity-build.patch

**File Modified:** `3party/jansson/jansson/CMakeLists.txt`

**Category:** Windows Unity Build / Build Configuration

**Purpose:** Disables Unity build specifically for jansson library.

**What it does:**
- Sets `UNITY_BUILD OFF` property for jansson target (both shared and static)

**Why it's needed:**
Even with patches 0065 and 0066, jansson's `dtoa.c` macro issues are fragile in Unity builds. Disabling Unity build for jansson is the safest fix.

**Without this patch:**
- Potential Unity build failures depending on file ordering
- Fragile build that may break with CMake changes

**Note:** This patch, combined with 0065 and 0066, provides defense in depth. Any one of them might be sufficient, but having all three ensures robustness.

---

## Policy

- Prefer a clean bridge layer in this repo.
- Only introduce patches if there is no viable clean integration path.
- Keep patches small, scoped, and re-applicable across tags.

## Potential Removals

The following patches are primarily for debugging and could potentially be removed in production:
- **0005** - Debug logging in framework.cpp
- **0006** - Debug logging in routing_manager.cpp  
- **0007** - Debug logging in routing_session.cpp
- **0008** - Partially debug logging, but the null-check is essential

The following patches have overlapping functionality and could be consolidated:
- **0065, 0066, 0067** - All address jansson Unity build issues. Patch 0067 alone might be sufficient.

## Usage

**Linux/macOS:**
```bash
./scripts/apply_comaps_patches.sh
```

**Windows PowerShell:**
```powershell
.\scripts\apply_comaps_patches.ps1
```
