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

## Documentation

| Document | Description |
|----------|-------------|
| [GUIDE.md](GUIDE.md) | Architectural blueprint and design philosophy |
| [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) | Developer setup and contribution guidelines |
| [docs/IMPLEMENTATION-ANDROID.md](docs/IMPLEMENTATION-ANDROID.md) | Android-specific implementation details |
| [example/](example/) | Working demo application |

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

