# ISSUE: Touch Events Sent Per-Frame May Cause Unnecessary FFI Overhead

## Severity: Low

## Description

The current touch handling implementation sends every `PointerMoveEvent` to the native layer via FFI. During a pan gesture, this can result in 60+ FFI calls per second.

## Location

- [lib/agus_maps_flutter.dart](../lib/agus_maps_flutter.dart) - `_handlePointerMove` method
- [src/agus_maps_flutter.cpp](../src/agus_maps_flutter.cpp) - `comaps_touch` function

## Current Behavior

```dart
void _handlePointerMove(PointerMoveEvent event) {
    _activePointers[event.pointer] = event.localPosition;
    _sendTouchEvent(TouchType.move, event.pointer, event.localPosition);
}
```

Every pointer move immediately calls `comaps_touch` via FFI, which:
1. Crosses the Dart/C++ boundary (small overhead)
2. Allocates a `df::TouchEvent` object (small overhead)
3. Calls `g_framework->TouchEvent(event)` (triggers render consideration)

## Impact

- **Battery**: Each FFI call wakes up native thread if sleeping
- **CPU**: High-frequency allocations in hot path
- **Latency**: Generally fine, but creates jitter on slower devices

## Potential Solutions

### Option A: Throttle on Dart Side (Recommended)

```dart
DateTime? _lastMoveTime;
static const _moveThrottleMs = 16; // ~60fps max

void _handlePointerMove(PointerMoveEvent event) {
    final now = DateTime.now();
    if (_lastMoveTime != null && 
        now.difference(_lastMoveTime!).inMilliseconds < _moveThrottleMs) {
        _activePointers[event.pointer] = event.localPosition;
        return; // Skip this event
    }
    _lastMoveTime = now;
    _activePointers[event.pointer] = event.localPosition;
    _sendTouchEvent(TouchType.move, event.pointer, event.localPosition);
}
```

### Option B: Batch Events on Native Side

Accumulate touch events and process them once per frame in the render loop.

### Option C: Use Flutter's Gesture Arena

Replace raw `Listener` with `GestureDetector` which already does velocity sampling.

## Measurement

To measure impact:
```bash
# Count FFI calls during pan
adb logcat -s AgusMapsFlutterNative | grep comaps_touch | wc -l
```

Expected: 60+ calls/second during pan
Target: 30-60 calls/second (match vsync)

## Decision

**Deferred** - Current implementation works fine on Galaxy S10. The Drape engine already handles event batching internally. Only optimize if profiling shows this as a bottleneck.
