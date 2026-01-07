# IMPL-01: Fix MWM Registration and LOD

## Problem

Gibraltar.mwm (and other country MWMs) are not being registered properly, resulting in no detailed roads/features when zooming in past scale 9.

### Root Cause Analysis

1. **Directory Structure Mismatch**: CoMaps' `RegisterAllMaps()` → `Storage::RegisterAllLocalMaps()` → `FindAllLocalMapsAndCleanup()` only scans **version-numbered subdirectories** (e.g., `250608/`) in the writable path. It explicitly skips the root folder.

2. **Current Extraction**: `extractMap()` places MWM files directly in the root of the files directory:
   ```
   /data/data/app.agus.maps.example/files/Gibraltar.mwm  ❌ NOT FOUND
   ```

3. **Expected Structure**:
   ```
   /data/data/app.agus.maps.example/files/
   ├── 250608/                    ← Version directory (YYMMDD format)
   │   └── Gibraltar.mwm          ✓ FOUND by RegisterAllMaps
   ├── World.mwm                  ✓ FOUND via GetReader (resource path)
   └── WorldCoasts.mwm            ✓ FOUND via GetReader (resource path)
   ```

4. **World/WorldCoasts Exception**: These are searched in resource paths via `GetReader()`, so they work even in the root directory.

## Solution: Add `registerSingleMap(path)` FFI Function

Instead of relying on directory scanning, we add a direct registration function that uses `LocalCountryFile::MakeTemporary()` - which bypasses the version folder requirement.

### Implementation Steps

#### Step 1: Add C++ FFI Function

**File**: `src/agus_maps_flutter.cpp`

Add new function:
```cpp
FFI_PLUGIN_EXPORT int comaps_register_single_map(const char* fullPath) {
    __android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", 
        "comaps_register_single_map: %s", fullPath);
    
    if (!g_framework) {
        __android_log_print(ANDROID_LOG_ERROR, "AgusMapsFlutterNative", 
            "comaps_register_single_map: Framework not initialized");
        return -1;  // Error: Framework not ready
    }
    
    try {
        platform::LocalCountryFile file = platform::LocalCountryFile::MakeTemporary(fullPath);
        file.SyncWithDisk();
        
        auto result = g_framework->RegisterMap(file);
        if (result.second == MwmSet::RegResult::Success) {
            __android_log_print(ANDROID_LOG_INFO, "AgusMapsFlutterNative", 
                "comaps_register_single_map: Successfully registered %s", fullPath);
            return 0;  // Success
        } else {
            __android_log_print(ANDROID_LOG_WARN, "AgusMapsFlutterNative", 
                "comaps_register_single_map: Failed to register %s, result=%d", 
                fullPath, static_cast<int>(result.second));
            return static_cast<int>(result.second);
        }
    } catch (std::exception const & e) {
        __android_log_print(ANDROID_LOG_ERROR, "AgusMapsFlutterNative", 
            "comaps_register_single_map: Exception: %s", e.what());
        return -2;  // Error: Exception
    }
}
```

#### Step 2: Add Header Declaration

**File**: `src/agus_maps_flutter.h`

```cpp
FFI_PLUGIN_EXPORT int comaps_register_single_map(const char* fullPath);
```

#### Step 3: Update FFI Bindings

**File**: `lib/agus_maps_flutter_bindings_generated.dart`

Add binding (or regenerate with ffigen):
```dart
int comaps_register_single_map(ffi.Pointer<ffi.Char> fullPath) {
  return _comaps_register_single_map(fullPath);
}
late final _comaps_register_single_mapPtr =
    _lookup<ffi.NativeFunction<ffi.Int Function(ffi.Pointer<ffi.Char>)>>(
        'comaps_register_single_map');
late final _comaps_register_single_map =
    _comaps_register_single_mapPtr.asFunction<int Function(ffi.Pointer<ffi.Char>)>();
```

#### Step 4: Add Dart Wrapper

**File**: `lib/agus_maps_flutter.dart`

```dart
/// Register a single MWM map file directly by full path.
/// 
/// This bypasses the version folder scanning and registers the map file
/// directly with the rendering engine. Use this for MWM files that are
/// not in the standard version directory structure.
/// 
/// Returns 0 on success, negative on error.
int registerSingleMap(String fullPath) {
  final pathPtr = fullPath.toNativeUtf8().cast<Char>();
  try {
    return _bindings.comaps_register_single_map(pathPtr);
  } finally {
    malloc.free(pathPtr);
  }
}
```

#### Step 5: Update Example App

**File**: `example/lib/main.dart`

Change `loadMap()` call to `registerSingleMap()` and move it after map creation:

```dart
// Store paths for later registration
List<String> _mapPathsToRegister = [];

Future<void> _initData() async {
  // ... extraction code ...
  
  // Store map paths (don't register yet - Framework not ready)
  _mapPathsToRegister.add(await agus_maps_flutter.extractMap('assets/maps/World.mwm'));
  _mapPathsToRegister.add(await agus_maps_flutter.extractMap('assets/maps/WorldCoasts.mwm'));
  _mapPathsToRegister.add(await agus_maps_flutter.extractMap('assets/maps/Gibraltar.mwm'));
  
  // ... rest of init ...
}

void _onMapReady() {
  // Register maps AFTER Framework is created (in nativeSetSurface)
  for (final path in _mapPathsToRegister) {
    final result = agus_maps_flutter.registerSingleMap(path);
    _log('Registered map $path: result=$result');
  }
  // ...
}
```

## Testing

1. Build and run the example app
2. Navigate to Gibraltar at zoom 14
3. Verify roads and buildings are visible
4. Check logcat for successful registration messages:
   ```
   comaps_register_single_map: Successfully registered /data/.../Gibraltar.mwm
   ```

## Dependencies

- Must include `platform/local_country_file.hpp` in `agus_maps_flutter.cpp`
- Framework must expose `RegisterMap()` or we use `m_featuresFetcher.RegisterMap()`

## Notes

- `MakeTemporary()` sets version to 0, which is fine for rendering
- World.mwm and WorldCoasts.mwm should still be registered this way for consistency
- This approach is more predictable than relying on directory scanning
