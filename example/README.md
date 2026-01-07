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

## Demonstrated Features

The example app implements a full-featured map viewer including:

- **Map Download Manager**: A complete UI to browse, search, and download offline map regions (MWM files) from mirror servers.
- **Disk Space Management**: Real-time monitoring of available storage with safety checks before downloading.
- **Fuzzy Search**: Search for countries and regions with intelligent fuzzy matching.
- **Local Caching**: Management of downloaded region data for instant offline access.
- **Interactive Map**:
  - **Zero-Copy Rendering**: Smooth 60fps rendering using the `AgusMap` widget.
  - **Gesture Support**: Pan, pinch-to-zoom, and rotation.
  - **Trackpad Support**: Native MacOS trackpad gestures (pinch/swipe).
- **Responsive UI**: Adapts layout for mobile and desktop window sizes.

## Getting Started

1.  **Get the dependencies**:
    ```bash
    flutter pub get
    ```

2.  **Run the app**:
    ```bash
    flutter run
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

### macOS
- Proven desktop support with resize capabilities.

### Windows
- Uses optimized CPU-mediated rendering (OpenGL -> D3D11).
- x86_64 support only.

### Linux
- Experimental support via GTK/GLX.
