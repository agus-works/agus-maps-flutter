# CoMaps Assets Management

This document provides a comprehensive guide to managing CoMaps assets in the Agus Maps Flutter plugin. Understanding asset management is essential for:

- **Plugin developers** contributing to the project
- **App developers** integrating the plugin into their Flutter apps
- **Troubleshooting** when maps fail to load or display incorrectly

---

## Table of Contents

1. [Overview](#overview)
2. [Asset Categories](#asset-categories)
3. [Source of Truth: thirdparty/comaps](#source-of-truth-thirdpartycomaps)
4. [Build-Time Asset Population](#build-time-asset-population)
5. [Runtime Asset Extraction](#runtime-asset-extraction)
6. [Platform-Specific Behavior](#platform-specific-behavior)
7. [MWM Map Files](#mwm-map-files)
8. [Troubleshooting](#troubleshooting)
9. [Manual Intervention Guide](#manual-intervention-guide)

---

## Overview

The CoMaps rendering engine requires several categories of static data files to function:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         CoMaps Asset Flow                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  1. SOURCE (thirdparty/comaps/data/)                                    │
│     │                                                                   │
│     ▼ scripts/copy_comaps_data.sh                                       │
│                                                                         │
│  2. FLUTTER ASSETS (example/assets/comaps_data/)                        │
│     │                                                                   │
│     ▼ Flutter build system (pubspec.yaml assets)                        │
│                                                                         │
│  3. APP BUNDLE (platform-specific)                                      │
│     │  • Android: APK assets/                                           │
│     │  • iOS/macOS: App.framework bundle                                │
│     │  • Windows: data/flutter_assets/                                  │
│     │                                                                   │
│     ▼ extractDataFiles() at runtime                                     │
│                                                                         │
│  4. WRITABLE DIRECTORY (platform-specific)                              │
│     │  • Android: /data/data/<package>/files/                           │
│     │  • iOS/macOS: ~/Documents/                                        │
│     │  • Windows: ~/Documents/agus_maps_flutter/                        │
│     │                                                                   │
│     ▼ initWithPaths(resourcePath, writablePath)                         │
│                                                                         │
│  5. COMAPS ENGINE (C++ Framework)                                       │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

**Key Principle:** Assets are **NOT committed to git** in the example app. They are:
1. Sourced from `thirdparty/comaps/data/` (the CoMaps checkout)
2. Copied to `example/assets/comaps_data/` at **build time**
3. The `example/assets/comaps_data/` directory is in `.gitignore`

This avoids duplicating ~200,000+ lines of JSON localization files in the repository.

---

## Asset Categories

### Essential Engine Files

These files are **required** for the CoMaps Framework to initialize:

| File | Purpose | Size |
|------|---------|------|
| `classificator.txt` | Map feature type hierarchy | ~500 KB |
| `types.txt` | Type definitions for map features | ~30 KB |
| `categories.txt` | Search category definitions | ~200 KB |
| `visibility.txt` | Zoom-level visibility rules | ~50 KB |
| `drules_proto.bin` | Binary drawing rules (default style) | ~2 MB |
| `drules_proto_default_light.bin` | Light theme drawing rules | ~2 MB |
| `drules_proto_default_dark.bin` | Dark theme drawing rules | ~2 MB |
| `packed_polygons.bin` | Pre-packed country boundary polygons | ~5 MB |
| `countries.txt` | Country/region definitions | ~200 KB |
| `countries_meta.txt` | Country metadata | ~20 KB |
| `transit_colors.txt` | Public transit line colors | ~5 KB |
| `colors.txt` | Map color definitions | ~10 KB |
| `patterns.txt` | Line pattern definitions | ~5 KB |
| `editor.config` | Map editor configuration | ~2 KB |

### Localization Files

Two directories contain localization JSON files for 45+ languages:

| Directory | Purpose | Files |
|-----------|---------|-------|
| `categories-strings/` | Search category translations | ~45 locales × ~500 lines each |
| `countries-strings/` | Country/region name translations | ~45 locales × ~2500 lines each |

**Structure:**
```
categories-strings/
├── en.json/
│   └── localize.json    # English category names
├── de.json/
│   └── localize.json    # German category names
├── ru.json/
│   └── localize.json    # Russian category names
└── ... (45+ locales)
```

### Rendering Assets

| Directory | Purpose |
|-----------|---------|
| `symbols/` | Map icons (POI markers, etc.) at various DPI scales |
| `styles/` | Map style definitions |
| `fonts/` | Font files for text rendering (optional, uses system fonts) |

### ICU Data (Transliteration)

| File | Purpose | Size |
|------|---------|------|
| `icudt75l.dat` | ICU library data for Unicode transliteration | ~1.3 MB |

This file enables search transliteration (e.g., searching "cafe" finds "café").

### MWM Map Files

| File | Purpose | Size |
|------|---------|------|
| `World.mwm` | Low-zoom world overview | ~50 MB |
| `WorldCoasts.mwm` | Coastline data | ~8 MB |
| `<Region>.mwm` | Detailed regional maps | Varies (1 MB - 800 MB) |

See [MWM Map Files](#mwm-map-files) section for details.

---

## Source of Truth: thirdparty/comaps

All CoMaps assets originate from the `thirdparty/comaps/data/` directory, which is a git checkout of the [CoMaps repository](https://codeberg.org/comaps/comaps).

### Fetching CoMaps Source

**macOS/Linux:**
```bash
./scripts/fetch_comaps.sh
```

**Windows (PowerShell 7+):**
```powershell
.\scripts\fetch_comaps.ps1
```

This will:
1. Clone the CoMaps repository to `thirdparty/comaps/`
2. Checkout the version specified in `$COMAPS_TAG` (default: `v2025.12.11-2`)
3. Initialize all git submodules recursively
4. Apply patches from `patches/comaps/`

### Verifying Source Data

```bash
# Check that data directory exists
ls thirdparty/comaps/data/

# Expected output:
# categories-strings/  countries.txt  drules_proto.bin  ...
# categories.txt       countries_meta.txt  fonts/  ...
```

---

## Build-Time Asset Population

Before building the example app, you must populate the Flutter assets directory.

### Running the Copy Script

**macOS/Linux:**
```bash
./scripts/copy_comaps_data.sh
```

**Windows (PowerShell 7+):**
```powershell
.\scripts\copy_comaps_data.ps1
```

### What the Script Does

1. **Checks** that `thirdparty/comaps/data/` exists
2. **Creates** `example/assets/comaps_data/` directory
3. **Copies** essential files:
   - `classificator.txt`, `types.txt`, `categories.txt`, etc.
   - `drules_proto*.bin` drawing rules
   - `packed_polygons.bin`, `countries*.txt`
4. **Copies** localization directories:
   - `categories-strings/`
   - `countries-strings/`
5. **Copies** rendering assets:
   - `symbols/`
   - `styles/`
   - `fonts/`

### Git Ignore Policy

The `example/assets/comaps_data/` directory is intentionally in `.gitignore`:

```gitignore
# CoMaps generated data files (copied from thirdparty/comaps/data)
example/assets/comaps_data/
```

**Rationale:**
- Avoids committing ~200,000+ lines of JSON to the repository
- Single source of truth is `thirdparty/comaps/data/`
- Reduces repository size from ~50 MB to ~5 MB

### pubspec.yaml Configuration

The example app's `pubspec.yaml` must declare all asset directories:

```yaml
flutter:
  assets:
    # MWM map files
    - assets/maps/Gibraltar.mwm
    - assets/maps/World.mwm
    - assets/maps/WorldCoasts.mwm
    - assets/maps/icudt75l.dat
    
    # CoMaps engine data
    - assets/comaps_data/
    - assets/comaps_data/fonts/
    
    # Localization (each locale must be listed explicitly!)
    - assets/comaps_data/categories-strings/en.json/
    - assets/comaps_data/categories-strings/de.json/
    - assets/comaps_data/categories-strings/ru.json/
    # ... (all 45+ locales)
    
    - assets/comaps_data/countries-strings/en.json/
    # ... (all 45+ locales)
    
    # Symbols (each DPI variant)
    - assets/comaps_data/symbols/
    - assets/comaps_data/symbols/6plus/
    - assets/comaps_data/symbols/hdpi/
    # ...
```

**Important:** Flutter does NOT recursively include subdirectory contents. Each subdirectory must be listed explicitly.

---

## Runtime Asset Extraction

At app startup, assets must be extracted from the app bundle to the device's writable directory. This is because the CoMaps C++ engine requires filesystem paths, not Flutter asset streams.

### Extraction Flow (Dart Side)

```dart
// 1. Extract MWM map files
final worldPath = await agus_maps_flutter.extractMap('assets/maps/World.mwm');
final coastsPath = await agus_maps_flutter.extractMap('assets/maps/WorldCoasts.mwm');
final gibraltarPath = await agus_maps_flutter.extractMap('assets/maps/Gibraltar.mwm');

// 2. Extract ICU data
await agus_maps_flutter.extractMap('assets/maps/icudt75l.dat');

// 3. Extract all CoMaps data files
String dataPath = await agus_maps_flutter.extractDataFiles();

// 4. Initialize the engine
agus_maps_flutter.initWithPaths(dataPath, dataPath);

// 5. After map surface is ready, register MWM files
agus_maps_flutter.registerSingleMap(worldPath);
agus_maps_flutter.registerSingleMap(coastsPath);
agus_maps_flutter.registerSingleMap(gibraltarPath);
```

### Extraction Caching

Assets are extracted **once** and cached. A marker file (`.comaps_data_extracted`) tracks whether extraction is complete:

```
Documents/
├── .comaps_data_extracted    # Marker file
├── classificator.txt
├── types.txt
├── categories-strings/
│   └── en.json/
│       └── localize.json
└── ... (other files)
```

If the marker file exists, extraction is skipped on subsequent app launches.

### Re-Extraction Trigger

Windows implements additional validation to re-extract if essential files are missing:

```cpp
// If any of these are missing, force re-extraction
const fs::path requiredFiles[] = {
    dataDir / "classificator.txt",
    dataDir / "types.txt",
    dataDir / "drules_proto.bin",
    dataDir / "packed_polygons.bin",
    dataDir / "transit_colors.txt",
    dataDir / "countries-strings" / "en.json" / "localize.json",
    dataDir / "categories-strings" / "en.json" / "localize.json",
};
```

---

## Platform-Specific Behavior

### Android

| Aspect | Details |
|--------|---------|
| **Bundle Location** | APK `assets/flutter_assets/assets/comaps_data/` |
| **Extraction Target** | `/data/data/<package>/files/` (app-private) |
| **Extraction Method** | `AssetManager.open()` → `FileOutputStream` |
| **Marker File** | `/data/data/<package>/files/.comaps_data_extracted` |

**Implementation:** `android/src/main/java/.../AgusMapsFlutterPlugin.java`

```java
private String extractDataFiles() throws IOException {
    File filesDir = context.getFilesDir();
    File markerFile = new File(filesDir, ".comaps_data_extracted");
    if (markerFile.exists()) {
        return filesDir.getAbsolutePath();
    }
    
    AssetManager assetManager = context.getAssets();
    String assetPrefix = FlutterInjector.instance()
        .flutterLoader()
        .getLookupKeyForAsset("assets/comaps_data");
    
    extractAssetsRecursive(assetManager, assetPrefix, filesDir);
    markerFile.createNewFile();
    
    return filesDir.getAbsolutePath();
}
```

### iOS

| Aspect | Details |
|--------|---------|
| **Bundle Location** | `App.framework/flutter_assets/assets/comaps_data/` |
| **Extraction Target** | `~/Documents/` (user's Documents directory) |
| **Extraction Method** | `FileManager.copyItem()` |
| **Marker File** | `~/Documents/.comaps_data_extracted` |
| **iCloud Backup** | Excluded via `isExcludedFromBackup = true` |

**Implementation:** `ios/Classes/AgusMapsFlutterPlugin.swift`

```swift
private func extractDataFiles() throws -> String {
    let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let markerFile = documentsDir.appendingPathComponent(".comaps_data_extracted")
    
    if FileManager.default.fileExists(atPath: markerFile.path) {
        return documentsDir.path
    }
    
    let dataAssetPath = lookupKeyForAsset("assets/comaps_data")
    if let bundleDataPath = Bundle.main.resourcePath?.appending("/\(dataAssetPath)") {
        try extractDirectory(from: bundleDataPath, to: documentsDir.path)
    }
    
    FileManager.default.createFile(atPath: markerFile.path, contents: nil)
    return documentsDir.path
}
```

### macOS

| Aspect | Details |
|--------|---------|
| **Bundle Location** | `AgusMapFlutter.app/Contents/Frameworks/App.framework/Resources/flutter_assets/assets/comaps_data/` |
| **Extraction Target** | `~/Documents/` (user's Documents directory) |
| **Extraction Method** | Same as iOS (`FileManager.copyItem()`) |
| **Marker File** | `~/Documents/.comaps_data_extracted` |

**Implementation:** Shares code with iOS in `ios/Classes/AgusMapsFlutterPlugin.swift` (unified Apple platforms).

### Windows

| Aspect | Details |
|--------|---------|
| **Bundle Location** | `<exe_dir>/data/flutter_assets/assets/comaps_data/` |
| **Extraction Target** | `%USERPROFILE%/Documents/agus_maps_flutter/` |
| **Extraction Method** | `std::filesystem::copy_file()` |
| **Marker File** | `%USERPROFILE%/Documents/agus_maps_flutter/.comaps_data_extracted` |
| **Validation** | Re-extracts if essential files are missing |

**Implementation:** `windows/agus_maps_flutter_plugin.cpp`

```cpp
std::string AgusMapsFlutterPlugin::ExtractAllDataFiles() {
    fs::path documentsDir = fs::path(GetDocumentsPath());
    fs::path dataDir = documentsDir / "agus_maps_flutter";
    fs::create_directories(dataDir);
    
    fs::path markerFile = dataDir / ".comaps_data_extracted";
    if (fs::exists(markerFile) && DataDirLooksComplete(dataDir)) {
        return dataDir.string();
    }
    
    std::string exeDir = GetExecutableDir();
    fs::path sourceDataDir = fs::path(exeDir) / "data" / "flutter_assets" / "assets" / "comaps_data";
    
    ExtractDirectory(sourceDataDir, dataDir);
    std::ofstream marker(markerFile);
    
    return dataDir.string();
}
```

---

## MWM Map Files

MWM (Maps With Me) files contain vector map data compiled from OpenStreetMap.

### Required Base Maps

| File | Purpose | Bundled in Example |
|------|---------|-------------------|
| `World.mwm` | Low-zoom world overview (zoom levels 0-9) | ✅ Yes |
| `WorldCoasts.mwm` | Coastline rendering | ✅ Yes |

These files are **required** for basic map display. Without them, only a blank map appears.

### Regional Maps

Regional maps provide detailed data for specific areas:

| Example | Size | Coverage |
|---------|------|----------|
| `Gibraltar.mwm` | ~1 MB | Gibraltar territory |
| `Germany_Bavaria.mwm` | ~150 MB | Bavaria, Germany |
| `United States_California.mwm` | ~200 MB | California, USA |
| `Philippines.mwm` | ~100 MB | Philippines |

### MWM File Locations Per Platform

#### Android
```
/data/data/<package>/files/
├── World.mwm           # Bundled (extracted)
├── WorldCoasts.mwm     # Bundled (extracted)
├── Gibraltar.mwm       # Bundled (extracted)
└── Philippines.mwm     # Downloaded
```

#### iOS
```
~/Documents/
├── World.mwm
├── WorldCoasts.mwm
├── Gibraltar.mwm
└── Philippines.mwm
```

#### macOS
```
~/Documents/
├── World.mwm
├── WorldCoasts.mwm
├── Gibraltar.mwm
└── Philippines.mwm
```

#### Windows
```
%USERPROFILE%/Documents/agus_maps_flutter/
├── World.mwm
├── WorldCoasts.mwm
├── Gibraltar.mwm
└── Philippines.mwm
```

### Bundling MWM Files in Your App

To bundle MWM files with your Flutter app:

1. **Add to assets directory:**
   ```
   your_app/assets/maps/
   ├── World.mwm
   ├── WorldCoasts.mwm
   └── YourRegion.mwm
   ```

2. **Declare in pubspec.yaml:**
   ```yaml
   flutter:
     assets:
       - assets/maps/World.mwm
       - assets/maps/WorldCoasts.mwm
       - assets/maps/YourRegion.mwm
   ```

3. **Extract at runtime:**
   ```dart
   final worldPath = await agus_maps_flutter.extractMap('assets/maps/World.mwm');
   final regionPath = await agus_maps_flutter.extractMap('assets/maps/YourRegion.mwm');
   ```

4. **Register with engine:**
   ```dart
   // After map surface is ready (in onMapReady callback)
   agus_maps_flutter.registerSingleMap(worldPath);
   agus_maps_flutter.registerSingleMap(regionPath);
   ```

### Downloading MWM Files

The plugin includes a download manager for fetching maps at runtime:

```dart
import 'package:agus_maps_flutter/mirror_service.dart';
import 'package:agus_maps_flutter/mwm_storage.dart';

// Get available mirrors
final mirrorService = MirrorService();
final mirrors = await mirrorService.fetchMirrors();

// Download a region
final downloadUrl = '${mirrors.first.url}/250101/Philippines.mwm';
// ... download file to Documents directory ...

// Register the downloaded map
agus_maps_flutter.registerSingleMap('/path/to/Philippines.mwm');

// Store metadata
final storage = await MwmStorage.create();
await storage.upsert(MwmMetadata(
  regionName: 'Philippines',
  snapshotVersion: '250101',
  fileSize: fileSize,
  downloadDate: DateTime.now(),
  filePath: downloadPath,
  isBundled: false,
));
```

### ICU Data File

The `icudt75l.dat` file is required for Unicode transliteration in search:

| Platform | Location After Extraction |
|----------|--------------------------|
| Android | `/data/data/<package>/files/icudt75l.dat` |
| iOS/macOS | `~/Documents/icudt75l.dat` |
| Windows | `%USERPROFILE%/Documents/agus_maps_flutter/icudt75l.dat` |

**Note:** This file should be bundled in `assets/maps/` alongside MWM files:
```yaml
flutter:
  assets:
    - assets/maps/icudt75l.dat
```

---

## Troubleshooting

### "Map shows blank" or "No tiles loaded"

**Cause:** Base maps (`World.mwm`, `WorldCoasts.mwm`) not registered.

**Solution:**
1. Verify maps are bundled in `pubspec.yaml`
2. Check extraction succeeded: `extractMap()` returns valid path
3. Ensure `registerSingleMap()` is called **after** map surface is ready
4. Call `invalidateMap()` and `forceRedraw()` after registration

### "classificator.txt not found" crash

**Cause:** CoMaps data files not extracted or path incorrect.

**Solution:**
1. Run `./scripts/copy_comaps_data.sh` before building
2. Verify `example/assets/comaps_data/` contains files
3. Check `pubspec.yaml` declares all asset directories
4. Ensure `extractDataFiles()` returns valid path

### "Search returns no results"

**Cause:** Localization files missing or not extracted.

**Solution:**
1. Verify `categories-strings/` and `countries-strings/` directories exist
2. Check that each locale is listed in `pubspec.yaml`:
   ```yaml
   - assets/comaps_data/categories-strings/en.json/
   ```
3. Delete `.comaps_data_extracted` marker and restart app to force re-extraction

### Windows: "Data incomplete, missing: ..."

**Cause:** Assets changed but old extraction marker exists.

**Solution:**
1. Delete `%USERPROFILE%/Documents/agus_maps_flutter/.comaps_data_extracted`
2. Optionally delete entire `agus_maps_flutter/` directory
3. Restart the app

### "CoMaps data directory not found" error

**Cause:** Build script not run before `flutter build`.

**Solution:**
```bash
# First, fetch CoMaps source
./scripts/fetch_comaps.sh

# Then, copy data files
./scripts/copy_comaps_data.sh

# Now build
flutter build <platform>
```

---

## Manual Intervention Guide

### Scenario 1: Adding a New Bundled Map

1. **Obtain the MWM file** from a CoMaps/Organic Maps mirror
2. **Place in assets:**
   ```bash
   cp NewRegion.mwm example/assets/maps/
   ```
3. **Update pubspec.yaml:**
   ```yaml
   assets:
     - assets/maps/NewRegion.mwm
   ```
4. **Extract and register in Dart code:**
   ```dart
   final path = await agus_maps_flutter.extractMap('assets/maps/NewRegion.mwm');
   // In onMapReady:
   agus_maps_flutter.registerSingleMap(path);
   ```

### Scenario 2: Updating CoMaps Data Files

When a new CoMaps version is released:

1. **Update the tag:**
   ```bash
   export COMAPS_TAG="v2025.12.20-1"
   ```
2. **Re-fetch source:**
   ```bash
   ./scripts/fetch_comaps.sh
   ```
3. **Re-copy data:**
   ```bash
   ./scripts/copy_comaps_data.sh
   ```
4. **Rebuild the app:**
   ```bash
   flutter clean && flutter build <platform>
   ```

### Scenario 3: Forcing Re-Extraction on User Devices

If you need users to re-extract data (e.g., after a breaking data format change):

1. **Change the marker file name** in the platform plugins
2. Or **increment a version check** in extraction logic
3. Users will automatically re-extract on next app launch

### Scenario 4: Reducing App Size

To reduce bundled app size:

1. **Remove unnecessary locales** from `pubspec.yaml`:
   ```yaml
   # Only include locales you need
   - assets/comaps_data/categories-strings/en.json/
   - assets/comaps_data/categories-strings/de.json/
   # Remove others
   ```
2. **Bundle only essential maps:**
   - Keep `World.mwm` and `WorldCoasts.mwm`
   - Let users download regional maps in-app

### Scenario 5: Custom Map Server

For production apps, host your own MWM files:

1. **Generate maps** using the [CoMaps generator tools](https://codeberg.org/comaps/comaps/src/branch/main/tools/python/maps_generator)
2. **Host on your CDN:**
   ```
   https://your-cdn.com/maps/250101/
   ├── World.mwm
   ├── WorldCoasts.mwm
   ├── YourCountry.mwm
   └── ...
   ```
3. **Configure mirror service** to use your server

---

## Related Documentation

- [IMPLEMENTATION-ANDROID.md](IMPLEMENTATION-ANDROID.md) — Android-specific build and asset handling
- [IMPLEMENTATION-IOS.md](IMPLEMENTATION-IOS.md) — iOS-specific build and asset handling
- [IMPLEMENTATION-WIN.md](IMPLEMENTATION-WIN.md) — Windows-specific build and asset handling
- [README.md](../README.md) — Main project documentation including map server setup
- [patches/comaps/README.md](../patches/comaps/README.md) — CoMaps patches and customizations
