# IMPL-04: Map Downloads Tab

## Overview

The example app includes a Downloads tab for discovering CoMaps mirrors,
browsing map regions, downloading `.mwm` files, tracking progress, and removing
installed maps.

The current UI follows the upstream CoMaps `countries.txt` hierarchy. The root
browser shows expandable country/region folders first; leaf `.mwm` files appear
only after expanding their parent, or directly in search results.

## Data Flow

1. `MirrorService.discoverMirrors()` starts with the CoMaps source defaults,
   merges any additional hosts returned by
   `https://cdn-us-1.comaps.app/servers`, and probes availability.
2. `getCountriesData()` fetches and parses the hierarchical `countries.txt`
   payload.
3. The Downloads tab stores the top-level regions for browsing and flattens the
   tree only for search or download execution.
4. Group download/delete actions resolve to descendant leaf regions.
5. Downloaded metadata is stored through `MwmStorage` and registered with the
   native map engine after a successful file write.

## Region Rules

- `MwmRegion.isGroup` means the region has child regions and is a folder in the
  browse UI.
- `MwmRegion.isLeaf` means the region maps to a downloadable `.mwm` file.
- `MwmRegion.totalDownloadSizeBytes` aggregates all descendant leaves for group
  rows.
- `MwmRegion.leafRegions` is the canonical list used for group download/delete
  operations.
- Top-level single-leaf countries may be wrapped by the UI as expandable browser
  roots so the initial view stays folder-oriented.

## Search Behavior

Search intentionally differs from browse mode. While browse mode preserves the
folder tree, search flattens the tree and returns matching leaf regions so users
can jump directly to a downloadable map.

## Cache Behavior

The downloads cache key is `downloads_cache_v2`. This invalidates the older flat
cache format and forces the app to refetch hierarchical region data. Cached
region data is still validated against the selected mirror before use.

## Layout Notes

The tab uses flexible layouts that are safe on smaller desktop windows and
mobile screens:

- Header status chips use `Wrap` instead of a fixed `Row`, preventing vertical
  overflow when labels are wide.
- The expanded mirror selector is height-constrained so it cannot force the main
  `Column` past its available height.
- The region list owns the remaining space through an expanded scrollable list.

## Verification

The current implementation was checked with:

```bash
dart format lib/mirror_service.dart lib/src/mirror_utils.dart \
  example/lib/downloads_tab.dart example/lib/downloads_cache.dart \
  tool/check_mirrors.dart tool/map_downloader.dart
dart analyze
dart run tool/check_mirrors.dart
```

Apple example builds were then verified from `example/`:

```bash
flutter build ios --debug --no-codesign --no-pub
flutter build macos --debug --no-pub
```
