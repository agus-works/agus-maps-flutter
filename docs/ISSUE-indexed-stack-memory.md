# ISSUE: IndexedStack Keeps All Tabs in Memory

## Severity: Medium

## Description

The example app uses `IndexedStack` to maintain state across tab switches, which keeps all four tabs (including the map) in the widget tree simultaneously. While this prevents map re-initialization when switching tabs, it means the downloads list and settings widgets remain in memory even when not visible.

## Location

- [example/lib/main.dart](../example/lib/main.dart) - `_MyAppState.build()` method

## Current Behavior

```dart
child: IndexedStack(
    index: _currentTabIndex,
    children: [
        _buildMapTab(),        // Always in memory
        _buildFavoritesTab(),  // Always in memory
        _buildDownloadsTab(),  // Always in memory
        const SettingsTab(),   // Always in memory
    ],
),
```

## Impact

- **Memory**: ~5-20MB extra RAM for non-visible tabs
- **Battery**: Minimal (hidden tabs don't render)
- **Startup**: All tabs initialize on first build

## Trade-off Analysis

### Keeping IndexedStack (Current)
**Pros:**
- Map texture persists across tab switches (critical!)
- No re-initialization lag when switching tabs
- Scroll position preserved in lists

**Cons:**
- Higher memory baseline
- All tabs built on startup

### Using Conditional Rendering
**Pros:**
- Lower memory when viewing non-map tabs
- Faster initial startup

**Cons:**
- Map must re-initialize when switching back (very slow!)
- OpenGL context recreation
- Asset re-registration

## Why This Is Actually Correct

The map tab contains a `Texture` widget connected to native OpenGL rendering. If the map widget is removed from the tree:

1. `SurfaceProducer` gets destroyed
2. Native EGL surface becomes invalid
3. OpenGL context must be recreated
4. Map tiles must be re-rendered

This costs 2-5 seconds on older devices vs. the ~10MB RAM cost of IndexedStack.

## Recommendation

**Keep the current implementation.** The memory cost is justified for maps. Consider:

1. Using `AutomaticKeepAliveClientMixin` for just the map tab
2. Disposing heavy resources in non-map tabs when hidden

```dart
// Example: Dispose downloads list when hidden
class DownloadsTab extends StatefulWidget {
    final bool isVisible;
    // ... pause network requests when !isVisible
}
```

## Decision

**By Design** - This is the correct architecture for maintaining map state. The example app already passes `isVisible` to `DownloadsTab` for optimization.
