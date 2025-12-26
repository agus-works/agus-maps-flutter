# Agus Maps Flutter - Release Guide

This guide explains how to use the pre-built artifacts from GitHub Releases.

## Release Artifacts

Each release includes the following artifacts:

| Artifact | Description | Size (approx) |
|----------|-------------|---------------|
| `agus-headers.tar.gz` | C++ header files for compilation | ~5 MB |
| `agus-binaries-ios.zip` | Pre-built XCFramework for iOS | ~150 MB |
| `agus-binaries-android.zip` | Pre-built native libraries for Android | ~100 MB |
| `agus-binaries-macos.zip` | Pre-built XCFramework for macOS | ~80 MB |
| `agus-maps-android.aab` | Android App Bundle (Play Store) | ~50 MB |
| `agus-maps-android.apk` | Universal APK (direct install) | ~80 MB |
| `agus-maps-ios-simulator.app.zip` | iOS Simulator app (debug) | ~100 MB |
| `agus-maps-macos.app.zip` | macOS app (release) | ~100 MB |

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
   curl -LO https://github.com/bangonkali/agus-maps-flutter/releases/latest/download/agus-maps-android.apk
   
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
curl -LO https://github.com/bangonkali/agus-maps-flutter/releases/latest/download/agus-maps-ios-simulator.app.zip
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

#### Installation Steps

```bash
# 1. Download and extract
curl -LO https://github.com/bangonkali/agus-maps-flutter/releases/latest/download/agus-maps-macos.app.zip
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

### Manual Download (Advanced)

If you need to download libraries manually:

```bash
# Set the version
VERSION="v0.0.30"

# Download iOS libraries
curl -LO "https://github.com/bangonkali/agus-maps-flutter/releases/download/${VERSION}/agus-binaries-ios.zip"
unzip agus-binaries-ios.zip -d ios/Frameworks/

# Download Android libraries
curl -LO "https://github.com/bangonkali/agus-maps-flutter/releases/download/${VERSION}/agus-binaries-android.zip"
unzip agus-binaries-android.zip -d android/prebuilt/

# Download macOS libraries
curl -LO "https://github.com/bangonkali/agus-maps-flutter/releases/download/${VERSION}/agus-binaries-macos.zip"
unzip agus-binaries-macos.zip -d macos/Frameworks/
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

```bash
# Clone the repository
git clone https://github.com/bangonkali/agus-maps-flutter.git
cd agus-maps-flutter

# Fetch dependencies
./scripts/fetch_comaps.sh

# Build for your platform
cd example
flutter build apk          # Android
flutter build ios          # iOS (requires Xcode)
flutter build macos        # macOS
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed build instructions.

---

## Version History

See [CHANGELOG.md](../CHANGELOG.md) for release notes and version history.
