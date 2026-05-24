# Navigation Implementation

This document records how path finding and turn-by-turn navigation work in
CoMaps and how `agus_maps_flutter` should expose that behavior to the example
Flutter app. The goal is to keep routing, matching, guidance, route rendering,
rerouting, and navigation-side settings in native code. Dart and Flutter should
act as a thin signaling layer and a host for app chrome around the native map UI.

## Goals

- Use CoMaps' native route engine instead of implementing route logic in Dart.
- Keep route geometry, route matching, turn generation, ETA, lane data, speed
  limits, speed cameras, rerouting, and route drawing in C++/native platform
  code.
- Expose small command/status APIs to Flutter for user intent: choose router,
  add route points, build, start following, stop, and apply settings.
- Let native CoMaps draw route lines, route point marks, road warning marks,
  speed camera marks, location arrow behavior, and navigation-follow camera.
- Keep the example app's settings tab aligned with CoMaps settings such as
  measurement units, voice guidance, speed camera warnings, and avoid options.
- Support Android, iOS, macOS, Linux, and Windows through the same FFI surface.

## CoMaps Navigation Stack

CoMaps navigation is centered around these native classes:

- `thirdparty/comaps/libs/map/framework.hpp`
- `thirdparty/comaps/libs/map/framework.cpp`
- `thirdparty/comaps/libs/map/routing_manager.hpp`
- `thirdparty/comaps/libs/map/routing_manager.cpp`
- `thirdparty/comaps/libs/routing/routing_session.hpp`
- `thirdparty/comaps/libs/routing/routing_session.cpp`
- `thirdparty/comaps/libs/routing/router.hpp`
- `thirdparty/comaps/libs/routing/index_router.hpp`
- `thirdparty/comaps/libs/routing/index_router.cpp`
- `thirdparty/comaps/libs/routing/route.hpp`
- `thirdparty/comaps/libs/routing/following_info.hpp`
- `thirdparty/comaps/libs/routing/routing_callbacks.hpp`
- `thirdparty/comaps/libs/routing/routing_settings.hpp`
- `thirdparty/comaps/libs/routing/routing_options.hpp`
- `thirdparty/comaps/libs/routing/speed_camera_manager.hpp`

`Framework` owns one `RoutingManager`. `RoutingManager` owns a
`routing::RoutingSession` and is the app-facing native coordinator for all route
planning and active navigation operations. `RoutingSession` owns the current
`Route`, route state, route matching state, rerouting thresholds, turn
notification manager, and speed camera manager. `IndexRouter` performs the real
graph routing for car, pedestrian, bicycle, and transit modes.

### Responsibility Split

`Framework`:

- Owns `RoutingManager`, `TrafficManager`, `TransitReadManager`, map storage,
  drape engine, bookmarks, search, and location-related UI plumbing.
- Creates the routing manager with callbacks to data source, country info,
  strings bundle, and power manager.
- Registers maps and gives routing access to local MWM files.
- For route following, forwards camera/follow behavior to `df::DrapeEngine`.

`RoutingManager`:

- Stores selected `RouterType`.
- Converts route point marks into `routing::Checkpoints`.
- Creates the selected router implementation through `SetRouterImpl()`.
- Starts route building with `BuildRoute()`.
- Inserts successful routes into drape with `InsertRoute()`.
- Maintains route point marks, transit marks, road warning marks, and speed
  camera marks through `BookmarkManager` edit sessions.
- Enables route following with `FollowRoute()`.
- Closes or removes routes with `CloseRouting()` and `RemoveRoute()`.
- Pushes GPS updates into the routing session with `CheckLocationForRouting()`.
- Triggers rebuilds when `RoutingSession` reports `RouteNeedsRebuild`.
- Produces app-facing `routing::FollowingInfo` snapshots.

`RoutingSession`:

- Owns the active route and session state.
- Calls `AsyncRouter`/`IRouter` to build and rebuild routes.
- Tracks route state with `routing::SessionState`.
- Matches GPS locations to the active route or nearby road graph.
- Detects movement away from the route and requests rerouting.
- Advances current route segment, subroute, checkpoints, and completion percent.
- Generates turn notifications and speed camera notifications.
- Holds `RoutingSettings` for matching thresholds, finish tolerance, turn
  display behavior, and rebuild sensitivity.

`IndexRouter` and routing graph classes:

- Load MWM road graphs through `IndexGraphLoader`.
- Build cross-MWM routes with `CrossMwmGraph` and `SingleVehicleWorldGraph`.
- Apply route options from `RoutingOptions::LoadCarOptionsFromSettings()`.
- Use `VehicleType`-specific estimators and vehicle models.
- Generate route segments, directions, road names, lane info, traffic, speed
  limits, and altitude data when available.

## Router Types

CoMaps defines `routing::RouterType` in `routing/router.hpp`:

- `Vehicle = 0`: car routing.
- `Pedestrian = 1`: walking route.
- `Bicycle = 2`: bicycle route.
- `Transit = 3`: pedestrian plus transit route.
- `Ruler = 4`: straight-line ruler route.

`RoutingManager::SetRouterImpl()` maps router types to vehicle types:

- `Vehicle` -> `VehicleType::Car`
- `Pedestrian` -> `VehicleType::Pedestrian`
- `Bicycle` -> `VehicleType::Bicycle`
- `Transit` -> `VehicleType::Transit`
- `Ruler` -> `RulerRouter`

For non-ruler routes, it creates an `IndexRouter` with country lookup,
registered MWM ids, vehicle model, altitudes flag, and the routing session.
Pedestrian, bicycle, and transit routes load altitude data where supported.

The selected router type is persisted by CoMaps under the `router` settings key
through `RoutingManager::SetLastUsedRouter()`. The plugin should call native
`SetRouter()` and should not keep an independent Dart-only selected router.

## Route Points

Route points are native route marks, not Dart objects that the map renderer must
draw. The core data type is `RouteMarkData` in `map/routing_mark.hpp`:

- `m_pointType`: `Start`, `Intermediate`, or `Finish`.
- `m_title` and `m_subTitle`: display/search text.
- `m_intermediateIndex`: stable ordering for intermediate stops.
- `m_isMyPosition`: route start can follow current device location.
- `m_position`: Mercator position.

`RoutingManager::AddRoutePoint()` writes these marks through
`RoutePointsLayout`. Start and finish points replace existing marks of the same
type. Intermediate points are reordered with `CheckpointPredictor` so a newly
added stop lands in a likely route order between start and finish.

The Flutter app should signal intent to native:

1. Clear existing points when starting a new plan.
2. Add a start point, using `isMyPosition` when the route should begin at the
   current native location.
3. Add zero or more intermediate points.
4. Add a finish point.
5. Call native route build.

The Flutter app should not draw route point markers itself unless it is only
rendering overlay controls outside the map. The native map already knows how to
draw and update route marks.

## Route Building Flow

`RoutingManager::BuildRoute()` is the high-level route build entry point:

1. Reads native route points from `RoutePointsLayout`.
2. Requires at least two points.
3. Replaces `isMyPosition` points with the current native my-position mark.
4. Rejects equal points.
5. Closes the previous active route while keeping route points.
6. Shows native route preview segments between route points.
7. Clears the position accumulator and seeds current position from the start.
8. Converts route point Mercator positions to `routing::Checkpoints`.
9. Calls `RoutingSession::BuildRoute()`.

`RoutingSession::BuildRoute()` changes state to `RouteBuilding`, asks the async
router to calculate, and later receives a route through its ready callback.
`RoutingSession::AssignRoute()` validates the result, resets old route state,
stores the new route, updates speed camera manager state, and moves to
`RouteNotStarted` when successful.

`RoutingManager::OnBuildRouteReady()` then:

1. Hides preview segments.
2. Calls `InsertRoute()` to send route geometry to drape.
3. Stops location follow so the user can inspect the built route.
4. Zooms to the full route for single-subroute non-ruler routes.
5. Calls the route building listener with `NoError`, `HasWarnings`, or an error.

Errors are represented by `routing::RouterResultCode` in
`routing/routing_callbacks.hpp`, including missing current position, start/end
not found, route not found, maps missing, stale files, transit route failures,
and internal errors.

## Route Rendering

Route drawing is native. `RoutingManager::InsertRoute()` reads route subroutes
and creates `df::Subroute` instances for `df::DrapeEngine::AddSubroute()`.

Styles are chosen by router type:

- Car: `df::RouteType::Car`, route color plus outline, traffic colors, turn
  distances.
- Bicycle: `df::RouteType::Bicycle`, bicycle pattern and turn distances.
- Pedestrian: `df::RouteType::Pedestrian`, pedestrian dashed pattern.
- Transit: `df::RouteType::Transit`, processed through `TransitRouteDisplay`
  with transit marks.
- Ruler: `df::RouteType::Ruler`, ruler pattern.

The route renderer also receives:

- Polyline points.
- Subroute base distance and depth.
- Fake-edge head/tail distances to avoid visual artifacts at snapped route
  ends.
- Traffic speed groups for car routes.
- Distances to rendered turn marks.

Flutter should not reconstruct this polyline for normal route drawing. If a
future Flutter overlay needs a summary, it should consume a native snapshot or
thumbnail generated by CoMaps rather than drawing a second route layer.

## Route Warnings And Avoid Options

CoMaps supports car routing options through `routing::RoutingOptions`:

- `Toll = 1 << 1`
- `Motorway = 1 << 2`
- `Ferry = 1 << 3`
- `Dirty = 1 << 4` for unpaved/track-like roads

Options are persisted by `RoutingOptions::SaveCarOptionsToSettings()` under
`avoid_routing_options_car`. `IndexRouter::MakeWorldGraph()` loads them for all
route builds and passes them into graph loaders and world graph routing. This is
important: avoid options must be set before route calculation, not applied after
a route is built.

`RoutingManager::CollectRoadWarnings()` scans built route segments for warning
road types. For car routes, warning marks are created for toll, ferry, and dirty
segments. `RouterResultCode::HasWarnings` is returned when warnings exist, so
the UI can offer to change options or accept the route.

The example settings tab now exposes:

- Avoid tolls.
- Avoid motorways.
- Avoid ferries.
- Avoid unpaved roads.

These feed the native `RoutingOptions` settings through the plugin FFI bridge.

## Following And Active Navigation

`RoutingManager::FollowRoute()` starts active navigation:

1. Calls `RoutingSession::EnableFollowMode()`.
2. Blocks transit scheme mode while following.
3. Notifies the framework delegate with the active router type.
4. Clears road warning marks.
5. Hides the start route point.
6. Puts route point marks into following mode.
7. Cancels route rebuild recommendations related to restored points.

`RoutingSession::EnableFollowMode()` moves `RouteNotStarted` or `OnRoute` to
`OnRoute` and sets `m_isFollowing`.

`Framework::FollowRoute()` and `DrapeEngine::FollowRoute()` handle camera
behavior: preferred zoom, 3D route zoom, auto zoom, perspective, and whether the
location arrow is glued to the route. That is a native concern. Flutter should
ask native to follow the route and then let the native renderer/camera manage
the map.

## Location Updates, Route Matching, And Rerouting

`RoutingManager::OnLocationUpdate()` feeds raw GPS data into the extrapolator.
The extrapolator keeps smooth arrow movement whether routing is active or not.
Its callback calls `RoutingManager::OnExtrapolatedLocationUpdate()`.

For each extrapolated GPS update, the routing manager:

1. Copies the GPS info.
2. Calls `GetRouteMatchingInfo()`.
3. `GetRouteMatchingInfo()` calls `CheckLocationForRouting()`.
4. `CheckLocationForRouting()` calls `RoutingSession::OnLocationPositionChanged()`.
5. If the session state becomes `RouteNeedsRebuild`, native starts a rebuild
   from the current GPS location and adjusts to the previous route when possible.
6. It then matches the GPS point to the active route or, for car routing, to the
   road graph.
7. It sends the matched GPS info, navigation flag, distance to next turn, speed
   limit, and route matching info into `DrapeEngine::SetGpsInfo()`.

`RoutingSession::OnLocationPositionChanged()` advances the route iterator when
the location matches the route. It passes checkpoints, detects finish, updates
speed camera state, records last good position, and fires the new-turn callback.
When movement drifts away from the route, it uses distance sensitivity,
speed-aware penalties, and missed-count thresholds before changing state to
`RouteNeedsRebuild`.

This is why route matching must stay native. Moving it to Dart would duplicate
the route polyline, route iterator, road graph projection, threshold tuning, and
rerouting state machine.

## Following Info Snapshot

`routing::FollowingInfo` is the native summary object for navigation UI:

- Distance to target as `platform::Distance`.
- Distance to next turn as `platform::Distance`.
- Primary car turn and secondary car turn.
- Roundabout exit number.
- ETA in seconds.
- Lane information.
- Pending turn notification strings.
- Current, next, and next-next street names.
- Completion percent.
- Pedestrian turn.
- Current speed limit in meters per second.
- Routing session state.
- Next intermediate stop index.
- Distance/time to next intermediate stop.

`RoutingSession::GetRouteFollowingInfo()` fills this from the active `Route`.
It uses CoMaps' native formatting rules for distances, native road-name logic,
native lane thresholds, and native turn-notification manager state.

The plugin now exposes `NavigationStatus` as a snapshot wrapper around native
following info. This should be enough for Flutter chrome such as a compact
navigation dashboard, but the native map remains responsible for route drawing,
route matching, and follow-camera behavior.

## Turn Notifications And Voice

Turn notification text is generated by native CoMaps:

- `RoutingManager::EnableTurnNotifications()` toggles notification generation.
- `RoutingManager::SetTurnNotificationsLocale()` sets TTS locale.
- `RoutingManager::SetTurnNotificationsUnits()` sets metric/imperial wording.
- `RoutingManager::GenerateNotifications()` returns current turn and speed
  camera notification strings and consumes them.

The Android app calls `Framework.nativeGenerateNotifications(announceStreets)`
from `NavigationService` when location updates arrive, then passes strings to
`TtsPlayer`. iOS does the same through `MWMRoutingManager` and listeners.

For Flutter, the right architecture is:

1. Native routing generates notification strings.
2. Flutter may own the platform TTS plugin or platform-specific service.
3. Flutter requests generated notifications only on native/location events or a
   low-frequency bridge callback, not on every frame.
4. The `announceStreetNames` setting should be passed to the native notification
   generation call when that call is exposed.

This phase exposes native toggles and locale. A later phase should expose a
notification-drain API or event stream that mirrors Android/iOS behavior.

## Speed Cameras And Speed Limits

`routing::SpeedCameraManager` is owned by `RoutingSession` and updated from GPS
updates while on route. It supports these modes:

- `Auto`: warn only when the user has risk of exceeding the speed limit.
- `Always`: warn for visible/upcoming cameras regardless of current speed.
- `Never`: do not warn, but the route can still cache/highlight camera data.

CoMaps also exposes current speed limit through `FollowingInfo::m_speedLimitMps`.
If the value is negative, no speed limit is known. If it is zero, there is no max
speed. Positive values are meters per second.

The example settings tab now exposes speed camera mode and speed limit display
preference. Speed camera mode is native. Speed limit display is stored for the
future navigation dashboard; the underlying speed limit value already comes from
native following info.

## Measurement Units

CoMaps stores measurement units under `settings::kMeasurementUnits` with
`measurement_utils::Units`:

- `Metric = 0`
- `Imperial = 1`

`platform::Distance::CreateFormatted()` reads the current measurement setting
and returns values in meters/kilometers or feet/miles. Speed camera labels,
speed formatting, altitude summaries, and turn notification text also use this
setting.

The example settings tab now writes measurement units through native FFI. The
bridge also calls `RoutingManager::SetTurnNotificationsUnits()` when a framework
is available so voice guidance switches units immediately.

## Android Reference Flow

CoMaps Android splits navigation into SDK/native and app UI layers:

- `thirdparty/comaps/android/sdk/src/main/java/app/organicmaps/sdk/routing/RoutingController.java`
- `thirdparty/comaps/android/sdk/src/main/java/app/organicmaps/sdk/routing/RoutingInfo.java`
- `thirdparty/comaps/android/sdk/src/main/java/app/organicmaps/sdk/Framework.java`
- `thirdparty/comaps/android/sdk/src/main/cpp/app/organicmaps/sdk/Framework.cpp`
- `thirdparty/comaps/android/app/src/main/java/app/organicmaps/routing/NavigationController.java`
- `thirdparty/comaps/android/app/src/main/java/app/organicmaps/routing/NavigationService.java`

`RoutingController` owns the UI state machine:

- `NONE`
- `PREPARE`
- `NAVIGATION`

It also tracks build state:

- `NONE`
- `BUILDING`
- `BUILT`
- `ERROR`

It registers native listeners:

- Route result listener.
- Progress listener.
- Recommendation listener.
- Saved route points load listener.

Native Android JNI exposes the same operations the Flutter plugin needs:

- `nativeBuildRoute()`
- `nativeFollowRoute()`
- `nativeDisableFollowing()`
- `nativeCloseRouting()`
- `nativeGetRouteFollowingInfo()`
- `nativeGenerateNotifications()`
- `nativeSetSpeedCamManagerMode()`
- `nativeGetSpeedCamManagerMode()`
- `nativeAddRoutePoint()`
- `nativeRemoveRoutePoint()`
- `nativeGetRoutePoints()`
- route point transactions and saved route point APIs

The Flutter plugin should follow this split: native owns route data and route
state; Flutter owns tab state, settings chrome, and lightweight controls.

## iOS Reference Flow

iOS wraps the same native manager through Objective-C/Swift:

- `thirdparty/comaps/iphone/Maps/Core/Framework/ProxyObjects/Routing/MWMRoutingManager.mm`
- `thirdparty/comaps/iphone/Maps/Core/Routing/MWMRouter.mm`
- `thirdparty/comaps/iphone/Maps/Core/Routing/MWMRouter+RouteManager.mm`
- `thirdparty/comaps/iphone/Maps/Classes/CustomViews/NavigationDashboard/MWMNavigationDashboardManager.mm`
- `thirdparty/comaps/iphone/Maps/Classes/CustomViews/NavigationDashboard/Views/NavigationTurnsView.swift`
- `thirdparty/comaps/iphone/Maps/UI/Routing/RoutingOptionsView.swift`

`MWMRoutingManager` exposes route points, route build/start/stop, speed camera
mode, following info, route listeners, and turn notification drain. It is a good
model for the plugin's native-first bridge because the UI layer asks for
snapshots and events without owning the route engine.

## Plugin Bridge Added In This Phase

The plugin now has a shared native helper:

- `src/agus_navigation_bridge.hpp`

It is exported from every supported native implementation:

- `src/agus_maps_flutter.cpp` for Android.
- `ios/agus_maps_flutter/Sources/agus_maps_flutter_native/agus_maps_flutter_ios.mm` for iOS.
- `macos/agus_maps_flutter/Sources/agus_maps_flutter_native/agus_maps_flutter_macos.mm` for macOS.
- `src/agus_maps_flutter_linux.cpp` for Linux.
- `src/agus_maps_flutter_win.cpp` for Windows.

The public C ABI lives in `src/agus_maps_flutter.h` and is regenerated into
`lib/agus_maps_flutter_bindings_generated.dart` with `ffigen`.

### Native Commands

The bridge exposes:

- `comaps_navigation_set_router(routerType)`
- `comaps_navigation_get_router()`
- `comaps_navigation_add_route_point(...)`
- `comaps_navigation_remove_route_point(markType, intermediateIndex)`
- `comaps_navigation_clear_route_points()`
- `comaps_navigation_build_route()`
- `comaps_navigation_follow_route()`
- `comaps_navigation_close_route(removeRoutePoints)`
- `comaps_navigation_is_active()`
- `comaps_navigation_is_built()`
- `comaps_navigation_is_building()`
- `comaps_navigation_is_following()`
- `comaps_navigation_copy_status()`
- `comaps_navigation_status_free(status)`

For route building, the helper installs no-op route result/progress callbacks so
native `RoutingManager::CallRouteBuilded()` always has a listener even before a
Flutter event stream is implemented. A future phase should replace the no-op
listener with a status bridge that captures result code, missing maps, and build
progress.

### Native Settings

The bridge exposes:

- `comaps_navigation_set_measurement_units(units)`
- `comaps_navigation_get_measurement_units()`
- `comaps_navigation_set_turn_notifications_enabled(enabled)`
- `comaps_navigation_get_turn_notifications_enabled()`
- `comaps_navigation_set_turn_notifications_locale(locale)`
- `comaps_navigation_set_speed_camera_mode(mode)`
- `comaps_navigation_get_speed_camera_mode()`
- `comaps_navigation_set_avoid_routing_options(mask)`
- `comaps_navigation_get_avoid_routing_options()`

These settings are intentionally native. Dart persists the example app's user
preference and then writes it into CoMaps when the native surface is ready.

### Dart API

`lib/agus_maps_flutter.dart` now wraps the native surface with:

- `NavigationRouterType`
- `NavigationRoutePointType`
- `NavigationMeasurementUnits`
- `NavigationSpeedCameraMode`
- `NavigationSessionState`
- `NavigationDistanceUnit`
- `NavigationDistance`
- `NavigationRoutingOptions`
- `NavigationSettings`
- `NavigationStatus`

Command wrappers:

- `setNavigationRouter()`
- `getNavigationRouter()`
- `addNavigationRoutePoint()`
- `removeNavigationRoutePoint()`
- `clearNavigationRoutePoints()`
- `buildNavigationRoute()`
- `followNavigationRoute()`
- `closeNavigationRoute()`
- `getNavigationStatus()`

Settings wrappers:

- `applyNavigationSettings()`
- `setNavigationMeasurementUnits()`
- `getNavigationMeasurementUnits()`
- `setNavigationTurnNotificationsEnabled()`
- `getNavigationTurnNotificationsEnabled()`
- `setNavigationTurnNotificationsLocale()`
- `setNavigationSpeedCameraMode()`
- `getNavigationSpeedCameraMode()`
- `setNavigationRoutingOptions()`
- `getNavigationRoutingOptions()`

## Example Settings

`example/lib/settings_tab.dart` now includes a navigation card with:

- Metric/imperial units.
- Voice guidance.
- Street names in voice.
- Speed limit display.
- Speed camera warning mode.
- Avoid tolls.
- Avoid motorways.
- Avoid ferries.
- Avoid unpaved roads.

`example/lib/main.dart` persists these values in `SharedPreferences` and applies
them to native CoMaps after the map surface is ready. This mirrors the existing
map appearance/layers approach: Flutter stores app preference, native owns map
behavior.

## Flutter Route Planning UI

The first route planning UI is intentionally small and native-backed:

1. User selects a destination from search or place page.
2. Flutter derives a preview start point from the current viewport center, then
  falls back to the bundled Gibraltar start when the viewport is too close to
  the destination.
3. Flutter calls native `clearNavigationRoutePoints()` and sets CoMaps vehicle
  routing.
4. Flutter asks native to set start and finish route points.
5. Flutter calls native `buildNavigationRoute()`.
6. Native calculates and renders preview route geometry and route marks.
7. Flutter shows a compact route panel backed by `getNavigationStatus()`
  polling.
8. User taps start.
9. Flutter calls native `followNavigationRoute()`.
10. Native switches camera/following/rendering behavior when native location
   state allows route following.

The route planner should not serialize route geometry through Dart for normal
display. It should only ask native for high-level status and user-readable
summary data.

### Manual Example Test

1. Build and run the example app on Android or macOS.
2. Open the map tab and wait for the map to render Gibraltar.
3. Search for a Gibraltar place, for example `Europa Point`, or enter
  coordinates such as `36.11185, -5.34582`.
4. Tap the route icon in the search result row, or tap a map place and use the
  route button in the place sheet.
5. Confirm that the route panel appears and reports building/ready/no-route
  state from native CoMaps.
6. When route ready is shown, confirm that the native map renders the route
  preview line and route marks.
7. Tap start to request native following mode. On devices without usable
  location updates, the preview route is still the primary testable result;
  full turn-by-turn following requires a native location near the route.
8. Tap clear to close native routing and remove route points.

## Future Navigation Dashboard

The dashboard should be a Flutter overlay, but all data should come from native
following info:

- Next turn icon from `turn`.
- Distance to turn from native formatted distance.
- Next street name from native road name logic.
- Optional second turn from `nextTurn`.
- Lane widgets from a future lane bridge.
- ETA and distance remaining from native following info.
- Current speed/speed limit from location plus native speed limit.
- Speed camera warning from native speed camera callbacks.
- Stop button calls `closeNavigationRoute(removeRoutePoints: true)`.

Turn enum values should mirror CoMaps' `routing::turns::CarDirection` and must
not be reordered. The same is true for `PedestrianDirection` and lane values
when they are exposed.

## Future Event Bridge

Polling `getNavigationStatus()` is acceptable for early UI work, but the final
implementation should add native events for low-frequency state changes:

- Route build started.
- Route build progress.
- Route build result with missing maps.
- Session state changed.
- New turn.
- Speed camera entered/left visible area.
- Route point passed.
- Route finished.

This can be implemented with Pigeon `FlutterApi` for low-frequency events or a
native snapshot queue like search. The native side should still own the callback
registration. Flutter should not receive high-frequency GPS or route geometry
updates unless there is a specific UI need.

## Platform Coverage Strategy

The routing engine itself is common C++. The plugin should keep all platform
implementations exporting the same C ABI even when platform UI differs.

Android:

- Uses `src/agus_maps_flutter.cpp` and the CoMaps Android platform layer.
- Native map rendering remains SurfaceTexture/OpenGL.
- Future voice guidance can use a foreground service or Flutter/platform TTS.

iOS:

- Uses `ios/agus_maps_flutter/Sources/agus_maps_flutter_native/agus_maps_flutter_ios.mm`.
- Native map rendering remains Metal/IOSurface.
- Future voice can mirror `MWMRoutingManager` notification drain plus iOS TTS.

macOS:

- Uses `macos/agus_maps_flutter/Sources/agus_maps_flutter_native/agus_maps_flutter_macos.mm`.
- Native map rendering remains Metal/IOSurface.
- Route planning should work through the common C++ manager; location provider
  availability is the main platform-specific concern.

Linux:

- Uses `src/agus_maps_flutter_linux.cpp`.
- Native map rendering remains EGL/OpenGL with pixel buffer texture.
- Location and TTS may need separate desktop implementations.

Windows:

- Uses `src/agus_maps_flutter_win.cpp`.
- Native map rendering remains WGL/OpenGL with D3D11 texture transfer.
- Location and TTS may need separate desktop implementations.

## Performance Notes

- Route calculation must stay off the Flutter UI isolate. CoMaps already runs
  route calculation asynchronously in native routing threads.
- Route matching must stay native because it needs route iterators, current
  route segment state, road graph projection, matching thresholds, and reroute
  state.
- Route drawing must stay native because drape already has optimized route
  subroute rendering, traffic coloring, and turn-distance rendering.
- Dart should avoid per-frame navigation calls. Poll status at dashboard cadence
  only until native events exist.
- Large geometry should not cross FFI unless there is a specific export feature
  such as saving GPX or showing an altitude chart.
- Settings should be written before route build, especially avoid options.
- Measurement units should be set before requesting following snapshots or turn
  notifications so native formatted distances are already correct.

## Implementation Checklist

Current phase:

- Shared native navigation FFI bridge across Android, iOS, macOS, Linux, and
  Windows.
- Dart navigation models and wrappers.
- Example settings for units, voice guidance, speed cameras, speed limit display,
  and avoid route options.
- Detailed CoMaps navigation architecture notes in this document.

Next phases:

- Add route build result/progress event bridge.
- Add place-page/search actions for route-to-here, route-from-here, and add stop.
- Add route planning overlay that calls native route point/build APIs.
- Add compact navigation dashboard driven by `NavigationStatus`.
- Add voice notification drain API and platform TTS/service integration.
- Add lane info and speed camera event bridge.
- Add route point transactions for drag/reorder workflows.
- Add saved route point restore flow.
- Add tests for settings persistence, FFI mask conversion, and route command
  error handling.
