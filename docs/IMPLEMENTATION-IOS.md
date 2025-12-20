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

### 2. CVPixelBuffer with IOSurface (Zero-Copy)

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

### 3. Metal Texture from CVPixelBuffer

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

### 4. GUI Thread (dispatch_async)

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

**Date:** 2025-01-06  
**Status:** ✅ iOS Infrastructure Complete - App Running on Device

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

### Known Limitations (Current State)
- ⚠️ Metal-only (no OpenGL ES fallback)
- ⚠️ FFI implementations are currently stubs - actual CoMaps Framework not yet instantiated
- ⚠️ No actual map rendering yet (CVPixelBuffer exists but no pixels drawn)

### Immediate Next Steps

1. **Create Framework in `agus_native_set_surface`** - Instantiate CoMaps Framework with Metal context
2. **Integrate DrapeEngine** - Use `AgusMetalContextFactory` for Metal EGL context
3. **Implement render loop** - Call `comaps_on_render_frame()` and notify Flutter via callback
4. **Touch event forwarding** - Forward pointer events from Swift to Framework

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
6. **Phase 6:** Real device testing + code signing 🚧 ← Current

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

### Tasks

- [ ] Test on physical iOS device
- [ ] Configure code signing for development
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
