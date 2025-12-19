# ISSUE: Surface Size Passed in Physical Pixels May Cause DPI Mismatch

## Severity: Low (Potential Bug)

## Description

The surface creation passes physical pixel dimensions, but the density is calculated separately from the display. If the widget's pixel ratio differs from the system's (e.g., in a scaled window), there could be a mismatch.

## Location

- [lib/agus_maps_flutter.dart](../lib/agus_maps_flutter.dart) - `_createSurface()` method
- [android/src/.../AgusMapsFlutterPlugin.java](../android/src/main/java/app/agus/maps/agus_maps_flutter/AgusMapsFlutterPlugin.java) - `createMapSurface` method

## Current Behavior

```dart
// Dart side
Future<void> _createSurface(Size logicalSize, double pixelRatio) async {
    final physicalWidth = (logicalSize.width * pixelRatio).toInt();
    final physicalHeight = (logicalSize.height * pixelRatio).toInt();
    // physicalWidth/Height sent to Java
}
```

```java
// Java side
WindowManager wm = (WindowManager) context.getSystemService(Context.WINDOW_SERVICE);
DisplayMetrics dm = new DisplayMetrics();
wm.getDefaultDisplay().getMetrics(dm);
density = dm.density;  // This might differ from Dart's pixelRatio!
```

## Potential Issue

On some devices or with accessibility scaling:
- Flutter's `MediaQuery.devicePixelRatio` = 2.75
- Android's `DisplayMetrics.density` = 3.0

This could cause:
- Slight blurriness (scaling mismatch)
- Touch coordinate offset
- Incorrect visual scale in Drape

## Impact

- **Visual**: Map may appear slightly blurry
- **Touch**: Coordinates might be off by a few pixels
- **Layout**: GUI elements sized incorrectly

## Verified Behavior

On Samsung Galaxy S10:
- Flutter reports: 3.0
- Android reports: 3.0
- No mismatch observed

## Solution

Pass the Dart-side pixel ratio to native:

```dart
final textureId = await _channel.invokeMethod('createMapSurface', {
    'width': physicalWidth,
    'height': physicalHeight,
    'pixelRatio': pixelRatio,  // Add this
});
```

```java
Float pixelRatio = call.argument("pixelRatio");
if (pixelRatio != null) {
    density = pixelRatio;
}
```

## Decision

**Monitor** - No issues observed on tested devices. Add the fix if users report blurriness or touch offset issues.
