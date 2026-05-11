# User Story: Search Persistence and Result Preservation

## As a map user
I want my search results to be cached and preserved after selection, so that I can explore multiple results without re-searching.

## Background
Previously, search results disappeared after selection, requiring users to re-enter queries to explore alternative results. Native CoMaps search is powerful but can be slow, especially on large datasets or when querying multiple MWM regions.

## Acceptance Criteria

### Result Preservation
- ✅ Search results remain visible in the sidebar after selecting a result
- ✅ Clicking a result focuses/zooms to it but does not close the search panel
- ✅ Users can navigate between multiple results without clearing the list
- ✅ The search field retains the query text after selection

### DuckDB Result Caching
- ✅ Search queries are cached in `agus.search_result_cache` table
- ✅ Cache entries include:
  - Normalized query string
  - Query locale
  - Map data revision fingerprint
  - Result payload (JSON)
  - Result count
  - Staleness flag and invalidation reason
  - Creation, update, and access timestamps

### Cache Hit Behavior
- ✅ Re-entering an exact query loads cached results instantly
- ✅ Native search still runs in background to refresh the cache
- ✅ User sees cached results immediately, updated results replace them when native search completes

### Cache Invalidation
- ✅ Cache entries are invalidated when:
  - MWM maps are added, deleted, hidden, shown, or upgraded
  - Map data revision fingerprint changes
- ✅ Stale cache entries are ignored for instant display
- ✅ Native search always runs to produce fresh results

### Map Data Revision Tracking
- ✅ Each cache entry stores a map data fingerprint
- ✅ Fingerprint is computed from visible MWM metadata (region name + version)
- ✅ Fingerprint changes trigger automatic cache invalidation
- ✅ Users never see outdated results from a different map state

## Implementation References

### Database Schema
- Table: `agus.search_result_cache`
- Schema documented in: `doc/schemas/README.md`

### Dart API
- `DuckDBLayerStore.upsertSearchCache()`
- `DuckDBLayerStore.getSearchCache()`
- `DuckDBLayerStore.searchCache()`
- `DuckDBLayerStore.invalidateSearchCacheByRevision()`
- `DuckDBLayerStore.invalidateAllSearchCache()`
- `DuckDBLayerStore.deleteSearchCache()`

### Native Bridge
- FFI bridge: `comaps_search_start()`, `comaps_search_copy_results()`, `comaps_search_cancel()`
- Polling-based result retrieval avoids Dart callbacks from native threads
- Status tracking: idle, running, completed, cancelled, error

### UI Behavior
- Search sidebar visibility: Controlled independently from result selection
- Result list: Preserved after selection, cleared only on explicit user action
- Command bar integration: Search commands feed queries into the same flow

## Testing Approach
- Manual: Open search, enter query, select multiple results, verify sidebar remains visible
- Manual: Re-enter exact query, verify instant cache hit, verify background refresh
- Manual: Add/remove MWM map, verify cache invalidation
- Unit: Test cache CRUD operations, invalidation logic, fingerprint generation

## Documentation
- Search implementation: `doc/IMPLEMENTATION-SEARCH.md`
- Database schemas: `doc/schemas/README.md`
- Command bar integration: `doc/COMMAND-BAR.md`

## Related Features
- Command-driven interaction state safety
- MWM ordering/upgrades/active map management
- Layer/feature focus centers
