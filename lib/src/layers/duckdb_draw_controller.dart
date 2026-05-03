part of '../../agus_maps_flutter.dart';

/// Drawing tools supported by the reusable DuckDB layer editor.
enum AgusDrawTool {
  /// Map interaction mode; draw overlay does not capture pointers.
  none,

  /// Single point/pin geometry.
  pin,

  /// Two-point line segment geometry.
  segment,

  /// Multi-vertex line geometry.
  line,

  /// Closed polygon outline geometry.
  polygon;

  /// Geometry kind stored for features drawn with this tool.
  AgusGeometryKind? get geometryKind => switch (this) {
        AgusDrawTool.pin => AgusGeometryKind.point,
        AgusDrawTool.segment => AgusGeometryKind.segment,
        AgusDrawTool.line => AgusGeometryKind.line,
        AgusDrawTool.polygon => AgusGeometryKind.polygon,
        AgusDrawTool.none => null,
      };

  /// Minimum vertex count required before commit is enabled.
  int get minimumVertices => switch (this) {
        AgusDrawTool.pin => 1,
        AgusDrawTool.segment => 2,
        AgusDrawTool.line => 2,
        AgusDrawTool.polygon => 3,
        AgusDrawTool.none => 0,
      };
}

/// Converts a Flutter-local overlay position to a WGS84 coordinate.
typedef AgusScreenProjector = FutureOr<AgusLatLon?> Function(
  Offset localPosition,
);

/// Called after a feature is committed so renderers can refresh.
typedef AgusLayerCommitCallback = FutureOr<void> Function();

/// A vertex captured by the draw overlay.
class AgusDrawPoint {
  /// Creates a draw vertex with both screen and geographic positions.
  const AgusDrawPoint({required this.screenPosition, required this.coordinate});

  /// Logical-pixel position within the draw overlay.
  final Offset screenPosition;

  /// WGS84 coordinate projected from [screenPosition].
  final AgusLatLon coordinate;

  /// Returns a copy with updated positions.
  AgusDrawPoint copyWith({Offset? screenPosition, AgusLatLon? coordinate}) {
    return AgusDrawPoint(
      screenPosition: screenPosition ?? this.screenPosition,
      coordinate: coordinate ?? this.coordinate,
    );
  }
}

/// Stateful controller for drawing DuckDB-backed features on top of [AgusMap].
class DuckDBLayerDrawController extends ChangeNotifier {
  /// Creates a draw controller for a single writable layer.
  DuckDBLayerDrawController({
    required this.store,
    required this.layerId,
    required this.projector,
    this.onCommitted,
  });

  /// Store used to persist committed features.
  final DuckDBLayerStore store;

  /// Target `agus.layers.layer_id` for committed features.
  final String layerId;

  /// Converts overlay positions to map coordinates.
  final AgusScreenProjector projector;

  /// Optional hook for refreshing native rendering after commit.
  final AgusLayerCommitCallback? onCommitted;

  final List<AgusDrawPoint> _vertices = <AgusDrawPoint>[];
  final Map<String, Object?> _metadata = <String, Object?>{};

  AgusDrawTool _tool = AgusDrawTool.none;
  int? _selectedVertexIndex;
  bool _isCommitting = false;
  String _title = '';
  String _note = '';

  /// Active draw tool.
  AgusDrawTool get tool => _tool;

  /// Captured vertices in draw order.
  List<AgusDrawPoint> get vertices =>
      List<AgusDrawPoint>.unmodifiable(_vertices);

  /// Index of the vertex currently being edited, if any.
  int? get selectedVertexIndex => _selectedVertexIndex;

  /// Whether the overlay should capture map pointer events.
  bool get isDrawing => _tool != AgusDrawTool.none;

  /// Whether a commit is currently writing to DuckDB.
  bool get isCommitting => _isCommitting;

  /// Optional user-entered feature title.
  String get title => _title;

  /// Optional user-entered feature note.
  String get note => _note;

  /// Extra key/value metadata included in committed feature properties.
  Map<String, Object?> get metadata =>
      Map<String, Object?>.unmodifiable(_metadata);

  /// Whether the current sketch can be committed.
  bool get canCommit =>
      _tool != AgusDrawTool.none &&
      _vertices.length >= _tool.minimumVertices &&
      !_isCommitting;

  /// Selects the active draw tool.
  void setTool(AgusDrawTool tool) {
    if (_tool == tool) return;
    _tool = tool;
    _vertices.clear();
    _selectedVertexIndex = null;
    notifyListeners();
  }

  /// Updates the user-facing metadata captured for the next commit.
  void updateMetadata(
      {String? title, String? note, Map<String, Object?>? extra}) {
    if (title != null) _title = title;
    if (note != null) _note = note;
    if (extra != null) {
      _metadata
        ..clear()
        ..addAll(extra);
    }
    notifyListeners();
  }

  /// Handles a pointer down in the overlay.
  Future<void> handlePointerDown(Offset localPosition) async {
    if (_tool == AgusDrawTool.none || _isCommitting) return;

    final nearest = _nearestVertex(localPosition);
    if (nearest != null) {
      _selectedVertexIndex = nearest;
      notifyListeners();
      return;
    }

    if (_tool == AgusDrawTool.segment && _vertices.length >= 2) {
      return;
    }
    if (_tool == AgusDrawTool.pin && _vertices.isNotEmpty) {
      _vertices.clear();
    }

    final coordinate = await projector(localPosition);
    if (coordinate == null) return;

    _vertices.add(AgusDrawPoint(
      screenPosition: localPosition,
      coordinate: coordinate,
    ));
    _selectedVertexIndex = _vertices.length - 1;
    notifyListeners();
  }

  /// Handles a drag move for vertex editing.
  Future<void> handlePointerMove(Offset localPosition) async {
    final index = _selectedVertexIndex;
    if (index == null || index < 0 || index >= _vertices.length) return;

    final coordinate = await projector(localPosition);
    if (coordinate == null) return;

    _vertices[index] = _vertices[index].copyWith(
      screenPosition: localPosition,
      coordinate: coordinate,
    );
    notifyListeners();
  }

  /// Finishes the current pointer edit gesture.
  void handlePointerUp() {
    if (_selectedVertexIndex == null) return;
    _selectedVertexIndex = null;
    notifyListeners();
  }

  /// Removes the most recently added vertex.
  void undoLastVertex() {
    if (_vertices.isEmpty || _isCommitting) return;
    _vertices.removeLast();
    _selectedVertexIndex = null;
    notifyListeners();
  }

  /// Cancels the current sketch and returns to map interaction mode.
  void cancel() {
    _tool = AgusDrawTool.none;
    _vertices.clear();
    _selectedVertexIndex = null;
    notifyListeners();
  }

  /// Persists the current sketch as a DuckDB feature.
  Future<String?> commit() async {
    final geometryKind = _tool.geometryKind;
    if (!canCommit || geometryKind == null) return null;

    _isCommitting = true;
    notifyListeners();

    try {
      final now = DateTime.now().toUtc();
      final featureId = 'feature_${now.microsecondsSinceEpoch}';
      store.upsertFeature(
        AgusLayerFeatureDraft(
          layerId: layerId,
          featureId: featureId,
          geometryWkt: _buildWkt(_tool, _vertices),
          geometryKind: geometryKind,
          properties: _buildProperties(now),
          boundingBox: _boundingBox(_vertices),
        ),
      );
      _vertices.clear();
      _selectedVertexIndex = null;
      _tool = AgusDrawTool.none;
      final commitCallback = onCommitted;
      if (commitCallback != null) {
        await commitCallback();
      }
      return featureId;
    } finally {
      _isCommitting = false;
      notifyListeners();
    }
  }

  int? _nearestVertex(Offset localPosition) {
    const hitRadius = 24.0;
    for (var index = _vertices.length - 1; index >= 0; index--) {
      if ((_vertices[index].screenPosition - localPosition).distance <=
          hitRadius) {
        return index;
      }
    }
    return null;
  }

  Map<String, Object?> _buildProperties(DateTime now) {
    return <String, Object?>{
      if (_title.trim().isNotEmpty) 'title': _title.trim(),
      if (_note.trim().isNotEmpty) 'note': _note.trim(),
      ..._metadata,
      'created_at': now.toIso8601String(),
    };
  }
}

String _buildWkt(AgusDrawTool tool, List<AgusDrawPoint> vertices) {
  final coordinates = switch (tool) {
    AgusDrawTool.pin => <AgusDrawPoint>[vertices.first],
    AgusDrawTool.segment || AgusDrawTool.line => vertices,
    AgusDrawTool.polygon => _closedPolygonVertices(vertices),
    AgusDrawTool.none => vertices,
  };

  final coordinateText = coordinates.map(_wktCoordinate).join(', ');
  return switch (tool) {
    AgusDrawTool.pin => 'POINT ($coordinateText)',
    AgusDrawTool.segment || AgusDrawTool.line => 'LINESTRING ($coordinateText)',
    AgusDrawTool.polygon => 'POLYGON (($coordinateText))',
    AgusDrawTool.none => 'GEOMETRYCOLLECTION EMPTY',
  };
}

List<AgusDrawPoint> _closedPolygonVertices(List<AgusDrawPoint> vertices) {
  if (vertices.isEmpty) return vertices;
  final first = vertices.first.coordinate;
  final last = vertices.last.coordinate;
  if (first.lat == last.lat && first.lon == last.lon) return vertices;
  return <AgusDrawPoint>[...vertices, vertices.first];
}

String _wktCoordinate(AgusDrawPoint vertex) {
  return '${_formatCoordinate(vertex.coordinate.lon)} '
      '${_formatCoordinate(vertex.coordinate.lat)}';
}

String _formatCoordinate(double value) {
  return value.toStringAsFixed(8).replaceFirst(RegExp(r'\.0+$'), '.0');
}

AgusBoundingBox? _boundingBox(List<AgusDrawPoint> vertices) {
  if (vertices.isEmpty) return null;
  var minLon = vertices.first.coordinate.lon;
  var maxLon = vertices.first.coordinate.lon;
  var minLat = vertices.first.coordinate.lat;
  var maxLat = vertices.first.coordinate.lat;

  for (final vertex in vertices.skip(1)) {
    minLon = min(minLon, vertex.coordinate.lon);
    maxLon = max(maxLon, vertex.coordinate.lon);
    minLat = min(minLat, vertex.coordinate.lat);
    maxLat = max(maxLat, vertex.coordinate.lat);
  }

  return AgusBoundingBox(
    minLon: minLon,
    minLat: minLat,
    maxLon: maxLon,
    maxLat: maxLat,
  );
}
