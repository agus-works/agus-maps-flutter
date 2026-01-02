# macOS Implementation Plan (MVP)

## Quick Start: Build & Run

### Prerequisites

- Flutter SDK 3.24+ installed
- Xcode 15+ with macOS 12.0+ SDK
- CocoaPods 1.14+
- macOS Monterey or later (for Metal development)
- ~5GB disk space for CoMaps build artifacts

### Debug Mode (Full debugging, slower)

Debug mode enables hot reload, step-through debugging, and verbose logging for both Flutter and native layers.

```bash
# 1. Bootstrap CoMaps dependencies and build XCFramework (first time only)
./scripts/bootstrap_macos.sh

# 2. Copy CoMaps data files (first time only)
./scripts/copy_comaps_data.sh

# 3. Install CocoaPods dependencies
cd example/macos
pod install

# 4. Run in debug mode
cd ..
flutter run -d macos --debug

# For verbose native logs, use Console.app
# Filter by: process:agus_maps_flutter_example category:AgusMapsFlutter
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
./scripts/bootstrap_macos.sh

# 2. Copy CoMaps data files (first time only)
./scripts/copy_comaps_data.sh

# 3. Build and run in release mode
cd example
flutter run -d macos --release

# Or build a .app bundle for distribution
flutter build macos --release
```

**Release mode characteristics:**
- Flutter: AOT compiled, tree-shaken, minified
- Native: `-O3` optimization, no debug symbols, no assertions
- Performance: Full speed, minimal battery usage
- App size: ~100MB (stripped, compressed)

---

## Goal

Get the macOS example app to:

1. Bundle a Gibraltar map file (`Gibraltar.mwm`) as an example asset.
2. On first launch, **ensure the map exists as a real file on disk** (extract/copy once if missing).
3. Pass the on-disk filesystem path into the native layer (FFI) so the native engine can open it using normal filesystem APIs (and later use `mmap`).
4. Set the initial camera to **Gibraltar** at **zoom 14**.
5. Render the map using **Metal** with **zero-copy texture sharing** via CVPixelBuffer/IOSurface.

This matches how CoMaps/Organic Maps operates: maps are stored as standalone `.mwm` files on disk and are memory-mapped by the OS for performance.

## Non-Goals (for this MVP)

- Search/routing functionality
- Download manager / storage management
- OpenGL fallback (Metal-only for now)

Those come after we have a repeatable dependency + data workflow and a stable FFI boundary.

---

## Architecture Overview

### Zero-Copy Texture Sharing (CVPixelBuffer + IOSurface)

The macOS implementation uses Flutter's `FlutterTexture` protocol with `CVPixelBuffer` backed by `IOSurface` for zero-copy GPU texture sharing. This is **identical to the iOS implementation** since both platforms share:

- Metal graphics API
- CVPixelBuffer/IOSurface for GPU memory sharing
- FlutterTexture protocol for Flutter integration

```
┌─────────────────────────────────────────────────────────────┐
│ Flutter Dart Layer                                          │
│   AgusMap widget → Texture(textureId)                       │
│   AgusMapController → FFI calls                             │
├─────────────────────────────────────────────────────────────┤
│ Flutter macOS Engine (Impeller/Skia)                        │
│   FlutterTextureRegistry → copyPixelBuffer                  │
│   Samples CVPixelBuffer as texture (zero-copy via IOSurface)│
├─────────────────────────────────────────────────────────────┤
│ AgusMapsFlutterPlugin.swift (macOS version)                 │
│   FlutterPlugin + FlutterTexture protocol                   │
│   CVPixelBuffer with kCVPixelBufferMetalCompatibilityKey    │
│   MethodChannel for asset extraction                        │
├─────────────────────────────────────────────────────────────┤
│ AgusMetalContextFactory.mm (shared with iOS)                │
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

### Key Differences from iOS

| Aspect | iOS | macOS |
|--------|-----|-------|
| UI Framework | UIKit | AppKit |
| Screen Scale | `UIScreen.main.scale` | `NSScreen.main?.backingScaleFactor` |
| Flutter Import | `import Flutter` | `import FlutterMacOS` |
| Asset Lookup | `FlutterDartProject.lookupKey(forAsset:)` | `FlutterDartProject.lookupKey(forAsset:)` |
| Platform Macro | `PLATFORM_IPHONE=1` | `PLATFORM_MAC=1` |
| Bundle API | `Bundle.main.resourcePath` | `Bundle.main.resourcePath` |
| Window Resize | N/A (fixed size) | `agus_native_resize_surface()` |
| AgusBridge.h | No resize function | Has `agus_native_resize_surface()` |

### Shared Code (reused from iOS)

The following files are **mostly identical** between iOS and macOS:

1. **AgusMetalContextFactory.h/.mm** — Metal context factory for CVPixelBuffer rendering
   - macOS version adds `g_currentRenderTexture` global for resize handling
2. **Active Frame Callback** — Same mechanism via `df::SetActiveFrameCallback`

### Platform-Specific Code

| File | iOS | macOS | Notes |
|------|-----|-------|-------|
| `AgusMapsFlutterPlugin.swift` | Uses `UIScreen`, `UIKit` | Uses `NSScreen`, `AppKit` | macOS has `nativeResizeSurface()` |
| `AgusBridge.h` | Base functions only | + `agus_native_resize_surface()` | macOS needs resize with pixel buffer |
| `AgusPlatformXXX.h/.mm` | `AgusPlatformIOS` | `AgusPlatformMacOS` | Path handling differs |
| `agus_maps_flutter_xxx.mm` | `agus_maps_flutter_ios.mm` | `agus_maps_flutter_macos.mm` | macOS has `g_metalContextFactory` |

---

## XCFramework Distribution

### Build Process

The CoMaps static libraries are pre-built into a universal XCFramework and published to GitHub Releases:

```bash
# Build XCFramework locally (for development)
./scripts/build_binaries_macos.sh

# Output: build/agus-binaries-macos/CoMaps.xcframework
#   ├── macos-arm64_x86_64/    (universal binary)
#   │   └── libcomaps.a
#   └── Info.plist
```

### Download During Pod Install

The XCFramework is automatically downloaded during `pod install` via the podspec's `prepare_command`:

```ruby
# macos/agus_maps_flutter.podspec
s.prepare_command = <<-CMD
  ./scripts/download_libs.sh macos
CMD

s.vendored_frameworks = 'Frameworks/CoMaps.xcframework'
```

### Version Mapping

| Plugin Version | CoMaps Tag | XCFramework Asset |
|----------------|------------|-------------------|
| 0.0.1 | v2025.12.11-2 | agus-binaries-macos.tar.gz |

---

## File Structure

```
macos/
├── agus_maps_flutter.podspec        # CocoaPods configuration
├── Classes/
│   ├── AgusMapsFlutterPlugin.swift  # Flutter plugin (macOS specific)
│   │   - Uses FlutterMacOS, AppKit
│   │   - Has nativeResizeSurface() for window resize
│   ├── AgusMetalContextFactory.h    # Metal context header
│   ├── AgusMetalContextFactory.mm   # Metal context impl
│   │   - Has g_currentRenderTexture for resize
│   ├── AgusBridge.h                 # C interface for Swift (macOS specific)
│   │   - Has agus_native_resize_surface()
│   ├── AgusPlatformMacOS.h          # macOS platform header
│   ├── AgusPlatformMacOS.mm         # macOS platform impl
│   └── agus_maps_flutter_macos.mm   # FFI implementation
│       - Has g_metalContextFactory pointer
│       - Implements agus_native_resize_surface()
├── Resources/
│   └── shaders_metal.metallib       # Pre-compiled Metal shaders
└── Frameworks/
    └── CoMaps.xcframework/          # Pre-built native libraries
```

**Note:** Unlike iOS, the macOS `AgusBridge.h` includes `agus_native_resize_surface()` for handling window resize. The iOS version does not have this function since iOS apps don't support window resizing.

---

## Implementation Steps

### Step 1: Create macOS Plugin Swift Class

Adapt `ios/Classes/AgusMapsFlutterPlugin.swift` for macOS:

1. Change `import Flutter` → `import FlutterMacOS`
2. Change `import UIKit` → `import AppKit`
3. Change `UIScreen.main.scale` → `NSScreen.main?.backingScaleFactor ?? 2.0`
4. Update asset lookup to work with macOS bundle structure

### Step 2: Adapt Metal Context Factory for macOS

Adapt these files from iOS with macOS-specific changes:
- `AgusMetalContextFactory.h` — Copy unchanged
- `AgusMetalContextFactory.mm` — Add `g_currentRenderTexture` global pointer for resize handling
- `AgusBridge.h` — Add `agus_native_resize_surface()` declaration for window resize support

### Step 3: Create macOS Platform Bridge

Create `AgusPlatformMacOS.h/.mm` (similar to iOS version):
- Initialize CoMaps Platform with resource/writable paths
- Use macOS-specific paths (`NSSearchPathForDirectoriesInDomains`)

### Step 4: Create macOS FFI Implementation

Create `agus_maps_flutter_macos.mm`:
- Adapt from `agus_maps_flutter_ios.mm`
- Change UIKit references to AppKit
- Use `PLATFORM_MAC=1` preprocessor define

### Step 5: Update Podspec

Update `macos/agus_maps_flutter.podspec`:
- Set platform to `:osx, '12.0'`
- Add Metal, MetalKit, CoreVideo frameworks
- Configure C++23 and header search paths
- Add vendored framework and resource bundles
- Add `prepare_command` for downloading binaries

### Step 6: Create Build Script

Create `scripts/build_binaries_macos.sh`:
- Build for `arm64` (Apple Silicon) and `x86_64` (Intel)
- Create universal binary with `lipo`
- Package as XCFramework

### Step 7: Update download_libs.sh

Add `macos` case to download the macOS-specific binaries.

### Step 8: Create Bootstrap Script

Create `scripts/bootstrap_macos.sh`:
- Fetch CoMaps source
- Apply patches
- Build Boost headers
- Build or download XCFramework
- Copy Metal shaders

---

## Build Configuration

### CMake Flags for macOS

```cmake
-DCMAKE_SYSTEM_NAME=Darwin
-DCMAKE_OSX_ARCHITECTURES="arm64;x86_64"
-DCMAKE_OSX_DEPLOYMENT_TARGET="12.0"
-DPLATFORM_DESKTOP=ON
-DPLATFORM_IPHONE=OFF
-DPLATFORM_MAC=ON
-DSKIP_TESTS=ON
-DSKIP_QT_GUI=ON
-DSKIP_TOOLS=ON
```

### Preprocessor Definitions

```
OMIM_METAL_AVAILABLE=1
PLATFORM_MAC=1
PLATFORM_DESKTOP=1
```

### Required Frameworks

```ruby
s.frameworks = [
  'Metal',
  'MetalKit', 
  'CoreVideo',
  'CoreGraphics',
  'CoreFoundation',
  'QuartzCore',
  'AppKit',
  'Foundation',
  'Security',
  'SystemConfiguration',
  'CoreLocation'
]
```

---

## CI/CD Integration

### New Workflow: `build-macos-native`

```yaml
build-macos-native:
  summary: Build CoMaps native libraries for macOS
  depends_on:
    - build-headers
  steps:
    - git-clone
    - Fetch CoMaps Source
    - Apply CoMaps Patches
    - Build Boost Headers
    - Build macOS Native Libraries (build_binaries_macos.sh)
    - Prepare macOS Binaries Artifact
    - deploy-to-bitrise-io
```

### New Workflow: `build-macos`

```yaml
build-macos:
  summary: Build macOS App
  depends_on:
    - build-macos-native
  steps:
    - Download Pre-built Binaries
    - Copy CoMaps Assets
    - Get Flutter Dependencies
    - Build macOS App
```

### Updated Pipeline

```yaml
build-release:
  workflows:
    build-headers: {}
    build-ios-native:
      depends_on: [build-headers]
    build-android-native:
      depends_on: [build-headers]
    build-macos-native:        # NEW
      depends_on: [build-headers]
    build-ios:
      depends_on: [build-ios-native]
    build-android:
      depends_on: [build-android-native]
    build-macos:               # NEW
      depends_on: [build-macos-native]
    release:
      depends_on: [build-ios, build-android, build-macos]
```

---

## Acceptance Criteria

- [x] macOS example app builds without errors
- [x] App launches and displays Gibraltar map
- [x] Pan/zoom gestures work correctly
- [x] Trackpad zoom: pinch + two-finger parallel swipe with cursor-centered focal point
- [x] Window resize works correctly (map doesn't turn white)
- [x] Rapid window resize is stable (no brownish/incomplete blocks)
- [ ] Map renders at 60fps with minimal CPU usage
- [ ] Release build is under 150MB
- [ ] Bootstrap script works on fresh checkout

---

## Known Issues & Considerations

### Window Resizing ✅ RESOLVED

Unlike iOS, macOS windows can be freely resized by users. This required special handling across two fixes:

#### Fix 1: White Screen on Resize

**Problem:** When the window is resized, Swift creates a new `CVPixelBuffer` but the native Metal rendering context was not being updated with the new texture. This caused the map to turn white after resize.

**Solution:** Added macOS-specific `agus_native_resize_surface()` function that:
- Accepts the new pixel buffer from Swift
- Updates `AgusMetalContextFactory` with the new texture via `SetPixelBuffer()`
- Calls `Framework::OnSize()` and `InvalidateRendering()` to trigger redraw

**Implementation Details:**
- `AgusBridge.h` (macOS): Added `agus_native_resize_surface(CVPixelBufferRef, int32_t, int32_t)` declaration
- `AgusMetalContextFactory.mm`: Uses global `g_currentRenderTexture` pointer that the drawable getter lambda references (fixes captured-by-value issue)
- `AgusMapsFlutterPlugin.swift`: Calls `nativeResizeSurface()` during resize instead of `nativeOnSizeChanged()`

#### Fix 2: Brownish/Incomplete Blocks During Rapid Resize

**Problem:** During rapid window dragging, resize events arrived every ~8ms, causing:
- Race conditions: texture swapped while render thread was actively using old texture
- Thrashing: 30+ texture recreations per second caused memory pressure

**Solution:** Two-pronged approach:

1. **Resize Debouncing (Swift):** Added 50ms debounce interval in `AgusMapsFlutterPlugin.swift` that waits for resize events to stop before performing the actual resize. Uses `DispatchWorkItem` cancellation pattern.

2. **Thread Synchronization (C++):** Added `std::mutex g_textureMutex` in `AgusMetalContextFactory.mm` to ensure thread-safe texture access. Both the drawable getter lambda and `SetRenderTexture()` acquire the mutex.

3. **Improved Resize Handler:** Added `MakeFrameActive()` call after resize to force immediate re-render of new viewport areas.

See [ISSUE-macos-resize-white-screen.md](ISSUE-macos-resize-white-screen.md) for full technical details.

**Key differences from iOS:**
- iOS: `AgusBridge.h` does NOT have `agus_native_resize_surface()` (iOS apps don't resize)
- macOS: Has the additional function, debouncing, and thread synchronization for resize

### Multiple Displays

macOS supports multiple displays with different scale factors. Consider:
- Using `window.backingScaleFactor` instead of `NSScreen.main`
- Handling display changes when window moves between monitors

### App Sandbox

macOS apps distributed via App Store must be sandboxed:
- Map files must be in app's container (`~/Library/Containers/...`)
- Network access entitlement required for map downloads

### Minimum macOS Version

- **12.0 (Monterey)**: Recommended for Metal 3 support
- **11.0 (Big Sur)**: Minimum for Apple Silicon native support
- **10.15 (Catalina)**: Absolute minimum for Metal and Flutter desktop

We target **12.0** to match iOS 15.6 parity and ensure modern Metal features.

---

## References

- iOS Implementation: [docs/IMPLEMENTATION-IOS.md](IMPLEMENTATION-IOS.md)
- Android Implementation: [docs/IMPLEMENTATION-ANDROID.md](IMPLEMENTATION-ANDROID.md)
- Render Loop Details: [docs/RENDER-LOOP.md](RENDER-LOOP.md)
- CI/CD Plan: [docs/IMPLEMENTATION-CI-CD.md](IMPLEMENTATION-CI-CD.md)
- CoMaps macOS code: `thirdparty/comaps/platform/platform_mac.mm`

---

*Last updated: January 2026*
