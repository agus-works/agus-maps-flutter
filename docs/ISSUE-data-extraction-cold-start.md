# ISSUE: Data Files Extracted on Every Cold Start Check

## Severity: Low

## Description

On every app launch, the plugin checks whether CoMaps data files need extraction by looking for a marker file (`.comaps_data_extracted`). While the extraction itself is skipped if the marker exists, the asset listing and file system checks still occur.

## Location

- [android/src/main/java/.../AgusMapsFlutterPlugin.java](../android/src/main/java/app/agus/maps/agus_maps_flutter/AgusMapsFlutterPlugin.java) - `extractDataFiles()` method

## Current Behavior

```java
private String extractDataFiles() throws IOException {
    File markerFile = new File(filesDir, ".comaps_data_extracted");
    if (markerFile.exists()) {
        // Early exit - good!
        return filesDir.getAbsolutePath();
    }
    
    // ... extraction code ...
}
```

The check itself is efficient (single file existence check), but the method is called on every initialization through `MethodChannel`.

## Impact

- **Startup time**: ~1-5ms added to cold start
- **I/O**: One `exists()` syscall per launch
- **Memory**: Minimal

## Why This Is Low Priority

1. The marker check is a single filesystem stat() call
2. It only runs once during app initialization
3. The actual extraction (when needed) streams efficiently with 32KB buffers

## Potential Optimization

Cache the extraction state in SharedPreferences to avoid filesystem check:

```java
SharedPreferences prefs = context.getSharedPreferences("agus_maps", MODE_PRIVATE);
if (prefs.getBoolean("data_extracted", false)) {
    return filesDir.getAbsolutePath();
}
// ... extract and set flag ...
prefs.edit().putBoolean("data_extracted", true).apply();
```

## Decision

**Won't Fix** - The current implementation is already efficient. The filesystem check is faster than SharedPreferences in most cases, and the simplicity of the current approach (marker file) makes debugging easier.
