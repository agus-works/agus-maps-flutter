# Agus Maps Example App

This example application demonstrates the capabilities of the `agus_maps_flutter` plugin. It serves as a complete reference implementation for building an offline map application with map downloading, storage management, and rendering features.


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
  <tr>
    <td align="center" width="50%">
      <a href="https://youtu.be/Uxb_1o9dFao">
        <img src="https://img.youtube.com/vi/Uxb_1o9dFao/maxresdefault.jpg" alt="Linux Demo" width="100%">
        <br><strong>🐧 Linux</strong>
      </a>
    </td>
    <td width="50%"></td>
  </tr>
</table>

## Features

The `agus_maps_flutter` plugin and this example app demonstrate:

- 🚀 **Zero-Copy Rendering** — Map data flows directly from disk to GPU via memory-mapping (iOS, macOS, Android)
- 🖥️ **Windows Support** — Full Windows x86_64 support with optimized CPU-mediated rendering
- 📴 **Fully Offline** — No internet required; uses compact MWM map files from OpenStreetMap
- 🎯 **Native Performance** — The battle-tested Drape engine from Organic Maps
- 🖐️ **Gesture Support** — Pan, pinch-to-zoom, rotation (multitouch)
- 🖱️ **macOS Trackpad Zoom** — Pinch or two-finger parallel swipe (Google Maps-style) with cursor-centered zoom
- 📐 **Responsive** — Automatically handles resize and device pixel ratio
- 🔍 **DPI-Aware Label Scaling** — Adjustable map label scale with persistent settings
- 🔌 **Simple API** — Drop-in `AgusMap` widget with `AgusMapController`
- **Fuzzy Search API** — Fast offline search logic for finding map regions

## Demonstrated Features

The example app implements a full-featured map viewer including:

- **Map Download Manager**: A complete UI to browse, search, and download offline map regions (MWM files) from mirror servers.
- **Disk Space Management**: Real-time monitoring of available storage with safety checks before downloading.
- **Fuzzy Search**: Search for countries and regions with intelligent fuzzy matching.
- **Local Caching**: Management of downloaded region data for instant offline access.
- **Interactive Map**:
  - **Zero-Copy Rendering**: Smooth 60fps rendering using the `AgusMap` widget.
  - **Gesture Support**: Pan, pinch-to-zoom, and rotation.
  - **Trackpad Support**: Native macOS trackpad gestures (pinch/swipe).
- **Responsive UI**: Adapts layout for mobile and desktop window sizes.
- **Settings**: Map label scale slider (persistent) for DPI/visual scaling.

## Getting Started

From the repository root, first build or install the native SDK artifacts. For
contributors working from source, keep `AGUS_MAPS_HOME` unset and build the
platform you are testing:

```bash
env -u AGUS_MAPS_HOME AGUS_MAPS_BUILD_MODE=contributor \
  dart run tool/build.dart --build-binaries --platform ios 2>&1 | tee ./output.log

env -u AGUS_MAPS_HOME AGUS_MAPS_BUILD_MODE=contributor \
  dart run tool/build.dart --build-binaries --platform macos 2>&1 | tee ./output.log
```

Then build the example:

```bash
cd example
flutter pub get 2>&1 | tee ../output.log

# iOS simulator debug build, no launch.
flutter build ios --simulator --debug 2>&1 | tee ../output.log

# macOS debug build, no launch.
flutter build macos --debug 2>&1 | tee ../output.log
```

To run instead of only building:

```bash
flutter run -d "iPhone 15 Pro" --debug 2>&1 | tee ../output.log
flutter run -d macos --debug 2>&1 | tee ../output.log
```

## Code Structure

- **`lib/main.dart`**: Entry point and main layout.
- **`lib/download_manager/`**: UI and logic for browsing and downloading maps.
- **`lib/map_view/`**: Implementation of the `AgusMap` widget and controller.

## Platform Notes

### Android
- Uses `SurfaceTexture` for zero-copy rendering.
- Tested on arm64 and x86_64.

### iOS
- Uses `IOSurface` + `Metal` for zero-copy rendering.
- Requires a physical device or Simulator.
- If Xcode reports missing `ios/Classes/AgusMapsApi.g.swift`, regenerate the
  workspace with `flutter pub get` and `pod install` under `example/ios`.

### macOS
- Proven desktop support with resize capabilities.
- Runtime extraction validates essential CoMaps data such as `subtypes.csv`
  before trusting the extraction marker.

### Windows
- Uses optimized CPU-mediated rendering (OpenGL -> D3D11).
- x86_64 support only.

### Linux
- Experimental support via GTK/GLX.
