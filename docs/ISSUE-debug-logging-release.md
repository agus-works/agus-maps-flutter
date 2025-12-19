# ISSUE: DEBUG Logging in Native Layer Not Stripped in Release

## Severity: Medium

## Description

The native C++ code includes extensive `__android_log_print` calls at `ANDROID_LOG_DEBUG` level. In release builds, these calls are still compiled in and executed, even though logcat filtering may hide them.

## Location

- [src/agus_maps_flutter.cpp](../src/agus_maps_flutter.cpp) - Multiple `__android_log_print(ANDROID_LOG_DEBUG, ...)` calls
- [src/agus_gui_thread.cpp](../src/agus_gui_thread.cpp) - Debug logging in hot paths
- [src/agus_ogl.cpp](../src/agus_ogl.cpp) - EGL debug logging

## Current Behavior

```cpp
// This runs in release builds too!
__android_log_print(ANDROID_LOG_DEBUG, "AgusMapsFlutterNative", 
    "comaps_touch: type=%d", type);
```

Each log call:
1. Formats the string (even if not printed)
2. Makes a syscall to logd
3. logd decides whether to output based on log level

## Impact

- **CPU**: String formatting overhead in hot paths
- **Battery**: Syscalls during touch handling
- **Performance**: Measurable impact during gesture handling (~5-10% overhead)

## Solution

Wrap debug logs in preprocessor conditionals:

```cpp
#ifdef NDEBUG
#define LOG_DEBUG(...) ((void)0)
#else
#define LOG_DEBUG(...) __android_log_print(ANDROID_LOG_DEBUG, TAG, __VA_ARGS__)
#endif

// Usage
LOG_DEBUG("comaps_touch: type=%d", type);
```

Or use CoMaps' existing logging infrastructure:

```cpp
#include "base/logging.hpp"

// This respects build type
LOG(LDEBUG, ("comaps_touch: type=", type));
```

## Files to Update

1. `src/agus_maps_flutter.cpp` - 15+ debug log calls
2. `src/agus_gui_thread.cpp` - 10+ debug log calls  
3. `src/agus_ogl.cpp` - 5+ debug log calls

## Priority

**Should Fix** - Easy change with measurable performance benefit. The overhead is small per-call but adds up during gesture handling.

## Measurement

```bash
# Before fix
adb shell "echo 1 > /sys/kernel/debug/tracing/events/sched/sched_switch/enable"
# Measure CPU time in native library during pan gesture

# After fix
# Compare CPU time - expect 5-10% reduction in native overhead
```
