# iOS Implementation Plan (MVP)

## Quick Start: Build & Run

### Prerequisites

- Flutter SDK 3.24+ installed
- Xcode 15+ with iOS 15.6+ SDK
- CocoaPods 1.14+
- macOS Sonoma or later (for Metal development)
- ~5GB disk space for CoMaps build artifacts

### Debug Mode (Full debugging, slower)

Debug mode enables hot reload, step-through debugging, and verbose logging for both Flutter and native layers.

```bash
# 1. Bootstrap CoMaps dependencies and build XCFramework (first time only)
./scripts/bootstrap_ios.sh

# 2. Copy CoMaps data files (first time only)
./scripts/copy_comaps_data.sh

# 3. Install CocoaPods dependencies
cd example/ios
pod install

# 4. Run in debug mode (simulator)
cd ..
flutter run --debug -d "iPhone 15 Pro"

# For verbose native logs, use Console.app or Xcode console
# Filter by: process:Runner category:AgusMapsFlutter
```

**Debug mode characteristics:**
- Flutter: Hot reload enabled, Dart DevTools available
- Native: Debug symbols included, assertions enabled, detailed logging
- Performance: Slower due to debug overhead, unoptimized native code
- App size: ~300MB+ (includes debug symbols)

### Release Mode (High performance, battery efficient)

Release mode produces an optimized build suitable for production use and accurate performance profiling.

```bash
# 1. Bootstrap CoMaps dependencies (first time only)
./scripts/bootstrap_ios.sh

# 2. Copy CoMaps data files (first time only)
./scripts/copy_comaps_data.sh

# 3. Build and run in release mode
cd example
flutter run --release -d "iPhone 15 Pro"

# Or build an IPA for distribution (requires signing)
flutter build ipa --release
```

**Release mode characteristics:**
- Flutter: AOT compiled, tree-shaken, minified
- Native: `-O3` optimization, no debug symbols, no assertions
- Performance: Full speed, minimal battery usage
- App size: ~100MB (stripped, compressed)

### Simulator Build (Unsigned - for development)

For local development and CI without code signing:

```bash
cd example

# Build for simulator (no signing required)
flutter build ios --simulator --debug

# Or run directly
flutter run -d "iPhone 15 Pro Simulator"
```

### Standalone Launch (Without Connected Laptop)

**Important:** Debug builds **cannot** be launched standalone from the iOS home screen. This is a Flutter/iOS security restriction.

If you try to launch a debug build from the home screen (without Xcode or Flutter tools connected), the app will fail immediately with:

```
[ERROR:flutter/runtime/ptrace_check.cc(75)] Could not call ptrace(PT_TRACE_ME): Operation not permitted

Cannot create a FlutterEngine instance in debug mode without Flutter tooling or Xcode.
To launch in debug mode in iOS 14+, run flutter run from Flutter tools, run from an IDE 
with a Flutter IDE plugin or run the iOS project from Xcode.
Alternatively profile and release mode apps can be launched from the home screen.
```

**Solution:** Use Release or Profile mode for standalone device testing:

```bash
cd example

# Release mode (recommended for standalone use)
flutter run --release -d <device-id>

# Or Profile mode (includes profiling hooks)
flutter run --profile -d <device-id>
```

After installing via `flutter run --release`, you can disconnect the laptop and launch the app from the home screen.

---

## Goal

Get the iOS example app to:

1. Bundle a Gibraltar map file (`Gibraltar.mwm`) as an example asset.
2. On first launch, **ensure the map exists as a real file on disk** (extract/copy once if missing).
3. Pass the on-disk filesystem path into the native layer (FFI) so the native engine can open it using normal filesystem APIs (and later use `mmap`).
4. Set the initial camera to **Gibraltar** at **zoom 14**.
5. Render the map using **Metal** with **zero-copy texture sharing** via CVPixelBuffer/IOSurface.

This matches how CoMaps/Organic Maps operates: maps are stored as standalone `.mwm` files on disk and are memory-mapped by the OS for performance.

## Non-Goals (for this MVP)

- Search/routing functionality
- Download manager / storage management
- OpenGL ES fallback (Metal-only for now)

Those come after we have a repeatable dependency + data workflow and a stable FFI boundary.

---

## Architecture Overview

### Zero-Copy Texture Sharing (CVPixelBuffer + IOSurface)

The iOS implementation uses Flutter's `FlutterTexture` protocol with `CVPixelBuffer` backed by `IOSurface` for zero-copy GPU texture sharing:

```
┌─────────────────────────────────────────────────────────────┐
│ Flutter Dart Layer                                          │
│   AgusMap widget → Texture(textureId)                       │
│   AgusMapController → FFI calls                             │
├─────────────────────────────────────────────────────────────┤
│ Flutter iOS Engine (Impeller/Skia)                          │
│   FlutterTextureRegistry → copyPixelBuffer                  │
│   Samples CVPixelBuffer as texture (zero-copy via IOSurface)│
├─────────────────────────────────────────────────────────────┤
│ AgusMapsFlutterPlugin.swift                                 │
│   FlutterPlugin + FlutterTexture protocol                   │
│   CVPixelBuffer with kCVPixelBufferMetalCompatibilityKey    │
│   MethodChannel for asset extraction                        │
├─────────────────────────────────────────────────────────────┤
│ AgusMetalContextFactory.mm                                  │
│   DrawMetalContext → MTLTexture from CVPixelBuffer          │
│   UploadMetalContext → shared MTLDevice                     │
│   CVMetalTextureCacheCreateTextureFromImage                 │
├─────────────────────────────────────────────────────────────┤
│ CoMaps Core (XCFramework)                                   │
│   Framework → DrapeEngine                                   │
│   dp::metal::MetalBaseContext                               │
│   map, drape, drape_frontend, platform, etc.                │
└─────────────────────────────────────────────────────────────┘
```

### Demand-Driven Rendering

To maximize battery efficiency, the renderer only draws frames when needed:

1. **User interaction** (pan, zoom, tap) → Dart sends touch event via FFI
2. **FFI call** invalidates the render state
3. **Native engine** renders a single frame to CVPixelBuffer
4. **Flutter** calls `copyPixelBuffer` on next VSync
5. **Texture widget** displays the frame

When idle (no interaction), no rendering occurs - preserving battery on slow devices.

### Active Frame Callback (Efficient Frame Notification)

The iOS implementation uses an **Active Frame Callback** mechanism to efficiently notify Flutter when new frames are ready. This hooks into CoMaps' internal render loop intelligence to avoid unnecessary work.

#### The Problem

CoMaps' DrapeEngine runs its own render loop on a background thread. A naive approach would be:
- **Option A:** Poll continuously (wastes CPU/battery)
- **Option B:** Notify on every render loop iteration (still wasteful - CoMaps renders even when nothing changed)

#### The Solution: Active Frame Detection + Rate Limiting

We combine two techniques:

1. **Active Frame Detection (Option 3):** CoMaps tracks `isActiveFrame` internally - this is `true` only when actual content changed (user interaction, animation, tile loading). We notify Flutter only when `isActiveFrame` is true.

2. **60fps Rate Limiting (Option 2):** Even with active frame detection, we cap notifications at 60fps (16ms minimum interval) to prevent overwhelming Flutter's texture refresh.

#### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ CoMaps DrapeEngine (Background Thread)                      │
│   FrontendRenderer::Routine()                               │
│     └─ if (isActiveFrame) NotifyActiveFrame()               │
├─────────────────────────────────────────────────────────────┤
│ active_frame_callback.cpp                                   │
│   NotifyActiveFrame() → calls registered callback           │
├─────────────────────────────────────────────────────────────┤
│ agus_maps_flutter_ios.mm (Render Thread)                    │
│   Callback checks:                                          │
│     1. 16ms since last notification? (60fps cap)            │
│     2. Not already pending? (atomic throttle)               │
│   If both pass → dispatch_async(main_queue, notify)         │
├─────────────────────────────────────────────────────────────┤
│ Main Thread                                                 │
│   notifyFlutterFrameReady() → textureFrameAvailable()       │
│   Flutter picks up new CVPixelBuffer on next VSync          │
└─────────────────────────────────────────────────────────────┘
```

#### Implementation Files

**New CoMaps files (patched):**

1. `drape_frontend/active_frame_callback.hpp` - Public API:
   ```cpp
   namespace df {
   using ActiveFrameCallback = std::function<void()>;
   void SetActiveFrameCallback(ActiveFrameCallback callback);
   void NotifyActiveFrame();
   }
   ```

2. `drape_frontend/active_frame_callback.cpp` - Thread-safe implementation:
   ```cpp
   namespace df {
   namespace {
   std::mutex g_callbackMutex;
   ActiveFrameCallback g_activeFrameCallback;
   }
   
   void SetActiveFrameCallback(ActiveFrameCallback callback) {
     std::lock_guard<std::mutex> lock(g_callbackMutex);
     g_activeFrameCallback = std::move(callback);
   }
   
   void NotifyActiveFrame() {
     std::lock_guard<std::mutex> lock(g_callbackMutex);
     if (g_activeFrameCallback)
       g_activeFrameCallback();
   }
   }
   ```

3. `drape_frontend/frontend_renderer.cpp` - Hook into render loop:
   ```cpp
   #include "drape_frontend/active_frame_callback.hpp"
   
   // In FrontendRenderer::Routine(), after determining isActiveFrame:
   else {
     m_frameData.m_inactiveFramesCounter = 0;
     NotifyActiveFrame();  // <-- Added: notify on active frames
   }
   ```

**iOS plugin file:**

`agus_maps_flutter_ios.mm` - Rate-limited callback registration:
```cpp
#include "drape_frontend/active_frame_callback.hpp"

// Rate limiting: 60fps max
static constexpr auto kMinFrameInterval = std::chrono::milliseconds(16);
static std::chrono::steady_clock::time_point g_lastFrameNotification;
static std::atomic<bool> g_frameNotificationPending{false};

// Forward declaration
static void notifyFlutterFrameReady();

// In agus_native_set_surface(), BEFORE CreateDrapeEngine():
df::SetActiveFrameCallback([]() {
    auto now = std::chrono::steady_clock::now();
    auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
        now - g_lastFrameNotification);
    
    // Rate limit to 60fps
    if (elapsed < kMinFrameInterval)
        return;
    
    // Prevent queuing multiple notifications
    bool expected = false;
    if (!g_frameNotificationPending.compare_exchange_strong(expected, true))
        return;
    
    g_lastFrameNotification = now;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        g_frameNotificationPending = false;
        notifyFlutterFrameReady();
    });
});
```

#### Why This Approach?

| Approach | CPU Usage When Idle | Battery Impact | Complexity |
|----------|---------------------|----------------|------------|
| Continuous polling | High (100% one core) | Poor | Low |
| Notify every iteration | Medium (many no-op calls) | Fair | Low |
| **Active frame + rate limit** | **Near zero** | **Excellent** | Medium |

The active frame callback leverages CoMaps' existing efficiency:
- DrapeEngine already tracks when content changes
- `isActiveFrame` is `false` when showing a static map
- We only do work when there's actually something new to show

#### Patch File

All CoMaps modifications are captured in `patches/comaps/0012-active-frame-callback.patch`, which is automatically applied by `./scripts/apply_comaps_patches.sh`.

---

## XCFramework Distribution

### Build Process

The CoMaps static libraries are pre-built into a universal XCFramework and published to GitHub Releases:

```bash
# Build XCFramework locally (for development)
./scripts/build_ios_xcframework.sh

# Output: ios/Frameworks/CoMaps.xcframework
#   ├── ios-arm64/                    (device)
#   │   └── libcomaps.a
#   ├── ios-arm64_x86_64-simulator/   (simulator)
#   │   └── libcomaps.a
#   └── Info.plist
```

### Download During Pod Install

The XCFramework is automatically downloaded during `pod install` via the podspec's `prepare_command`:

```ruby
# ios/agus_maps_flutter.podspec
s.prepare_command = <<-CMD
  ./scripts/download_ios_xcframework.sh
CMD

s.vendored_frameworks = 'Frameworks/CoMaps.xcframework'
```

### Version Mapping

| Plugin Version | CoMaps Tag | XCFramework Asset |
|----------------|------------|-------------------|
| 0.0.1 | v2025.12.11-2 | CoMaps.xcframework.zip |

---

## Plugin Distribution for External Consumers

### Overview

When developers install this plugin in their own Flutter projects (via pub.dev or git), they need:
1. **CoMaps.xcframework.zip** — Pre-built static libraries
2. **CoMaps-headers.tar.gz** — Header files required for compilation

Both artifacts are published to GitHub Releases and automatically downloaded during `pod install`.

### In-Repo vs External Consumer Detection

The download script uses dual-mode detection:

| Scenario | Detection | Behavior |
|----------|-----------|----------|
| **In-repo (example app)** | `.git` exists AND `thirdparty/comaps` exists | Skip download, use local headers |
| **External consumer** | No `.git` or no `thirdparty/comaps` | Download from GitHub Releases, fail loudly on error |

### Header Distribution

External consumers don't have access to `thirdparty/comaps/` (it's git-ignored and not published). Instead:

1. **Bitrise CI** bundles all headers from `thirdparty/comaps/` into `CoMaps-headers.tar.gz`
2. **Download script** fetches and extracts headers to `ios/Headers/`
3. **Podspec** uses conditional header paths:
   - In-repo: `$(PODS_TARGET_SRCROOT)/../thirdparty/comaps/...`
   - External: `$(PODS_TARGET_SRCROOT)/Headers/...`

### Version Verification

The download script verifies that the GitHub Release version matches `pubspec.yaml`:
- Extracts version from `pubspec.yaml` (e.g., `0.0.1`)
- Downloads from `https://github.com/.../releases/download/v0.0.1/`
- **Fails loudly** if version mismatch or download fails (external consumers only)

### GitHub Release Artifacts

Each release includes:

| Artifact | Size (approx) | Purpose |
|----------|---------------|---------|
| `CoMaps.xcframework.zip` | ~150MB | Pre-built static libraries (device + simulator) |
| `CoMaps-headers.tar.gz` | ~50-100MB | Header files for compilation |
| `agus-maps-android.aab` | ~50MB | Android App Bundle |
| `agus-maps-android.apk` | ~80MB | Universal Android APK |

### Scripts

| Script | Purpose |
|--------|---------|
| `scripts/bundle_ios_headers.sh` | Bundles headers from `thirdparty/comaps/` into tarball |
| `scripts/download_ios_xcframework.sh` | Downloads XCFramework + headers (dual-mode) |
| `scripts/build_ios_xcframework.sh` | Builds XCFramework from source |

---

## File Structure

### Plugin Files (ios/)

```
ios/
├── agus_maps_flutter.podspec       # Pod specification with XCFramework
├── Frameworks/                      # Downloaded XCFramework (git-ignored)
│   └── CoMaps.xcframework/
└── Classes/
    ├── AgusMapsFlutterPlugin.swift  # FlutterPlugin + FlutterTexture
    ├── AgusMetalContextFactory.h    # Metal context factory header
    ├── AgusMetalContextFactory.mm   # Metal rendering context
    ├── AgusPlatformIOS.h            # Platform stubs header
    ├── AgusPlatformIOS.mm           # iOS platform implementation
    └── agus_maps_flutter.c          # FFI forwarder (legacy)
```

### Scripts (scripts/)

```
scripts/
├── bootstrap_ios.sh                 # Main iOS setup script
├── build_ios_xcframework.sh         # Build CoMaps XCFramework
├── download_ios_xcframework.sh      # Download pre-built XCFramework
├── fetch_comaps.sh                  # Clone/update CoMaps source
├── apply_comaps_patches.sh          # Apply local patches
└── copy_comaps_data.sh              # Copy data files to example
```

### Example App (example/ios/)

```
example/ios/
├── Podfile                          # CocoaPods dependencies (iOS 15.6)
├── Runner/
│   ├── AppDelegate.swift            # Flutter app delegate
│   └── Assets.xcassets/             # App icons, launch screen
└── Runner.xcworkspace/              # Xcode workspace
```

---

## Implementation Details

### 1. FlutterTexture Protocol (AgusMapsFlutterPlugin.swift)

```swift
class AgusMapsFlutterPlugin: NSObject, FlutterPlugin, FlutterTexture {
    var pixelBuffer: CVPixelBuffer?
    var textureRegistry: FlutterTextureRegistry?
    var textureId: Int64 = -1
    
    // FlutterTexture protocol
    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        guard let buffer = pixelBuffer else { return nil }
        return Unmanaged.passRetained(buffer)
    }
}
```

### 2. AgusMetalDrawable (Fake CAMetalDrawable)

Since we render to a CVPixelBuffer for Flutter's `FlutterTexture` instead of a `CAMetalLayer`, we need a custom implementation of `CAMetalDrawable`. This is explicitly against Apple's documentation which states "Don't implement this protocol yourself."

However, CoMaps' `MetalBaseContext` expects a `CAMetalDrawable` to render into. Our `AgusMetalDrawable` wraps a CVPixelBuffer-backed `MTLTexture` and presents it as a drawable.

#### Private Methods Problem

`CAMetalDrawable` has many **private/undocumented methods** that Metal framework calls internally during:
- Command buffer submission
- Drawable lifecycle management  
- GPU-CPU synchronization
- Internal caching and reference counting

When these private methods are missing, the app crashes with:
```
'-[AgusMetalDrawable touch]: unrecognized selector sent to instance'
'-[AgusMetalDrawable baseObject]: unrecognized selector sent to instance'
```

#### Why Crashes Only on Second Launch?

The crashes typically occur on the **second app launch** (not the first) due to:

1. **Metal Internal State Caching:** On first launch, Metal initializes fresh state. On subsequent launches, Metal may take different code paths that access cached drawable behaviors, triggering calls to private methods that weren't called during initial setup.

2. **Framework Recreation Timing:** On cold start with persisted settings (like `settings.ini`), the Framework initialization sequence differs. It may skip certain "first-run" paths and exercise different Metal API interactions.

3. **CoMaps State Restoration:** When the app has cached map state (view position, loaded tiles), DrapeEngine's initialization triggers different rendering paths that call additional drawable methods.

4. **Background/Foreground Transitions:** If the app was backgrounded and reopened, Metal's internal drawable pool management may call lifecycle methods not used during initial creation.

#### Implemented Private Methods

| Method | Purpose |
|--------|---------|
| `touch` | Marks drawable as in-use for lifecycle tracking |
| `baseObject` | Returns underlying object for internal management |
| `drawableSize` | Returns drawable dimensions for calculations |
| `iosurface` | Returns IOSurface (nil for us - managed separately) |
| `isValid` | Checks if drawable can still be rendered to |
| `addPresentScheduledHandler:` | Schedules presentation callbacks |
| `setDrawableAvailableSemaphore:` | GPU-CPU synchronization |
| `drawableAvailableSemaphore` | Returns synchronization semaphore |

#### Future-Proofing

If new crashes occur with "unrecognized selector", check the crash log for the method name and add a stub implementation that either:
- Returns a sensible default (`nil`, `0`, `self`, `YES`)
- Calls handlers immediately (for block-based methods)
- Does nothing (for notification/lifecycle methods)

### 3. CVPixelBuffer with IOSurface (Zero-Copy)

```objc
// Create CVPixelBuffer backed by IOSurface for zero-copy GPU sharing
NSDictionary *attrs = @{
    (id)kCVPixelBufferMetalCompatibilityKey: @YES,
    (id)kCVPixelBufferIOSurfacePropertiesKey: @{},
    (id)kCVPixelBufferWidthKey: @(width),
    (id)kCVPixelBufferHeightKey: @(height),
    (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)
};

CVPixelBufferRef pixelBuffer;
CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                    kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)attrs,
                    &pixelBuffer);
```

### 4. Metal Texture from CVPixelBuffer

```objc
// Create Metal texture cache
CVMetalTextureCacheRef textureCache;
CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, metalDevice, nil, &textureCache);

// Create MTLTexture from CVPixelBuffer (zero-copy)
CVMetalTextureRef cvMetalTexture;
CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache,
                                          pixelBuffer, nil, MTLPixelFormatBGRA8Unorm,
                                          width, height, 0, &cvMetalTexture);

id<MTLTexture> metalTexture = CVMetalTextureGetTexture(cvMetalTexture);
```

### 5. GUI Thread (dispatch_async)

```objc
// Post task to iOS main thread
void GuiThread::Push(Task && task) {
    dispatch_async(dispatch_get_main_queue(), ^{
        task();
    });
}
```

---

## Bitrise CI/CD Workflows

### build-ios-xcframework

Builds the CoMaps XCFramework and publishes to GitHub Releases:

1. Clone repo + fetch CoMaps source
2. Apply patches
3. Build Boost headers
4. Run `build_ios_xcframework.sh` (CMake → libtool → xcodebuild -create-xcframework)
5. Zip and upload `CoMaps.xcframework.zip` to release

### build-ios

Builds the Flutter example app for iOS simulator:

1. Download pre-built XCFramework from Releases
2. Run `pod install`
3. Copy CoMaps data assets
4. Run `flutter build ios --simulator`
5. Archive as `.app` bundle

---

## Status Report

**Date:** 2025-12-20  
**Status:** ✅ Active Frame Callback Complete - Efficient Rendering Implemented

### Completed

#### Build Infrastructure
- [x] Create XCFramework build script (`scripts/build_ios_xcframework.sh`)
- [x] Create XCFramework download script (`scripts/download_ios_xcframework.sh`)
- [x] Create iOS bootstrap script (`scripts/bootstrap_ios.sh`)
- [x] Update `.gitignore` for `ios/Frameworks/`
- [x] Update podspec for vendored framework
- [x] Add Bitrise iOS workflows (`build-ios-xcframework`, `build-ios`)
- [x] Update release pipeline to include iOS artifacts
- [x] Update example Podfile for iOS 15.6 + C++23

#### Plugin Registration & FFI
- [x] Fix plugin registration by adding `pluginClass: AgusMapsFlutterPlugin` to pubspec.yaml iOS section
- [x] Fix FFI symbol loading by using `DynamicLibrary.process()` for iOS (symbols linked into main executable)
- [x] Create `agus_maps_flutter_ios.mm` with all FFI function implementations
- [x] Create `AgusBridge.h` for Swift-to-C interop declarations
- [x] Fix `extern "C"` linkage in `AgusPlatformIOS.h`
- [x] Add utfcpp header search path to podspec

#### Flutter Plugin Implementation
- [x] Implement `AgusMapsFlutterPlugin.swift` (FlutterTexture protocol)
- [x] Fix `lookupKeyForAsset` to use `FlutterDartProject.lookupKey(forAsset:)`
- [x] Implement `extractMap` method channel handler
- [x] Implement `extractDataFiles` method channel handler
- [x] Implement `createMapSurface` method channel handler
- [x] CVPixelBuffer creation with Metal compatibility flags
- [x] Texture registration with Flutter engine

#### Native Platform Layer
- [x] Create `AgusMetalContextFactory.mm` (Metal EGL context)
- [x] Add `AgusPlatformIOS.mm` with path initialization
- [x] Implement `AgusPlatformIOS_InitPaths()` for resources/writable directories

#### Verified Working on Device
- [x] Plugin registered in `GeneratedPluginRegistrant.m`
- [x] Asset extraction from bundle to Documents directory
- [x] Data files extraction (countries_countries.txt, etc.)
- [x] Platform initialization with correct paths
- [x] Surface creation with CVPixelBuffer
- [x] Texture ID returned to Flutter
- [x] Map registration FFI call succeeds (returns 0)

### Build Configuration: DEBUG/RELEASE Preprocessor Definitions

CoMaps' `base/base.hpp` has a compile-time assertion that requires **exactly one** of `DEBUG` or `RELEASE`/`NDEBUG` to be defined:

```cpp
#if defined(DEBUG)
  #define MY_DEBUG_DEFINED 1
#else
  #define MY_DEBUG_DEFINED 0
#endif

#if defined(NDEBUG) || defined(RELEASE)
  #define MY_RELEASE_DEFINED 1
#else
  #define MY_RELEASE_DEFINED 0
#endif

static_assert(MY_DEBUG_DEFINED ^ MY_RELEASE_DEFINED, 
    "Either Debug or Release should be defined, but not both");
```

#### Problem

When building Release mode for iOS, the build would fail with:
```
Static assertion failed: Either Debug or Release should be defined, but not both
```

This happens because:
1. Xcode's Release configuration defines `NDEBUG` automatically
2. But the podspec also needs to set `RELEASE=1` for CoMaps' internal code paths
3. Similarly, Debug configuration needs `DEBUG=1` explicitly

#### Solution: Podfile post_install Hook

The fix requires adding configuration-specific preprocessor definitions via a `post_install` hook in the example app's `Podfile`:

```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      # Existing settings...
      
      # Add DEBUG/RELEASE definitions for CoMaps
      if config.name == 'Debug'
        existing = config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] || ['$(inherited)']
        config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] = existing + ['DEBUG=1']
      else
        # Release and Profile configurations
        existing = config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] || ['$(inherited)']
        config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] = existing + ['NDEBUG=1', 'RELEASE=1']
      end
    end
  end
end
```

After modifying the Podfile, regenerate the Xcode project:

```bash
cd example/ios
rm -rf Pods Podfile.lock
pod install
```

### Known Limitations (Current State)
- ⚠️ Metal-only (no OpenGL ES fallback)

### Immediate Next Steps

1. **Test on physical device** - Verify map renders correctly with active frame callback
2. **Performance profiling** - Measure CPU/battery savings vs. continuous polling
3. **Memory profiling** - Ensure no leaks in CVPixelBuffer handling

---

## Acceptance Criteria

- Example app on iOS Simulator:
  - Bundles `Gibraltar.mwm` in app assets
  - On first launch, copies map to Documents directory
  - Calls native `comaps_load_map_path(extractedPath)`
  - Calls native `comaps_set_view(36.1408, -5.3536, 14)`
  - Renders map via Metal → CVPixelBuffer → FlutterTexture
  - Shows success/failure in UI and native logs

---

## Next Milestones

1. **Phase 1:** XCFramework build + distribution ✅
2. **Phase 2:** FlutterTexture + CVPixelBuffer integration ✅
3. **Phase 3:** Plugin registration + FFI working ✅
4. **Phase 4:** Metal rendering context + Framework creation ✅
5. **Phase 5:** Touch/gesture handling ✅
6. **Phase 6:** Real device testing + code signing ✅
7. **Phase 7:** Active frame callback (efficient rendering) ✅
8. **Phase 8:** Performance profiling + optimization 🚧 ← Current

---

## Phase 4 Implementation Details (Completed)

### Framework Creation

The `agus_native_set_surface()` function in `agus_maps_flutter_ios.mm` now:

1. Creates Framework with FrameworkParams on first surface creation
2. Creates `AgusMetalContextFactory` from CVPixelBuffer for Metal rendering
3. Wraps in `ThreadSafeFactory` for thread-safe context access
4. Creates DrapeEngine with `dp::ApiVersion::Metal`
5. Enables rendering via `Framework::SetRenderingEnabled()`

```cpp
void agus_native_set_surface(int64_t textureId, CVPixelBufferRef pixelBuffer, 
                              int32_t width, int32_t height, float density) {
    // Create Framework on this thread if not already created
    if (!g_framework) {
        FrameworkParams params;
        params.m_enableDiffs = false;
        g_framework = std::make_unique<Framework>(params, false /* loadMaps */);
        g_framework->RegisterAllMaps();
    }
    
    // Create Metal context factory with the CVPixelBuffer
    m2::PointU screenSize(width, height);
    auto metalFactory = new agus::AgusMetalContextFactory(pixelBuffer, screenSize);
    g_threadSafeFactory = make_unique_dp<dp::ThreadSafeFactory>(metalFactory);
    
    // Create DrapeEngine with Metal API
    Framework::DrapeCreationParams p;
    p.m_apiVersion = dp::ApiVersion::Metal;
    p.m_surfaceWidth = width;
    p.m_surfaceHeight = height;
    p.m_visualScale = density;
    g_framework->CreateDrapeEngine(make_ref(g_threadSafeFactory), std::move(p));
    
    g_framework->SetRenderingEnabled(make_ref(g_threadSafeFactory));
}
```

### Touch Events

Touch events are forwarded via `comaps_touch()` using `df::TouchEvent`:

```cpp
void comaps_touch(int type, int id1, float x1, float y1, int id2, float x2, float y2) {
    df::TouchEvent event;
    switch (type) {
        case 1: event.SetTouchType(df::TouchEvent::TOUCH_DOWN); break;
        case 2: event.SetTouchType(df::TouchEvent::TOUCH_MOVE); break;
        case 3: event.SetTouchType(df::TouchEvent::TOUCH_UP); break;
        case 4: event.SetTouchType(df::TouchEvent::TOUCH_CANCEL); break;
    }
    // Set touch points and forward to Framework
    g_framework->TouchEvent(event);
}
```

### Map Registration

Single map registration via `platform::LocalCountryFile`:

```cpp
int comaps_register_single_map(const char* fullPath) {
    platform::LocalCountryFile file = platform::LocalCountryFile::MakeTemporary(fullPath);
    file.SyncWithDisk();
    auto result = g_framework->RegisterMap(file);
    return result.second == MwmSet::RegResult::Success ? 0 : -1;
}
```

---

## Phase 5: Touch/Gesture Handling (Completed)

Touch handling on iOS uses Flutter's built-in `Listener` widget, **not** native UIKit gesture recognizers. This is because we're using `FlutterTexture` (not a platform view), so touch events are handled entirely within Flutter and forwarded via FFI.

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Flutter Dart Layer                                          │
│   AgusMap widget                                            │
│     └─ Listener widget captures PointerEvents               │
│         └─ _sendTouchEvent() converts to physical pixels    │
│             └─ sendTouchEvent() calls FFI comaps_touch()    │
├─────────────────────────────────────────────────────────────┤
│ Native iOS (agus_maps_flutter_ios.mm)                       │
│   comaps_touch() → df::TouchEvent → Framework::TouchEvent() │
└─────────────────────────────────────────────────────────────┘
```

### Implementation Details

1. **Flutter `Listener` widget** wraps the `Texture` widget in `AgusMap`:
   ```dart
   Listener(
     onPointerDown: _handlePointerDown,
     onPointerMove: _handlePointerMove,
     onPointerUp: _handlePointerUp,
     onPointerCancel: _handlePointerCancel,
     child: Texture(textureId: _textureId!),
   )
   ```

2. **Coordinate conversion** scales logical pixels to physical pixels:
   ```dart
   void _sendTouchEvent(TouchType type, int pointerId, Offset position) {
     final x1 = position.dx * _devicePixelRatio;
     final y1 = position.dy * _devicePixelRatio;
     sendTouchEvent(type, pointerId, x1, y1, id2: id2, x2: x2, y2: y2);
   }
   ```

3. **Multitouch support** tracks active pointers for pinch-to-zoom:
   ```dart
   final Map<int, Offset> _activePointers = {};
   // Second pointer passed to native when available
   ```

4. **FFI binding** in `agus_maps_flutter_bindings_generated.dart`:
   ```dart
   void comaps_touch(int type, int id1, double x1, double y1, 
                     int id2, double x2, double y2);
   ```

5. **Native forwarding** in `agus_maps_flutter_ios.mm`:
   ```cpp
   void comaps_touch(int type, int id1, float x1, float y1, 
                     int id2, float x2, float y2) {
     df::TouchEvent event;
     switch (type) {
       case 1: event.SetTouchType(df::TouchEvent::TOUCH_DOWN); break;
       case 2: event.SetTouchType(df::TouchEvent::TOUCH_MOVE); break;
       case 3: event.SetTouchType(df::TouchEvent::TOUCH_UP); break;
       case 4: event.SetTouchType(df::TouchEvent::TOUCH_CANCEL); break;
     }
     g_framework->TouchEvent(event);
   }
   ```

### Why Not Native Gesture Recognizers?

- `FlutterTexture` renders to a GPU texture that Flutter composites
- The texture is displayed via Flutter's `Texture` widget
- Flutter owns the view hierarchy, not UIKit
- Touch events naturally flow through Flutter's gesture system
- This is simpler and avoids Swift↔C++ bridging complexity

---

## Phase 6: Real Device Testing + Code Signing (Current)

### Status

- [x] iOS build succeeds with `flutter build ios --debug`
- [x] Code signing works automatically with development team
- [x] App installs on physical device
- [ ] App runs and renders map correctly (testing in progress)

### Tasks

- [x] Test on physical iOS device (build + install working)
- [x] Configure code signing for development (auto-configured)
- [ ] Verify Metal rendering performance
- [ ] Test memory usage and battery impact
- [ ] Verify touch responsiveness (pan, zoom, tap)
- [ ] Test map loading from Documents directory

### Code Signing Setup

For development testing on a physical device:

1. Open `example/ios/Runner.xcworkspace` in Xcode
2. Select the Runner target → Signing & Capabilities
3. Select your development team
4. Xcode will create provisioning profile automatically

### Running on Device

```bash
cd example
flutter run --release -d <device-id>

# List available devices
flutter devices
```

### Performance Profiling

Use Xcode Instruments for:
- Metal System Trace (GPU performance)
- Time Profiler (CPU usage)
- Allocations (memory usage)
- Energy Log (battery impact)

---

## Phase 7: Active Frame Callback (Completed)

The Active Frame Callback mechanism provides battery-efficient frame notifications by integrating with CoMaps' internal render loop intelligence.

### Problem Statement

When embedding CoMaps in Flutter via `FlutterTexture`, we need to notify Flutter when new frames are ready. However:

1. **CoMaps owns the render thread** - DrapeEngine runs its own render loop on a background thread
2. **Continuous polling wastes power** - Checking every frame burns CPU/battery
3. **Naive notification is inefficient** - CoMaps renders even when the map is static (to handle potential future changes)

### Solution: Hook into `isActiveFrame`

CoMaps' `FrontendRenderer` already tracks whether each frame contains meaningful changes:

```cpp
// In FrontendRenderer::Routine() - simplified
bool isActiveFrame = true;  // Assume active initially

// Various conditions set isActiveFrame = false:
// - No user interaction pending
// - No animations running  
// - No tiles being loaded
// - No overlays changing

if (isActiveFrame) {
    m_frameData.m_inactiveFramesCounter = 0;
} else {
    ++m_frameData.m_inactiveFramesCounter;
}
```

We added a callback hook that fires only when `isActiveFrame` is true:

```cpp
if (isActiveFrame) {
    m_frameData.m_inactiveFramesCounter = 0;
    NotifyActiveFrame();  // Our addition
}
```

### Rate Limiting Strategy

Even with active frame detection, we apply a 60fps cap:

```cpp
static constexpr auto kMinFrameInterval = std::chrono::milliseconds(16);
static std::chrono::steady_clock::time_point g_lastFrameNotification;
static std::atomic<bool> g_frameNotificationPending{false};

df::SetActiveFrameCallback([]() {
    auto now = std::chrono::steady_clock::now();
    auto elapsed = now - g_lastFrameNotification;
    
    // Rate limit: at most one notification per 16ms
    if (elapsed < kMinFrameInterval)
        return;
    
    // Atomic throttle: prevent queuing multiple dispatch_async calls
    bool expected = false;
    if (!g_frameNotificationPending.compare_exchange_strong(expected, true))
        return;
    
    g_lastFrameNotification = now;
    
    // Dispatch to main thread for Flutter notification
    dispatch_async(dispatch_get_main_queue(), ^{
        g_frameNotificationPending = false;
        notifyFlutterFrameReady();
    });
});
```

### Why Atomic Throttling?

The `g_frameNotificationPending` atomic prevents a race condition:

1. Frame 1 rendered → `dispatch_async` queued
2. Frame 2 rendered (within 1ms) → Would queue another `dispatch_async`
3. Frame 3 rendered (within 1ms) → Would queue yet another

Without atomic throttling, the main thread queue could fill with redundant notifications. The atomic ensures only one notification is "in flight" at a time.

### Thread Safety

The callback is invoked from CoMaps' render thread, but Flutter's `textureFrameAvailable()` must be called on the main thread. The implementation handles this safely:

```
Render Thread                    Main Thread
     │                                │
     ├── NotifyActiveFrame()          │
     │   └── Rate limit check         │
     │   └── Atomic throttle check    │
     │   └── dispatch_async ──────────┼──> notifyFlutterFrameReady()
     │                                │    └── textureFrameAvailable()
     │                                │
```

### Files Modified

| File | Change |
|------|--------|
| `drape_frontend/active_frame_callback.hpp` | New: callback API declaration |
| `drape_frontend/active_frame_callback.cpp` | New: thread-safe callback storage |
| `drape_frontend/frontend_renderer.cpp` | Modified: call `NotifyActiveFrame()` |
| `drape_frontend/CMakeLists.txt` | Modified: add new source files |
| `ios/Classes/agus_maps_flutter_ios.mm` | Modified: register callback with rate limiting |

### Rebuild Required

After modifying CoMaps source files, rebuild the XCFramework:

```bash
./scripts/build_ios_xcframework.sh
```

This compiles the new `active_frame_callback.cpp` into `libcomaps.a` and packages it into `ios/Frameworks/CoMaps.xcframework`.

### Verification

To verify the symbol exists in the built framework:

```bash
nm ios/Frameworks/CoMaps.xcframework/ios-arm64/libcomaps.a | grep SetActiveFrameCallback
# Should output: T __ZN2df22SetActiveFrameCallbackENSt3__18functionIFvvEEE
```

### Status

- [x] Created `active_frame_callback.hpp` and `.cpp`
- [x] Modified `frontend_renderer.cpp` to call `NotifyActiveFrame()`
- [x] Updated `CMakeLists.txt` with new source files
- [x] Implemented rate-limited callback in `agus_maps_flutter_ios.mm`
- [x] Created patch `0012-active-frame-callback.patch`
- [x] Rebuilt XCFramework with new files
- [x] Verified iOS build succeeds
