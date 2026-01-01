# Render Loop Comparison: CoMaps Native vs Flutter Plugin

This document provides a detailed comparison between CoMaps' native app render loop (using DrapeEngine) and our Flutter plugin implementations on iOS, Android, macOS, and Windows. This serves as a reference for achieving implementation parity and for future ports to Linux.

---

## Table of Contents

1. [Thread Architecture](#1-thread-architecture)
2. [Render Loop Flow](#2-render-loop-flow)
3. [Frame Timing & VSync](#3-frame-timing--vsync)
4. [Active Frame Detection](#4-active-frame-detection)
5. [Surface Management](#5-surface-management)
6. [Context Factory Implementation](#6-context-factory-implementation)
7. [Present/Swap Handling](#7-presentswap-handling)
8. [Frame Notification to Flutter](#8-frame-notification-to-flutter)
9. [Platform-Specific Issues](#9-platform-specific-issues)
10. [Parity Checklist](#10-parity-checklist)
11. [Future Platform Notes](#11-future-platform-notes-linux)

---

## 1. Thread Architecture

### CoMaps Native App (Reference Implementation)

The Drape rendering engine uses a **two-thread model**:

```
┌─────────────────────────────────────────────────────────────────────┐
│                          Main Thread                                 │
│  • UI event dispatch (UIKit/Android Activity)                       │
│  • Touch event capture → forwards to UserEventStream                │
│  • Framework API calls                                               │
└───────────────────────────────┬─────────────────────────────────────┘
                                │ Messages via ThreadsCommutator
                                ▼
┌───────────────────────────────────────────────────────────────────────┐
│                      FrontendRenderer Thread                          │
│  • Main render loop (RenderFrame)                                     │
│  • User event processing (pan/zoom/rotate)                           │
│  • Scene rendering (2D/3D layers, overlays, routes)                  │
│  • Present() / eglSwapBuffers / presentDrawable                      │
│  • Frame timing and suspend logic                                     │
└───────────────────────────────┬───────────────────────────────────────┘
                                │ Shared TextureManager
                                ▼
┌───────────────────────────────────────────────────────────────────────┐
│                      BackendRenderer Thread                           │
│  • Tile loading and parsing                                          │
│  • Texture uploads to GPU                                            │
│  • Resource preparation (render buckets)                             │
│  • Uses separate "upload" graphics context                           │
└───────────────────────────────────────────────────────────────────────┘
```

**Key characteristics:**
- Both threads communicate via `ThreadsCommutator` message queue
- Each thread has its own graphics context (EGL context / Metal command queue)
- Contexts share textures but have separate command buffers
- `WaitForInitialization()` synchronizes startup of both contexts

### Flutter Plugin: iOS Implementation

```
┌─────────────────────────────────────────────────────────────────────┐
│                     Main Thread (iOS)                                │
│  • Flutter engine runs here                                          │
│  • AgusMapsFlutterPlugin.swift handles MethodChannel                │
│  • CVPixelBuffer creation and texture registration                  │
│  • textureFrameAvailable() called here (via dispatch_async)         │
└───────────────────────────────┬─────────────────────────────────────┘
                                │ CVPixelBuffer shared (IOSurface)
                                ▼
┌───────────────────────────────────────────────────────────────────────┐
│                      FrontendRenderer Thread                          │
│  • Same as native - managed by DrapeEngine                           │
│  • Renders to MTLTexture backed by CVPixelBuffer                     │
│  • df::NotifyActiveFrame() → dispatch_async → main thread            │
└───────────────────────────────┬───────────────────────────────────────┘
                                │
                                ▼
┌───────────────────────────────────────────────────────────────────────┐
│                      BackendRenderer Thread                           │
│  • Same as native - managed by DrapeEngine                           │
│  • Uses UploadMetalContext (headless)                                │
└───────────────────────────────────────────────────────────────────────┘
```

**Key differences from native:**
- No CAMetalLayer - renders to CVPixelBuffer-backed MTLTexture
- Frame notification via `dispatch_async` to main thread
- Flutter's Impeller/Skia samples the CVPixelBuffer directly (zero-copy via IOSurface)

### Flutter Plugin: Android Implementation

```
┌─────────────────────────────────────────────────────────────────────┐
│                     Main Thread (Android)                            │
│  • Flutter engine runs here                                          │
│  • AgusMapsFlutterPlugin.java handles MethodChannel                 │
│  • SurfaceProducer creation and texture registration                │
│  • onFrameReady() called here (via JNI + Handler.post)              │
└───────────────────────────────┬─────────────────────────────────────┘
                                │ Surface/ANativeWindow shared
                                ▼
┌───────────────────────────────────────────────────────────────────────┐
│                      FrontendRenderer Thread                          │
│  • Same as native - managed by DrapeEngine                           │
│  • Renders via EGL to Surface (window surface)                       │
│  • df::NotifyActiveFrame() → JNI call → main thread                  │
└───────────────────────────────┬───────────────────────────────────────┘
                                │
                                ▼
┌───────────────────────────────────────────────────────────────────────┐
│                      BackendRenderer Thread                           │
│  • Same as native - managed by DrapeEngine                           │
│  • Uses AgusOGLContext with pbuffer surface                          │
└───────────────────────────────────────────────────────────────────────┘
```

**Key differences from native:**
- Uses Flutter's `SurfaceProducer` instead of standard `SurfaceView`
- Frame notification via JNI callback to Java + Handler.post to main thread
- EGL context bound to Flutter's surface texture

### Flutter Plugin: Windows Implementation (x86_64)

```
┌─────────────────────────────────────────────────────────────────────┐
│                     Main Thread (Windows)                            │
│  • Flutter engine runs here                                          │
│  • AgusMapsFlutterPlugin.cpp handles MethodChannel                  │
│  • D3D11 texture registration via FlutterDesktopGpuSurfaceDescriptor│
│  • OnFrameReady() called here (via callback chain)                  │
└───────────────────────────────┬─────────────────────────────────────┘
                                │ D3D11 DXGI Shared Handle
                                ▼
┌───────────────────────────────────────────────────────────────────────┐
│                      FrontendRenderer Thread                          │
│  • Same as native - managed by DrapeEngine                           │
│  • Renders to OpenGL FBO via WGL context                             │
│  • Present() → CopyToSharedTexture() → notifyFlutterFrameReady()    │
└───────────────────────────────┬───────────────────────────────────────┘
                                │ glReadPixels (CPU-mediated copy)
                                ▼
┌───────────────────────────────────────────────────────────────────────┐
│                      BackendRenderer Thread                           │
│  • Same as native - managed by DrapeEngine                           │
│  • Uses AgusWglContext with shared WGL context                       │
└───────────────────────────────────────────────────────────────────────┘
```

**Key differences from native and other platforms:**
- Uses WGL/OpenGL for rendering (not EGL or Metal)
- **NOT zero-copy**: Frame transfer via `glReadPixels()` → CPU buffer → D3D11 staging texture
- D3D11 shared texture exposed to Flutter via DXGI handle
- Frame notification via direct callback (no JNI or dispatch_async needed)
- Currently x86_64 only; ARM64 Windows untested

---

## 2. Render Loop Flow

### CoMaps Native: FrontendRenderer::RenderFrame()

```cpp
void FrontendRenderer::RenderFrame()
{
  // 1. Validate graphics context
  if (!m_context->Validate())
    return;

  // 2. Process user events (pan, zoom, rotate, tap)
  ScreenBase const & modelView = ProcessEvents(modelViewChanged, viewportChanged, needActiveFrame);

  // 3. Begin rendering (Metal: acquire drawable, OpenGL: bind FBO)
  if (!m_context->BeginRendering())
    return;

  // 4. Determine if this is an "active" frame
  bool isActiveFrame = modelViewChanged || viewportChanged || needActiveFrame;
  isActiveFrame |= needUpdateDynamicTextures;
  isActiveFrame |= m_userEventStream.IsWaitingForActionCompletion();
  isActiveFrame |= InterpolationHolder::Instance().IsActive();
  isActiveFrame |= AnimationSystem::Instance().HasMapAnimations();

  // 5. Prepare scene (if active)
  if (isActiveFrame)
    PrepareScene(modelView);

  // 6. Render scene layers
  RenderScene(modelView, isActiveFrameForScene);
  // Layers: 2D geometry → User lines → 3D buildings → Traffic → Routes → Overlays → GUI

  // 7. End rendering
  m_context->EndRendering();

  // 8. Track active/inactive frames
  if (!isActiveFrame) {
    m_frameData.m_inactiveFramesCounter++;
  } else {
    m_frameData.m_inactiveFramesCounter = 0;
    NotifyActiveFrame();  // <-- Our patch: notify Flutter
  }

  // 9. Message processing / suspend decision
  bool const canSuspend = (m_frameData.m_inactiveFramesCounter > kMaxInactiveFrames);
  if (canSuspend) {
    ProcessSingleMessage(IsRenderingEnabled());  // Blocking wait - saves battery
  } else {
    // Non-blocking: process messages within time budget
  }

  // 10. Present frame to screen
  m_context->Present();  // eglSwapBuffers / Metal commit

  // 11. Frame rate limiting (navigation mode)
  if (m_myPositionController->IsRouteFollowingActive())
    std::this_thread::sleep_for(kNavigationFrameInterval);
}
```

### Flutter Plugin: iOS Flow

```cpp
// In agus_maps_flutter_ios.mm

void agus_native_set_surface(int64_t textureId, CVPixelBufferRef pixelBuffer, ...) {
    // 1. Create Framework (if first time)
    if (!g_framework) {
        g_framework = std::make_unique<Framework>(params, false);
        g_framework->RegisterAllMaps();
    }
    
    // 2. Create Metal context factory targeting CVPixelBuffer
    auto metalFactory = new agus::AgusMetalContextFactory(pixelBuffer, screenSize);
    g_threadSafeFactory = make_unique_dp<dp::ThreadSafeFactory>(metalFactory);
    
    // 3. Register active frame callback BEFORE creating DrapeEngine
    df::SetActiveFrameCallback([]() {
        notifyFlutterFrameReady();  // Rate-limited, dispatches to main thread
    });
    
    // 4. Create DrapeEngine - this starts the render threads
    Framework::DrapeCreationParams p;
    p.m_apiVersion = dp::ApiVersion::Metal;
    p.m_surfaceWidth = width;
    p.m_surfaceHeight = height;
    g_framework->CreateDrapeEngine(make_ref(g_threadSafeFactory), std::move(p));
    
    // 5. Enable rendering
    g_framework->SetRenderingEnabled(make_ref(g_threadSafeFactory));
}

// Frame notification flow:
// FrontendRenderer::RenderFrame() 
//   → isActiveFrame == true 
//   → NotifyActiveFrame() 
//   → df::g_activeFrameCallback() 
//   → notifyFlutterFrameReady()
//   → rate limit check (16ms)
//   → dispatch_async(main_queue) 
//   → AgusMapsFlutterPlugin.notifyFrameReadyFromNative()
//   → textureRegistry.textureFrameAvailable(textureId)
//   → Flutter composites new frame on next VSync
```

### Flutter Plugin: Android Flow

```cpp
// In agus_maps_flutter.cpp (JNI)

JNIEXPORT void JNICALL nativeSetSurface(JNIEnv* env, jobject thiz, 
    jlong textureId, jobject surface, jint width, jint height, jfloat density) {
    
    ANativeWindow* window = ANativeWindow_fromSurface(env, surface);
    
    // 1. Create Framework (if first time)
    if (!g_framework) {
        g_framework = std::make_unique<Framework>(params, false);
        g_framework->RegisterAllMaps();
    }
    
    // 2. Create OGL context factory with ANativeWindow
    auto oglFactory = new agus::AgusOGLContextFactory(window);
    g_factory = make_unique_dp<dp::ThreadSafeFactory>(oglFactory);
    
    // 3. Register active frame callback
    df::SetActiveFrameCallback([]() {
        notifyFlutterFrameReady();  // Rate-limited, JNI callback
    });
    
    // 4. Create DrapeEngine
    Framework::DrapeCreationParams p;
    p.m_apiVersion = dp::ApiVersion::OpenGLES3;
    g_framework->CreateDrapeEngine(make_ref(g_factory), std::move(p));
}

// Frame notification flow:
// FrontendRenderer::RenderFrame()
//   → isActiveFrame == true
//   → NotifyActiveFrame()
//   → notifyFlutterFrameReady()
//   → rate limit check (16ms)
//   → JNI AttachCurrentThread
//   → env->CallVoidMethod(g_pluginInstance, g_notifyFrameReadyMethod)
//   → AgusMapsFlutterPlugin.onFrameReady()
//   → mainHandler.post() 
//   → textureRegistry update
```

---

## 3. Frame Timing & VSync

### CoMaps Native

```cpp
// Constants from frontend_renderer.cpp
double constexpr kVSyncInterval = 0.06;              // ~16fps for OpenGL ES
double constexpr kVSyncIntervalMetalVulkan = 0.03;   // ~33fps for Metal/Vulkan
uint32_t constexpr kMaxInactiveFrames = 2;           // Frames before suspend
```

**Behavior:**
- Render loop runs continuously while active
- After `kMaxInactiveFrames` inactive frames, blocks on message wait (suspend)
- In navigation mode, additional frame limiting via `sleep_for`

### Flutter Plugin: Frame Rate Limiting

```cpp
// Both iOS and Android implementations
static constexpr auto kMinFrameInterval = std::chrono::milliseconds(16);  // ~60fps max
static std::chrono::steady_clock::time_point g_lastFrameNotification;
static std::atomic<bool> g_frameNotificationPending{false};

static void notifyFlutterFrameReady() {
    // Rate limiting: 60fps max
    auto now = std::chrono::steady_clock::now();
    auto elapsed = now - g_lastFrameNotification;
    if (elapsed < kMinFrameInterval)
        return;  // Too soon
    
    // Atomic throttle: prevent queuing multiple notifications
    bool expected = false;
    if (!g_frameNotificationPending.compare_exchange_strong(expected, true))
        return;  // Already pending
    
    g_lastFrameNotification = now;
    
    // Platform-specific dispatch to main thread...
    // iOS: dispatch_async(dispatch_get_main_queue(), ...)
    // Android: JNI callback + Handler.post()
}
```

**Key difference:** We add explicit 60fps rate limiting on top of CoMaps' native active frame detection, because Flutter needs time to composite and present each frame.

---

## 4. Active Frame Detection

### CoMaps Native: isActiveFrame Logic

```cpp
// In FrontendRenderer::RenderFrame()
bool isActiveFrame = false;

// Model view changes (pan, zoom, rotate)
isActiveFrame |= modelViewChanged;
isActiveFrame |= viewportChanged;

// External request (e.g., API call to show location)
isActiveFrame |= needActiveFrame;

// Dynamic texture updates
isActiveFrame |= needUpdateDynamicTextures;

// User action in progress (e.g., drag gesture not yet complete)
isActiveFrame |= m_userEventStream.IsWaitingForActionCompletion();

// Interpolations (smooth zoom transitions)
isActiveFrame |= InterpolationHolder::Instance().IsActive();

// Map animations (route progress, markers, etc.)
isActiveFrame |= AnimationSystem::Instance().HasMapAnimations();
```

### Flutter Plugin: Notification Hook

We added a patch to call `NotifyActiveFrame()` when `isActiveFrame` is true:

```cpp
// In frontend_renderer.cpp (patched)
if (!isActiveFrame) {
    m_frameData.m_inactiveFramesCounter++;
} else {
    m_frameData.m_inactiveFramesCounter = 0;
    NotifyActiveFrame();  // <-- Our addition
}
```

**Callback registration (both platforms):**

```cpp
df::SetActiveFrameCallback([]() {
    notifyFlutterFrameReady();
});
```

---

## 5. Surface Management

### CoMaps Native iOS (Metal)

```objc
// MWMMapView.mm - uses CAMetalLayer
- (void)layoutSubviews {
    [super layoutSubviews];
    CAMetalLayer * layer = (CAMetalLayer *)self.layer;
    layer.drawableSize = self.bounds.size * self.contentScaleFactor;
    // DrapeEngine automatically gets new drawables from layer
}
```

### Flutter Plugin iOS

```objc
// AgusMetalContextFactory.mm - uses CVPixelBuffer
@interface AgusMetalDrawable : NSObject <CAMetalDrawable>
@property (nonatomic, strong) id<MTLTexture> texture;
// Fake drawable that wraps CVPixelBuffer-backed texture
@end

// CVPixelBuffer creation (in Swift plugin)
let attrs: [String: Any] = [
    kCVPixelBufferMetalCompatibilityKey: true,
    kCVPixelBufferIOSurfacePropertiesKey: [:],  // Zero-copy via IOSurface
]
CVPixelBufferCreate(..., &pixelBuffer)

// MTLTexture from CVPixelBuffer (zero-copy)
CVMetalTextureCacheCreateTextureFromImage(cache, pixelBuffer, ..., &cvMetalTexture)
```

**Key difference:** Flutter plugin uses CVPixelBuffer + IOSurface for zero-copy texture sharing. CoMaps native uses CAMetalLayer directly.

### Flutter Plugin macOS (Window Resize Handling)

macOS requires special handling for window resize because Swift creates a new CVPixelBuffer but the native Metal context needs to be updated:

```swift
// AgusMapsFlutterPlugin.swift - handleResizeMapSurface
try createPixelBuffer(width: width, height: height)

// Call macOS-specific resize function that passes new pixel buffer
guard let buffer = pixelBuffer else { /* error */ }
nativeResizeSurface(pixelBuffer: buffer, width: Int32(width), height: Int32(height))

textureRegistry?.textureFrameAvailable(textureId)
```

```cpp
// agus_maps_flutter_macos.mm
static agus::AgusMetalContextFactory* g_metalContextFactory = nullptr;

void agus_native_resize_surface(CVPixelBufferRef pixelBuffer, int32_t width, int32_t height) {
    if (g_metalContextFactory) {
        m2::PointU screenSize(width, height);
        g_metalContextFactory->SetPixelBuffer(pixelBuffer, screenSize);
    }
    if (g_framework && g_drapeEngineCreated) {
        g_framework->OnSize(width, height);
        g_framework->InvalidateRendering();
    }
}
```

```cpp
// AgusMetalContextFactory.mm - uses global texture pointer for lambda
static id<MTLTexture> g_currentRenderTexture = nil;

DrawMetalContext(...) : MetalBaseContext(device, screenSize, []() -> id<CAMetalDrawable> {
    // References GLOBAL pointer, not captured value
    if (!g_currentDrawable || g_currentDrawable.texture != g_currentRenderTexture) {
        g_currentDrawable = [[AgusMetalDrawable alloc] initWithTexture:g_currentRenderTexture];
    }
    return g_currentDrawable;
}) { g_currentRenderTexture = renderTexture; }

void SetRenderTexture(id<MTLTexture> texture, m2::PointU const & screenSize) {
    g_currentRenderTexture = texture;  // Update global
    g_currentDrawable = [[AgusMetalDrawable alloc] initWithTexture:texture];
    Resize(screenSize.x, screenSize.y);
}
```

**Key difference from iOS:** macOS has window resize, requiring `agus_native_resize_surface()` to pass the new pixel buffer. iOS doesn't need this since apps don't resize windows.

### CoMaps Native Android

```java
// MapSurfaceView.java
class MapSurfaceView extends GLSurfaceView {
    // Standard OpenGL ES surface view
}
```

### Flutter Plugin Android

```java
// AgusMapsFlutterPlugin.java
surfaceProducer = textureRegistry.createSurfaceProducer();
surfaceProducer.setSize(width, height);
Surface surface = surfaceProducer.getSurface();
nativeSetSurface(surfaceProducer.id(), surface, width, height, density);
```

```cpp
// agus_ogl.cpp - EGL with ANativeWindow
AgusOGLContextFactory::AgusOGLContextFactory(ANativeWindow* window) {
    m_display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    // Create window surface from Flutter's Surface
    // Create pbuffer for upload context
}
```

**Key difference:** Flutter's `SurfaceProducer` provides the Surface instead of standard SurfaceView.

---

## 6. Context Factory Implementation

### Interface (shared)

```cpp
// drape/graphics_context_factory.hpp
class GraphicsContextFactory {
public:
    virtual GraphicsContext * GetDrawContext() = 0;
    virtual GraphicsContext * GetResourcesUploadContext() = 0;
    virtual bool IsDrawContextCreated() const = 0;
    virtual bool IsUploadContextCreated() const = 0;
    virtual void WaitForInitialization(GraphicsContext * context) = 0;
    virtual void SetPresentAvailable(bool available) = 0;
};
```

### iOS: AgusMetalContextFactory

```cpp
// AgusMetalContextFactory.mm
class AgusMetalContextFactory : public dp::GraphicsContextFactory {
    drape_ptr<DrawMetalContext> m_drawContext;
    drape_ptr<UploadMetalContext> m_uploadContext;
    
    id<MTLDevice> m_metalDevice;
    CVMetalTextureCacheRef m_textureCache;
    id<MTLTexture> m_renderTexture;  // From CVPixelBuffer
    
    // DrawMetalContext: renders to m_renderTexture
    // UploadMetalContext: headless, shares device
};
```

### Android: AgusOGLContextFactory

```cpp
// agus_ogl.hpp
class AgusOGLContextFactory : public dp::GraphicsContextFactory {
    AgusOGLContext * m_drawContext;
    AgusOGLContext * m_uploadContext;
    
    EGLDisplay m_display;
    EGLSurface m_windowSurface;     // For draw context
    EGLSurface m_pixelbufferSurface; // For upload context
    
    // Both contexts share EGLConfig
    // Draw context: attached to ANativeWindow
    // Upload context: attached to pbuffer (offscreen)
};
```

---

## 7. Present/Swap Handling

### CoMaps Native iOS (Metal)

```objc
// MetalBaseContext::Present()
- (void)Present {
    RequestFrameDrawable();  // Gets drawable from CAMetalLayer
    [m_frameCommandBuffer presentDrawable:m_frameDrawable];
    [m_frameCommandBuffer commit];
    [m_frameCommandBuffer waitUntilCompleted];
}
```

### Flutter Plugin iOS

```objc
// DrawMetalContext::Present() in AgusMetalContextFactory.mm
void Present() override {
    // Call base class Present() to commit Metal commands
    dp::metal::MetalBaseContext::Present();
    
    // Note: Frame notification moved to df::SetActiveFrameCallback
    // No explicit present to screen - Flutter reads CVPixelBuffer
}
```

**Key difference:** No `presentDrawable` - Flutter composites the CVPixelBuffer directly.

### CoMaps Native Android

```cpp
// AndroidOGLContext::Present()
void Present() {
    if (m_presentAvailable)
        eglSwapBuffers(m_display, m_surface);
}
```

### Flutter Plugin Android

```cpp
// AgusOGLContext::Present()
void Present() {
    if (m_presentAvailable && m_surface != EGL_NO_SURFACE)
        eglSwapBuffers(m_display, m_surface);
}
```

**Key difference:** Same mechanism, but the surface is Flutter's SurfaceTexture.

---

## 8. Frame Notification to Flutter

### iOS Implementation

```cpp
// agus_maps_flutter_ios.mm
static void notifyFlutterFrameReady(void) {
    // Rate limiting + atomic throttle (see section 3)
    
    dispatch_async(dispatch_get_main_queue(), ^{
        g_frameNotificationPending.store(false);
        
        // Call Swift plugin
        Class pluginClass = NSClassFromString(@"agus_maps_flutter.AgusMapsFlutterPlugin");
        [pluginClass performSelector:@selector(notifyFrameReadyFromNative)];
    });
}

// AgusMapsFlutterPlugin.swift
@objc public static func notifyFrameReadyFromNative() {
    DispatchQueue.main.async {
        sharedInstance?.notifyFrameReady()
    }
}

public func notifyFrameReady() {
    textureRegistry?.textureFrameAvailable(textureId)
}
```

### Android Implementation

```cpp
// agus_maps_flutter.cpp
static void notifyFlutterFrameReady() {
    // Rate limiting + atomic throttle
    
    if (g_javaVM && g_pluginInstance && g_notifyFrameReadyMethod) {
        JNIEnv* env;
        bool attached = false;
        
        // Attach to JVM if needed
        if (g_javaVM->GetEnv((void**)&env, JNI_VERSION_1_6) == JNI_EDETACHED) {
            g_javaVM->AttachCurrentThread(&env, nullptr);
            attached = true;
        }
        
        // Call Java callback
        env->CallVoidMethod(g_pluginInstance, g_notifyFrameReadyMethod);
        
        if (attached)
            g_javaVM->DetachCurrentThread();
    }
}

// AgusMapsFlutterPlugin.java
public void onFrameReady() {
    if (surfaceProducer != null) {
        mainHandler.post(() -> {
            textureRegistry.registerImageTexture(surfaceProducer);
        });
    }
}
```

---

## 9. Platform-Specific Issues

### iOS Issues

| Issue | Severity | Description | Status |
|-------|----------|-------------|--------|
| **Missing depth buffer** | Medium | CVPixelBuffer doesn't include depth attachment. 3D buildings may not render correctly. | ⚠️ Needs investigation |
| **Stencil buffer** | Medium | Similar to depth - CVPixelBuffer is BGRA8 only | ⚠️ Needs investigation |
| **Memory management** | Low | CVPixelBuffer lifecycle must match render usage | ✅ Using IOSurface |
| **Resize handling** | Medium | CVPixelBuffer must be recreated on resize | ✅ Implemented |
| **Background/foreground** | Medium | SetPresentAvailable not fully tested | ⚠️ Needs testing |

### Android Issues

| Issue | Severity | Description | Status |
|-------|----------|-------------|--------|
| **JNI thread attachment** | High | Render thread must attach/detach from JVM for callbacks | ✅ Implemented |
| **EGL context loss** | High | Android can destroy EGL context at any time | ⚠️ Partial handling |
| **Surface lifecycle** | High | SurfaceProducer destroyed/recreated on background | ⚠️ Needs more testing |
| **ANativeWindow reference** | Medium | Must properly release ANativeWindow | ✅ Implemented |
| **Frame notification race** | Medium | JNI callback + Handler.post adds latency | ✅ Rate limited |

### Common Issues (Both Platforms)

| Issue | Severity | Description | Status |
|-------|----------|-------------|--------|
| **60fps cap vs VSync** | Low | Our 16ms cap may not match device VSync | ℹ️ Acceptable |
| **First frame delay** | Low | DrapeEngine startup time causes initial blank | ✅ Expected |
| **Touch event thread** | Low | Touch events from main thread, processed on render thread | ✅ Working |
| **Memory pressure** | Medium | No explicit memory warning handling | ⚠️ TODO |

---

## 10. Parity Checklist

### Thread Model

| Feature | CoMaps Native | iOS Plugin | Android Plugin |
|---------|---------------|------------|----------------|
| FrontendRenderer thread | ✅ | ✅ (via DrapeEngine) | ✅ (via DrapeEngine) |
| BackendRenderer thread | ✅ | ✅ (via DrapeEngine) | ✅ (via DrapeEngine) |
| ThreadsCommutator | ✅ | ✅ (via DrapeEngine) | ✅ (via DrapeEngine) |
| Thread-safe context factory | ✅ | ✅ ThreadSafeFactory | ✅ ThreadSafeFactory |

### Render Loop

| Feature | CoMaps Native | iOS Plugin | Android Plugin |
|---------|---------------|------------|----------------|
| RenderFrame loop | ✅ | ✅ (via DrapeEngine) | ✅ (via DrapeEngine) |
| User event processing | ✅ | ✅ (via TouchEvent) | ✅ (via TouchEvent) |
| Active frame detection | ✅ | ✅ (patched) | ✅ (patched) |
| Frame suspend logic | ✅ | ✅ (via DrapeEngine) | ✅ (via DrapeEngine) |
| Present/swap | ✅ | ✅ (Metal commit) | ✅ (eglSwapBuffers) |

### Frame Notification

| Feature | CoMaps Native | iOS Plugin | Android Plugin |
|---------|---------------|------------|----------------|
| Active frame callback | N/A (renders to layer) | ✅ dispatch_async | ✅ JNI callback |
| 60fps rate limiting | N/A | ✅ | ✅ |
| Atomic throttle | N/A | ✅ | ✅ |
| Main thread dispatch | N/A | ✅ | ✅ Handler.post |

### Surface Management

| Feature | CoMaps Native | iOS Plugin | Android Plugin |
|---------|---------------|------------|----------------|
| Render target | CAMetalLayer / GLSurfaceView | CVPixelBuffer | SurfaceProducer |
| Context creation | Direct layer | Metal texture cache | EGL + ANativeWindow |
| Resize handling | Automatic | Manual recreate | setSize() |
| Background handling | SetPresentAvailable | ⚠️ Partial | ⚠️ Partial |

---

## 11. Future Platform Notes (Linux)

### Windows (Implemented)

**Implementation status:** ✅ Complete (x86_64 only)

**Architecture:**
- WGL/OpenGL for CoMaps rendering to offscreen FBO
- `glReadPixels()` to read framebuffer to CPU buffer (NOT zero-copy)
- RGBA→BGRA conversion with Y-flip during copy
- D3D11 staging texture for CPU→GPU transfer
- D3D11 shared texture exposed via DXGI handle
- Flutter samples shared texture via `FlutterDesktopGpuSurfaceDescriptor`

**Thread Architecture:**

```
┌─────────────────────────────────────────────────────────────────────┐
│                     Main Thread (Windows)                            │
│  • Flutter engine runs here                                          │
│  • AgusMapsFlutterPlugin.cpp handles MethodChannel                  │
│  • D3D11 texture registration                                       │
│  • Frame notification via callback chain                             │
└───────────────────────────────┬─────────────────────────────────────┘
                                │ DXGI Shared Handle (GPU memory)
                                ▼
┌───────────────────────────────────────────────────────────────────────┐
│                      FrontendRenderer Thread                          │
│  • Managed by DrapeEngine                                            │
│  • Renders to OpenGL FBO via WGL context                             │
│  • Present() → glReadPixels → D3D11 staging → shared texture         │
│  • Frame callback → notifyFlutterFrameReady()                        │
└───────────────────────────────┬───────────────────────────────────────┘
                                │
                                ▼
┌───────────────────────────────────────────────────────────────────────┐
│                      BackendRenderer Thread                           │
│  • Managed by DrapeEngine                                            │
│  • Uses AgusWglContext with shared WGL context                       │
└───────────────────────────────────────────────────────────────────────┘
```

**Key characteristics:**
- **NOT zero-copy**: CPU-mediated frame transfer (~2-5ms overhead per frame at 1080p)
- Uses native WGL/OpenGL (not ANGLE/EGL)
- x86_64 only; ARM64 Windows theoretically possible but untested
- Requires Visual Studio 2022 + vcpkg for building

**Files:**
- Plugin: `windows/agus_maps_flutter_plugin.cpp`
- WGL context: `src/AgusWglContextFactory.cpp`, `AgusWglContextFactory.hpp`
- FFI bridge: `src/agus_maps_flutter_win.cpp`
- Platform init: `src/agus_platform_win.cpp`

### macOS (Implemented)

**Implementation approach:**
- Same as iOS: CVPixelBuffer backed by IOSurface for zero-copy GPU texture sharing
- Metal API identical between iOS and macOS
- `AgusMetalContextFactory` reused directly from iOS implementation
- Frame notification via `DispatchQueue.main.async`
- Uses `FlutterMacOS` framework with `FlutterTexture` protocol

**Thread Architecture:**

```
┌─────────────────────────────────────────────────────────────────────┐
│                     Main Thread (macOS)                              │
│  • Flutter engine runs here                                          │
│  • AgusMapsFlutterPlugin.swift handles MethodChannel                │
│  • CVPixelBuffer creation and texture registration                  │
│  • textureFrameAvailable() called here (via DispatchQueue.main)     │
└───────────────────────────────┬─────────────────────────────────────┘
                                │ CVPixelBuffer shared (IOSurface)
                                ▼
┌───────────────────────────────────────────────────────────────────────┐
│                      FrontendRenderer Thread                          │
│  • Same as native - managed by DrapeEngine                           │
│  • Renders to MTLTexture backed by CVPixelBuffer                     │
│  • df::NotifyActiveFrame() → DispatchQueue.main → Flutter            │
└───────────────────────────────┬───────────────────────────────────────┘
                                │
                                ▼
┌───────────────────────────────────────────────────────────────────────┐
│                      BackendRenderer Thread                           │
│  • Same as native - managed by DrapeEngine                           │
│  • Uses UploadMetalContext (headless)                                │
└───────────────────────────────────────────────────────────────────────┘
```

**Key differences from iOS:**
- Uses `AppKit` instead of `UIKit`
- Data stored in `~/Library/Application Support/<bundle>` instead of Documents
- `NSScreen.main?.backingScaleFactor` instead of `UIScreen.main.scale`
- Minimum deployment: macOS 12.0 (Monterey) for Metal 3 features
- Window resizing is common - Metal context handles resize via `UpdateSurface()`

**Files:**
- Plugin: `macos/Classes/AgusMapsFlutterPlugin.swift`
- Metal context: `macos/Classes/AgusMetalContextFactory.mm` (identical to iOS)
- FFI bridge: `macos/Classes/agus_maps_flutter_macos.mm`
- Platform init: `macos/Classes/AgusPlatformMacOS.mm`

### Linux

**Expected approach:**
- OpenGL ES via EGL + X11/Wayland or Vulkan
- Flutter Linux uses GTK embedding
- Frame notification via `g_idle_add` or direct callback

**Key considerations:**
- Multiple windowing systems (X11, Wayland)
- EGL context creation differs from Android
- Mesa/NVIDIA driver differences
- CoMaps has OpenGL ES support that can be reused

### Shared Infrastructure

For all desktop platforms, consider:

1. **Unified context factory base class** for desktop:
   ```cpp
   class AgusDesktopContextFactory : public dp::GraphicsContextFactory {
       // Common resize, lifecycle, synchronization logic
   };
   ```

2. **Platform-agnostic frame callback**:
   ```cpp
   // Already done via df::SetActiveFrameCallback
   // Just need platform-specific dispatch to main thread
   ```

3. **Configuration via compile-time flags**:
   ```cpp
   #if defined(AGUS_PLATFORM_MACOS) || defined(PLATFORM_MAC)
   // Metal - same as iOS (zero-copy via IOSurface)
   #elif defined(AGUS_PLATFORM_WINDOWS) || defined(OMIM_OS_WINDOWS)
   // WGL/OpenGL + D3D11 (CPU-mediated copy)
   #elif defined(AGUS_PLATFORM_LINUX)
   // OpenGL ES or Vulkan (TBD)
   #endif
   ```

### Zero-Copy Status by Platform

| Platform | Zero-Copy | Mechanism |
|----------|-----------|-----------|
| iOS | ✅ Yes | CVPixelBuffer + IOSurface + Metal texture cache |
| macOS | ✅ Yes | CVPixelBuffer + IOSurface + Metal texture cache |
| Android | ✅ Yes | SurfaceTexture + EGL native window |
| Windows | ❌ No | glReadPixels → CPU → D3D11 staging → shared texture |
| Linux | TBD | Likely EGL or Vulkan interop |

---

## References

- CoMaps source: `thirdparty/comaps/libs/drape_frontend/frontend_renderer.cpp`
- CoMaps Metal context: `thirdparty/comaps/libs/drape/metal/metal_base_context.mm`
- iOS implementation: `ios/Classes/AgusMetalContextFactory.mm`, `agus_maps_flutter_ios.mm`
- macOS implementation: `macos/Classes/AgusMetalContextFactory.mm`, `agus_maps_flutter_macos.mm`
- Android implementation: `src/agus_ogl.cpp`, `src/agus_maps_flutter.cpp`
- Windows implementation: `src/AgusWglContextFactory.cpp`, `src/agus_maps_flutter_win.cpp`
- Active frame callback patch: `patches/comaps/0012-active-frame-callback.patch`

---

*Last updated: December 2025*
