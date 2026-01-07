# Issue: macOS Window Resize Causes White Screen

## Status: ✅ RESOLVED

**Commits:**
- `9f79c20` - fix(macos): window resize breaks map rendering (initial fix)
- `TBD` - fix(macos): resize instability with rapid events (debouncing + thread safety)

---

## Problem Description

When resizing the macOS application window, the map widget would break and turn completely white. The map displayed correctly initially, but any window resize operation would cause the rendering to fail.

### Symptoms

- Map displays correctly on initial launch
- Resizing the window (dragging edges/corners) causes map to turn white
- Console logs show resize events being processed
- Metal context appears to be updating, but rendering fails

### Root Cause Analysis

The issue was a **captured-by-value lambda** problem in the Metal context factory combined with **missing pixel buffer update** during resize.

#### Problem 1: Swift Creates New Pixel Buffer, Native Not Updated

When the window is resized, the Swift plugin creates a new `CVPixelBuffer` with the new dimensions:

```swift
// AgusMapsFlutterPlugin.swift - handleResizeMapSurface
try createPixelBuffer(width: width, height: height)  // NEW buffer created
nativeOnSizeChanged(width: Int32(width), height: Int32(height))  // BUG: doesn't pass buffer!
```

The `agus_native_on_size_changed()` function only called `Framework::OnSize()` but **never updated the Metal texture** with the new pixel buffer:

```cpp
// agus_maps_flutter_macos.mm - BEFORE FIX
void agus_native_on_size_changed(int32_t width, int32_t height) {
    g_framework->OnSize(width, height);  // Framework knows new size
    // BUG: Metal context still rendering to OLD texture!
}
```

#### Problem 2: Lambda Captured Texture by Value

Even if we called `SetPixelBuffer()` on the Metal context factory, the drawable getter lambda captured the initial texture by value:

```cpp
// AgusMetalContextFactory.mm - BEFORE FIX
DrawMetalContext(id<MTLDevice> device, id<MTLTexture> renderTexture, ...)
    : dp::metal::MetalBaseContext(device, screenSize, [renderTexture]() -> id<CAMetalDrawable> {
        // renderTexture is CAPTURED BY VALUE here!
        // Even if m_renderTexture is updated, this lambda still uses the old one
        if (!g_currentDrawable || g_currentDrawable.texture != renderTexture) {
            g_currentDrawable = [[AgusMetalDrawable alloc] initWithTexture:renderTexture];
        }
        return g_currentDrawable;
    })
```

The lambda was stored in `MetalBaseContext::m_drawableRequest` and called every frame to get the drawable. Since `renderTexture` was captured by value, updating `m_renderTexture` member had no effect on what the lambda returned.

---

## Solution

### Fix 1: Add macOS-Specific Resize Function

Created a new function `agus_native_resize_surface()` that accepts the new pixel buffer:

```cpp
// agus_maps_flutter_macos.mm
extern "C" void agus_native_resize_surface(
    CVPixelBufferRef pixelBuffer,
    int32_t width,
    int32_t height
) {
    // Update the Metal context factory with the new pixel buffer
    if (g_metalContextFactory) {
        m2::PointU screenSize(width, height);
        g_metalContextFactory->SetPixelBuffer(pixelBuffer, screenSize);
    }
    
    // Notify framework of size change
    if (g_framework && g_drapeEngineCreated) {
        g_framework->OnSize(width, height);
        g_framework->InvalidateRendering();  // Force redraw
    }
}
```

### Fix 2: Use Global Texture Pointer for Lambda

Changed the drawable getter lambda to reference a global texture pointer that can be updated:

```cpp
// AgusMetalContextFactory.mm - AFTER FIX
static id<MTLTexture> g_currentRenderTexture = nil;

DrawMetalContext(id<MTLDevice> device, id<MTLTexture> renderTexture, ...)
    : dp::metal::MetalBaseContext(device, screenSize, []() -> id<CAMetalDrawable> {
        // Now references GLOBAL pointer that can be updated
        if (!g_currentDrawable || g_currentDrawable.texture != g_currentRenderTexture) {
            g_currentDrawable = [[AgusMetalDrawable alloc] initWithTexture:g_currentRenderTexture];
        }
        return g_currentDrawable;
    })
{
    g_currentRenderTexture = renderTexture;  // Initialize global
    g_currentDrawable = [[AgusMetalDrawable alloc] initWithTexture:renderTexture];
}

void SetRenderTexture(id<MTLTexture> texture, m2::PointU const & screenSize) {
    m_renderTexture = texture;
    g_currentRenderTexture = texture;  // Update global so lambda sees new texture
    g_currentDrawable = [[AgusMetalDrawable alloc] initWithTexture:texture];
    Resize(screenSize.x, screenSize.y);
}
```

### Fix 3: Update Swift Plugin to Use New Function

```swift
// AgusMapsFlutterPlugin.swift - AFTER FIX
private func handleResizeMapSurface(call: FlutterMethodCall, result: @escaping FlutterResult) {
    // ...
    try createPixelBuffer(width: width, height: height)
    
    guard let buffer = pixelBuffer else { /* error */ }
    nativeResizeSurface(pixelBuffer: buffer, width: Int32(width), height: Int32(height))
    
    textureRegistry?.textureFrameAvailable(textureId)
    result(true)
}

private func nativeResizeSurface(pixelBuffer: CVPixelBuffer, width: Int32, height: Int32) {
    agus_native_resize_surface(pixelBuffer, width, height)
}
```

---

## Files Changed

| File | Change |
|------|--------|
| `macos/Classes/AgusBridge.h` | Added `agus_native_resize_surface()` declaration |
| `macos/Classes/agus_maps_flutter_macos.mm` | Added `g_metalContextFactory` pointer, implemented `agus_native_resize_surface()` |
| `macos/Classes/AgusMetalContextFactory.mm` | Added `g_currentRenderTexture` global, updated constructor and `SetRenderTexture()` |
| `macos/Classes/AgusMapsFlutterPlugin.swift` | Added `nativeResizeSurface()` wrapper, updated `handleResizeMapSurface()` |

---

## Follow-up Fix: Resize Instability with Rapid Events

### Problem

After the initial fix, a secondary issue was discovered: when rapidly resizing the window (by dragging corners/edges), the map would sometimes render with **incomplete/brownish blocks**, especially in expanded viewport areas. This happened intermittently, not consistently like the original white screen issue.

### Root Cause

Analysis of the logs showed resize events arriving approximately every **8ms** during active window dragging:

```
03:57:23.516 CVPixelBuffer created: 2520x1304
03:57:23.533 CVPixelBuffer created: 2510x1298  (17ms later)
03:57:23.541 CVPixelBuffer created: 2502x1292  (8ms later)
03:57:23.558 CVPixelBuffer created: 2498x1288  (17ms later)
...
```

Two issues caused the instability:

1. **Race Condition**: New CVPixelBuffer/Metal texture was being created while the render thread was actively using the old texture. The texture swap had no synchronization.

2. **Thrashing**: Creating 30+ textures per second during rapid resize caused memory pressure and incomplete tile rendering.

### Solution

#### Fix 1: Resize Debouncing (Swift)

Added 50ms debounce interval in `AgusMapsFlutterPlugin.swift`:

```swift
// Properties for debouncing
private var pendingResizeWorkItem: DispatchWorkItem?
private var lastResizeWidth: Int = 0
private var lastResizeHeight: Int = 0
private static let resizeDebounceInterval: TimeInterval = 0.05  // 50ms

private func handleResizeMapSurface(call: FlutterMethodCall, result: @escaping FlutterResult) {
    // Store requested dimensions
    lastResizeWidth = width
    lastResizeHeight = height
    
    // Cancel any pending resize
    pendingResizeWorkItem?.cancel()
    
    // Debounce - wait until resize events stop
    let workItem = DispatchWorkItem { [weak self] in
        self?.performResize(width: self!.lastResizeWidth, height: self!.lastResizeHeight)
    }
    pendingResizeWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.resizeDebounceInterval, execute: workItem)
    
    result(true)  // Return immediately
}
```

#### Fix 2: Thread Synchronization (C++)

Added mutex protection in `AgusMetalContextFactory.mm`:

```cpp
#include <mutex>

static std::mutex g_textureMutex;

// In drawable getter lambda:
std::lock_guard<std::mutex> lock(g_textureMutex);
if (!g_currentDrawable || g_currentDrawable.texture != g_currentRenderTexture) {
    g_currentDrawable = [[AgusMetalDrawable alloc] initWithTexture:g_currentRenderTexture];
}

// In SetRenderTexture:
void SetRenderTexture(id<MTLTexture> texture, m2::PointU const & screenSize) {
    {
        std::lock_guard<std::mutex> lock(g_textureMutex);
        m_renderTexture = texture;
        g_currentRenderTexture = texture;
        g_currentDrawable = [[AgusMetalDrawable alloc] initWithTexture:texture];
    }
    Resize(screenSize.x, screenSize.y);
}
```

#### Fix 3: Improved Resize Handler (C++)

Enhanced `agus_native_resize_surface()` in `agus_maps_flutter_macos.mm`:

```cpp
extern "C" void agus_native_resize_surface(CVPixelBufferRef pixelBuffer, int32_t width, int32_t height) {
    // Skip if Framework/DrapeEngine not ready
    if (!g_framework || !g_drapeEngineCreated) {
        return;
    }
    
    // Update Metal context (thread-safe via mutex)
    if (g_metalContextFactory) {
        m2::PointU screenSize(width, height);
        g_metalContextFactory->SetPixelBuffer(pixelBuffer, screenSize);
    }
    
    // Notify framework and force redraw
    g_framework->OnSize(width, height);
    g_framework->InvalidateRendering();
    g_framework->MakeFrameActive();  // Force immediate re-render
}
```

### Files Changed (Follow-up Fix)

| File | Change |
|------|--------|
| `macos/Classes/AgusMapsFlutterPlugin.swift` | Added debounce properties, refactored resize handling |
| `macos/Classes/AgusMetalContextFactory.mm` | Added `#include <mutex>`, `g_textureMutex`, mutex protection |
| `macos/Classes/agus_maps_flutter_macos.mm` | Added early return check, `MakeFrameActive()` call |

---

## Why macOS-Only?

This fix is specific to macOS because:

1. **iOS doesn't have resizable windows** - iOS apps run fullscreen or in fixed split-view sizes. The `resizeMapSurface` method is rarely/never called on iOS.

2. **Android uses different architecture** - Android's `SurfaceProducer` handles resize differently through the EGL/ANativeWindow pipeline.

3. **Windows uses CPU-mediated transfer** - Windows doesn't use CVPixelBuffer/IOSurface, so this specific issue doesn't apply.

The existing `agus_native_on_size_changed()` function is preserved for compatibility with iOS and for cases where only the Framework needs to know about size changes without replacing the underlying texture.

---

## Testing

1. Launch the macOS example app
2. Verify map displays correctly
3. Resize window by dragging corners/edges
4. Verify map continues to render correctly at new size
5. Verify pan/zoom gestures still work after resize

---

## Related Issues

- [ISSUE-egl-context-recreation.md](ISSUE-egl-context-recreation.md) - Similar issue on Android with EGL context
- [RENDER-LOOP.md](RENDER-LOOP.md) - Render loop architecture documentation

---

*Created: January 2026*
