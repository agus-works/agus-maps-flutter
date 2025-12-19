# ISSUE: EGL Context Recreation Not Fully Tested on Resume

## Severity: Medium (Potential Bug)

## Description

When the app is backgrounded and resumed, Android may destroy the EGL context. The current implementation has `onSurfaceDestroyed` and `onSurfaceAvailable` callbacks, but the context recreation path hasn't been fully tested.

## Location

- [android/src/.../AgusMapsFlutterPlugin.java](../android/src/main/java/app/agus/maps/agus_maps_flutter/AgusMapsFlutterPlugin.java) - Surface callbacks
- [src/agus_maps_flutter.cpp](../src/agus_maps_flutter.cpp) - `nativeOnSurfaceChanged`, `nativeOnSurfaceDestroyed`
- [src/agus_ogl.cpp](../src/agus_ogl.cpp) - `SetSurface`, `ResetSurface`

## Current Behavior

```java
surfaceProducer.setCallback(new TextureRegistry.SurfaceProducer.Callback() {
    @Override
    public void onSurfaceAvailable() {
        Surface surface = surfaceProducer.getSurface();
        nativeOnSurfaceChanged(surfaceProducer.id(), surface, surfaceWidth, surfaceHeight, density);
    }
    
    @Override
    public void onSurfaceDestroyed() {
        nativeOnSurfaceDestroyed();
    }
});
```

```cpp
// nativeOnSurfaceDestroyed
if (g_framework) {
    g_framework->SetRenderingDisabled(true /* destroySurface */);
}
```

## Potential Issues

1. **Context not fully recreated**: `g_factory` may have stale EGL context pointers
2. **Window surface leak**: Old ANativeWindow may not be properly released
3. **Drape state loss**: Render buckets and overlays might become invalid

## Test Scenarios Needed

1. **Quick background/foreground**: Press home, immediately return
2. **Long background**: Leave app in background for 30+ minutes
3. **Memory pressure**: Open heavy apps while backgrounded
4. **Screen rotation**: Rotate while map is visible
5. **Split screen**: Enter/exit multi-window mode

## Impact

- **Crash**: Possible segfault if EGL context invalid
- **Black screen**: Map might not render after resume
- **Memory leak**: ANativeWindow reference leak

## Recommended Fix

Add comprehensive context validation:

```cpp
extern "C" JNIEXPORT void JNICALL
Java_..._nativeOnSurfaceChanged(JNIEnv* env, ...) {
    // Validate existing factory state
    if (g_factory) {
        // Properly tear down old context
        auto* rawFactory = static_cast<dp::ThreadSafeFactory*>(g_factory.get());
        // Reset surfaces, recreate contexts
    }
    
    // Create fresh context with new surface
    ANativeWindow* window = ANativeWindow_fromSurface(env, surface);
    // ... full recreation path
}
```

## Decision

**Should Fix** - This is a reliability issue that could cause crashes in production. Needs comprehensive testing on multiple devices.

## Testing Command

```bash
# Stress test background/foreground cycles
adb shell am start -n app.agus.maps.agus_maps_flutter_example/.MainActivity
sleep 2
adb shell input keyevent KEYCODE_HOME
sleep 5
adb shell am start -n app.agus.maps.agus_maps_flutter_example/.MainActivity
# Repeat and check logcat for errors
```
