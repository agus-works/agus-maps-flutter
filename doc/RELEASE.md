# Agus Maps Flutter - Release Guide

This guide explains how to use the pre-built artifacts from GitHub Releases.

## Release Artifacts

Each release includes the following artifacts:

### Plugin Binaries (Unified Package)

| Artifact | Description | Size (approx) |
|----------|-------------|---------------|
| **`agus-maps-binaries-vX.Y.Z.zip`** | **All platform binaries, assets, and headers** | ~500 MB |

The unified package contains everything needed for all platforms:
- Android native libraries (arm64-v8a, armeabi-v7a, x86_64)
- iOS XCFramework
- macOS XCFramework  
- Windows DLLs (x64)
- Linux shared libraries (x86_64)
- CoMaps data files and ICU data
- C++ headers (for building from source)

> **💡 Recommended:** Download only `agus-maps-binaries-vX.Y.Z.zip` and extract it into the plugin root. This places all binaries in the correct locations with a single extraction.

> **Note:** Headers are included for developers who need to build from source. Typical plugin consumers using pre-built binaries do **NOT** need headers - the pre-compiled native libraries are ready to use.

### Example Apps

| Artifact | Description | Size (approx) |
|----------|-------------|---------------|
| `agus-maps-android.apk` | Universal APK (direct install) | ~80 MB |
| `agus-maps-android.aab` | Android App Bundle (Play Store) | ~50 MB |
| `agus-maps-ios-simulator.app.zip` | iOS Simulator app (debug) | ~100 MB |
| `agus-maps-macos.app.zip` | macOS app (release) | ~100 MB |
| `agus-maps-windows.zip` | Windows app (release, x86_64) | ~150 MB |
| `agus-maps-linux.zip` | Linux app (release, x86_64) | ~100 MB |

---

## Installing the Example App

### Android

#### Option 1: Install APK via ADB (Recommended)

1. **Enable Developer Options** on your Android device:
   - Go to **Settings > About Phone**
   - Tap **Build Number** 7 times
   - Go back to **Settings > Developer Options**
   - Enable **USB Debugging**

2. **Connect your device** via USB and authorize the connection

3. **Install the APK**:
   ```bash
   # Download the APK
   curl -LO https://github.com/agus-works/agus-maps-flutter/releases/latest/download/agus-maps-android.apk
   
   # Install via ADB
   adb install agus-maps-android.apk
   ```

4. **Launch the app**: Find "Agus Maps" in your app drawer

#### Option 2: Install APK directly on device

1. Download `agus-maps-android.apk` on your Android device
2. Open the downloaded file
3. Allow installation from unknown sources if prompted
4. Tap **Install**

#### Option 3: Android Emulator

```bash
# Start an emulator (must have Google Play or be x86_64)
emulator -avd Pixel_6_API_34

# Install the APK
adb install agus-maps-android.apk

# Launch the app
adb shell am start -n app.agus.maps.agus_maps_flutter_example/.MainActivity
```

#### About the AAB (App Bundle)

The `.aab` file is for **Play Store distribution only**. It cannot be installed directly on a device. Use it when:
- Uploading to Google Play Console
- Testing with Play Console's internal testing track

To test an AAB locally, use `bundletool`:
```bash
# Install bundletool
brew install bundletool

# Generate APKs from AAB
bundletool build-apks --bundle=agus-maps-android.aab --output=agus-maps.apks

# Install on connected device
bundletool install-apks --apks=agus-maps.apks
```

---

### iOS Simulator

The iOS build is a **debug build** for the **iOS Simulator only**. It will not run on physical iOS devices (requires code signing).

#### Prerequisites
- macOS with Xcode installed
- iOS Simulator runtime installed

#### Installation Steps

```bash
# 1. Download and extract the app
curl -LO https://github.com/agus-works/agus-maps-flutter/releases/latest/download/agus-maps-ios-simulator.app.zip
unzip agus-maps-ios-simulator.app.zip

# 2. Boot a simulator (if not already running)
xcrun simctl boot "iPhone 15 Pro"

# Or list available simulators and pick one:
xcrun simctl list devices available

# 3. Install the app
xcrun simctl install booted Runner.app

# 4. Launch the app
xcrun simctl launch booted app.agus.maps.agus_maps_flutter_example
```

#### Alternative: Drag and Drop

1. Open **Simulator.app** (from Xcode or Spotlight)
2. Extract `agus-maps-ios-simulator.app.zip`
3. Drag `Runner.app` onto the simulator window
4. The app will be installed and appear on the home screen

#### Troubleshooting

**"App cannot be installed"**: The simulator architecture must match. Our build supports:
- `x86_64` (Intel Macs)
- `arm64` (Apple Silicon Macs)

**"Unable to boot"**: Try a different simulator:
```bash
# List all available simulators
xcrun simctl list devices

# Boot a specific one
xcrun simctl boot "iPhone 14"
```

---

### macOS

The macOS app is an **unsigned release build**. It will work on macOS 12.0 (Monterey) or later.

> ⚠️ **Note for macOS Beta Users:** Pre-built releases are compiled on macOS 15.x (Sequoia). If you're running a macOS beta (e.g., macOS 26 Tahoe), the pre-built app may not launch due to Flutter VM snapshot compatibility issues. In this case, [build from source](#building-from-source) on your machine.

#### Installation Steps

```bash
# 1. Download and extract
curl -LO https://github.com/agus-works/agus-maps-flutter/releases/latest/download/agus-maps-macos.app.zip
unzip agus-maps-macos.app.zip

# 2. Remove quarantine attribute (required for unsigned apps)
xattr -cr agus_maps_flutter_example.app

# 3. Run the app
open agus_maps_flutter_example.app
```

#### Alternative: Finder

1. Download `agus-maps-macos.app.zip`
2. Double-click to extract
3. Right-click on `agus_maps_flutter_example.app` and select **Open**
4. Click **Open** in the security dialog

#### Gatekeeper Warning

Since the app is unsigned, macOS will show a security warning. To bypass:

1. **First attempt**: Right-click > Open > Open
2. **If blocked**: Go to **System Preferences > Security & Privacy > General** and click **Open Anyway**

#### Requirements

- macOS 12.0 (Monterey) or later
- Apple Silicon (M1/M2/M3) or Intel Mac
- ~500 MB free disk space for map data

---

### Windows (x86_64)

The Windows app is an **unsigned release build** for **x86_64 (64-bit Intel/AMD)** systems.

> ⚠️ **Architecture Note:** Only x86_64 is supported. ARM64 Windows (Snapdragon X, etc.) is not currently supported due to lack of testing hardware.

#### Installation Steps

```powershell
# 1. Download and extract
# Using PowerShell or download from browser
Invoke-WebRequest -Uri "https://github.com/agus-works/agus-maps-flutter/releases/latest/download/agus-maps-windows.zip" -OutFile "agus-maps-windows.zip"
Expand-Archive -Path "agus-maps-windows.zip" -DestinationPath "agus-maps-windows"

# 2. Run the app
.\agus-maps-windows\agus_maps_flutter_example.exe
```

#### Alternative: File Explorer

1. Download `agus-maps-windows.zip` from the [releases page](https://github.com/agus-works/agus-maps-flutter/releases)
2. Right-click and select **Extract All...**
3. Navigate to the extracted folder
4. Double-click `agus_maps_flutter_example.exe`

#### Windows Defender SmartScreen

Since the app is unsigned, Windows may show a SmartScreen warning:

1. Click **More info**
2. Click **Run anyway**

#### Requirements

- Windows 10 or later (64-bit x86_64 only)
- ~500 MB free disk space for map data
- OpenGL 2.0+ compatible graphics driver
- Visual C++ Redistributable (usually pre-installed)

#### Known Limitations

- **Not zero-copy rendering**: Windows uses CPU-mediated frame transfer (glReadPixels). This may result in slightly higher CPU usage during map animations compared to iOS/macOS/Android.
- **ARM64 not supported**: ARM64 Windows devices (Snapdragon X, etc.) are not supported.

---

### Windows Troubleshooting

| Issue | Solution |
|-------|----------|
| "VCRUNTIME140.dll not found" | Install [Visual C++ Redistributable](https://aka.ms/vs/17/release/vc_redist.x64.exe) |
| App won't start | Ensure you're on x86_64 Windows, not ARM64 |
| Blank/white map | Check map data files exist in `Documents\agus_maps_flutter\` |
| Poor performance | Update graphics drivers; ensure hardware OpenGL is available |

---

### Linux (x86_64)

The Linux app is a **release build** for **x86_64 (64-bit Intel/AMD)** systems. Tested on Ubuntu 22.04+ with Mesa drivers.

> ⚠️ **Architecture Note:** Only x86_64 is supported. ARM64 Linux is not currently supported.

#### Prerequisites

- Ubuntu 22.04+ or equivalent (Debian, Fedora, etc.)
- OpenGL ES 3.0 or OpenGL 3.2+ support (Mesa or proprietary drivers)
- GTK 3 runtime libraries

Install required runtime dependencies:
```bash
# Ubuntu/Debian
sudo apt-get install libgtk-3-0 libgl1 libegl1 libepoxy0

# Fedora
sudo dnf install gtk3 mesa-libGL mesa-libEGL libepoxy
```

#### Installation Steps

```bash
# 1. Download and extract
curl -LO https://github.com/agus-works/agus-maps-flutter/releases/latest/download/agus-maps-linux.zip
unzip agus-maps-linux.zip -d agus-maps-linux

# 2. Run the app
cd agus-maps-linux
./agus_maps_flutter_example
```

#### Alternative: File Manager

1. Download `agus-maps-linux.zip` from the [releases page](https://github.com/agus-works/agus-maps-flutter/releases)
2. Right-click and select **Extract Here** or use your archive manager
3. Navigate to the extracted folder
4. Double-click `agus_maps_flutter_example` (may require marking as executable)

#### Making the App Executable

If the app doesn't run when double-clicked:
```bash
chmod +x agus_maps_flutter_example
./agus_maps_flutter_example
```

#### Requirements

- Linux x86_64 (Ubuntu 22.04+ recommended)
- ~500 MB free disk space for map data
- OpenGL ES 3.0 or OpenGL 3.2+ compatible graphics driver
- GTK 3 runtime libraries

#### Known Limitations

- **Not zero-copy rendering**: Linux uses CPU-mediated frame transfer (glReadPixels) similar to Windows. This may result in slightly higher CPU usage during map animations.
- **ARM64 not supported**: ARM64 Linux devices are not supported.
- **Wayland**: The app runs under XWayland on Wayland systems. Native Wayland support is pending Flutter upstream.

---

### Linux Troubleshooting

| Issue | Solution |
|-------|----------|
| "error while loading shared libraries" | Install missing libraries with `apt-get install libgtk-3-0 libepoxy0` |
| App won't start | Ensure you have OpenGL support: `glxinfo \| grep "OpenGL version"` |
| Blank/white map | Check map data files exist in `~/.local/share/agus_maps_flutter/` |
| Poor performance | Update Mesa drivers: `sudo apt-get upgrade mesa-*` |
| Permission denied | Run `chmod +x agus_maps_flutter_example` |

---

## Using Pre-built Libraries in Your Project

If you're integrating the Agus Maps Flutter plugin into your own project, the native libraries will be downloaded automatically during the build process.

### How It Works

#### iOS (CocoaPods)

The `agus_maps_flutter.podspec` includes a `prepare_command` that:
1. Downloads `agus-binaries-ios.zip` from the latest GitHub release
2. Extracts the XCFramework to `ios/Frameworks/`
3. Links against the pre-built libraries

No manual steps required - just run `pod install`.

#### Android (Gradle)

The `android/build.gradle` includes a task that:
1. Downloads `agus-binaries-android.zip` from the latest GitHub release
2. Extracts native libraries to `android/prebuilt/`
3. Includes them in the APK via `jniLibs`

No manual steps required - the Gradle sync handles everything.

### Unified Binary Package (Recommended)

The easiest way to set up all pre-built binaries at once is to use the **unified binary package**. This single zip file contains all platform binaries structured so that extracting it into the plugin root places everything in the correct locations.

```bash
# Set the version
VERSION="v0.0.30"

# Download the unified package
curl -LO "https://github.com/agus-works/agus-maps-flutter/releases/download/${VERSION}/agus-maps-binaries-${VERSION}.zip"

# Navigate to your local/vendored copy of the plugin
cd path/to/agus_maps_flutter

# Extract - everything falls into place!
unzip agus-maps-binaries-${VERSION}.zip
```

After extraction, you'll have:
```
agus_maps_flutter/
├── android/prebuilt/
│   ├── arm64-v8a/libagus_maps_flutter.so
│   ├── armeabi-v7a/libagus_maps_flutter.so
│   └── x86_64/libagus_maps_flutter.so
├── ios/Frameworks/
│   └── CoMaps.xcframework/
├── macos/Frameworks/
│   └── CoMaps.xcframework/
├── windows/prebuilt/x64/
│   ├── agus_maps_flutter.dll
│   └── zlib1.dll
├── linux/prebuilt/x86_64/
│   └── libagus_maps_flutter.so
├── assets/
│   ├── comaps_data/
│   │   └── ... (CoMaps resource files)
│   └── maps/
│       └── icudt75l.dat
└── headers/              # For building from source (optional)
    └── ... (C++ headers)
```

> **Note:** The `headers/` directory is only needed if you're building native code from source. For typical plugin consumers using pre-built binaries, headers can be ignored or deleted.

---

## Map Data

# Download Windows libraries
curl -LO "https://github.com/agus-works/agus-maps-flutter/releases/download/${VERSION}/agus-binaries-windows.zip"
unzip agus-binaries-windows.zip -d windows/prebuilt/
```

---

## Map Data

The example app includes minimal map data for testing. For production use, you'll need to:

1. Download `.mwm` map files from [OpenStreetMap data sources](https://download.geofabrik.de/)
2. Place them in the app's documents directory
3. The app will automatically detect and load available maps

### Data Directory Structure

```
<app_documents>/
├── fonts/           # Required TrueType fonts
├── resources/       # Classification and style data
│   ├── classificator.txt
│   ├── colors.txt
│   ├── countries.txt
│   ├── drules_proto_clear.bin
│   └── ...
└── maps/            # Downloaded .mwm files
    ├── World.mwm
    ├── WorldCoasts.mwm
    └── <region>.mwm
```

---

## Troubleshooting

### Android

| Issue | Solution |
|-------|----------|
| "App not installed" | Enable "Install from unknown sources" in settings |
| ADB device not found | Run `adb devices` and check USB debugging is enabled |
| App crashes on launch | Check logcat: `adb logcat -s Flutter` |

### iOS Simulator

| Issue | Solution |
|-------|----------|
| "Unable to install" | Ensure simulator is booted: `xcrun simctl boot "iPhone 15"` |
| Wrong architecture | Use an arm64 simulator on Apple Silicon Macs |
| App won't launch | Check Console.app for crash logs |

### macOS

| Issue | Solution |
|-------|----------|
| "App is damaged" | Run `xattr -cr <app_name>.app` |
| "Cannot verify developer" | Right-click > Open > Open |
| Blank map | Ensure map data files are in place |

---

## Building from Source

If you prefer to build from source instead of using pre-built binaries:

**Linux:**
```bash
# Clone the repository
git clone https://github.com/agus-works/agus-maps-flutter.git
cd agus-maps-flutter

# Install dependencies
sudo apt-get install build-essential cmake ninja-build libgtk-3-dev libepoxy-dev libegl-dev

# Fetch CoMaps source
./scripts/apply_comaps_patches.sh

# Build for Linux
cd example
flutter build linux        # Linux
```

**macOS:**
```bash
# Clone the repository
git clone https://github.com/agus-works/agus-maps-flutter.git
cd agus-maps-flutter

# Bootstrap (fetches CoMaps, applies patches, builds boost)
./scripts/bootstrap.sh

# Build for your platform
cd example
flutter build apk          # Android
flutter build ios          # iOS (requires Xcode)
flutter build macos        # macOS
```

**Windows PowerShell:**
```powershell
# Clone the repository
git clone https://github.com/agus-works/agus-maps-flutter.git
cd agus-maps-flutter

# Bootstrap (fetches CoMaps, applies patches)
.\scripts\bootstrap.ps1

# Build for your platform
cd example
flutter build apk          # Android (requires Android SDK + NDK)
flutter build windows      # Windows
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed build instructions.

---

## Version History

See [CHANGELOG.md](../CHANGELOG.md) for release notes and version history.
