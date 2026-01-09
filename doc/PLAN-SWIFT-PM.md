# Swift Package Manager Support - Implementation Plan

> **Status:** Planning / Research  
> **Target Version:** unspecified
> **Author:** Agus Maps Team  
> **Last Updated:** January 2026

## Executive Summary

This document outlines the plan to add Swift Package Manager (SwiftPM) support to `agus_maps_flutter` for iOS and macOS platforms. SwiftPM is Flutter's preferred future direction for Apple platform dependencies, but our plugin's architecture presents unique challenges due to the vendored `CoMaps.xcframework` binary dependency.

**Key Decision:** We will implement a **hybrid approach** maintaining both CocoaPods and SwiftPM support, with different trade-offs for each:

| Dependency Manager | AGUS_MAPS_HOME Support | Auto-download XCFramework | Recommended For |
|--------------------|------------------------|---------------------------|-----------------|
| **CocoaPods** | ✅ Yes | ❌ No (v0.1.7+) | Enterprise, air-gapped, custom SDK locations |
| **SwiftPM** | ❌ No | ✅ Yes | Standard consumers, simpler setup |


## Table of Contents

1. [Background](#background)
2. [Current Architecture](#current-architecture)
3. [SwiftPM Constraints](#swiftpm-constraints)
4. [Proposed Architecture](#proposed-architecture)
5. [Implementation Tasks](#implementation-tasks)
6. [CI/CD Changes](#cicd-changes)
7. [Migration Path](#migration-path)
8. [Risk Assessment](#risk-assessment)
9. [Open Questions](#open-questions)
10. [References](#references)


## Background

### Why SwiftPM?

Flutter is migrating to Swift Package Manager for iOS and macOS native dependencies:

1. **Bundled with Xcode** - No need to install Ruby and CocoaPods
2. **Growing ecosystem** - Access to Swift packages on [swiftpackageindex.com](https://swiftpackageindex.com)
3. **Flutter's direction** - SwiftPM is the future; CocoaPods is legacy

As of Flutter 3.24+, SwiftPM support is available (opt-in). Flutter falls back to CocoaPods for plugins that don't support SwiftPM.

### Current State (v0.1.7)

- **CocoaPods only** - `ios/agus_maps_flutter.podspec` and `macos/agus_maps_flutter.podspec`
- **AGUS_MAPS_HOME workflow** - Consumers download SDK, set env var, plugin copies XCFramework
- **CI detection** - Allows plugin-local prebuilt directories for CI builds
- **No SwiftPM support** - Consumers with SwiftPM enabled fall back to CocoaPods


## Current Architecture

### Directory Structure

```
ios/
├── agus_maps_flutter.podspec      # CocoaPods spec
├── Classes/
│   ├── AgusMapsFlutterPlugin.swift
│   ├── AgusBridge.h
│   ├── AgusMetalContextFactory.h
│   ├── AgusMetalContextFactory.mm
│   ├── AgusPlatformIOS.h
│   ├── AgusPlatformIOS.mm
│   ├── agus_maps_flutter.c
│   └── agus_maps_flutter_ios.mm
├── Frameworks/
│   └── CoMaps.xcframework/        # Vendored binary (~50MB)
└── Resources/
    └── shaders_metal.metallib     # Metal shaders
```

### How XCFramework Gets There (v0.1.7)

```
┌─────────────────────────────────────────────────────────────────┐
│                        pod install                               │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    prepare_command runs                          │
├─────────────────────────────────────────────────────────────────┤
│  1. Check Frameworks/CoMaps.xcframework exists?                  │
│     └─ YES → exit 0 (in-repo or CI already copied)               │
│                                                                  │
│  2. Check $CI env var?                                           │
│     └─ YES → mkdir Frameworks, exit 0 (CI will copy later)       │
│                                                                  │
│  3. Check $AGUS_MAPS_HOME?                                       │
│     └─ YES → cp -R $AGUS_MAPS_HOME/ios/Frameworks/... → exit 0   │
│                                                                  │
│  4. No framework found → exit 1 with error message               │
└─────────────────────────────────────────────────────────────────┘
```


## SwiftPM Constraints

### 1. No `prepare_command` Equivalent

CocoaPods runs `prepare_command` before integration. SwiftPM has **no pre-resolution hook**. Our current logic for:
- Checking `$AGUS_MAPS_HOME`
- Copying XCFramework from SDK
- CI placeholder creation

...cannot be replicated in SwiftPM.

### 2. Binary Target Requirements

SwiftPM supports binary dependencies via `.binaryTarget()`:

```swift
// Remote URL (requires checksum)
.binaryTarget(
    name: "CoMaps",
    url: "https://github.com/.../CoMaps.xcframework.zip",
    checksum: "abc123def456..."  // SHA256, REQUIRED
)

// Local path (development only, not for distributed packages)
.binaryTarget(
    name: "CoMaps",
    path: "Frameworks/CoMaps.xcframework"
)
```

**Implications:**

| Approach | Works for pub.dev? | Works for Git dependency? | Works for AGUS_MAPS_HOME? |
|----------|-------------------|---------------------------|---------------------------|
| Remote URL | ✅ Yes | ✅ Yes | ❌ No |
| Local path | ❌ No | ❌ No (must exist at resolution) | ❌ No |

### 3. Checksum Management

Every release requires:
1. Build XCFramework
2. Create ZIP archive
3. Compute SHA256: `shasum -a 256 CoMaps-ios.xcframework.zip`
4. Update `Package.swift` with new checksum
5. Commit and tag

This creates a **chicken-and-egg problem**: The `Package.swift` must contain the checksum of the ZIP that will be uploaded in the same release.

**Solution:** Two-phase release process or checksum file approach (see [CI/CD Changes](#cicd-changes)).

### 4. Objective-C++ Interop

SwiftPM supports Obj-C/C++ but requires separate targets:

```swift
targets: [
    // Pure Swift target
    .target(
        name: "agus_maps_flutter",
        dependencies: ["AgusObjC", "CoMaps"]
    ),
    // Obj-C++ target
    .target(
        name: "AgusObjC",
        dependencies: ["CoMaps"],
        path: "Sources/AgusObjC",
        publicHeadersPath: "include"
    ),
    // Binary target
    .binaryTarget(name: "CoMaps", ...)
]
```

Our `.mm` files must be in a separate target from Swift files.

### 5. Resource Handling

SwiftPM resources work differently:

```swift
resources: [
    .copy("Resources/shaders_metal.metallib"),  // Copy as-is
    .process("PrivacyInfo.xcprivacy")           // Process (localization, etc.)
]
```

Accessing resources in code:

```swift
#if SWIFT_PACKAGE
    let url = Bundle.module.url(forResource: "shaders_metal", withExtension: "metallib")
#else
    let url = Bundle(for: Self.self).url(forResource: "shaders_metal", withExtension: "metallib")
#endif
```


## Proposed Architecture

### Directory Structure (After SwiftPM Support)

```
ios/
├── agus_maps_flutter.podspec              # KEEP - CocoaPods support
├── agus_maps_flutter/                      # NEW - SwiftPM package
│   ├── Package.swift
│   └── Sources/
│       ├── agus_maps_flutter/              # Swift target
│       │   ├── AgusMapsFlutterPlugin.swift
│       │   ├── AgusBridge.h                # Bridging header
│       │   └── Resources/
│       │       ├── shaders_metal.metallib
│       │       └── PrivacyInfo.xcprivacy
│       └── AgusObjC/                       # Obj-C++ target
│           ├── include/
│           │   ├── module.modulemap
│           │   ├── AgusMetalContextFactory.h
│           │   └── AgusPlatformIOS.h
│           ├── AgusMetalContextFactory.mm
│           ├── AgusPlatformIOS.mm
│           └── agus_maps_flutter_ios.mm
├── Classes/                                # KEEP - CocoaPods source path
│   └── ... (existing files)
├── Frameworks/                             # KEEP - CocoaPods vendored path
│   └── CoMaps.xcframework/
└── Resources/                              # KEEP - CocoaPods resources
    └── shaders_metal.metallib
```

### Package.swift Template

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "agus_maps_flutter",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(name: "agus-maps-flutter", targets: ["agus_maps_flutter"])
    ],
    dependencies: [],
    targets: [
        // Binary dependency - auto-downloaded from GitHub releases
        .binaryTarget(
            name: "CoMaps",
            url: "https://github.com/agus-works/agus-maps-flutter/releases/download/vX.Y.Z/CoMaps-ios.xcframework.zip",
            checksum: "PLACEHOLDER_CHECKSUM_SHA256"
        ),
        
        // Objective-C++ interop layer
        .target(
            name: "AgusObjC",
            dependencies: ["CoMaps"],
            path: "Sources/AgusObjC",
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("../../.."),  // For ../src headers
            ]
        ),
        
        // Main Swift target
        .target(
            name: "agus_maps_flutter",
            dependencies: ["AgusObjC", "CoMaps"],
            path: "Sources/agus_maps_flutter",
            resources: [
                .copy("Resources/shaders_metal.metallib"),
                .process("Resources/PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
```

### Consumer Experience Comparison

#### SwiftPM Consumer (New - vX.Y.Z+)

```yaml
# pubspec.yaml
dependencies:
  agus_maps_flutter: ^X.Y.Z

flutter:
  assets:
    - assets/comaps_data/
    - assets/maps/
```

```bash
# No AGUS_MAPS_HOME needed!
# XCFramework auto-downloads during package resolution
flutter run
```

**Trade-off:** Cannot use custom SDK location. Must use the version bundled with plugin release.

#### CocoaPods Consumer (Existing - AGUS_MAPS_HOME)

```yaml
# pubspec.yaml
dependencies:
  agus_maps_flutter: ^X.Y.Z

flutter:
  disable-swift-package-manager: true  # Force CocoaPods
  assets:
    - assets/comaps_data/
    - assets/maps/
```

```bash
export AGUS_MAPS_HOME=/path/to/agus-maps-sdk-vX.Y.Z
flutter run
```

**Trade-off:** More manual setup, but full control over SDK location.


## Implementation Tasks

### Phase 1: File Structure Migration

- [ ] Create `ios/agus_maps_flutter/` directory
- [ ] Create `ios/agus_maps_flutter/Package.swift` (with placeholder checksum)
- [ ] Create `ios/agus_maps_flutter/Sources/agus_maps_flutter/` directory
- [ ] Create `ios/agus_maps_flutter/Sources/AgusObjC/` directory
- [ ] Create `ios/agus_maps_flutter/Sources/AgusObjC/include/module.modulemap`

### Phase 2: Source File Organization

- [ ] Copy Swift files to `Sources/agus_maps_flutter/`
- [ ] Copy Obj-C++ files to `Sources/AgusObjC/`
- [ ] Copy headers to `Sources/AgusObjC/include/`
- [ ] Copy resources to `Sources/agus_maps_flutter/Resources/`
- [ ] Update `#if SWIFT_PACKAGE` guards for resource loading
- [ ] Verify imports work between targets

### Phase 3: Podspec Updates

- [ ] Update `s.source_files` to point to new paths
- [ ] Update `s.public_header_files` paths
- [ ] Update `s.resource_bundles` paths
- [ ] Run `pod lib lint` to verify CocoaPods still works

### Phase 4: CI/CD Integration

- [ ] Add step to create `CoMaps-ios.xcframework.zip`
- [ ] Add step to create `CoMaps-macos.xcframework.zip`
- [ ] Add step to compute SHA256 checksums
- [ ] Add step to update `Package.swift` with checksums
- [ ] Update release artifact list

### Phase 5: macOS Support

- [ ] Repeat Phase 1-3 for `macos/` directory
- [ ] Create `macos/agus_maps_flutter/Package.swift`
- [ ] Verify macOS-specific code paths

### Phase 6: Testing

- [ ] Test CocoaPods build (SwiftPM disabled)
- [ ] Test SwiftPM build (SwiftPM enabled)
- [ ] Test on iOS Simulator
- [ ] Test on iOS Device
- [ ] Test on macOS
- [ ] Test example app with both configurations

### Phase 7: Documentation

- [ ] Update README.md with SwiftPM instructions
- [ ] Update GUIDE.md with SwiftPM architecture
- [ ] Update CONTRIBUTING.md
- [ ] Add CHANGELOG.md entry for vX.Y.Z


## CI/CD Changes

### New Release Artifacts

| Artifact | Description | Used By |
|----------|-------------|---------|
| `agus-maps-sdk-vX.Y.Z.zip` | Full SDK (all platforms) | CocoaPods consumers, Android, Linux, Windows |
| `CoMaps-ios.xcframework.zip` | iOS framework only | SwiftPM (iOS) |
| `CoMaps-macos.xcframework.zip` | macOS framework only | SwiftPM (macOS) |

### Checksum Management Strategy

**Option A: Two-Phase Release (Recommended)**

1. **Pre-release tag** (`vX.Y.Z-rc1`):
   - Build XCFrameworks
   - Upload ZIPs to pre-release
   - Compute checksums
   - Update `Package.swift` with checksums
   - Commit checksum update

2. **Final release tag** (`vX.Y.Z`):
   - Tag the commit with updated checksums
   - Move artifacts from pre-release to final release
   - Delete pre-release

**Option B: Checksum File**

Store checksums in a separate file that CI updates:

```
ios/agus_maps_flutter/checksums.json
{
  "ios": "abc123...",
  "macos": "def456..."
}
```

Then in `Package.swift`:

```swift
// Read checksum from file at build time
// NOTE: This doesn't work - SwiftPM doesn't support dynamic checksums
```

**Verdict:** Option A is the only viable approach.

### Updated Workflow Steps

```yaml
# .github/workflows/devops.yml (additions)

- name: Create iOS XCFramework ZIP for SwiftPM
  run: |
    cd build/ios
    zip -r CoMaps-ios.xcframework.zip CoMaps.xcframework
    shasum -a 256 CoMaps-ios.xcframework.zip > CoMaps-ios.xcframework.zip.sha256

- name: Create macOS XCFramework ZIP for SwiftPM  
  run: |
    cd build/macos
    zip -r CoMaps-macos.xcframework.zip CoMaps.xcframework
    shasum -a 256 CoMaps-macos.xcframework.zip > CoMaps-macos.xcframework.zip.sha256

- name: Update Package.swift Checksums
  run: |
    IOS_CHECKSUM=$(cat build/ios/CoMaps-ios.xcframework.zip.sha256 | awk '{print $1}')
    MACOS_CHECKSUM=$(cat build/macos/CoMaps-macos.xcframework.zip.sha256 | awk '{print $1}')
    
    sed -i "s/PLACEHOLDER_IOS_CHECKSUM/${IOS_CHECKSUM}/" ios/agus_maps_flutter/Package.swift
    sed -i "s/PLACEHOLDER_MACOS_CHECKSUM/${MACOS_CHECKSUM}/" macos/agus_maps_flutter/Package.swift
    
    git add ios/agus_maps_flutter/Package.swift macos/agus_maps_flutter/Package.swift
    git commit -m "chore: update SwiftPM checksums for ${GITHUB_REF_NAME}"
    git push
```


## Migration Path

### For Existing CocoaPods Users (v0.1.7 → vX.Y.Z)

**No changes required.** CocoaPods workflow remains identical:

```bash
export AGUS_MAPS_HOME=/path/to/agus-maps-sdk-vX.Y.Z
flutter clean && flutter run
```

### For New Users Adopting SwiftPM

1. Ensure Flutter 3.24+ with SwiftPM enabled:
   ```bash
   flutter config --enable-swift-package-manager
   ```

2. Add dependency (no AGUS_MAPS_HOME needed):
   ```yaml
   dependencies:
     agus_maps_flutter: ^X.Y.Z
   ```

3. Copy assets to app (still required):
   ```bash
   # Download SDK for assets only
   curl -LO https://github.com/.../agus-maps-sdk-vX.Y.Z.zip
   unzip agus-maps-sdk-vX.Y.Z.zip -d /tmp/sdk
   cp -r /tmp/sdk/assets/* my_app/assets/
   ```

4. Build:
   ```bash
   flutter run
   ```

### Switching from SwiftPM to CocoaPods

If a user needs `AGUS_MAPS_HOME` after starting with SwiftPM:

```yaml
# pubspec.yaml
flutter:
  disable-swift-package-manager: true
```

```bash
# Remove SwiftPM integration
cd ios && rm -rf .build .swiftpm
cd macos && rm -rf .build .swiftpm

# Set up CocoaPods
export AGUS_MAPS_HOME=/path/to/sdk
flutter clean && flutter run
```


## Risk Assessment

### High Risk

| Risk | Impact | Mitigation |
|------|--------|------------|
| Checksum update fails in CI | Release broken | Two-phase release with verification step |
| Obj-C++ target linking issues | Build failures | Extensive testing on multiple Xcode versions |
| Resource loading differs | Runtime crashes | `#if SWIFT_PACKAGE` guards everywhere |

### Medium Risk

| Risk | Impact | Mitigation |
|------|--------|------------|
| SwiftPM resolution slow (~50MB download) | Poor DX | Document expected times; consider CDN |
| CocoaPods regressions | Existing users affected | Run both validation paths in CI |
| Xcode version incompatibilities | Build failures | Test on Xcode 15, 16 |

### Low Risk

| Risk | Impact | Mitigation |
|------|--------|------------|
| File path conflicts | Build warnings | Careful directory naming |
| Documentation confusion | User frustration | Clear separation in docs |


## Open Questions

### Q1: Should we support `darwin` unified package?

Flutter supports a `darwin/` directory for code shared between iOS and macOS. Our implementations are currently separate.

**Options:**
- A) Keep separate `ios/` and `macos/` (current)
- B) Create unified `darwin/` package with platform conditionals

**Recommendation:** Keep separate for vX.Y.Z. Unification can be v0.2.0.

### Q2: How to handle assets for SwiftPM users?

SwiftPM handles the XCFramework, but assets (`comaps_data/`, `maps/`) must still be copied manually.

**Options:**
- A) Keep current: User downloads full SDK, copies assets
- B) Create separate assets-only package
- C) Publish assets as SwiftPM resource bundle

**Recommendation:** Option A for vX.Y.Z. Document clearly.

### Q3: Minimum iOS/macOS version for SwiftPM?

Current podspec specifies iOS 15.6 and macOS 12.0. SwiftPM package must match.

**Decision needed:** Can we lower minimums for SwiftPM, or must they stay aligned?

### Q4: Should SwiftPM be the default?

Once SwiftPM support is added, Flutter will prefer it over CocoaPods.

**Implications:**
- New users automatically get SwiftPM (auto-download)
- Existing users with `AGUS_MAPS_HOME` must add `disable-swift-package-manager: true`

**Recommendation:** Yes, let SwiftPM be default. Document the opt-out for AGUS_MAPS_HOME users.


## References

### Flutter Documentation
- [Swift Package Manager for plugin authors](https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-plugin-authors)
- [Swift Package Manager for app developers](https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-app-developers)

### Apple Documentation
- [PackageDescription](https://developer.apple.com/documentation/packagedescription)
- [Bundling Resources with a Swift Package](https://developer.apple.com/documentation/xcode/bundling-resources-with-a-swift-package)
- [Distributing Binary Frameworks as Swift Packages](https://developer.apple.com/documentation/xcode/distributing-binary-frameworks-as-swift-packages)

### Related Issues
- Flutter SwiftPM tracking: [flutter/flutter#126005](https://github.com/flutter/flutter/issues/126005)


## Appendix A: Module Map Template

```c
// ios/agus_maps_flutter/Sources/AgusObjC/include/module.modulemap
module AgusObjC {
    header "AgusMetalContextFactory.h"
    header "AgusPlatformIOS.h"
    
    export *
}
```

## Appendix B: Bridging Header Alternative

If module maps prove problematic, we can use a bridging header approach:

```swift
// Sources/agus_maps_flutter/Bridging-Header.h
#import "AgusMetalContextFactory.h"
#import "AgusPlatformIOS.h"
```

Note: SwiftPM doesn't officially support bridging headers, but some workarounds exist.


## Changelog

| Date | Author | Changes |
|------|--------|---------|
| 2026-01-09 | Agus Maps Team | Initial draft |
