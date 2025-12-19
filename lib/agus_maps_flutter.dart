import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:ffi/ffi.dart';

import 'agus_maps_flutter_bindings_generated.dart';

// Export additional services
export 'mwm_storage.dart';
export 'mirror_service.dart';

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

final _channel = const MethodChannel('agus_maps_flutter');

Future<String> extractMap(String assetPath) async {
  final String? path = await _channel.invokeMethod('extractMap', {
    'assetPath': assetPath,
  });
  return path!;
}

/// Extract all CoMaps data files (classificator, types, categories, etc.)
/// Returns the path to the directory containing the extracted files.
Future<String> extractDataFiles() async {
  final String? path = await _channel.invokeMethod('extractDataFiles');
  return path!;
}

Future<String> getApkPath() async {
  final String? path = await _channel.invokeMethod('getApkPath');
  return path!;
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
  final pathPtr = fullPath.toNativeUtf8().cast<Char>();
  try {
    return _bindings.comaps_register_single_map(pathPtr);
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

/// Create a map rendering surface with the given dimensions.
/// If width/height are not specified, uses the screen size.
Future<int> createMapSurface({int? width, int? height}) async {
  final int? textureId = await _channel.invokeMethod('createMapSurface', {
    if (width != null) 'width': width,
    if (height != null) 'height': height,
  });
  return textureId!;
}

/// Resize the map surface to new dimensions.
Future<void> resizeMapSurface(int width, int height) async {
  await _channel.invokeMethod('resizeMapSurface', {
    'width': width,
    'height': height,
  });
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

  /// Controller for programmatic map control.
  /// If not provided, the map can only be controlled via gestures.
  final AgusMapController? controller;

  const AgusMap({
    super.key,
    this.initialLat,
    this.initialLon,
    this.initialZoom,
    this.onMapReady,
    this.controller,
  });

  @override
  State<AgusMap> createState() => _AgusMapState();
}

class _AgusMapState extends State<AgusMap> {
  int? _textureId;
  Size? _currentSize; // Logical size
  bool _surfaceCreated = false;
  double _devicePixelRatio = 1.0;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _createSurface(Size logicalSize, double pixelRatio) async {
    if (_surfaceCreated) return;
    _surfaceCreated = true;
    _devicePixelRatio = pixelRatio;

    // Convert logical pixels to physical pixels for crisp rendering
    final physicalWidth = (logicalSize.width * pixelRatio).toInt();
    final physicalHeight = (logicalSize.height * pixelRatio).toInt();

    debugPrint(
      '[AgusMap] Creating surface: ${logicalSize.width.toInt()}x${logicalSize.height.toInt()} logical, ${physicalWidth}x$physicalHeight physical (ratio: $pixelRatio)',
    );

    final textureId = await createMapSurface(
      width: physicalWidth,
      height: physicalHeight,
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

  Future<void> _handleResize(Size newLogicalSize, double pixelRatio) async {
    if (_currentSize == newLogicalSize && _devicePixelRatio == pixelRatio)
      return;
    if (_textureId == null) return;

    _devicePixelRatio = pixelRatio;

    // Convert logical pixels to physical pixels
    final physicalWidth = (newLogicalSize.width * pixelRatio).toInt();
    final physicalHeight = (newLogicalSize.height * pixelRatio).toInt();

    if (physicalWidth <= 0 || physicalHeight <= 0) return;

    debugPrint(
      '[AgusMap] Resizing: ${newLogicalSize.width.toInt()}x${newLogicalSize.height.toInt()} logical, ${physicalWidth}x$physicalHeight physical',
    );

    await resizeMapSurface(physicalWidth, physicalHeight);

    if (mounted) {
      setState(() {
        _currentSize = newLogicalSize;
      });
    }
  }

  // Track active pointers for multitouch
  final Map<int, Offset> _activePointers = {};

  void _handlePointerDown(PointerDownEvent event) {
    _activePointers[event.pointer] = event.localPosition;
    _sendTouchEvent(TouchType.down, event.pointer, event.localPosition);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    _activePointers[event.pointer] = event.localPosition;
    _sendTouchEvent(TouchType.move, event.pointer, event.localPosition);
  }

  void _handlePointerUp(PointerUpEvent event) {
    _sendTouchEvent(TouchType.up, event.pointer, event.localPosition);
    _activePointers.remove(event.pointer);
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _sendTouchEvent(TouchType.cancel, event.pointer, event.localPosition);
    _activePointers.remove(event.pointer);
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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final pixelRatio = MediaQuery.of(context).devicePixelRatio;

        // Create surface on first layout
        if (!_surfaceCreated && size.width > 0 && size.height > 0) {
          // Use post-frame callback to avoid calling during build
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _createSurface(size, pixelRatio);
          });
        } else if (_surfaceCreated &&
            (_currentSize != size || _devicePixelRatio != pixelRatio)) {
          // Handle resize or pixel ratio change
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _handleResize(size, pixelRatio);
          });
        }

        if (_textureId == null) {
          return const Center(child: CircularProgressIndicator());
        }

        return Listener(
          onPointerDown: _handlePointerDown,
          onPointerMove: _handlePointerMove,
          onPointerUp: _handlePointerUp,
          onPointerCancel: _handlePointerCancel,
          child: Texture(textureId: _textureId!),
        );
      },
    );
  }
}

const String _libName = 'agus_maps_flutter';

/// The dynamic library in which the symbols for [AgusMapsFlutterBindings] can be found.
final DynamicLibrary _dylib = () {
  if (Platform.isMacOS || Platform.isIOS) {
    return DynamicLibrary.open('$_libName.framework/$_libName');
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
