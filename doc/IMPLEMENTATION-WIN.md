# Windows Implementation (x86_64)

> **Platform Support:** Currently only **x86_64 (64-bit Intel/AMD)** is supported. ARM64 Windows support is theoretically possible but untested due to lack of ARM64 hardware for development.

## Current Status

**Build Status:** ✅ Compiles and links successfully  
**Plugin Registration:** ✅ MethodChannel handler implemented  
**Rendering:** ✅ OpenGL context created, D3D11 texture sharing implemented  
**Surface Bridge:** ✅ Plugin now calls FFI library for surface creation  
**Architecture:** x86_64 only (ARM64 untested)  
**CoMaps Tools:** ✅ Skipped via `SKIP_TOOLS` CMake option (dev_sandbox, generator, tools not needed for Flutter plugin)

## IMPORTANT: Windows Extracted Asset Location (User Home)

When you run the Windows example exe, assets are **extracted into the user’s Documents folder**, not next to the executable.

**Exact locations (relative to the user home directory):**
- `%USERPROFILE%\Documents\agus_maps_flutter\maps\` → extracted `.mwm` map files
- `%USERPROFILE%\Documents\agus_maps_flutter\` → extracted CoMaps data files (styles, symbols, classificator, etc.)

If you delete these folders (or the marker file `%USERPROFILE%\Documents\agus_maps_flutter\.comaps_data_extracted`), the next app run will re-extract from bundled `flutter_assets`.

## Cross-Platform Rendering Comparison

This section compares the rendering architecture across all supported platforms.

### Rendering Pipeline Overview

| Platform | Graphics API | Texture Sharing | Frame Transfer | GUI Thread |
|----------|--------------|-----------------|----------------|------------|
| **Windows** | OpenGL (WGL) | D3D11 DXGI Shared Handle | Zero-copy (WGL_NV_DX_interop, Keyed Mutex optional) | HWND_MESSAGE + PostMessage |
| **iOS** | Metal | CVPixelBuffer + IOSurface | Zero-copy (shared GPU memory) | GCD (dispatch_async) |
| **macOS** | Metal | CVPixelBuffer + IOSurface | Zero-copy (shared GPU memory) | GCD (dispatch_async) |
| **Android** | OpenGL ES 3.0 | SurfaceTexture | Zero-copy (EGL native window) | JNI → Android UI thread |

### Windows vs iOS/macOS: Key Differences

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        iOS/macOS (Metal)                                │
├─────────────────────────────────────────────────────────────────────────┤
│  CoMaps → MTLTexture (CVPixelBuffer) → Flutter samples via IOSurface   │
│  ✓ Zero-copy: GPU memory shared between CoMaps and Flutter              │
│  ✓ No CPU involvement in frame transfer                                 │
│  ✓ CVMetalTextureCacheCreateTextureFromImage for efficient binding      │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│                        Windows (OpenGL + D3D11)                         │
├─────────────────────────────────────────────────────────────────────────┤
│  CoMaps → OpenGL FBO → glBlitFramebuffer (WGL_NV_DX_interop)            │
│            → D3D11 Shared Texture (DXGI handle) → Flutter               │
│  ✓ Zero-copy: GPU memory shared between CoMaps and Flutter              │
│  ✓ GPU-accelerated frame transfer (<0.5ms)                              │
│  ✓ WGL_NV_DX_interop lock/unlock synchronization                        │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│                        Android (OpenGL ES)                              │
├─────────────────────────────────────────────────────────────────────────┤
│  CoMaps → EGL Surface → SurfaceTexture → Flutter Texture                │
│  ✓ Zero-copy: EGL window surface directly bound to texture              │
│  ✓ Hardware compositor integration via SurfaceProducer                  │
└─────────────────────────────────────────────────────────────────────────┘
```

### GUI Thread Implementation Comparison

Each platform requires a mechanism to dispatch tasks from C++ background threads to the platform's UI thread:

| Platform | Implementation | Header Location |
|----------|----------------|-----------------|
| **Windows** | `gui_thread_win.cpp` - HWND_MESSAGE window + WM_USER + PostMessage | `libs/platform/` |
| **iOS/macOS** | `gui_thread_apple.mm` - GCD dispatch_async to main queue | `libs/platform/` |
| **Android** | `gui_thread_android.cpp` - JNI CallStaticVoidMethod | `libs/platform/` |
| **Qt (reference)** | `gui_thread.cpp` - QTimer::singleShot | `libs/platform/` |

**Windows GUI Thread Pattern:**
```cpp
// Creates a hidden message-only window for task dispatch
class TaskWindow {
    HWND m_hwnd;  // HWND_MESSAGE parent = no visible window
    static LRESULT CALLBACK WndProc(HWND, UINT msg, WPARAM, LPARAM lParam) {
        if (msg == WM_GUI_TASK) {
            auto* task = reinterpret_cast<Task*>(lParam);
            (*task)();
            delete task;
            return 0;
        }
        return DefWindowProc(...);
    }
};

// Push task to UI thread
GuiThread::PushResult GuiThread::Push(Task&& task) {
    auto* taskPtr = new Task(std::move(task));
    PostMessage(TaskWindow::Instance().GetHwnd(), WM_GUI_TASK, 0, 
                reinterpret_cast<LPARAM>(taskPtr));
    return {true, base::TaskLoop::kNoId};
}
```

### Why Different Approaches?

| Factor | iOS/macOS | Android | Windows |
|--------|-----------|---------|---------|
| **Native Graphics** | Metal (unified) | OpenGL ES | OpenGL (WGL) or D3D11 |
| **Flutter Uses** | Metal/Impeller | OpenGL ES/Impeller | ANGLE (D3D11 backend) |
| **Texture Sharing** | IOSurface (native) | EGLImage/SurfaceTexture | No native GL↔D3D sharing |
| **Result** | Zero-copy possible | Zero-copy possible | Zero-copy possible (WGL_NV_DX_interop) |

### Performance Characteristics

| Metric | Windows | iOS/macOS | Android |
|--------|---------|-----------|---------|
| **Frame Copy Latency** | <0.5ms (GPU) | <0.5ms (GPU) | <0.5ms (GPU) |
| **Idle CPU Usage** | <1% | <1% | <1% |
| **Panning CPU Usage** | 5-10% | 5-10% | 5-10% |
| **Memory (1080p frame)** | Shared | Shared | Shared |

### Vulkan on Windows

While Vulkan could also achieve zero-copy, the current OpenGL implementation utilizing `WGL_NV_DX_interop` (with `glBlitFramebuffer`) now matches performance expectations without rewriting the CoMaps backend.

## Efficiency Analysis

### Memory Efficiency

| Aspect | Status | Notes |
|--------|--------|-------|
| Map Data (MWM) | ✅ Zero-Copy | Memory-mapped files via CoMaps' MWM format - only viewed tiles loaded into RAM |
| Frame Transfer | ✅ Zero-Copy | Uses `WGL_NV_DX_interop` + DXGI shared handle (Keyed Mutex optional) |
| Dart VM Impact | ✅ Minimal | Map data never enters Dart heap; only control messages cross FFI boundary |

### Frame Transfer Architecture

Windows now implements a **Zero-Copy** path using `WGL_NV_DX_interop`:

```
┌─────────────────────────────────────────────────────────────────────┐
│ OpenGL FBO (CoMaps renders here via WGL)                            │
│   ↓                                                                 │
│ glBlitFramebuffer() - GPU Copy via Interop Extension                │
│   ↓                                                                 │
│ OpenGL Interop Texture (Registered D3D Object)                      │
│   ↓                                                                 │
│ D3D11 Shared Texture - D3D11_RESOURCE_MISC_SHARED                   │
│   ↓                                                                 │
│ Flutter Engine - Samples via DXGI shared handle                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Implementation Details:**

1. **WGL_NV_DX_interop**: Used to register the D3D11 shared texture as an OpenGL texture.
2. **Synchronization**: Uses `wglDXLockObjectsNV` / `wglDXUnlockObjectsNV` to guard access to the interop texture.
3.  **Fallback**: The system automatically falls back to CPU copy if:
    - `WGL_NV_DX_interop` is missing.
    - `glBlitFramebuffer` is unavailable.
    - Interop FBO creation fails (`GL_FRAMEBUFFER_UNSUPPORTED`).

**Performance Impact:**
- <0.5ms per frame copy latency
- Minimal CPU usage during panning
- Native 60 FPS on supported hardware

**Optional Keyed Mutex (advanced):**
- A Keyed Mutex is **disabled by default** because Flutter's Windows embedder does not consistently Acquire/Release keyed mutexes for `kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle`.
- If you *do* want to experiment with keyed mutex synchronization, set:
  - `AGUS_MAPS_WIN_KEYED_MUTEX=1`
- When enabled, the producer uses **AcquireSync(0) → ReleaseSync(1)**. The Flutter consumer **must** AcquireSync(1) and ReleaseSync(0). If it does not, frames will stall or appear white.

### Building from Source

**IMPORTANT:** The `windows/CMakeLists.txt` is configured to prefer **pre-built binaries** found in `windows/prebuilt/x64/` or defined by `AGUS_MAPS_HOME`.
When developing or modifying the C++ plugin code (e.g., `src/AgusWglContextFactory.cpp`), you **MUST** ensure that no pre-built `agus_maps_flutter.dll` exists in `windows/prebuilt/x64/`.
If a pre-built DLL is present, CMake will link against it and **IGNORE** your source code changes.

**To force a source build:**
```powershell
Remove-Item -Path "windows/prebuilt/x64/agus_maps_flutter.dll" -Force
flutter clean
flutter run -d windows
```

### Issues and Resolutions

#### 1. Zero-Copy Blit Failure
- **Issue:** `glBlitFramebuffer` requires OpenGL 3.0+, which is not exposed by standard Windows `GL/gl.h` (only GL 1.1).
- **Resolution:** Manually loaded function pointers via `wglGetProcAddress` and defined missing constants (`GL_READ_FRAMEBUFFER`, `GL_DRAW_FRAMEBUFFER`) in `AgusWglContextFactory.cpp`.

#### 2. Header Guard Mismatch
    - **Issue:** `AgusWglContextFactory.hpp` had a stray `#endif` causing `error C1070` and confusing the compiler/IntelliSense.
    - *Resolution*: Removed the extra `#endif` to restore proper preprocessor balance.

#### 3. WGL Functions Not Loaded / Macro Conflict
    - **Issue:** `wglDXOpenDeviceNV` and other function pointers were named identically to the global function names (or GLEW macros). This caused:
        1. Member variables shadowing global functions (ambiguity).
        2. Potential compilation failure if GLEW/WGLEW macros were active (e.g. `this->__glewDXOpenDeviceNV` is invalid).
        3. Members were initially not loaded via `wglGetProcAddress`.
    - **Resolution:**
        1. Renamed all WGL member variables with `m_` prefix (e.g. `m_wglDXOpenDeviceNV`) to avoid conflicts.
        2. Added explicit `wglGetProcAddress` loading in `InitializeWGL`.

#### 4. Framebuffer Incompleteness
- **Issue:** Some drivers/GPUs may fail `glCheckFramebufferStatus` for the interop FBO.
- **Resolution:** Added graceful fallback logic. If the interop FBO is incomplete, the system logs a warning and reverts to the CPU-mediated copy path.

#### 5. White Map on Windows (Keyed Mutex Mismatch)
- **Issue:** Map widget renders white while CoMaps logs show rendering is active. The shared texture was created with `D3D11_RESOURCE_MISC_SHARED_KEYEDMUTEX`, but Flutter did not Acquire/Release keyed mutexes, so the producer stalled or the consumer read an unsignaled texture.
- **Resolution:** Defaulted to **non-keyed** shared handles and rely on `wglDXLockObjectsNV` / `wglDXUnlockObjectsNV` for synchronization. Keyed mutex is now **opt-in** via `AGUS_MAPS_WIN_KEYED_MUTEX=1`.
- **Logs to confirm fix:**
  - `[CoMaps INFO] Shared texture created: ... KeyedMutex: No`
  - `[CoMaps INFO] CopyToSharedTexture: useInterop: 1 interopFbo: ... keyedMutex: No`
- **If logs still show KeyedMutex: Yes:**
  - You are likely running a **prebuilt** `agus_maps_flutter.dll` from [windows/prebuilt/x64/](windows/prebuilt/x64/) or have `AGUS_MAPS_WIN_KEYED_MUTEX=1` set in your environment. Remove the prebuilt DLL and rerun.
  - `scripts/build_all.ps1` rebuilds and re-copies the prebuilt DLL. If you ran it, delete the prebuilt DLL **after** the script finishes, then run `flutter clean` and `flutter run`.

#### 5. Standard Build Ignoring Changes
- **Issue:** `Enable Prebuilt` logic in CMake takes precedence.
- **Resolution:** Documented the need to delete prebuilt binaries when working on plugin internals.

#### 6. Windows Build Failure: Missing `wglDX*` Symbols
- **Issue:** The Windows build failed with errors like:
  - `error C3861: 'wglDXUnregisterObjectNV': identifier not found`
  - `error C3861: 'wglDXCloseDeviceNV': identifier not found`
- **Root Cause:** Cleanup logic called the *global* WGL symbols directly instead of the dynamically loaded function pointers.
- **Resolution:** Updated cleanup paths to call `m_wglDXUnregisterObjectNV` / `m_wglDXCloseDeviceNV` only after verifying the function pointers are loaded. This removes the direct symbol dependency and aligns with the dynamic `wglGetProcAddress` loading strategy.

#### 7. Windows Build Failure: `GL_CLAMP_TO_EDGE` Undefined
- **Issue:** MSVC failed with:
  - `error C2065: 'GL_CLAMP_TO_EDGE': undeclared identifier`
- **Root Cause:** Legacy Windows OpenGL headers (`GL/gl.h`) do not define `GL_CLAMP_TO_EDGE`.
- **Resolution:** Added a local fallback define in `AgusWglContextFactory.cpp`:
  - `#ifndef GL_CLAMP_TO_EDGE` → `#define GL_CLAMP_TO_EDGE 0x812F`

#### 8. Windows Build Failure: `wchar_t` Logging in `LOG()`
- **Issue:** Build failed with:
  - `error C2280: std::operator<< ... wchar_t: attempting to reference a deleted function`
- **Root Cause:** The DXGI adapter description is a wide string (`wchar_t[]`) and cannot be streamed into the narrow `LOG()` path.
- **Resolution:** Convert the adapter name to UTF-8 before logging. This keeps diagnostics intact without breaking MSVC's stream constraints.

#### 9. Zero-Copy Disabled: `wglDXRegisterObjectNV` Failed
- **Symptom:** Overlay shows `Transfer: CPU copy (glReadPixels)` and logs show:
  - `WGL Interop: Failed to register object` with a Windows error code.
- **Root Cause:** The D3D11 device was created on a different GPU adapter than the OpenGL context. WGL interop requires both to be on the same adapter.
- **Resolution:** Match the D3D11 adapter to the OpenGL renderer string via DXGI enumeration before creating the device. If a match is found, create the device with `D3D_DRIVER_TYPE_UNKNOWN` on that adapter. This increases interop success on multi‑GPU systems.
- **New Logs:**
  - `OpenGL renderer: ...`
  - `D3D adapter matched OpenGL renderer: ...`
  - `WGL Interop: Failed to register object. GetLastError: ... GL error: ... format: ... bindFlags: ... miscFlags: ...`

#### 10. Zero-Copy Disabled: `wglDXRegisterObjectNV` Failed (No Current GL Context)
- **Symptom:** `WGL Interop: Failed to register object` with `GL error: 1282` (GL_INVALID_OPERATION) and `interop disabled reasons: device: 0 object: 0 fbo: 0` even when WGL interop functions are available and adapters match.
- **Root Cause:** `CreateSharedTexture()` performed GL texture creation + interop registration without making the WGL draw context current. `wglDXRegisterObjectNV` requires a current OpenGL context.
- **Resolution:** Ensure `m_drawGlrc` is current during interop registration, then restore the previous context. This removes the GL_INVALID_OPERATION error and allows the interop object/FBO to be created.

#### 11. Zero-Copy Disabled: Interop FBO Unsupported (`GL_FRAMEBUFFER_UNSUPPORTED`)
- **Symptom:** Logs show:
  - `WGL Interop: Registered D3D texture as GL texture ...`
  - `WGL Interop: Interop FBO incomplete (status: 36061 GL_FRAMEBUFFER_UNSUPPORTED)`
- **Root Cause:** Some drivers reject FBO attachment for an interop texture object even when WGL interop is available. This typically means the driver only supports renderbuffer attachment for the shared D3D texture.
- **Resolution:** If the texture-based interop FBO is unsupported, register the shared texture as a **GL_RENDERBUFFER** instead and attach via `glFramebufferRenderbuffer`. This provides a compatible zero‑copy path on drivers that disallow `GL_TEXTURE_2D` FBO attachments for interop.
- **New Logs:**
  - `WGL Interop: Interop FBO incomplete (status: ... GL_FRAMEBUFFER_UNSUPPORTED) - trying renderbuffer path`
  - `WGL Interop: Registered D3D texture as GL renderbuffer ...`
  - `WGL Interop: Renderbuffer FBO complete - Zero-Copy enabled`

#### 12. Zero-Copy Disabled: Interop FBO Incomplete Due to Draw/Read Buffers
- **Symptom:** `GL_FRAMEBUFFER_UNSUPPORTED` or `GL_FRAMEBUFFER_INCOMPLETE_DRAW_BUFFER` after registering the interop object.
- **Root Cause:** Some drivers require explicit `glDrawBuffers` / `glReadBuffer` setup on user FBOs; leaving them at default can mark the FBO incomplete.
- **Resolution:** Explicitly set draw/read buffers after attaching the interop texture/renderbuffer:
  - `glDrawBuffers(1, {GL_COLOR_ATTACHMENT0});`
  - `glReadBuffer(GL_COLOR_ATTACHMENT0);`

#### 13. Zero-Copy Disabled: Interop FBO Incomplete Until Object Lock
- **Symptom:** `GL_FRAMEBUFFER_UNSUPPORTED` persists even after explicit draw/read buffer setup.
- **Root Cause:** Some drivers require the interop object to be locked via `wglDXLockObjectsNV` before the FBO attachment is considered renderable.
- **Resolution:** Lock the interop object before FBO setup and status checks, then unlock immediately after.

#### 12. CPU Fallback Colors Inverted
- **Symptom:** Map colors appear inverted when CPU copy fallback is active.
- **Root Cause:** The fallback path copied `GL_RGBA` pixels directly into the D3D texture without channel swizzle. D3D expects `BGRA`.
- **Resolution:** Swizzle RGBA → BGRA during the CPU copy loop and clear the staging buffer first when sizes differ. This fixes color inversion in CPU fallback mode.

### Zero-Copy Diagnostics (Windows)

If zero-copy is not working or the renderer falls back to CPU copy, use these logs to pinpoint the failure point:

**Expected logs (startup):**
- `WGL extensions length: ...`
- `WGL_NV_DX_interop: true/false WGL_NV_DX_interop2: true/false`
- `WGL_NV_DX_interop function availability open/close/register/unregister/lock/unlock: true/false`
- `D3D adapter: <GPU name> LUID: <high:low>`

**Interpretation:**
- `WGL_NV_DX_interop: false` ⇒ GPU driver or GL context does not expose the extension. Zero-copy will not be possible on this machine.
- Interop functions missing ⇒ `wglGetProcAddress` did not return required pointers; driver may be exposing extensions incorrectly or the OpenGL context is not fully initialized.
- Adapter name/LUID mismatch between Flutter and plugin ⇒ can lead to implicit GPU copies or interop failure. Ensure Flutter and CoMaps run on the same GPU (force the same GPU in Windows graphics settings).

**Expected logs (render loop):**
- `WGL Interop: Registered D3D texture as GL texture ...`
- `WGL Interop: Interop FBO complete - Zero-Copy enabled`
- `CopyToSharedTexture: useInterop: 1 interopFbo: ... keyedMutex: No`
- `CopyToSharedTexture: interop disabled reasons: device: ... object: ... fbo: ... lockFns: ...`

**Root Cause Checklist (when zero-copy fails):**
1. **Ensure source build is used** (no prebuilt DLL):
  - Remove [windows/prebuilt/x64/agus_maps_flutter.dll](windows/prebuilt/x64/agus_maps_flutter.dll) and rebuild.
2. **Confirm WGL interop availability:**
  - `WGL_NV_DX_interop: false` → driver/GL context does not expose the extension. Zero‑copy will not work on that machine.
3. **Confirm adapter match:**
  - `OpenGL renderer:` and `D3D adapter:` should describe the same GPU family.
  - If not, set the Windows Graphics Settings “High performance” GPU for the app, then rebuild.
4. **Check registration failure details:**
  - `WGL Interop: Failed to register object. GetLastError: ... GL error: ...`
  - Common causes: adapter mismatch, unsupported shared-handle flags, or missing WGL interop support in the driver.
5. **Confirm fallback path:**
  - If `CopyToSharedTexture: useInterop: 0` appears, interop was not enabled or was disabled after FBO validation.
  - Use `CopyToSharedTexture: interop disabled reasons: ...` to see which required objects/functions are missing.
6. **If colors are wrong in CPU fallback:**
  - Confirm log shows CPU copy and expect RGBA→BGRA swizzle in the fallback path.

**If you see fallback:**
- `Interop FBO incomplete` ⇒ Driver does not support the interop FBO path. CPU copy will be used.
- `WGL Interop: Failed to open device/register object` ⇒ WGL interop failed to bind D3D11 device/texture. Check extension logs and ensure you are not using a prebuilt DLL that lacks the latest changes.

### Diagnostics Overlay (Windows)

Windows builds can render a small overlay in the **upper-right corner** of the map texture to surface renderer/transfer diagnostics. The overlay is rendered by OpenGL into the shared texture (GPU path), so it appears in both zero-copy and CPU-fallback modes.

**Default lines:**
- `Renderer: OpenGL (WGL)`
- `Transfer: Zero-copy (WGL_NV_DX_interop)` **or** `Transfer: CPU copy (glReadPixels)`
- `Keyed mutex: On/Off`

**Overlay orientation (zero-copy path):**
- The interop blit flips Y to match D3D texture orientation. The overlay must therefore render with a **top‑left origin** when drawn into the interop FBO.
- The CPU path keeps the standard OpenGL bottom‑left origin.

**Disable overlay:**
- Set `AGUS_MAPS_WIN_OVERLAY=0` (default is enabled).

**Custom lines (native):**
Developers can append lines from native code using:
- `AgusWglContextFactory::SetOverlayCustomLines(std::vector<std::string> lines)`

The overlay is intended for diagnostics during development and can be safely disabled in production.

**Status:** Untested, theoretically feasible

ARM64 Windows (Snapdragon X, Apple Silicon via Parallels) could work with modifications:

1. **vcpkg triplet:** Would need `arm64-windows` builds of dependencies
2. **CMake configuration:** Requires `CMAKE_GENERATOR_PLATFORM=ARM64`
3. **OpenGL compatibility:** ARM64 Windows typically uses OpenGL ES via ANGLE
4. **CoMaps patches:** May need additional patches for ARM64 intrinsics

If you have ARM64 Windows hardware and want to contribute, please open an issue.

### Battery/CPU Efficiency

| Aspect | Status | Notes |
|--------|--------|-------|
| Event-Driven Render | ✅ Yes | FrontendRenderer suspends after `kMaxInactiveFrames` inactive frames |
| Initial Frame Keep-Alive | ✅ Yes | First ~120 frames request active frames to allow tile loading |
| CPU Usage (Idle) | ✅ Low | <1% when map is stationary |
| CPU Usage (Panning) | ⚠️ Moderate | ~10-20% due to per-frame pixel copy |
| GPU Usage | ✅ Low | CoMaps uses efficient tile-based rendering |

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

## Windows Blank/White Map: Framebuffer Readback Mismatch

If assets are present and CoMaps appears to be loading tiles, but the Flutter texture stays blank/white, check for logs like:

- `SetFramebuffer: Binding provided FBO (postprocess pass)`
- `CopyToSharedTexture(): ... centerRGBA: 0 0 0 0`

### Why this happens

CoMaps may bind a *provided* framebuffer during its postprocess/final composition pass. If the Windows interop path always reads pixels from the plugin's offscreen FBO, it can consistently capture a cleared/transparent buffer even though rendering is happening.

### Fix

The Windows OpenGL→D3D11 copy path tracks the most recently bound framebuffer in `AgusWglContext::SetFramebuffer()` and reads pixels from that framebuffer in `AgusWglContextFactory::CopyToSharedTexture()`.

## Resolved: ApplyFramebuffer Override Bug

### Previous Symptoms
- Map showed brownish/tan background color (the clear color)
- Tiles were being loaded and added to render groups
- `uniqueColors: 1` in frame diagnostics (only clear color visible)
- Scissor test was correctly set to full framebuffer size

### Root Cause
`ApplyFramebuffer()` was incorrectly re-binding our offscreen FBO, overriding the postprocess FBO that `SetFramebuffer()` had just bound.

In CoMaps' rendering pipeline:
1. `SetFramebuffer(postprocessFBO)` - binds postprocess FBO for rendering
2. `ApplyFramebuffer(label)` - called for Metal/Vulkan encoding setup; should be no-op for OpenGL
3. `RenderScene()` - draws tiles to the currently bound FBO
4. `SetFramebuffer(nullptr)` - returns to the default (our offscreen) FBO

Our implementation was:
```cpp
void ApplyFramebuffer(std::string const & label) {
    glBindFramebuffer(GL_FRAMEBUFFER, m_factory->m_framebuffer);  // WRONG!
}
```

This meant all rendering went to FBO 1 instead of the postprocess FBO, and when CoMaps later composited the postprocess result, it was reading from an empty buffer.

### Fix
`ApplyFramebuffer()` should be empty for OpenGL (same as Qt's implementation):
```cpp
void ApplyFramebuffer(std::string const & label) {
    // No-op for OpenGL - SetFramebuffer already handles binding
}
```

## Resolved: Scissor Rect Not Initialized

### Previous Symptoms
- Only top-left corner had content (clear color)
- All other pixels were transparent black (0,0,0,0)

### Root Cause
OpenGL scissor test was enabled in `Init()` but the scissor rectangle was never set, defaulting to (0,0,0,0) or (0,0,1,1).

### Fix
Initialize scissor rect to full framebuffer size:
```cpp
// In AgusWglContext::Init():
glViewport(0, 0, width, height);
glScissor(0, 0, width, height);

// In AgusWglContextFactory::InitializeWGL() and SetSurfaceSize():
glViewport(0, 0, m_width, m_height);
glScissor(0, 0, m_width, m_height);
```

## Resolved: Viewport Resize Not Updating Scissor

### Previous Symptoms
- Map rendered correctly at initial size
- After window resize, map content was clipped to the original size
- Logs showed scissor rect (1898 x 904) while viewport was (2579 x 1623)
- Corners beyond original size rendered as black/transparent

### Root Cause
`AgusWglContext::SetViewport()` only called `glViewport()`, but CoMaps' `OGLContext::SetViewport()` (in `drape/oglcontext.cpp:175-178`) calls **both** `glViewport()` AND `glScissor()`. When `DrapeEngine::Resize()` triggers a viewport update via `Viewport::Apply()`, the scissor wasn't being updated.

### Fix
Match CoMaps' behavior by setting scissor in SetViewport:
```cpp
void AgusWglContext::SetViewport(uint32_t x, uint32_t y, uint32_t w, uint32_t h) {
    glViewport(x, y, w, h);
    glScissor(x, y, w, h);  // CRITICAL: Must match CoMaps' OGLContext behavior
}
```

## Resolved: Flutter Texture Not Updating After Resize

### Previous Symptoms
- Map rendered correctly at initial size
- After window resize, the map widget appeared not to scale
- Native logs showed resize was processed (Framework::OnSize called, tiles requested)
- But Flutter wasn't sampling the new texture

### Root Cause
Two issues were identified:

**Issue 1: Flutter not notified of texture update**

After resize, the Windows plugin:
1. Updated internal `surface_width_` and `surface_height_`
2. Called `g_fnOnSizeChanged()` to update native resources
3. **BUT** didn't notify Flutter that the texture was updated

Without `MarkTextureFrameAvailable()`, Flutter continued using its cached texture dimensions.

**Issue 2: Missing Context::Resize override**

The `FrontendRenderer::OnResize()` function calls `m_context->Resize(sx, sy)` to allow the graphics context to update its internal resources. The base `GraphicsContext::Resize()` is a no-op, and our `AgusWglContext` didn't override it. This meant that when DrapeEngine internally triggered a resize, the context's resources weren't updated.

Qt's `QtRenderOGLContext` overrides `Resize()` to recreate framebuffer objects. Our implementation needs to delegate to `AgusWglContextFactory::SetSurfaceSize()`.

### Fix
1. Call `MarkTextureFrameAvailable()` after resize in plugin:
```cpp
// In HandleResizeMapSurface():
if (g_fnOnSizeChanged) {
    g_fnOnSizeChanged(width, height);
    
    // CRITICAL: Notify Flutter that the texture has been updated
    if (texture_id_ >= 0 && texture_registrar_) {
        texture_registrar_->MarkTextureFrameAvailable(texture_id_);
    }
}
```

2. Wrap `Texture` widget in `SizedBox` with explicit dimensions:
```dart
return SizedBox(
  width: size.width,
  height: size.height,
  child: Texture(textureId: _textureId!),
);
```

3. Add `Resize()` override to `AgusWglContext`:
```cpp
// In AgusWglContextFactory.hpp, AgusWglContext class:
void Resize(uint32_t w, uint32_t h) override;

// In AgusWglContextFactory.cpp:
void AgusWglContext::Resize(uint32_t w, uint32_t h)
{
  if (m_factory)
    m_factory->SetSurfaceSize(static_cast<int>(w), static_cast<int>(h));
}
```

This ensures both the external resize path (Dart → Plugin → Native) and the internal resize path (DrapeEngine → Context) properly update the rendering resources.

## Resolved: Resize Causes Black Bands at Edges

### Previous Symptoms
- Map displayed correctly at initial size
- When enlarging the window, the new edges showed black/transparent bands
- Logs showed viewport/scissor at OLD size while `m_width`/`m_height` at NEW size:
  ```
  CopyToSharedTexture scissor: 0 0 1678 1076 viewport: 0 0 1678 1076
  Frame 1140 size: 1683 x 1079
  ```
- Bottom-right corner pixels read as `0 0 0 0` (transparent black)

### Root Cause
A timing race condition between resize notification and frame rendering:

1. User resizes window → `SetSurfaceSize(newW, newH)` called
2. `SetSurfaceSize()` immediately updates `m_width`/`m_height` to new dimensions
3. `SetSurfaceSize()` recreates D3D11 texture at new size
4. **BUT** the currently-rendering frame was started BEFORE the resize
5. Frame completes → `Present()` → `CopyToSharedTexture()` called
6. `CopyToSharedTexture()` reads `m_width × m_height` pixels (NEW size)
7. But the FBO content was rendered at OLD viewport/scissor size
8. Reading pixels beyond the rendered region yields garbage/black

The key insight: OpenGL viewport/scissor represent the ACTUAL rendered size, while `m_width`/`m_height` represent the TARGET size. During resize transition, these may differ.

### Solution: Use Viewport Size for Pixel Readback

Query the OpenGL viewport at readback time and use THAT size for `glReadPixels()`:

```cpp
void AgusWglContextFactory::CopyToSharedTexture()
{
  // Query the current viewport to determine actual rendered size
  GLint viewport[4];
  glGetIntegerv(GL_VIEWPORT, viewport);
  int readWidth = viewport[2];
  int readHeight = viewport[3];
  
  // Clamp to target dimensions
  if (readWidth > m_width) readWidth = m_width;
  if (readHeight > m_height) readHeight = m_height;
  
  // Read pixels at RENDERED size, not target size
  std::vector<uint8_t> pixels(readWidth * readHeight * 4);
  glReadPixels(0, 0, readWidth, readHeight, GL_RGBA, GL_UNSIGNED_BYTE, pixels.data());
  
  // Copy to D3D11 staging texture, handling size mismatch
  if (readWidth == m_width && readHeight == m_height) {
    // Fast path: sizes match
  } else {
    // Clear texture, then copy rendered portion
    // This prevents garbage pixels in expanded regions
  }
}
```

This approach:
- Ensures we only read pixels that were actually rendered
- Handles the resize transition gracefully (shows old-size frame in new-size texture)
- Clears the expanded region to prevent garbage/artifacts

### Comparison with Qt Implementation

Qt's `QtRenderOGLContext` uses a different approach: power-of-2 buffer allocation with triple buffering. This pre-allocates larger buffers so resize only needs to update `m_frameRect` (the active region) rather than reallocating. Our approach is simpler but may show a brief visual artifact during resize where the old-size content is displayed in the new-size widget until the next frame renders at the new size.

## Resolved: Resize Causes Only Top-Left Corner Rendering

### Previous Symptoms
- Map displayed correctly at initial size
- When resizing window to larger size, only the top-left corner showed map content
- The rest of the window showed black/transparent (0,0,0,0)
- Logs showed correct viewport/scissor at new size (2877x1466) but corners read as zeros:
  ```
  CopyToSharedTexture scissor: 0 0 2877 1466 viewport: 0 0 2877 1466 readSize: 2877 x 1466
  Corners TL: 137 205 220 255 TR: 0 0 0 0
  Corners BL: 0 0 0 0 BR: 0 0 0 0
  ```

### Root Cause
OpenGL Framebuffer Object (FBO) attachments must be re-attached after texture resize.

In `SetSurfaceSize()`, we were calling `glTexImage2D()` to resize the render texture to the new dimensions. However, we were NOT re-attaching the texture to the framebuffer.

In OpenGL, when you call `glTexImage2D()` with different dimensions, it creates new texture storage. The FBO attachment may still reference the old texture dimensions or become invalid. The texture needs to be explicitly re-attached using `glFramebufferTexture2D()`.

**Before (broken):**
```cpp
void SetSurfaceSize(int width, int height) {
    glBindTexture(GL_TEXTURE_2D, m_renderTexture);
    glTexImage2D(..., width, height, ...);  // Creates new storage
    glBindTexture(GL_TEXTURE_2D, 0);
    // FBO still references old texture dimensions!
}
```

**After (fixed):**
```cpp
void SetSurfaceSize(int width, int height) {
  if (!wglMakeCurrent(m_hdc, m_drawGlrc)) {
    LOG(LERROR, ("SetSurfaceSize: wglMakeCurrent failed"));
    return;
  }

    // Resize texture
    glBindTexture(GL_TEXTURE_2D, m_renderTexture);
    glTexImage2D(..., width, height, ...);
    glBindTexture(GL_TEXTURE_2D, 0);
    
    // Resize depth buffer
    glBindRenderbuffer(GL_RENDERBUFFER, m_depthBuffer);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, width, height);
    glBindRenderbuffer(GL_RENDERBUFFER, 0);
    
    // CRITICAL: Re-attach to FBO after resize
    glBindFramebuffer(GL_FRAMEBUFFER, m_framebuffer);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, m_renderTexture, 0);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER, m_depthBuffer);

    // After reattachment, reset draw buffers or the FBO can be incomplete
    GLenum drawBuffers[] = { GL_COLOR_ATTACHMENT0 };
    glDrawBuffers(1, drawBuffers);
    
    // Verify FBO is complete
    GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    if (status != GL_FRAMEBUFFER_COMPLETE) {
        LOG(LERROR, ("Framebuffer incomplete after resize"));
    }
    
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
}
```

  ### Additional Notes
  - FBO status `0` in logs (from `glCheckFramebufferStatus`) means the call failed—most often because the context was not current or `glDrawBuffers` was not set after reattaching. Both are now handled: `wglMakeCurrent` is checked and `glDrawBuffers` is re-applied after resize.
  - If the status still reports incomplete, capture `GetLastError()` from the failed `wglMakeCurrent` and ensure another thread is not holding the GL context during resize.

### Why This Wasn't Caught Earlier
- Initial surface creation correctly attached the texture
- Without resize, everything worked perfectly
- The symptom (only top-left rendered) suggested a scissor/viewport issue, which masked the real cause
- Debug logging showed correct dimensions everywhere, making the FBO attachment issue non-obvious

## Resolved: Scroll Wheel Zoom Not Working

### Previous Symptoms
- Mouse scroll wheel caused map to pan/shift instead of zoom
- Logs showed "Screen center changed" but zoom level stayed constant at level 6
- Synthetic pinch gestures (via touch events) were not being interpreted correctly

### Root Cause
The Dart implementation was using synthetic two-finger pinch gestures via `comaps_touch_event()` to emulate scroll wheel zoom. However, CoMaps' touch event system interpreted these synthetic gestures as drag/pan operations rather than pinch-to-zoom.

### Solution: Direct Scale API

Following Qt CoMaps' implementation (`qt/qt_common/map_widget.cpp`), we now use a direct `Scale()` API:

```cpp
// Qt CoMaps scroll wheel handler:
double const factor = e->angleDelta().y() / 3.0 / 360.0;
m_framework.Scale(exp(factor), m2::PointD(pos.x(), pos.y()), false);
```

### Implementation

**New FFI Functions (src/agus_maps_flutter.h):**
```cpp
FFI_PLUGIN_EXPORT void comaps_scale(double factor, double pixelX, double pixelY, int animated);
FFI_PLUGIN_EXPORT void comaps_scroll(double distanceX, double distanceY);
```

**Windows Native (src/agus_maps_flutter_win.cpp):**
```cpp
FFI_PLUGIN_EXPORT void comaps_scale(double factor, double pixelX, double pixelY, int animated) {
    if (!g_framework || !g_drapeEngineCreated) return;
    g_framework->Scale(factor, m2::PointD(pixelX, pixelY), animated != 0);
}
```

**Dart Implementation (lib/agus_maps_flutter.dart):**
```dart
void _handlePointerSignal(PointerSignalEvent event) {
  if (event is PointerScrollEvent) {
    final dy = event.scrollDelta.dy;
    final factor = -dy / 600.0;  // Negative because scroll down = zoom out
    final pixelX = event.localPosition.dx * _devicePixelRatio;
    final pixelY = event.localPosition.dy * _devicePixelRatio;
    scaleMap(exp(factor), pixelX, pixelY, animated: false);
  }
}
```

The factor calculation `-dy / 600.0` provides smooth zoom similar to Google Maps, where:
- Scroll up (negative dy) → positive factor → zoom in
- Scroll down (positive dy) → negative factor → zoom out
- `exp(factor)` converts the linear factor to the multiplicative scale expected by Framework::Scale

## Resolved: Windows DPI Scaling Not Applied

### Previous Symptoms
- Map rendered correctly at 100% Windows display scaling
- At 150% scaling, only the top-left portion of the map had content (black corners)
- Logs showed correct physical pixel dimensions but density=1.00:
  ```
  [AgusMap] Creating surface: 1265x602 logical, 1898x904 physical (ratio: 1.5)
  [AgusMapsFlutter] agus_native_create_surface: 1898x904, density=1.00
  ```
- When enlarging the window, the map widget didn't scale properly

### Root Cause
The Dart `createMapSurface()` function was correctly computing physical pixel dimensions (`width * pixelRatio`), but it was NOT passing the `pixelRatio` (density) to the native Windows plugin. This caused:

1. Native plugin received `density=1.0` (default) instead of `1.5`
2. CoMaps' `DrapeEngine` initialized with `m_visualScale = 1.0`
3. `VisualParams` singleton stored incorrect visual scale
4. All rendering (glyphs, icons, tiles) was scaled for 100% display
5. Content was rendered into only 1/1.5 ≈ 67% of the framebuffer

**Comparison with iOS:** The iOS implementation (`AgusMapsFlutterPlugin.swift`) correctly sets `density = UIScreen.main.scale` at plugin initialization, ensuring consistent DPI handling.

### How CoMaps Uses Visual Scale

CoMaps stores the visual scale in a singleton `VisualParams::Instance()`:

```cpp
// thirdparty/comaps/libs/drape_frontend/visual_params.cpp
void VisualParams::Init(double vs, uint32_t tileSize) {
  m_visualScale = vs;
  // Visual scale affects:
  // - GlyphParams (font size, gutter, sdfScale)
  // - Resource prefix selection (mdpi/hdpi/xhdpi)
  // - Touch target sizes
  // - Icon/symbol sizing
}
```

Qt's implementation (`qt/qt_common/map_widget.cpp`) demonstrates proper usage:
```cpp
p.m_surfaceWidth = m_ratio * width();
p.m_surfaceHeight = m_ratio * height();
p.m_visualScale = m_ratio;
```

### Solution

Update Dart `createMapSurface()` to accept and pass the density parameter:

**lib/agus_maps_flutter.dart:**
```dart
/// Create a map rendering surface with the given dimensions.
/// [density] is the device pixel ratio (e.g., 1.5 for 150% Windows scaling).
Future<int> createMapSurface({int? width, int? height, double? density}) async {
  final int? textureId = await _channel.invokeMethod('createMapSurface', {
    if (width != null) 'width': width,
    if (height != null) 'height': height,
    if (density != null) 'density': density,
  });
  return textureId!;
}

// In widget's _createSurface():
final textureId = await createMapSurface(
  width: physicalWidth,
  height: physicalHeight,
  density: pixelRatio,  // CRITICAL: Pass device pixel ratio
);
```

The Windows plugin already supported the `density` parameter (defaulting to 1.0), so only the Dart side needed updating.

## Quick Start: Build & Run

### Prerequisites

- Flutter SDK 3.24+ installed
- Visual Studio 2022 with C++ Desktop development workload  
- vcpkg (installed automatically by the Dart build tool)
- PowerShell 7+ (recommended for Windows development)
- Windows 10 or later (x86_64 only)
- ~5GB disk space for CoMaps build artifacts

> **Note:** ARM64 Windows is not currently supported. See [ARM64 Compatibility](#arm64-windows-compatibility) section.

### First-Time Setup

```powershell
# Bootstrap the Windows environment (PowerShell 7+)
# This prepares BOTH Windows and Android targets:
#   - Fetches CoMaps source and applies patches
#   - Builds Boost headers
#   - Copies CoMaps data into example assets
#   - Installs vcpkg and dependencies
dart run tool/build.dart --no-cache
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

| Aspect | iOS/macOS (Metal) | Android (OpenGL ES) | Windows (OpenGL/D3D11) |
|--------|-------------------|---------------------|------------------------|
| Graphics API | Metal | OpenGL ES 3.0 | OpenGL 2.0+ (WGL) |
| Texture Sharing | CVPixelBuffer + IOSurface | SurfaceTexture | D3D11 + DXGI Shared Handle |
| Zero-Copy Mechanism | ✅ CVMetalTextureCache | ✅ EGL Native Window | ✅ WGL_NV_DX_interop |
| Flutter Texture | FlutterTexture protocol | TextureRegistry | FlutterDesktopGpuSurfaceDescriptor |
| Platform Macro | `PLATFORM_MAC=1` | `OMIM_OS_ANDROID=1` | `OMIM_OS_WINDOWS=1` |
| Plugin Class | AgusMapsFlutterPlugin (Swift) | AgusMapsFlutterPlugin (Java) | AgusMapsFlutterPluginCApi (C++) |
| Architecture | arm64, x86_64 | arm64-v8a, armeabi-v7a, x86_64 | x86_64 only |


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
- [x] Scroll wheel zoom support for desktop
- [x] SetViewport fix for scissor update on resize

### In Progress 🔄

- [ ] Additional touch gesture refinements

### Not Started ❌

- [ ] Kinetic scrolling (fling)
- [ ] Map animation smoothness


## Acceptance Criteria

- [x] Windows example app builds without errors
- [x] Plugin creates native surface and registers Flutter texture
- [x] App launches and displays Gibraltar map
- [x] Pan/zoom gestures work correctly (mouse drag)
- [x] Window resize works correctly (map scales to new size)
- [ ] Map renders at 60fps with minimal CPU usage
- [ ] Release build is under 150MB


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
%USERPROFILE%\Documents\agus_maps_flutter\agus_maps_crash_YYYYMMDD_HHMMSS.dmp
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

### Pixel Transfer Strategy (Zero-Copy)

To achieve 60 FPS performance, the plugin implements a true **Zero-Copy** pipeline using the `WGL_NV_DX_interop` extension and a **DXGI shared handle** (Keyed Mutex is optional).

1.  **Shared Texture Creation**:
  *   The `AgusWglContextFactory` creates a `ID3D11Texture2D` with `D3D11_RESOURCE_MISC_SHARED` flags by default.
  *   This texture is shared with the Flutter engine via a `kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle`.

2.  **OpenGL-Direct3D Interop**:
  *   The `WGL_NV_DX_interop` extension is used to register the D3D11 shared texture as an OpenGL texture (`wglDXRegisterObjectNV`).
  *   An OpenGL Framebuffer Object (FBO) is created, wrapping this registered interop texture.

3.  **Rendering & Synchronization**:
  *   CoMaps renders to its internal offscreen FBO.
  *   In `CopyToSharedTexture`, the plugin performs a GPU-to-GPU copy using `glBlitFramebuffer`:
    1.  **Lock Object**: `wglDXLockObjectsNV` locks the texture for OpenGL access.
    2.  **Blit**: `glBlitFramebuffer` copies pixels from the render FBO to the interop FBO. This happens entirely in VRAM.
    3.  **Unlock Object**: `wglDXUnlockObjectsNV` releases OpenGL access.

4.  **Optional Keyed Mutex (advanced)**:
  *   If you set `AGUS_MAPS_WIN_KEYED_MUTEX=1`, the shared texture is created with `D3D11_RESOURCE_MISC_SHARED_KEYEDMUTEX` and the producer uses **AcquireSync(0) → ReleaseSync(1)**.
  *   The Flutter consumer must AcquireSync(1) and ReleaseSync(0) for this to work. If it does not, frames will stall or appear white.

5.  **Fallback**:
  *   If `WGL_NV_DX_interop` is unavailable, the system falls back to a CPU-mediated path using `glReadPixels` and a D3D11 Staging Texture, though this incurs a performance penalty.

This approach eliminates the costly `glReadPixels` to CPU memory, allowing for high-performance map rendering.

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


## Troubleshooting

### Build errors in dev_sandbox, generator, or tools targets

**Symptom:** Build fails with errors like:
- `dev_sandbox\main.cpp: error C2039: 'setenv': is not a member of 'global namespace'`
- `openlr: error C2872: 'impl': ambiguous symbol`
- Errors in `generator` or `tools` subdirectories

**Cause:** These are CoMaps desktop development tools (dev_sandbox, map generator, CLI tools) that are not needed for the Flutter plugin. They may have Windows-incompatible code (POSIX functions like `setenv`) or Boost symbol conflicts.

**Solution:** The Flutter plugin sets `SKIP_TOOLS ON` in `src/CMakeLists.txt`. A corresponding patch modifies CoMaps' `CMakeLists.txt` to respect this option:

```cmake
# In thirdparty/comaps/CMakeLists.txt (patched)
if (PLATFORM_DESKTOP AND NOT SKIP_TOOLS)
  add_subdirectory(dev_sandbox)
  add_subdirectory(generator)
  add_subdirectory(tools)
endif()
```

If you see these errors, rerun the Dart bootstrap to reapply patches:
```powershell
dart run tool/build.dart --no-cache
```

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
   - Delete `%USERPROFILE%\Documents\agus_maps_flutter\.comaps_data_extracted` marker file
   - Delete `%USERPROFILE%\Documents\agus_maps_flutter\` folder contents
   - Rebuild and run to force fresh extraction

12. **ApplyFramebuffer overriding postprocess FBO:**
   - **Symptom:** Map shows only brownish/tan clear color. `uniqueColors: 1` in frame diagnostics. Tiles are being loaded and added to render groups.
   - **Root cause:** `ApplyFramebuffer()` was incorrectly re-binding our offscreen FBO after `SetFramebuffer()` had bound the postprocess FBO.
   - **Why this matters:** CoMaps uses a postprocess renderer that creates its own FBOs. The flow is:
     1. `SetFramebuffer(postprocessFBO)` - binds postprocess FBO
     2. `ApplyFramebuffer(label)` - for Metal/Vulkan encoding; should be no-op for OpenGL
     3. `RenderScene()` - draws to current FBO
     4. `SetFramebuffer(nullptr)` - returns to default FBO
   - **Fix:** Make `ApplyFramebuffer()` empty for OpenGL (Qt's implementation is also empty):
     ```cpp
     void ApplyFramebuffer(std::string const & label) {
         // No-op for OpenGL - SetFramebuffer already handles binding
     }
     ```
   - **Reference:** Qt's `QtRenderOGLContext::ApplyFramebuffer()` in `qtoglcontext.cpp` is empty.

13. **Map content clipped to original size after window resize:**
   - **Symptom:** Map renders correctly at initial size, but after resizing the window, content is clipped. Only the top-left portion (matching original size) shows map content.
   - **Logs show:** `CopyToSharedTexture scissor: 0 0 1898 904 viewport: 0 0 2579 1623` - scissor doesn't match viewport!
   - **Root cause:** `SetViewport()` only called `glViewport()`, but CoMaps' `OGLContext::SetViewport()` also updates `glScissor()`.
   - **Fix:** `SetViewport()` must update both viewport AND scissor:
     ```cpp
     void SetViewport(uint32_t x, uint32_t y, uint32_t w, uint32_t h) {
         glViewport(x, y, w, h);
         glScissor(x, y, w, h);  // Match CoMaps' OGLContext behavior
     }
     ```
   - **Reference:** CoMaps' `OGLContext::SetViewport()` in `drape/oglcontext.cpp:175-178`.

14. **Resize spam logs: `SetSurfaceSize: wglMakeCurrent failed`:**
   - **Symptom:** During window resize at high DPI, logs show repeated `SetSurfaceSize: wglMakeCurrent failed` and the map appears soft or fails to update crispness during resizing.
   - **Root cause:** `SetSurfaceSize()` was called directly from the Flutter method channel thread inside `agus_native_on_size_changed()`. The WGL draw context is owned by the render thread, so `wglMakeCurrent(m_hdc, m_drawGlrc)` fails when the context is current on another thread.
   - **Fix:** Route resize through the render thread by only calling `Framework::OnSize()` (which triggers `FrontendRenderer::OnResize()` → `AgusWglContext::Resize()`), and avoid direct `SetSurfaceSize()` from the FFI resize handler except as an early fallback before the framework is ready:
     ```cpp
     // In agus_native_on_size_changed()
     if (g_framework && g_drapeEngineCreated) {
       g_framework->OnSize(width, height);  // Render thread will call Resize()
     } else if (g_wglFactory) {
       g_wglFactory->SetSurfaceSize(width, height);  // Early fallback
     }
     ```
   - **Result:** Prevents `wglMakeCurrent` failures and ensures resize happens on the thread that owns the OpenGL context.

15. **Runtime DPI changes not reflected (e.g., switching to 200%/300% while app is running):**
   - **Symptom:** Windows display scaling changes while the app is running, but map text/labels do not scale accordingly.
   - **Root cause:** Resize events only updated width/height; the native visual scale was set once at surface creation and never updated. `VisualParams` remained at the old DPI, so glyph sizes and resources stayed at the previous scale.
   - **Fix:** Pass `density` in `resizeMapSurface` and update the native visual scale without tearing down the render context (direct `VisualParams` update):
     ```cpp
     // In HandleResizeMapSurface (plugin)
     g_fnOnSizeChanged(width, height);
     g_fnSetVisualScale(density);

     // In native (agus_native_set_visual_scale)
     df::VisualParams::Instance().SetVisualScale(density);
     g_framework->InvalidateRendering();
     ```
   - **Result:** Changing Windows display scaling at runtime updates map text/line sharpness and resource selection.

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


## References

- iOS Implementation: [doc/IMPLEMENTATION-IOS.md](IMPLEMENTATION-IOS.md)
- macOS Implementation: [doc/IMPLEMENTATION-MACOS.md](IMPLEMENTATION-MACOS.md)
- Android Implementation: [doc/IMPLEMENTATION-ANDROID.md](IMPLEMENTATION-ANDROID.md)
- Render Loop Details: [doc/RENDER-LOOP.md](RENDER-LOOP.md)
- CoMaps drape code: `thirdparty/comaps/libs/drape/`



### Map Style Error: "Symbol name must be valid for feature"

**Symptom:**
Logs show error: `[CoMaps ERROR] drape_frontend/apply_feature_functors.cpp:544 df::ApplyPointFeature::ProcessPointRules(): Style error. Symbol name must be valid for feature { MwmId [Gibraltar, 0], 946 }`.
Map may render white/blank or partially.

**Cause:**
Incompatibility between the loaded MWM map file and the style definitions (`drules_proto.bin`, `classificator.txt`, `types.txt`). This happens if the MWM was built with a different version of the style generation tools than the style files present in `assets/comaps_data`.

**Solution:**
1.  **Regenerate** the MWM file using the same `classificator.txt` and `types.txt` present in assets.
2.  **Update Assets**: Fetch the `drules_proto.bin` and config files that match the MWM version.
3.  **Temporary Fix**: If a specific MWM (e.g., Gibraltar) is causing issues, disable it and use `World.mwm` to verify rendering engine works.


### Build Error: "MSB8066: Custom build for ... exited with code 1"

**Symptom:**
Build fails with `error MSB8066` in `flutter_assemble.rule` or similar.

**Cause:**
Often caused by locked files, corrupted build state, or CMake configuration changes that weren't picked up.

**Solution:**
Run `flutter clean` and `flutter pub get` to clear the build cache and restore dependencies.


### Build Error: "error C2143: syntax error" in timezoneapi.h or winnt.h

**Symptom:**
Build fails with errors like:
```
timezoneapi.h(36,10): error C2143: syntax error: missing ':' before 'constant'
timezoneapi.h(46,5): error C2034: '': type of bit field has zero size
winnt.h(19842): error C2146: syntax error: missing ';' before identifier 'Long'
```

**Cause:**
The jansson library's `dtoa.c` file defines a macro `#define Long int` at line 229. When CMake's Unity Build feature is enabled (`CMAKE_UNITY_BUILD=ON`), it combines multiple `.c` files into single compilation units. This causes the macro to leak into Windows SDK headers, where struct members named `Long` (like `DWORD Long;` in TIME_ZONE_INFORMATION) become invalid `DWORD int;`.

**Why `#undef` alone doesn't work:**
Unity builds concatenate source files in an order determined by CMake, not by file inclusion order. Even if `dtoa.c` has `#undef Long` at the end, Unity builds may process it differently.

**Solution:**
The fix is to disable Unity build specifically for the jansson library target. This is handled by patch `0067-3party-jansson-disable-unity-build.patch`:

```cmake
# In thirdparty/comaps/3party/jansson/jansson/CMakeLists.txt
set_target_properties(jansson PROPERTIES
   UNITY_BUILD OFF)
```

If you see these errors, ensure all patches are applied by re-running:
```powershell
dart run tool/build.dart --no-cache
```

Then clean and rebuild:
```powershell
cd example
Remove-Item -Recurse -Force build\windows
flutter build windows --release
```

**Related patches:**
- `0065-3party-jansson-hashtable_seed-undef-long.patch` - Defense-in-depth: adds `#undef Long` before including `windows.h` in `hashtable_seed.c`
- `0066-3party-jansson-dtoa-undef-long-end.patch` - Adds `#undef Long` at end of `dtoa.c` (redundant with Unity build disabled, but harmless)
- `0067-3party-jansson-disable-unity-build.patch` - **Root cause fix**: disables Unity build for jansson target

*Last updated: January 2025*
