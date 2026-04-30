import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'src/agus_maps_api.g.dart';

import 'agus_maps_flutter_bindings_generated.dart';

// Export additional services
export 'mwm_storage.dart';
export 'mirror_service.dart';
export 'src/agus_maps_api.g.dart'
    show
        PlacePageData,
        PlacePageFeatureId,
        PlacePageCoordinates,
        PlacePageIntMetadataEntry,
        PlacePageStringMetadataEntry,
        RenderState;

/// Low-frequency map-ready event emitted by native platforms.
class MapReadyEvent {
  final int surfaceId;

  const MapReadyEvent(this.surfaceId);
}

/// Low-frequency render state change event emitted by native platforms.
class RenderStateChangedEvent {
  final RenderState state;
  final int? surfaceId;

  const RenderStateChangedEvent(this.state, this.surfaceId);
}

/// Low-frequency place page change event emitted by native platforms.
class PlacePageChangedEvent {
  final PlacePageData? placePage;

  const PlacePageChangedEvent(this.placePage);
}

/// Broadcast streams for low-frequency native notifications.
class AgusMapsFlutterEvents {
  AgusMapsFlutterEvents._() {
    AgusMapsFlutterApi.setUp(_AgusMapsFlutterApiHandler(this));
  }

  static final AgusMapsFlutterEvents instance = AgusMapsFlutterEvents._();

  final StreamController<MapReadyEvent> _mapReadyController =
      StreamController<MapReadyEvent>.broadcast();
  final StreamController<RenderStateChangedEvent>
      _renderStateChangedController =
      StreamController<RenderStateChangedEvent>.broadcast();
  final StreamController<PlacePageChangedEvent> _placePageChangedController =
      StreamController<PlacePageChangedEvent>.broadcast();

  Stream<MapReadyEvent> get onMapReady => _mapReadyController.stream;
  Stream<RenderStateChangedEvent> get onRenderStateChanged =>
      _renderStateChangedController.stream;
  Stream<PlacePageChangedEvent> get onPlacePageChanged =>
      _placePageChangedController.stream;

  void _emitMapReady(int surfaceId) {
    _mapReadyController.add(MapReadyEvent(surfaceId));
  }

  void _emitRenderStateChanged(RenderState state, int? surfaceId) {
    _renderStateChangedController.add(
      RenderStateChangedEvent(state, surfaceId),
    );
  }

  void _emitPlacePageChanged(PlacePageData? placePage) {
    _placePageChangedController.add(PlacePageChangedEvent(placePage));
  }
}

class _AgusMapsFlutterApiHandler extends AgusMapsFlutterApi {
  final AgusMapsFlutterEvents _events;

  _AgusMapsFlutterApiHandler(this._events);

  @override
  void onMapReady(int surfaceId) {
    _events._emitMapReady(surfaceId);
  }

  @override
  void onRenderStateChanged(RenderState state, int? surfaceId) {
    _events._emitRenderStateChanged(state, surfaceId);
  }

  @override
  void onPlacePageChanged(PlacePageData? placePage) {
    // Place page data arrives pre-localized from native layer.
    // No Dart-side localization needed - native handles all type translations.
    _events._emitPlacePageChanged(placePage);
  }
}

// NOTE: PlacePageLocalization class has been removed.
// All localization is now handled by native code via setLocale().
// POI type names arrive pre-localized in place page subtitle.

/// Get the current place page data, if available.
/// Place page data arrives pre-localized from native layer.
Future<PlacePageData?> getCurrentPlacePage() async {
  try {
    return await AgusMapsHostApi().getCurrentPlacePage();
  } catch (error) {
    debugPrint('[AgusMap] Failed to fetch place page: $error');
    return null;
  }
}

void closePlacePage() {
  AgusMapsHostApi().clearPlacePageSelection();
}

/// A very short-lived native function.
///
/// For very short-lived functions, it is fine to call them on the main isolate.
/// They will block the Dart execution while running the native function, so
/// only do this for native functions which are guaranteed to be short-lived.
int sum(int a, int b) => _bindings.sum(a, b);

/// A longer lived native function, which occupies the thread calling it.
///
/// Do not call these kind of native functions in the main isolate. They will
/// block Dart execution. This will cause dropped frames in Flutter applications.
/// Instead, call these native functions on a separate isolate.
///
/// Modify this to suit your own use case. Example use cases:
///
/// 1. Reuse a single isolate for various different kinds of requests.
/// 2. Use multiple helper isolates for parallel execution.
Future<int> sumAsync(int a, int b) async {
  final SendPort helperIsolateSendPort = await _helperIsolateSendPort;
  final int requestId = _nextSumRequestId++;
  final _SumRequest request = _SumRequest(requestId, a, b);
  final Completer<int> completer = Completer<int>();
  _sumRequests[requestId] = completer;
  helperIsolateSendPort.send(request);
  return completer.future;
}

final AgusMapsHostApi _hostApi = AgusMapsHostApi();
final AgusMapsFlutterEvents _flutterEvents = AgusMapsFlutterEvents.instance;

/// Access to low-frequency native event streams.
AgusMapsFlutterEvents get mapsFlutterEvents => _flutterEvents;

Future<String> extractMap(String assetPath) async {
  return _hostApi.extractMap(assetPath);
}

/// Extract all CoMaps data files (classificator, types, categories, etc.)
/// Returns the path to the directory containing the extracted files.
Future<String> extractDataFiles() async {
  return _hostApi.extractDataFiles();
}

Future<String> getApkPath() async {
  return _hostApi.getApkPath();
}

void init(String apkPath, String storagePath) {
  final apkPathPtr = apkPath.toNativeUtf8().cast<Char>();
  final storagePathPtr = storagePath.toNativeUtf8().cast<Char>();
  _bindings.comaps_init(apkPathPtr, storagePathPtr);
  malloc.free(apkPathPtr);
  malloc.free(storagePathPtr);
}

/// Initialize CoMaps with separate resource and writable paths
void initWithPaths(String resourcePath, String writablePath) {
  final resourcePathPtr = resourcePath.toNativeUtf8().cast<Char>();
  final writablePathPtr = writablePath.toNativeUtf8().cast<Char>();
  _bindings.comaps_init_paths(resourcePathPtr, writablePathPtr);
  malloc.free(resourcePathPtr);
  malloc.free(writablePathPtr);
}

/// Set the locale for native POI type localization.
///
/// This controls how POI type names are translated in place page data
/// (e.g., "amenity-fuel" → "Gas Station", "amenity-compressed_air" → "Compressed Air").
///
/// **When to call:**
/// - After [initWithPaths] so the resource directory with localization files is known
/// - Before creating the map surface or displaying any place pages for best results
/// - Can be called at any time to change locale (affects subsequent place page requests)
///
/// **Behavior:**
/// - If not called, the system locale is auto-detected (may not work reliably on all platforms)
/// - Explicitly calling this is recommended for consistent behavior across platforms
///
/// **Example:**
/// ```dart
/// final dataPath = await extractDataFiles();
/// initWithPaths(dataPath, dataPath);
/// setLocale(ui.PlatformDispatcher.instance.locale.toLanguageTag()); // e.g., "en-US"
/// await createMapSurface();
/// ```
///
/// [localeTag] - BCP 47 locale tag (e.g., "en-US", "zh-Hans", "de", "ja")
void setLocale(String localeTag) {
  final localeTagPtr = localeTag.toNativeUtf8().cast<Char>();
  try {
    _bindings.comaps_set_locale(localeTagPtr);
  } on ArgumentError {
    // Symbol may not exist on platforms where the binary was built before this feature.
    // Native will fall back to auto-detection based on system locale.
    if (kDebugMode) {
      debugPrint(
        '[AgusMap] setLocale: Symbol not found, using native auto-detection',
      );
    }
  } finally {
    malloc.free(localeTagPtr);
  }
}

void loadMap(String path) {
  final pathPtr = path.toNativeUtf8().cast<Char>();
  _bindings.comaps_load_map_path(pathPtr);
  malloc.free(pathPtr);
}

/// Register a single MWM map file directly by full path.
///
/// This bypasses the version folder scanning and registers the map file
/// directly with the rendering engine. Use this for MWM files that are
/// not in the standard version directory structure.
///
/// Returns 0 on success, negative values on error:
///   -1: Framework not initialized (call after map surface is created)
///   -2: Exception during registration
///   >0: MwmSet::RegResult error code
int registerSingleMap(String fullPath) {
  // Normalize path separators for Windows (convert / to \)
  String normalizedPath = fullPath;
  if (Platform.isWindows) {
    normalizedPath = fullPath.replaceAll('/', '\\');
  }
  final pathPtr = normalizedPath.toNativeUtf8().cast<Char>();
  try {
    return _bindings.comaps_register_single_map(pathPtr);
  } finally {
    malloc.free(pathPtr);
  }
}

/// Register a single MWM map file directly by full path, with an explicit
/// snapshot version (e.g. 251209).
///
/// This avoids the native side defaulting the LocalCountryFile version to 0,
/// which can cause `VersionTooOld (2)` for World/WorldCoasts and any region
/// where the engine expects a specific snapshot version.
int registerSingleMapWithVersion(String fullPath, int version) {
  String normalizedPath = fullPath;
  if (Platform.isWindows) {
    normalizedPath = fullPath.replaceAll('/', '\\');
  }
  final pathPtr = normalizedPath.toNativeUtf8().cast<Char>();
  try {
    try {
      return _bindings.comaps_register_single_map_with_version(
          pathPtr, version);
    } on ArgumentError {
      // Symbol may not exist on some platforms/binaries. Fall back to legacy API.
      return _bindings.comaps_register_single_map(pathPtr);
    }
  } finally {
    malloc.free(pathPtr);
  }
}

/// Debug: List all registered MWMs and their bounds.
/// Output goes to Android logcat (tag: AgusMapsFlutterNative).
void debugListMwms() {
  _bindings.comaps_debug_list_mwms();
}

/// Debug: Check if a lat/lon point is covered by any registered MWM.
/// Output goes to Android logcat (tag: AgusMapsFlutterNative).
///
/// Use this to verify that a specific location (like Manila) is covered
/// by one of the registered MWM files.
void debugCheckPoint(double lat, double lon) {
  _bindings.comaps_debug_check_point(lat, lon);
}

void setView(double lat, double lon, int zoom) {
  _bindings.comaps_set_view(lat, lon, zoom);
}

/// Invalidate the current viewport to force tile reload.
/// Call this after registering maps to ensure tiles are refreshed.
void invalidateMap() {
  _bindings.comaps_invalidate();
}

/// Force a complete redraw by updating the map style.
///
/// This clears all render groups and forces the BackendRenderer to re-request
/// all tiles from scratch. Use this after registering map files to ensure
/// tiles are loaded for newly registered regions.
///
/// This is more heavy-handed than [invalidateMap] and should be called when
/// maps are registered AFTER the DrapeEngine has been initialized, as the
/// engine may have already calculated tile coverage before the maps were
/// available.
void forceRedraw() {
  _bindings.comaps_force_redraw();
}

/// Touch event types
enum TouchType {
  none, // 0
  down, // 1
  move, // 2
  up, // 3
  cancel, // 4
}

/// Send a touch event to the map engine.
///
/// [type] is the touch event type (down, move, up, cancel).
/// [id1], [x1], [y1] are the first pointer's ID and coordinates.
/// [id2], [x2], [y2] are the second pointer's data (use -1 for id2 if single touch).
void sendTouchEvent(
  TouchType type,
  int id1,
  double x1,
  double y1, {
  int id2 = -1,
  double x2 = 0,
  double y2 = 0,
}) {
  _bindings.comaps_touch(type.index, id1, x1, y1, id2, x2, y2);
}

/// Scale (zoom) the map by a factor, centered on a specific pixel point.
///
/// [factor] is the zoom factor (>1 zooms in, <1 zooms out).
/// Use `exp(scrollDelta)` for smooth Google Maps-like scrolling.
/// [pixelX], [pixelY] are the screen coordinates to zoom towards (in physical pixels).
/// [animated] controls whether to animate the zoom transition.
///
/// This is the preferred method for scroll wheel zoom on desktop platforms,
/// matching the behavior of the Qt implementation.
void scaleMap(
  double factor,
  double pixelX,
  double pixelY, {
  bool animated = false,
}) {
  _bindings.comaps_scale(factor, pixelX, pixelY, animated ? 1 : 0);
}

/// Scroll/pan the map by pixel distance.
///
/// [distanceX], [distanceY] are the distances to scroll in physical pixels.
void scrollMap(double distanceX, double distanceY) {
  _bindings.comaps_scroll(distanceX, distanceY);
}

/// Create a map rendering surface with the given dimensions.
/// If width/height are not specified, uses the screen size.
/// [density] is the device pixel ratio (e.g., 1.5 for 150% scaling on Windows).
Future<int> createMapSurface({int? width, int? height, double? density}) async {
  final request = CreateMapSurfaceRequest(
    width: width,
    height: height,
    density: density,
  );
  return _hostApi.createMapSurface(request);
}

/// Resize the map surface to new dimensions.
///
/// [density] is optional; on Windows it updates visual scale when display DPI changes.
Future<void> resizeMapSurface(int width, int height, {double? density}) async {
  final request = ResizeMapSurfaceRequest(
    width: width,
    height: height,
    density: density,
  );
  await _hostApi.resizeMapSurface(request);
}

/// Destroy the active map surface if one exists.
Future<bool> destroyMapSurface() {
  return _hostApi.destroyMapSurface();
}

/// Controller for programmatic control of an AgusMap.
///
/// Use this to move the map, change zoom level, and other operations.
class AgusMapController {
  /// Move the map to the specified coordinates and zoom level.
  ///
  /// [lat] and [lon] specify the center point in WGS84 coordinates.
  /// [zoom] is the zoom level (typically 0-20, where higher is more zoomed in).
  void moveToLocation(double lat, double lon, int zoom) {
    setView(lat, lon, zoom);
  }

  /// Animate the map to the specified coordinates.
  /// Currently this is the same as moveToLocation; animation support
  /// will be added in a future version.
  void animateToLocation(double lat, double lon, int zoom) {
    // TODO: Implement animated camera movement
    setView(lat, lon, zoom);
  }

  /// Zoom in by one level.
  void zoomIn() {
    // TODO: Implement zoom level tracking and relative zoom
    debugPrint('[AgusMapController] zoomIn not yet implemented');
  }

  /// Zoom out by one level.
  void zoomOut() {
    // TODO: Implement zoom level tracking and relative zoom
    debugPrint('[AgusMapController] zoomOut not yet implemented');
  }
}

/// A Flutter widget that displays a CoMaps map.
///
/// The widget handles initialization, sizing, and gesture events.
class AgusMap extends StatefulWidget {
  /// Initial latitude for the map center.
  final double? initialLat;

  /// Initial longitude for the map center.
  final double? initialLon;

  /// Initial zoom level (0-20).
  final int? initialZoom;

  /// Callback when the map is ready.
  final VoidCallback? onMapReady;

  /// Callback when a place page (POI) is available after a tap.
  ///
  /// The callback receives null if no place page is available.
  final ValueChanged<PlacePageData?>? onPlacePage;

  /// Controller for programmatic map control.
  /// If not provided, the map can only be controlled via gestures.
  final AgusMapController? controller;

  /// Whether the map is currently visible.
  ///
  /// When false, resize operations are skipped to avoid unnecessary
  /// memory allocations (e.g., CVPixelBuffer recreation on iOS).
  /// This is important when using IndexedStack where the map widget
  /// remains in the tree but is not visible.
  ///
  /// The resize will be applied when the map becomes visible again.
  final bool isVisible;

  /// User-defined scale multiplier for labels/icons.
  ///
  /// This does not change zoom; it adjusts visual scale only.
  final double userScale;

  const AgusMap({
    super.key,
    this.initialLat,
    this.initialLon,
    this.initialZoom,
    this.onMapReady,
    this.onPlacePage,
    this.controller,
    this.isVisible = true,
    this.userScale = 1.0,
  });

  @override
  State<AgusMap> createState() => _AgusMapState();
}

class _TapState {
  final Offset startPosition;
  final Duration startTime;
  bool moved = false;

  _TapState(this.startPosition, this.startTime);
}

class _AgusMapState extends State<AgusMap> with WidgetsBindingObserver {
  int? _textureId;
  Size? _currentSize; // Logical size
  bool _surfaceCreated = false;
  double _devicePixelRatio = 1.0;
  double _userScale = 1.0;

  // Track pending resize to apply when becoming visible
  Size? _pendingResizeSize;
  double? _pendingResizePixelRatio;
  double? _pendingResizeUserScale;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _scheduleMetricsResize();
  }

  void _scheduleMetricsResize() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final renderObject = context.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) return;

      final size = renderObject.size;
      if (size.width <= 0 || size.height <= 0) return;

      final pixelRatio = View.of(context).devicePixelRatio;
      final userScale = widget.userScale;

      if (!_surfaceCreated) {
        if (widget.isVisible) {
          _createSurface(size, pixelRatio, userScale);
        } else {
          _pendingResizeSize = size;
          _pendingResizePixelRatio = pixelRatio;
          _pendingResizeUserScale = userScale;
        }
        return;
      }

      if (_currentSize == size &&
          _devicePixelRatio == pixelRatio &&
          _userScale == userScale) {
        return;
      }

      if (widget.isVisible) {
        _handleResize(size, pixelRatio, userScale);
      } else {
        _pendingResizeSize = size;
        _pendingResizePixelRatio = pixelRatio;
        _pendingResizeUserScale = userScale;
      }
    });
  }

  @override
  void didUpdateWidget(AgusMap oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Apply pending resize when becoming visible
    if (widget.isVisible && !oldWidget.isVisible) {
      if (_pendingResizeSize != null && _pendingResizePixelRatio != null) {
        debugPrint('[AgusMap] Applying deferred resize on visibility change');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handleResize(
            _pendingResizeSize!,
            _pendingResizePixelRatio!,
            _pendingResizeUserScale ?? widget.userScale,
          );
          _pendingResizeSize = null;
          _pendingResizePixelRatio = null;
          _pendingResizeUserScale = null;
        });
      }
    }
  }

  Future<void> _createSurface(
    Size logicalSize,
    double pixelRatio,
    double userScale,
  ) async {
    if (_surfaceCreated) return;
    _surfaceCreated = true;
    _devicePixelRatio = pixelRatio;
    _userScale = userScale;

    // Convert logical pixels to physical pixels for crisp rendering
    final physicalWidth = Platform.isWindows
        ? (logicalSize.width * pixelRatio).round()
        : (logicalSize.width * pixelRatio).toInt();
    final physicalHeight = Platform.isWindows
        ? (logicalSize.height * pixelRatio).round()
        : (logicalSize.height * pixelRatio).toInt();

    final visualScale = pixelRatio * userScale;
    debugPrint(
      '[AgusMap] Creating surface: ${logicalSize.width.toInt()}x${logicalSize.height.toInt()} logical, ${physicalWidth}x$physicalHeight physical (ratio: $pixelRatio, userScale: ${userScale.toStringAsFixed(2)}, visual: ${visualScale.toStringAsFixed(3)})',
    );
    if (Platform.isWindows) {
      debugPrint(
        '[AgusMap] Windows DPR diagnostic: logical=${logicalSize.width.toStringAsFixed(2)}x${logicalSize.height.toStringAsFixed(2)} '
        'dpr=${pixelRatio.toStringAsFixed(3)} userScale=${userScale.toStringAsFixed(2)} physical=${physicalWidth}x$physicalHeight',
      );
    }

    final textureId = await createMapSurface(
      width: physicalWidth,
      height: physicalHeight,
      density: visualScale,
    );

    if (!mounted) return;

    setState(() {
      _textureId = textureId;
      _currentSize = logicalSize;
    });

    // Set initial view if specified
    if (widget.initialLat != null && widget.initialLon != null) {
      setView(widget.initialLat!, widget.initialLon!, widget.initialZoom ?? 14);
    }

    widget.onMapReady?.call();
  }

  Future<void> _handleResize(
    Size newLogicalSize,
    double pixelRatio,
    double userScale,
  ) async {
    if (_currentSize == newLogicalSize &&
        _devicePixelRatio == pixelRatio &&
        _userScale == userScale) {
      return;
    }
    if (_textureId == null) return;

    _devicePixelRatio = pixelRatio;
    _userScale = userScale;

    // Convert logical pixels to physical pixels
    final physicalWidth = Platform.isWindows
        ? (newLogicalSize.width * pixelRatio).round()
        : (newLogicalSize.width * pixelRatio).toInt();
    final physicalHeight = Platform.isWindows
        ? (newLogicalSize.height * pixelRatio).round()
        : (newLogicalSize.height * pixelRatio).toInt();

    if (physicalWidth <= 0 || physicalHeight <= 0) return;

    final visualScale = pixelRatio * userScale;
    debugPrint(
      '[AgusMap] Resizing: ${newLogicalSize.width.toInt()}x${newLogicalSize.height.toInt()} logical, ${physicalWidth}x$physicalHeight physical (ratio: $pixelRatio, userScale: ${userScale.toStringAsFixed(2)}, visual: ${visualScale.toStringAsFixed(3)})',
    );
    if (Platform.isWindows) {
      debugPrint(
        '[AgusMap] Windows DPR diagnostic (resize): logical=${newLogicalSize.width.toStringAsFixed(2)}x${newLogicalSize.height.toStringAsFixed(2)} '
        'dpr=${pixelRatio.toStringAsFixed(3)} userScale=${userScale.toStringAsFixed(2)} physical=${physicalWidth}x$physicalHeight',
      );
    }

    await resizeMapSurface(physicalWidth, physicalHeight, density: visualScale);

    if (mounted) {
      setState(() {
        _currentSize = newLogicalSize;
      });
    }
  }

  // Track active pointers for multitouch
  final Map<int, Offset> _activePointers = {};
  final Map<int, _TapState> _tapStates = {};
  bool _hadMultiplePointers = false;

  static const double _tapSlop = 8.0;
  static const Duration _tapTimeout = Duration(milliseconds: 350);

  void _handlePointerDown(PointerDownEvent event) {
    _activePointers[event.pointer] = event.localPosition;
    _tapStates[event.pointer] = _TapState(event.localPosition, event.timeStamp);
    if (_activePointers.length > 1) {
      _hadMultiplePointers = true;
    }
    _sendTouchEvent(TouchType.down, event.pointer, event.localPosition);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    _activePointers[event.pointer] = event.localPosition;
    final tap = _tapStates[event.pointer];
    if (tap != null) {
      final distance = (event.localPosition - tap.startPosition).distance;
      if (distance > _tapSlop) {
        tap.moved = true;
      }
    }
    _sendTouchEvent(TouchType.move, event.pointer, event.localPosition);
  }

  void _handlePointerUp(PointerUpEvent event) {
    _sendTouchEvent(TouchType.up, event.pointer, event.localPosition);
    final tap = _tapStates.remove(event.pointer);
    _activePointers.remove(event.pointer);

    if (_activePointers.isEmpty) {
      if (tap != null &&
          !tap.moved &&
          !_hadMultiplePointers &&
          (event.timeStamp - tap.startTime) <= _tapTimeout) {
        _emitPlacePageIfAvailable();
      }
      _hadMultiplePointers = false;
      _tapStates.clear();
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _sendTouchEvent(TouchType.cancel, event.pointer, event.localPosition);
    _activePointers.remove(event.pointer);
    _tapStates.remove(event.pointer);
    if (_activePointers.isEmpty) {
      _hadMultiplePointers = false;
      _tapStates.clear();
    }
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) return;
    if (_activePointers.isNotEmpty)
      return; // don't interfere with real drag/pinch

    if (event is PointerScrollEvent) {
      // Use direct scale API similar to Qt CoMaps implementation
      // Qt uses: factor = angleDelta.y() / 3.0 / 360.0, then exp(factor)
      // Flutter's scrollDelta.dy is typically ~100 per notch (platform-dependent)
      // We tune the divisor for a good zoom feel similar to Google Maps
      final dy = event.scrollDelta.dy;

      // Calculate zoom factor - larger divisor = slower zoom
      // 3.0 * 360.0 = 1080 matches Qt behavior
      // We use a slightly smaller value for faster, more responsive zoom
      final factor = -dy / 600.0; // Negative because scroll down = zoom out

      // Convert logical position to physical pixels
      final pixelX = event.localPosition.dx * _devicePixelRatio;
      final pixelY = event.localPosition.dy * _devicePixelRatio;

      // Apply exponential zoom factor for smooth, proportional zooming
      // exp(factor) ensures zoom rate is consistent regardless of current zoom level
      scaleMap(exp(factor), pixelX, pixelY, animated: false);
    }
  }

  void _sendTouchEvent(TouchType type, int pointerId, Offset position) {
    // Use cached pixel ratio for coordinate conversion (matches surface dimensions)
    final pixelRatio = _devicePixelRatio;

    // Convert logical coordinates to physical pixels
    final x1 = position.dx * pixelRatio;
    final y1 = position.dy * pixelRatio;

    // Check for second pointer (multitouch)
    int id2 = -1;
    double x2 = 0;
    double y2 = 0;

    for (final entry in _activePointers.entries) {
      if (entry.key != pointerId) {
        id2 = entry.key;
        x2 = entry.value.dx * pixelRatio;
        y2 = entry.value.dy * pixelRatio;
        break;
      }
    }

    sendTouchEvent(type, pointerId, x1, y1, id2: id2, x2: x2, y2: y2);
  }

  void _emitPlacePageIfAvailable() {
    if (widget.onPlacePage == null) {
      return;
    }

    Future.delayed(const Duration(milliseconds: 60), () async {
      if (!mounted) return;
      final data = await getCurrentPlacePage();
      if (!mounted) return;
      widget.onPlacePage?.call(data);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final pixelRatio = MediaQuery.of(context).devicePixelRatio;
        final userScale = widget.userScale;

        // Create surface on first layout (only if visible)
        if (!_surfaceCreated && size.width > 0 && size.height > 0) {
          if (widget.isVisible) {
            // Use post-frame callback to avoid calling during build
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _createSurface(size, pixelRatio, userScale);
            });
          }
        } else if (_surfaceCreated &&
            (_currentSize != size ||
                _devicePixelRatio != pixelRatio ||
                _userScale != userScale)) {
          // Handle resize or pixel ratio change
          if (widget.isVisible) {
            // Apply resize immediately when visible
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _handleResize(size, pixelRatio, userScale);
            });
          } else {
            // Defer resize until visible to avoid unnecessary memory allocations
            // (e.g., keyboard open/close causing CVPixelBuffer recreation on iOS)
            _pendingResizeSize = size;
            _pendingResizePixelRatio = pixelRatio;
            _pendingResizeUserScale = userScale;
          }
        }

        if (_textureId == null) {
          return const Center(child: CircularProgressIndicator());
        }

        return Listener(
          onPointerDown: _handlePointerDown,
          onPointerMove: _handlePointerMove,
          onPointerUp: _handlePointerUp,
          onPointerCancel: _handlePointerCancel,
          onPointerSignal: _handlePointerSignal,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: Texture(
              textureId: _textureId!,
              filterQuality:
                  Platform.isWindows ? FilterQuality.none : FilterQuality.low,
            ),
          ),
        );
      },
    );
  }
}

const String _libName = 'agus_maps_flutter';

/// The dynamic library in which the symbols for [AgusMapsFlutterBindings] can be found.
final DynamicLibrary _dylib = () {
  if (Platform.isMacOS) {
    return DynamicLibrary.open('$_libName.framework/$_libName');
  }
  if (Platform.isIOS) {
    // On iOS, the plugin is linked into the main executable
    // Use process() to look up symbols from the app itself
    return DynamicLibrary.process();
  }
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open('lib$_libName.so');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('$_libName.dll');
  }
  throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
}();

/// The bindings to the native functions in [_dylib].
final AgusMapsFlutterBindings _bindings = AgusMapsFlutterBindings(_dylib);

/// A request to compute `sum`.
///
/// Typically sent from one isolate to another.
class _SumRequest {
  final int id;
  final int a;
  final int b;

  const _SumRequest(this.id, this.a, this.b);
}

/// A response with the result of `sum`.
///
/// Typically sent from one isolate to another.
class _SumResponse {
  final int id;
  final int result;

  const _SumResponse(this.id, this.result);
}

/// Counter to identify [_SumRequest]s and [_SumResponse]s.
int _nextSumRequestId = 0;

/// Mapping from [_SumRequest] `id`s to the completers corresponding to the correct future of the pending request.
final Map<int, Completer<int>> _sumRequests = <int, Completer<int>>{};

/// The SendPort belonging to the helper isolate.
Future<SendPort> _helperIsolateSendPort = () async {
  // The helper isolate is going to send us back a SendPort, which we want to
  // wait for.
  final Completer<SendPort> completer = Completer<SendPort>();

  // Receive port on the main isolate to receive messages from the helper.
  // We receive two types of messages:
  // 1. A port to send messages on.
  // 2. Responses to requests we sent.
  final ReceivePort receivePort = ReceivePort()
    ..listen((dynamic data) {
      if (data is SendPort) {
        // The helper isolate sent us the port on which we can sent it requests.
        completer.complete(data);
        return;
      }
      if (data is _SumResponse) {
        // The helper isolate sent us a response to a request we sent.
        final Completer<int> completer = _sumRequests[data.id]!;
        _sumRequests.remove(data.id);
        completer.complete(data.result);
        return;
      }
      throw UnsupportedError('Unsupported message type: ${data.runtimeType}');
    });

  // Start the helper isolate.
  await Isolate.spawn((SendPort sendPort) async {
    final ReceivePort helperReceivePort = ReceivePort()
      ..listen((dynamic data) {
        // On the helper isolate listen to requests and respond to them.
        if (data is _SumRequest) {
          final int result = _bindings.sum_long_running(data.a, data.b);
          final _SumResponse response = _SumResponse(data.id, result);
          sendPort.send(response);
          return;
        }
        throw UnsupportedError('Unsupported message type: ${data.runtimeType}');
      });

    // Send the port to the main isolate on which we can receive requests.
    sendPort.send(helperReceivePort.sendPort);
  }, receivePort.sendPort);

  // Wait until the helper isolate has sent us back the SendPort on which we
  // can start sending requests.
  return completer.future;
}();
