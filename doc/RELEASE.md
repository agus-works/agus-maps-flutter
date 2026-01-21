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

All example app artifacts include the version tag in the filename (e.g., `-vX.Y.Z`):

| Artifact | Description | Size (approx) |
|----------|-------------|---------------|
| `agus-maps-android-vX.Y.Z.apk` | Universal APK (direct install) | ~80 MB |
| `agus-maps-android-vX.Y.Z.aab` | Android App Bundle (Play Store) | ~50 MB |
| `agus-maps-ios-simulator-vX.Y.Z.app.zip` | iOS Simulator app (debug) | ~100 MB |
| `agus-maps-macos-vX.Y.Z.app.zip` | macOS app (release) | ~100 MB |
| `agus-maps-windows-vX.Y.Z.zip` | Windows app (release, x86_64) | ~150 MB |
| `agus-maps-linux-vX.Y.Z.zip` | Linux app (release, x86_64) | ~100 MB |


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
   # Download the APK (replace vX.Y.Z with actual version)
   curl -LO https://github.com/agus-works/agus-maps-flutter/releases/latest/download/agus-maps-android-vX.Y.Z.apk
   
   # Install via ADB
   adb install agus-maps-android-vX.Y.Z.apk
   ```

4. **Launch the app**: Find "Agus Maps" in your app drawer

#### Option 2: Install APK directly on device

1. Download `agus-maps-android-vX.Y.Z.apk` on your Android device
2. Open the downloaded file
3. Allow installation from unknown sources if prompted
4. Tap **Install**

#### Option 3: Android Emulator

```bash
# Start an emulator (must have Google Play or be x86_64)
emulator -avd Pixel_6_API_34

# Install the APK (replace vX.Y.Z with actual version)
adb install agus-maps-android-vX.Y.Z.apk

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

# Generate APKs from AAB (replace vX.Y.Z with actual version)
bundletool build-apks --bundle=agus-maps-android-vX.Y.Z.aab --output=agus-maps.apks

# Install on connected device
bundletool install-apks --apks=agus-maps.apks
```


### iOS Simulator

The iOS build is a **debug build** for the **iOS Simulator only**. It will not run on physical iOS devices (requires code signing).

#### Prerequisites
- macOS with Xcode installed
- iOS Simulator runtime installed

#### Installation Steps

```bash
# 1. Download and extract the app (replace vX.Y.Z with actual version)
curl -LO https://github.com/agus-works/agus-maps-flutter/releases/latest/download/agus-maps-ios-simulator-vX.Y.Z.app.zip
unzip agus-maps-ios-simulator-vX.Y.Z.app.zip

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
2. Extract `agus-maps-ios-simulator-vX.Y.Z.app.zip`
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


### macOS

The macOS app is an **unsigned release build**. It will work on macOS 12.0 (Monterey) or later.

> ⚠️ **Note for macOS Beta Users:** Pre-built releases are compiled on macOS 15.x (Sequoia). If you're running a macOS beta (e.g., macOS 26 Tahoe), the pre-built app may not launch due to Flutter VM snapshot compatibility issues. In this case, [build from source](#building-from-source) on your machine.

#### Installation Steps

```bash
# 1. Download and extract (replace vX.Y.Z with actual version)
curl -LO https://github.com/agus-works/agus-maps-flutter/releases/latest/download/agus-maps-macos-vX.Y.Z.app.zip
unzip agus-maps-macos-vX.Y.Z.app.zip

# 2. Remove quarantine attribute (required for unsigned apps)
xattr -cr agus_maps_flutter_example.app

# 3. Run the app
open agus_maps_flutter_example.app
```

#### Alternative: Finder

1. Download `agus-maps-macos-vX.Y.Z.app.zip`
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


### Windows (x86_64)

The Windows app is an **unsigned release build** for **x86_64 (64-bit Intel/AMD)** systems.

> ⚠️ **Architecture Note:** Only x86_64 is supported. ARM64 Windows (Snapdragon X, etc.) is not currently supported due to lack of testing hardware.

#### Installation Steps

```powershell
# 1. Download and extract (replace vX.Y.Z with actual version)
# Using PowerShell or download from browser
Invoke-WebRequest -Uri "https://github.com/agus-works/agus-maps-flutter/releases/latest/download/agus-maps-windows-vX.Y.Z.zip" -OutFile "agus-maps-windows-vX.Y.Z.zip"
Expand-Archive -Path "agus-maps-windows-vX.Y.Z.zip" -DestinationPath "agus-maps-windows"

# 2. Run the app
.\agus-maps-windows\agus_maps_flutter_example.exe
```

#### Alternative: File Explorer

1. Download `agus-maps-windows-vX.Y.Z.zip` from the [releases page](https://github.com/agus-works/agus-maps-flutter/releases)
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


### Windows Troubleshooting

| Issue | Solution |
|-------|----------|
| "VCRUNTIME140.dll not found" | Install [Visual C++ Redistributable](https://aka.ms/vs/17/release/vc_redist.x64.exe) |
| App won't start | Ensure you're on x86_64 Windows, not ARM64 |
| Blank/white map | Check map data files exist in `Documents\agus_maps_flutter\` |
| Poor performance | Update graphics drivers; ensure hardware OpenGL is available |


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
# 1. Download and extract (replace vX.Y.Z with actual version)
curl -LO https://github.com/agus-works/agus-maps-flutter/releases/latest/download/agus-maps-linux-vX.Y.Z.zip
unzip agus-maps-linux-vX.Y.Z.zip -d agus-maps-linux

# 2. Run the app
cd agus-maps-linux
./agus_maps_flutter_example
```

#### Alternative: File Manager

1. Download `agus-maps-linux-vX.Y.Z.zip` from the [releases page](https://github.com/agus-works/agus-maps-flutter/releases)
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


### Linux Troubleshooting

| Issue | Solution |
|-------|----------|
| "error while loading shared libraries" | Install missing libraries with `apt-get install libgtk-3-0 libepoxy0` |
| App won't start | Ensure you have OpenGL support: `glxinfo \| grep "OpenGL version"` |
| Blank/white map | Check map data files exist in `~/.local/share/agus_maps_flutter/` |
| Poor performance | Update Mesa drivers: `sudo apt-get upgrade mesa-*` |
| Permission denied | Run `chmod +x agus_maps_flutter_example` |


## Using Pre-built Libraries in Your Project

If you're integrating the Agus Maps Flutter plugin into your own project, you must **manually download and extract** the pre-built binaries before building.

> **⚠️ Important (v0.1.3+):** The build systems do NOT auto-download binaries. You must manually download and extract the unified package before building. This ensures deterministic builds with no network calls during compilation.

### Manual Setup (Required)

**Step 1: Add the plugin dependency**

```yaml
# pubspec.yaml
dependencies:
  agus_maps_flutter: ^X.Y.Z
```

**Step 2: Download the unified binary package**

Download `agus-maps-binaries-vX.Y.Z.zip` from [GitHub Releases](https://github.com/agus-works/agus-maps-flutter/releases).

```bash
# Replace X.Y.Z with your plugin version
curl -LO "https://github.com/agus-works/agus-maps-flutter/releases/download/vX.Y.Z/agus-maps-binaries-vX.Y.Z.zip"
```

**Step 3: Extract to your app root**

Extract the ZIP directly to your Flutter app's root directory:

```bash
# Linux/macOS
unzip agus-maps-binaries-vX.Y.Z.zip -d /path/to/my_app/

# Windows (PowerShell)
Expand-Archive -Path agus-maps-binaries-vX.Y.Z.zip -DestinationPath C:\path\to\my_app\
```

**Step 4: Configure assets**

Add the assets to your `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/comaps_data/
    - assets/maps/
```

**Step 5: Build**

```bash
flutter build <platform>
```

### Unified Package Structure

After extraction, your app directory should contain:

```
my_app/
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
├── linux/prebuilt/x64/
│   └── libagus_maps_flutter.so
├── assets/
│   ├── comaps_data/
│   │   └── ... (CoMaps resource files)
│   └── maps/
│       └── icudt75l.dat
├── headers/              # For building from source (optional)
│   └── ... (C++ headers)
├── lib/                  # Your app code
└── pubspec.yaml
```

> **Note:** The `headers/` directory is only needed if you're building native code from source. For typical plugin consumers using pre-built binaries, headers can be ignored or deleted.

### Upgrading to a New Version

When upgrading the plugin version, you must also update the binaries:

1. Update `pubspec.yaml` with the new version
2. Run `flutter pub get`
3. Download the **matching** unified binary package
4. Extract to your app root (overwrites existing binaries)
5. Run `flutter clean && flutter build <platform>`

> **Why manual?** This approach ensures deterministic builds with no network calls during compilation. CI/CD pipelines work reliably in air-gapped environments, and you always know exactly which binaries are being used.

### How Each Platform Detects Binaries

All platforms use **detection-only** logic with clear error messages when binaries are missing:

#### iOS (CocoaPods)

The `agus_maps_flutter.podspec` looks for:
- `ios/Frameworks/CoMaps.xcframework/`

**Requirement:** The `CoMaps.xcframework` must be present. The recommended way is to set `AGUS_MAPS_HOME` which points to the SDK containing this framework. The podspec will automatically copy it from the SDK during `pod install`.

#### macOS (CocoaPods)

The `agus_maps_flutter.podspec` looks for:
- `macos/Frameworks/CoMaps.xcframework/`

**Requirement:** The `CoMaps.xcframework` must be present. The recommended way is to set `AGUS_MAPS_HOME` which points to the SDK containing this framework. The podspec will automatically copy it from the SDK during `pod install`.

#### Android (Gradle)

The `android/build.gradle` checks:
1. `android/prebuilt/{arm64-v8a,armeabi-v7a,x86_64}/` in the app's android folder

If not found, the build will fail with instructions to download the binaries.

#### Windows (CMake)

The `windows/CMakeLists.txt` checks:
1. Plugin-local: `<plugin>/windows/prebuilt/x64/`
2. App project: `<app>/windows/prebuilt/x64/`

If not found, CMake will fail with a `FATAL_ERROR` and download instructions.

#### Linux (CMake)

The `linux/CMakeLists.txt` checks:
1. Plugin-local: `<plugin>/linux/prebuilt/x64/`
2. App project: `<app>/linux/prebuilt/x64/`

If not found, CMake will fail with a `FATAL_ERROR` and download instructions.


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

### iOS/macOS Build Failures (SDK Consumers)

| Issue | Solution |
|-------|----------|
| `'platform/platform.hpp' file not found` | Clear cached headers and re-run pod install (see below) |
| `fatal error: '...' file not found` after SDK switch | Clear cached headers and re-run pod install (see below) |
| Build worked before but fails after changing `AGUS_MAPS_HOME` | Clear cached headers and re-run pod install (see below) |

#### Clearing Cached Headers When Switching SDK Versions

The plugin caches headers and frameworks from `AGUS_MAPS_HOME` in the pub.dev cache. If you switch SDK versions or change the SDK path, stale cached files may cause build failures with missing header errors.

**Solution:**

```bash
# 1. Clear the cached headers and frameworks from pub cache
rm -rf ~/.pub-cache/hosted/pub.dev/agus_maps_flutter-*/macos/Headers
rm -rf ~/.pub-cache/hosted/pub.dev/agus_maps_flutter-*/macos/Frameworks
rm -rf ~/.pub-cache/hosted/pub.dev/agus_maps_flutter-*/ios/Headers
rm -rf ~/.pub-cache/hosted/pub.dev/agus_maps_flutter-*/ios/Frameworks

# 2. Clean the app build
cd your_app
flutter clean

# 3. Re-run pub get
flutter pub get

# 4. Re-run pod install with the correct AGUS_MAPS_HOME
# macOS:
cd macos && AGUS_MAPS_HOME=/path/to/agus-maps-sdk-vX.Y.Z pod install && cd ..

# iOS:
cd ios && AGUS_MAPS_HOME=/path/to/agus-maps-sdk-vX.Y.Z pod install && cd ..

# 5. Build again
flutter build macos --release  # or ios, etc.
```

> **Why does this happen?** The podspec copies headers from `AGUS_MAPS_HOME` during `pod install` and stores a marker file tracking the SDK path. If you previously used a different SDK path (even if deleted), the marker may point to the old location and the cached headers may be incomplete or outdated. Clearing the cache forces a fresh copy from the current SDK.


## Building from Source

> **Note:** Building from source is intended for **developers** who want to modify the native code or build binaries from scratch. **Plugin consumers** should use the pre-built binaries from [GitHub Releases](https://github.com/agus-works/agus-maps-flutter/releases).

### Build Host → Target Platform Matrix

The recommended build script is `build_all.ps1` for Windows and `build_all.sh` for macOS/Linux. These scripts automate the entire build process including fetching CoMaps source, applying patches, building native libraries, and generating Flutter apps.

| Build Host | Script | Target Platforms | Notes |
|------------|--------|------------------|-------|
| **Windows** | `.\scripts\build_all.ps1` | Android, Windows | Requires Android SDK + NDK, Visual Studio |
| **macOS** | `./scripts/build_all.sh` | Android, iOS, macOS | Requires Xcode, Android SDK + NDK |
| **Linux** | `./scripts/build_all.sh` | Android, Linux | Requires GTK3 dev libs, Android SDK + NDK |

### Prerequisites

**All platforms:**
- Flutter 3.38+ with desktop support enabled
- CMake 4.2+
- Ninja build system
- Git

**Windows-specific:**
- Visual Studio 2022 with C++ desktop development workload
- Android SDK with NDK 27.3+ (for Android targets)
- vcpkg (for Windows native dependencies)

**macOS-specific:**
- Xcode 15+ with command line tools
- CocoaPods
- Android SDK with NDK 27.3+ (for Android targets)

**Linux-specific:**
- GCC/Clang with C++23 support
- GTK3, EGL, epoxy development libraries
- Android SDK with NDK 27.3+ (for Android targets)

### Build Instructions

#### Windows (PowerShell 7+)

```powershell
# Clone the repository
git clone https://github.com/agus-works/agus-maps-flutter.git
cd agus-maps-flutter

# Run the all-in-one build script
# This handles: CoMaps fetch, patching, Boost headers, data generation,
# native library builds, asset copying, and Flutter app builds
.\scripts\build_all.ps1
```

**Outputs:**
- `build\agus-binaries-android\` - Android native libraries (.so)
- `build\agus-binaries-windows\x64\` - Windows native libraries (.dll)
- `example\build\app\outputs\flutter-apk\app-release.apk` - Android APK
- `example\build\windows\x64\runner\Release\` - Windows executable

#### macOS

```bash
# Clone the repository
git clone https://github.com/agus-works/agus-maps-flutter.git
cd agus-maps-flutter

# Run the all-in-one build script
# This handles: CoMaps fetch, patching, Boost headers, data generation,
# native library builds (iOS, macOS, Android), asset copying, and Flutter app builds
./scripts/build_all.sh
```

**Outputs:**
- `build/agus-binaries-android/` - Android native libraries (.so)
- `build/agus-binaries-ios/` - iOS XCFramework
- `build/agus-binaries-macos/` - macOS XCFramework
- `example/build/` - Flutter app builds for each platform

#### Linux

```bash
# Clone the repository
git clone https://github.com/agus-works/agus-maps-flutter.git
cd agus-maps-flutter

# Install system dependencies (Ubuntu/Debian)
sudo apt-get install build-essential cmake ninja-build clang \
    libgtk-3-dev libepoxy-dev libegl-dev pkg-config

# Run the all-in-one build script
./scripts/build_all.sh
```

**Outputs:**
- `build/agus-binaries-linux/x86_64/` - Linux native libraries (.so)
- `build/agus-binaries-android/` - Android native libraries (.so)
- `example/build/linux/x64/release/bundle/` - Linux executable

### Caching

The build scripts support intelligent caching of the CoMaps source tree:

- First build: Downloads and patches CoMaps (~2-3 GB), creates `.thirdparty-<tag>.tar.gz` cache
- Subsequent builds: Extracts from cache (much faster)
- Cache is tagged with CoMaps version to ensure correctness

To force a fresh build, delete the cache file:
```bash
rm .thirdparty-*.tar.gz
rm -rf thirdparty/
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for more detailed development setup instructions.


## Version History

See [CHANGELOG.md](../CHANGELOG.md) for release notes and version history.
