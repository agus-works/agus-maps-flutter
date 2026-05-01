# Search Implementation

This document records how search works in CoMaps and how the Flutter plugin
should expose the same behavior to the example app.

## Problem

The example app previously searched a small Dart-side list of hardcoded places.
That means visible map features, downloaded MWM data, localized category names,
addresses, streets, suggestions, and ranked offline results were never queried.
A user could see a restaurant, street, or POI in the current viewport and still
get no result because the Flutter app was not calling the CoMaps search engine.

## How CoMaps Search Works

CoMaps search is native, asynchronous, and built around `SearchAPI`:

- `thirdparty/comaps/libs/map/search_api.hpp`
- `thirdparty/comaps/libs/map/search_api.cpp`
- `thirdparty/comaps/libs/search/search_params.hpp`
- `thirdparty/comaps/libs/search/result.hpp`

`Framework` owns `SearchAPI` and exposes it through `Framework::GetSearchAPI()`.
The search API delegates UI callbacks back through `Framework::RunUITask()`, so
results are delivered asynchronously on the GUI thread.

### Search Modes

CoMaps has several modes, but the app-facing map search flow primarily uses two:

- `SearchEverywhere`: searches all registered/offline map data and returns the
  list shown in the search UI.
- `SearchInViewport`: searches the current visible map viewport and creates
  search marks on the map.

The Qt desktop implementation in `thirdparty/comaps/qt/search_panel.cpp` can
switch between these modes explicitly. Android uses an interactive flow in
`thirdparty/comaps/android/sdk/src/main/cpp/app/organicmaps/sdk/search/SearchEngine.cpp`:

1. Start `SearchInViewport` with the same query.
2. Start `SearchEverywhere` for the table/list results.
3. When everywhere search ends normally, call `PokeSearchInViewport()` so the
   viewport markers refresh against the latest visible rect.
4. Tapping a suggestion writes the suggestion into the search box.
5. Tapping a real result calls `Framework::ShowSearchResult(result)`.

The Flutter example should follow the Android interactive flow because it gives
both an on-map viewport search and a ranked result list.

### Search Parameters

`SearchAPI::SearchEverywhere()` builds `search::SearchParams` with:

- `m_mode = search::Mode::Everywhere`
- `m_query` from user input, without Dart-side normalization
- `m_inputLocale` from the platform input locale, falling back to `en`
- `m_position` from `SearchAPI::Delegate::GetCurrentPosition()` when available
- `m_viewport` from the current map viewport when initialized
- `m_maxNumResults = SearchParams::kDefaultNumResultsEverywhere` (30)
- `m_suggestsEnabled = true`
- `m_needAddress = true`
- `m_needHighlighting = true`
- `m_categorialRequest` from the UI category-search flag

`SearchAPI::SearchInViewport()` builds params with:

- `m_mode = search::Mode::Viewport`
- the same query, input locale, position, and viewport
- `m_maxNumResults = SearchParams::kDefaultNumResultsInViewport` (200)
- `m_suggestsEnabled = false`
- `m_needAddress = false`
- `m_needHighlighting = false`
- `m_categorialRequest` from the UI category-search flag

`SearchAPI` delays a request until the viewport is initialized. It also skips
similar repeated viewport queries unless forced.

### Result Delivery

Search results arrive through callbacks more than once. Each non-final callback
contains the full result list found so far, not only the new entries. A final
end marker announces completion or cancellation.

Each `search::Result` can be one of:

- `Feature`: a map feature/POI/street/etc. with feature id and center point.
- `LatLon`: a parsed coordinate result.
- `Postcode`: a postcode result with a center point.
- `PureSuggest`: a textual suggestion with no selectable map point.
- `SuggestFromFeature`: a suggestion tied to a feature.

Important fields/methods:

- `GetString()` gives the display title.
- `GetAddress()` gives the address/region string when requested.
- `GetLocalizedFeatureType()` gives a localized type such as restaurant,
  street, hotel, etc.
- `GetFeatureDescription()` combines localized type, matched subtype, and
  details.
- `IsSuggest()` tells the UI to treat the result as a query suggestion.
- `GetSuggestionString()` gives the query text to insert for suggestions.
- `HasPoint()` and `GetFeatureCenter()` provide the Mercator center for map
  results.
- `GetHighlightRange()`/`GetDescHighlightRange()` provide match highlighting.

Results are already ranked and deduplicated by the native engine. The Flutter UI
must preserve the native order.

### Selecting Results

Real map results must be selected with `Framework::ShowSearchResult(result)`,
not just by moving to raw coordinates. That function:

1. Cancels active searches.
2. Stops location follow.
3. Builds the native place page selection.
4. Chooses a feature-appropriate zoom/scale.
5. Centers the native viewport.
6. Activates the native map selection mark.

Suggestions must not call `ShowSearchResult()`. They should replace the text in
the search field and start a new search.

## Flutter Plugin Specification

The plugin exposes a small polling-based FFI bridge over CoMaps search. Polling
keeps the native callbacks inside C++ and avoids calling Dart from CoMaps search
threads.

### Native FFI Surface

The C header defines:

- `AgusSearchResult`: one flattened result row.
- `AgusSearchResults`: a snapshot of the current native search state.
- `comaps_search_start(query, locale, interactive, isCategory)`: starts a new
  search generation. Interactive mode starts viewport and everywhere search.
- `comaps_search_copy_results()`: returns the latest snapshot.
- `comaps_search_results_free(snapshot)`: frees a snapshot.
- `comaps_search_show_result(index)`: selects a native result by current result
  index using `Framework::ShowSearchResult()`.
- `comaps_search_cancel()`: cancels active native searches and clears bridge
  state.

The bridge snapshots include status so Dart can show an in-progress state:

- `idle`: no active query.
- `running`: native search has started and more callbacks may arrive.
- `completed`: native search ended normally.
- `cancelled`: native search was cancelled.
- `error`: bridge could not start or process the query.

### Dart API

The public Dart layer wraps the FFI structs in immutable Dart classes:

- `NativeSearchResult`
- `NativeSearchSnapshot`
- `NativeSearchStatus`

The example app uses:

- `startNativeSearch(query, locale: ..., interactive: true)`
- `getNativeSearchSnapshot()` on a short polling timer
- `showNativeSearchResult(index)` for real native rows
- `cancelNativeSearch()` when closing or clearing the search box

### Example App Behavior

The example search box should behave like CoMaps:

1. Debounce user input.
2. If the input is empty, cancel native search and clear local results.
3. If the input is coordinates, show a coordinate result immediately.
4. Start native interactive search after the map surface is ready.
5. Preserve native result order.
6. Keep local favorites as supplemental results, after native and coordinate
   results.
7. Do not use the hardcoded POI index as the primary search source.
8. Show a searching state while native search is running.
9. Tapping a suggestion replaces the query and searches again.
10. Tapping a native map result calls `showNativeSearchResult(index)`.
11. Tapping a local coordinate/favorite result moves the controller directly.

### Platform Coverage

All target platforms must compile the same FFI declarations:

- Android: `src/agus_maps_flutter.cpp`
- iOS: `ios/Classes/agus_maps_flutter_ios.mm`
- macOS: `macos/Classes/agus_maps_flutter_macos.mm`
- Linux: `src/agus_maps_flutter_linux.cpp`
- Windows: `src/agus_maps_flutter_win.cpp`

The implementation should share the bridge logic through a common helper header
so behavior remains consistent across platforms.

## Limitations

- This phase does not expose downloader search or bookmark search in Dart.
- Native highlight ranges are not exposed by this bridge yet. The example UI
  renders plain text until a richer highlighted text widget is added.
- Viewport search markers depend on the native framework's current viewport;
  searching before the map surface is ready should be ignored or delayed by Dart.
- The checked-in Android prebuilts under `android/prebuilt` predate this search
  bridge and do not export the `comaps_search_*` symbols. In-repo Android
  validation should build without `AGUS_MAPS_HOME`, or the prebuilts must be
  regenerated before shipping an external SDK package.
