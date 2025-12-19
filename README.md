<p align="center">
  <img src="https://raw.githubusercontent.com/comaps/comaps/HEAD/iphone/Maps/Assets.xcassets/AppIcon.appiconset/icon-1024%401x.png" width="120" alt="Agus Maps Logo">
</p>

<h1 align="center">Agus Maps Flutter</h1>

<p align="center">
  <strong>High-performance offline maps for Flutter, powered by the CoMaps/Organic Maps rendering engine.</strong>
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#quick-start">Quick Start</a> •
  <a href="#development-setup">Dev Setup</a> •
  <a href="#comparison">Comparison</a> •
  <a href="#documentation">Docs</a> •
  <a href="#roadmap">Roadmap</a>
</p>

---

## What is Agus Maps?

Agus Maps Flutter is a **native Flutter plugin** that embeds the powerful [CoMaps](https://github.com/comaps/comaps) (fork of Organic Maps) rendering engine directly into your Flutter app. Unlike tile-based solutions, it renders **vector maps** with zero-copy GPU acceleration, delivering smooth 60fps performance even on low-end devices.

### Why Another Map Plugin?

Most Flutter map solutions either:
- Render tiles in Dart (slow, GC pressure, jank on older devices)
- Use PlatformView embedding (performance overhead, gesture conflicts, "airspace" issues)

**Agus Maps takes a different approach:** The C++ rendering engine draws directly to a GPU texture that Flutter composites natively—no copies, no bridges, no compromises.

---

## Features

- 🚀 **Zero-Copy Rendering** — Map data flows directly from disk to GPU via memory-mapping
- 📴 **Fully Offline** — No internet required; uses compact MWM map files from OpenStreetMap
- 🎯 **Native Performance** — The battle-tested Drape engine from Organic Maps
- 🖐️ **Gesture Support** — Pan, pinch-to-zoom, rotation (multitouch)
- 📐 **Responsive** — Automatically handles resize and device pixel ratio
- 🔌 **Simple API** — Drop-in `AgusMap` widget with `AgusMapController`
- 📥 **Map Download Manager** — Browse and download maps from mirror servers with progress tracking
- 🔍 **Fuzzy Search** — Search for regions with intelligent fuzzy matching
- 💾 **Caching** — Downloaded region data cached locally for instant subsequent loads
- 📊 **Disk Space Management** — Real-time disk space monitoring with safety checks

---

## Quick Start

### Installation

```yaml
dependencies:
  agus_maps_flutter: ^0.1.0
```

### Basic Usage

```dart
import 'package:agus_maps_flutter/agus_maps_flutter.dart';

// Initialize the engine (call once at app startup)
await agus_maps_flutter.initWithPaths(dataPath, dataPath);
agus_maps_flutter.loadMap(mapFilePath);

// Add the map widget
AgusMap(
  initialLat: 36.1408,
  initialLon: -5.3536,
  initialZoom: 14,
  onMapReady: () => print('Map is ready!'),
)
```

### Programmatic Control

```dart
final controller = AgusMapController();

AgusMap(
  controller: controller,
  // ...
)

// Move the map
controller.moveToLocation(40.4168, -3.7038, 12);
```

See the [example app](example/) for a complete working demo.

---

## Development Setup

This section covers how to bootstrap a local build environment from a fresh clone and validate that everything works.

### Prerequisites (All Platforms)

- **Flutter SDK** (3.19+): [Install Flutter](https://docs.flutter.dev/get-started/install)
- **Git**: With SSH keys configured for GitHub (or set `COMAPS_USE_HTTPS=true`)
- **~10GB free disk space**: For CoMaps source and build artifacts

Verify your Flutter installation:

```bash
flutter doctor
```

---

### 🤖 Android (Available Now)

Fully supported and tested on Samsung Galaxy S10 and similar devices.

#### Prerequisites

- **Android Studio** (2023.1+) with:
  - Android SDK (API 24+)
  - Android NDK (r25c or later, installed via SDK Manager)
  - CMake (3.22+, installed via SDK Manager)
- **Java 17** (bundled with Android Studio or install separately)

#### Step 1: Clone the Repository

```bash
git clone git@github.com:comaps/agus_maps_flutter.git
cd agus_maps_flutter
```

Or using HTTPS:

```bash
git clone https://github.com/comaps/agus_maps_flutter.git
cd agus_maps_flutter
```

#### Step 2: Bootstrap Native Dependencies

This fetches CoMaps, applies patches, and prepares assets:

```bash
./scripts/bootstrap_android.sh
```

**What this does:**
- Clones CoMaps into `./thirdparty/comaps` (tagged release)
- Applies patches from `./patches/comaps`
- Builds Boost headers
- Copies font assets to the example app

> **Note:** First run takes 5-10 minutes (large repo + submodules). Subsequent runs are fast.

#### Step 3: Copy CoMaps Data Files

```bash
./scripts/copy_comaps_data.sh
```

This copies essential map data files (classificator, styles, symbols) to the example app assets.

#### Step 4: Get Flutter Dependencies

```bash
cd example
flutter pub get
```

#### Step 5: Connect Your Device

1. Enable **Developer Options** on your Android device
2. Enable **USB Debugging**
3. Connect via USB and authorize the connection

Verify device is connected:

```bash
flutter devices
```

You should see your device listed (e.g., `SM G973F (mobile) • XXXXXXXXXX • android-arm64`).

#### Step 6: Run the Example App

```bash
# From the example/ directory
flutter run
```

**First build takes 10-20 minutes** (compiles CoMaps C++ engine via CMake/NDK). Subsequent builds are incremental and much faster.

#### Validation Checklist

Once the app launches on your device, verify:

- [ ] **Map renders** — You should see the Gibraltar map (or world view)
- [ ] **Pan gesture works** — Drag to move the map
- [ ] **Pinch-to-zoom works** — Two-finger zoom in/out
- [ ] **Downloads tab** — Can browse available regions
- [ ] **No crashes** — Check `flutter logs` for errors

#### Troubleshooting

| Issue | Solution |
|-------|----------|
| `NDK not found` | Install NDK via Android Studio > SDK Manager > SDK Tools |
| `CMake error` | Install CMake 3.22+ via SDK Manager |
| Build fails on Boost | Delete `thirdparty/comaps/3party/boost/boost` and re-run bootstrap |
| `INSTALL_FAILED_INSUFFICIENT_STORAGE` | Free space on device or use `flutter clean` |
| App crashes on launch | Check `adb logcat` for native crashes; ensure data files copied |

#### Development Workflow

After initial setup, the typical workflow is:

```bash
# Make changes to Dart code
flutter run  # Hot reload works!

# Make changes to C++ code (src/)
flutter clean && flutter run  # Full rebuild needed

# Update CoMaps version
COMAPS_TAG=v2025.xx.xx ./scripts/fetch_comaps.sh
./scripts/apply_comaps_patches.sh
flutter clean && flutter run
```

---

### 🍎 iOS / macOS

> **🚧 Coming Soon**
>
> iOS and macOS support is planned. The architecture will mirror Android:
> - Metal-based rendering to Flutter Texture
> - CocoaPods integration via `ios/agus_maps_flutter.podspec`
> - Same Dart API surface
>
> Track progress in the [Roadmap](#roadmap) section.

---

### 🪟 Windows

> **🚧 Coming Soon**
>
> Windows support is planned with:
> - OpenGL/ANGLE rendering to Flutter Texture
> - CMake-based build integration
> - Same Dart API surface
>
> Track progress in the [Roadmap](#roadmap) section.

---

### 🐧 Linux

> **🚧 Coming Soon**
>
> Linux support is planned with:
> - OpenGL rendering to Flutter Texture
> - CMake-based build integration
> - Same Dart API surface
>
> Track progress in the [Roadmap](#roadmap) section.

---

<h2 id="comparison">Comparison with Other Solutions</h2>

| Feature | Agus Maps | flutter_map | google_maps_flutter | mapbox_gl |
|---------|-----------|-------------|---------------------|-----------|
| **Rendering** | Native GPU (zero-copy) | Dart/Skia | PlatformView | PlatformView |
| **Offline Support** | ✅ Full | ✅ With tiles | ❌ Limited | ✅ With SDK |
| **Performance** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| **Memory Usage** | Very Low | High (GC) | Medium | Medium |
| **License** | Apache 2.0 | BSD | Proprietary | Proprietary |
| **Pricing** | Free | Free | Usage-based | Usage-based |
| **Data Source** | OpenStreetMap | Any tiles | Google | Mapbox |
| **Widget Integration** | ✅ Native | ✅ Native | ⚠️ PlatformView | ⚠️ PlatformView |

### Pros ✅

- **Truly offline** — No API keys, no usage limits, no internet dependency
- **Best-in-class performance** — The same engine that powers Organic Maps (20M+ users)
- **Privacy-first** — No telemetry, no tracking, data stays on device
- **Compact map files** — Entire countries in tens of MB (Germany ~800MB, Gibraltar ~1MB)
- **Free forever** — Open source, Apache 2.0 license
- **Flutter-native composition** — No PlatformView overhead, works perfectly with overlays

### Cons ⚠️

- **Limited styling** — Uses Organic Maps' cartographic style (not customizable yet)
- **No real-time traffic** — Offline-first design means no live data
- **Android-only (currently)** — iOS, desktop platforms are planned but not yet implemented
- **MWM format required** — Must use pre-generated map files (not arbitrary tile servers)
- **Early stage** — Search and routing APIs not yet exposed

---

## Why It's Efficient

Agus Maps achieves excellent performance on older devices (tested on Samsung Galaxy S10) through architectural choices that minimize resource usage:

| Aspect | How We Achieve It | Learn More |
|--------|-------------------|------------|
| **Memory** | Memory-mapped files (mmap) — only viewed tiles loaded into RAM | [Details](docs/ARCHITECTURE-ANDROID.md#memory-efficiency) |
| **Battery** | Event-driven rendering — CPU/GPU sleep when map is idle | [Details](docs/ARCHITECTURE-ANDROID.md#battery-efficiency) |
| **CPU** | Multi-threaded — heavy work on background threads, UI never blocked | [Details](docs/ARCHITECTURE-ANDROID.md#processor-efficiency) |
| **Startup** | One-time asset extraction, cached on subsequent launches | [Details](docs/IMPLEMENTATION-ANDROID.md) |

```
Traditional Map App          Agus Maps
┌─────────────────┐         ┌─────────────────┐
│ Download tiles  │         │ Load from disk  │
│ Decode images   │         │ (memory-mapped) │
│ Store in RAM    │         │ Direct to GPU   │
│ Copy to GPU     │         │                 │
│ Render          │         │ Render          │
└─────────────────┘         └─────────────────┘
   ~100MB RAM                  ~20MB RAM
   Always polling              Sleep when idle
```

---

## Documentation

| Document | Description |
|----------|-------------|
| [GUIDE.md](GUIDE.md) | Architectural blueprint and design philosophy |
| [docs/ARCHITECTURE-ANDROID.md](docs/ARCHITECTURE-ANDROID.md) | Deep dive: memory efficiency, battery savings, how it works |
| [docs/IMPLEMENTATION-ANDROID.md](docs/IMPLEMENTATION-ANDROID.md) | Build instructions, debug/release modes, acceptance criteria |
| [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) | Developer setup, commit guidelines, known issues |
| [example/](example/) | Working demo application with downloads manager |

### Technical Deep Dives

For those who want to understand *why* Agus Maps is efficient:

- **[How Memory Mapping Works](docs/ARCHITECTURE-ANDROID.md#memory-efficiency)** — Why we use 10x less RAM than tile-based solutions
- **[Battery Efficiency](docs/ARCHITECTURE-ANDROID.md#battery-efficiency)** — Event-driven rendering that sleeps when idle
- **[Multi-threaded Architecture](docs/ARCHITECTURE-ANDROID.md#processor-efficiency)** — How we keep the UI thread responsive
- **[Old Phone Compatibility](docs/ARCHITECTURE-ANDROID.md#why-this-works-on-older-phones)** — Tested on Samsung Galaxy S10 and similar devices

### Known Issues & Optimization Opportunities

We track efficiency-related issues in dedicated files. See [CONTRIBUTING.md](docs/CONTRIBUTING.md#known-issues) for the full list, including:

- Debug logging overhead in release builds
- EGL context recreation on app resume
- Touch event throttling considerations

---

## Roadmap

### ✅ Completed (Android)
- Native rendering to Flutter Texture
- Touch gesture forwarding (pan, zoom)
- Viewport resize handling with proper DPI scaling
- Basic Dart API (`AgusMap`, `AgusMapController`)
- Map Download Manager with mirror selection
- Region caching for instant loads
- Fuzzy search for region browsing
- Disk space detection and safety checks
- MWM registration API for dynamic map loading

### 🔄 In Progress
- Animated camera transitions
- UI widgets (compass, scale bar)

### 📋 Planned
- iOS / macOS implementation
- Linux / Windows implementation  
- Search API integration
- Routing API integration
- POI tap callbacks
- Map deletion/management

---

## Map Data

Agus Maps uses MWM files from OpenStreetMap. You can download maps from:
- [Organic Maps Downloads](https://organicmaps.app/downloads/)
- [CoMaps Mirror](https://omaps.webfreak.org/)
- **In-app**: Use the built-in Downloads tab to browse and download regions

The example app bundles a small Gibraltar map for testing.

---

## License

```
Apache License 2.0

Copyright 2024 Agus App

Licensed under the Apache License, Version 2.0
```

This project incorporates code from [CoMaps](https://github.com/comaps/comaps) (Apache 2.0) and [Organic Maps](https://github.com/organicmaps/organicmaps) (Apache 2.0).

---

<p align="center">
  <sub>Built with ❤️ for the Flutter community</sub>
</p>

