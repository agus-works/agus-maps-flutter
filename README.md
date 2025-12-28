<p align="center">
  <img src="./logo.png" width="120" alt="Agus Maps Logo">
</p>

<h1 align="center">Agus Maps Flutter</h1>

<p align="center">
  <strong>High-performance offline maps for Flutter, powered by the CoMaps/Organic Maps rendering engine.</strong>
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#demos">Demos</a> •
  <a href="#quick-start">Quick Start</a> •
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

## Demos

<table>
  <tr>
    <td align="center" width="50%">
      <a href="https://youtu.be/YVaBJ8uW5Ag">
        <img src="https://img.youtube.com/vi/YVaBJ8uW5Ag/maxresdefault.jpg" alt="Android Demo" width="100%">
        <br><strong>📱 Android</strong>
      </a>
    </td>
    <td align="center" width="50%">
      <a href="https://youtu.be/Jt0QE9Umsng">
        <img src="https://img.youtube.com/vi/Jt0QE9Umsng/maxresdefault.jpg" alt="iOS Demo" width="100%">
        <br><strong>📱 iOS</strong>
      </a>
    </td>
  </tr>
  <tr>
    <td align="center" width="50%">
      <a href="https://youtu.be/Gd53HFrAGts">
        <img src="https://img.youtube.com/vi/Gd53HFrAGts/maxresdefault.jpg" alt="macOS Demo" width="100%">
        <br><strong>🖥️ macOS</strong>
      </a>
    </td>
    <td align="center" width="50%">
      <a href="https://youtu.be/SWoLl-700LM">
        <img src="https://img.youtube.com/vi/SWoLl-700LM/maxresdefault.jpg" alt="Windows Demo" width="100%">
        <br><strong>🪟 Windows</strong>
      </a>
    </td>
  </tr>
</table>

---

## Features

- 🚀 **Zero-Copy Rendering** — Map data flows directly from disk to GPU via memory-mapping (iOS, macOS, Android)
- 🖥️ **Windows Support** — Full Windows x86_64 support with optimized CPU-mediated rendering
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

<h2 id="comparison">Comparison with Other Solutions</h2>

| Feature | Agus Maps | flutter_map | google_maps_flutter | mapbox_gl |
|---------|-----------|-------------|---------------------|-----------|
| **Rendering** | Native GPU (zero-copy*) | Dart/Skia | PlatformView | PlatformView |
| **Offline Support** | ✅ Full | ✅ With tiles | ❌ Limited | ✅ With SDK |
| **Performance** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| **Memory Usage** | Very Low | High (GC) | Medium | Medium |
| **License** | Apache 2.0 | BSD | Proprietary | Proprietary |
| **Pricing** | Free | Free | Usage-based | Usage-based |
| **Data Source** | OpenStreetMap | Any tiles | Google | Mapbox |
| **Widget Integration** | ✅ Native | ✅ Native | ⚠️ PlatformView | ⚠️ PlatformView |
| **Platforms** | Android, iOS, macOS, Windows | All | Android, iOS | Android, iOS |

*\*Zero-copy on iOS, macOS, Android. Windows uses optimized CPU-mediated transfer.*

### Platform Support

| Platform | Architecture | Rendering | Zero-Copy |
|----------|--------------|-----------|-----------|
| **iOS** | arm64, x86_64 (sim) | Metal | ✅ Yes (IOSurface) |
| **macOS** | arm64, x86_64 | Metal | ✅ Yes (IOSurface) |
| **Android** | arm64-v8a, armeabi-v7a, x86_64 | OpenGL ES | ✅ Yes (SurfaceTexture) |
| **Windows** | x86_64 only | OpenGL + D3D11 | ❌ No (CPU-mediated) |
| **Linux** | — | — | 🚧 Planned |

> **Windows Note:** ARM64 Windows (Snapdragon X, etc.) is not currently supported due to lack of testing hardware. Contributions welcome!

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
- **Windows not zero-copy** — Windows uses CPU-mediated frame transfer (still performant, ~60fps)
- **Windows x86_64 only** — ARM64 Windows not yet supported
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

### Zero-Copy Architecture (iOS, macOS, Android)

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

### Windows Architecture (x86_64)

Windows uses a different architecture due to OpenGL/D3D11 interop limitations:

```
┌─────────────────────────────────────────────────────────────┐
│ CoMaps (OpenGL via WGL)                                     │
│   ↓ glReadPixels (GPU→CPU, ~2-5ms)                          │
│ CPU Buffer (RGBA→BGRA + Y-flip)                             │
│   ↓ D3D11 staging texture                                   │
│ D3D11 Shared Texture (DXGI handle)                          │
│   ↓ Zero-copy to Flutter                                    │
│ Flutter Texture Widget                                       │
└─────────────────────────────────────────────────────────────┘
   Still achieves 60fps on modern hardware
   ~30-40MB RAM for rendering pipeline
```

> **Note:** While Windows is not true zero-copy, the map data itself (MWM files) still uses memory-mapping. The CPU-mediated transfer only affects the frame display, not the map data loading.

---

## Documentation

| Document | Description |
|----------|-------------|
| [GUIDE.md](GUIDE.md) | Architectural blueprint and design philosophy |
| [docs/ARCHITECTURE-ANDROID.md](docs/ARCHITECTURE-ANDROID.md) | Deep dive: memory efficiency, battery savings, how it works |
| [docs/IMPLEMENTATION-ANDROID.md](docs/IMPLEMENTATION-ANDROID.md) | Android build instructions, debug/release modes |
| [docs/IMPLEMENTATION-WIN.md](docs/IMPLEMENTATION-WIN.md) | Windows build instructions, x86_64 only |
| [docs/RENDER-LOOP.md](docs/RENDER-LOOP.md) | Render loop comparison across all platforms |
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

### ✅ Completed (iOS / macOS)
- Metal-based rendering with zero-copy IOSurface
- CVPixelBuffer texture sharing
- Full gesture support

### ✅ Completed (Windows x86_64)
- WGL/OpenGL rendering to offscreen FBO
- D3D11 shared texture integration
- Mouse gesture support (drag, scroll wheel zoom)
- DPI-aware rendering
- Window resize handling

### 🔄 In Progress
- Animated camera transitions
- UI widgets (compass, scale bar)

### 📋 Planned
- Linux implementation
- Windows ARM64 support (needs testing hardware)
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

