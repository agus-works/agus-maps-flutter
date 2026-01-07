# ISSUE: Native String Allocation on Every FFI Call

## Severity: Low

## Description

FFI string parameters are converted using `toNativeUtf8()` which allocates memory for each call. While necessary for the FFI boundary, the current pattern allocates and frees memory frequently.

## Location

- [lib/agus_maps_flutter.dart](../lib/agus_maps_flutter.dart) - Multiple functions using `toNativeUtf8()`

## Current Behavior

```dart
void loadMap(String path) {
    final pathPtr = path.toNativeUtf8().cast<Char>();  // malloc
    _bindings.comaps_load_map_path(pathPtr);
    malloc.free(pathPtr);  // free
}

int registerSingleMap(String fullPath) {
    final pathPtr = fullPath.toNativeUtf8().cast<Char>();  // malloc
    try {
        return _bindings.comaps_register_single_map(pathPtr);
    } finally {
        malloc.free(pathPtr);  // free
    }
}
```

## Impact

- **Memory**: Small allocations/frees cause fragmentation over time
- **CPU**: malloc/free overhead (~100ns each)
- **GC**: Not Dart GC managed, but native heap pressure

## Why This Is Low Priority

1. These functions are called rarely (init, map registration)
2. Touch events don't use string parameters
3. The allocations are small (<1KB typically)
4. The pattern is correct and prevents memory leaks

## Where It Would Matter

If we added high-frequency string-based APIs like:
- `getPlaceName(lat, lon)` called per-frame
- `searchAutocomplete(query)` called per-keystroke

## Potential Optimization (Only If Needed)

For high-frequency string APIs, use a pooled allocator:

```dart
class NativeStringPool {
    final List<Pointer<Char>> _pool = [];
    static const _poolSize = 8;
    
    Pointer<Char> acquire(String str) {
        // Reuse from pool if available and large enough
        // Otherwise allocate
    }
    
    void release(Pointer<Char> ptr) {
        // Return to pool if not full, otherwise free
    }
}
```

## Decision

**Won't Fix** - Current usage pattern is correct and performant. No high-frequency string APIs exist. The try/finally pattern ensures proper cleanup.
