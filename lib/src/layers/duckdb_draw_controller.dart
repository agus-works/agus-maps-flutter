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

/// Converts a WGS84 coordinate to a Flutter-local overlay position.
typedef AgusCoordinateProjector = Offset? Function(AgusLatLon coordinate);

/// Called after a feature is committed so renderers can refresh.
typedef AgusLayerCommitCallback = FutureOr<void> Function();

/// Current Drape-owned map interaction state for project-layer editing.
enum AgusDrapeInteractionMode {
  /// Normal map interaction; no drawing/edit visuals are submitted.
  inactive,

  /// New feature sketching; taps add vertices while drag gestures pan the map.
  drawing,

  /// Persisted feature vertex editing.
  editingFeature,
}

/// Renders or clears native Drape interaction geometry.
typedef AgusNativeEditGeometryRenderer = void Function(
  AgusDrapeInteractionMode mode,
  String? geometryWkt,
);

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
    this.coordinateProjector,
    this.nativeEditGeometryRenderer,
    this.onCommitted,
  });

  /// Store used to persist committed features.
  final DuckDBLayerStore store;

  /// Target `agus.layers.layer_id` for committed features.
  final String layerId;

  /// Converts overlay positions to map coordinates.
  final AgusScreenProjector projector;

  /// Converts map coordinates to overlay positions for committed feature edits.
  final AgusCoordinateProjector? coordinateProjector;

  /// Draws committed-feature edit handles inside the native map scene.
  final AgusNativeEditGeometryRenderer? nativeEditGeometryRenderer;

  /// Optional hook for refreshing native rendering after commit.
  final AgusLayerCommitCallback? onCommitted;

  final List<AgusDrawPoint> _vertices = <AgusDrawPoint>[];
  final Map<String, Object?> _metadata = <String, Object?>{};

  AgusDrawTool _tool = AgusDrawTool.none;
  AgusLayerFeature? _editingFeature;
  int? _selectedVertexIndex;
  bool _isCommitting = false;
  String? _lastError;
  String _title = '';
  String _note = '';

  /// Active draw tool.
  AgusDrawTool get tool => _tool;

  /// Captured vertices in draw order.
  List<AgusDrawPoint> get vertices =>
      List<AgusDrawPoint>.unmodifiable(_vertices);

  /// Index of the vertex currently being edited, if any.
  int? get selectedVertexIndex => _selectedVertexIndex;

  /// Whether the overlay is capturing a new sketch.
  bool get isDrawing => _tool != AgusDrawTool.none && _editingFeature == null;

  /// Whether a committed feature is being edited.
  bool get isEditingFeature => _editingFeature != null;

  /// Whether the overlay should capture pointer events.
  bool get isEditing => isDrawing || isEditingFeature;

  /// Whether a commit is currently writing to DuckDB.
  bool get isCommitting => _isCommitting;

  /// Last editing error surfaced by the controller.
  String? get lastError => _lastError;

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
    if (_tool == tool && _editingFeature == null) return;
    if (_editingFeature == null &&
        _tool != AgusDrawTool.none &&
        tool != AgusDrawTool.none) {
      _lastError =
          'Finish or cancel the current feature before choosing another geometry type.';
      notifyListeners();
      return;
    }
    _tool = tool;
    _editingFeature = null;
    _vertices.clear();
    _selectedVertexIndex = null;
    _lastError = null;
    if (tool == AgusDrawTool.none) {
      _clearNativeInteractionGeometry();
    } else {
      _renderNativeInteractionGeometry();
    }
    notifyListeners();
  }

  /// Starts moving a committed point feature.
  void beginMovePointFeature(AgusLayerFeature feature) {
    beginEditFeature(feature);
  }

  /// Starts editing a committed feature's vertices.
  void beginEditFeature(AgusLayerFeature feature) {
    final nextTool = _drawToolForFeature(feature);
    final nextVertices = _drawPointsForFeature(feature);

    _tool = nextTool;
    _vertices
      ..clear()
      ..addAll(nextVertices);
    _selectedVertexIndex = null;
    _editingFeature = feature;
    _lastError = null;
    _renderNativeInteractionGeometry();
    notifyListeners();
  }

  /// Reprojects committed-feature edit handles after map camera movement.
  void reprojectEditedFeatureVertices() {
    if (_editingFeature == null || _vertices.isEmpty) return;

    final projectCoordinate = coordinateProjector;
    if (projectCoordinate == null) return;

    var changed = false;
    for (var index = 0; index < _vertices.length; index++) {
      final vertex = _vertices[index];
      final nextPosition = projectCoordinate(vertex.coordinate);
      if (nextPosition == null) continue;
      if ((nextPosition - vertex.screenPosition).distance < 0.5) continue;
      _vertices[index] = vertex.copyWith(screenPosition: nextPosition);
      changed = true;
    }

    if (changed) notifyListeners();
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

  /// Adds a sketch vertex from a map tap.
  bool handleMapTap(Offset localPosition) {
    if (!_canAddSketchVertex) return false;
    unawaited(_addSketchVertex(localPosition));
    return true;
  }

  /// Starts a captured vertex-drag interaction when the pointer hits a handle.
  bool handlePointerDown(Offset localPosition) {
    if (_isCommitting || _editingFeature == null) return false;

    final nearest = _nearestVertex(localPosition);
    if (nearest == null) return false;

    _selectedVertexIndex = nearest;
    notifyListeners();
    return true;
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
    _renderNativeInteractionGeometry();
    notifyListeners();
  }

  /// Finishes the current pointer edit gesture.
  Future<void> handlePointerUp() async {
    if (_editingFeature != null) {
      await _commitEditedFeature();
      return;
    }

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
    _editingFeature = null;
    _vertices.clear();
    _selectedVertexIndex = null;
    _lastError = null;
    _clearNativeInteractionGeometry();
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
      _clearNativeInteractionGeometry();
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

  Future<void> _commitEditedFeature() async {
    final feature = _editingFeature;
    if (feature == null || _selectedVertexIndex == null || _isCommitting) {
      _selectedVertexIndex = null;
      notifyListeners();
      return;
    }

    _isCommitting = true;
    notifyListeners();

    try {
      store.upsertFeature(
        AgusLayerFeatureDraft(
          layerId: feature.layerId,
          featureId: feature.featureId,
          geometryWkt: _buildFeatureWkt(feature.geometryKind, _vertices),
          geometryKind: feature.geometryKind,
          properties: feature.properties,
          style: feature.style,
          boundingBox: _boundingBox(_vertices),
          zIndex: feature.zIndex,
          minZoom: feature.minZoom,
          maxZoom: feature.maxZoom,
        ),
      );
      _lastError = null;
      _renderNativeInteractionGeometry();
      final commitCallback = onCommitted;
      if (commitCallback != null) {
        await commitCallback();
      }
    } catch (error) {
      _lastError = 'Feature edit failed: $error';
    } finally {
      _selectedVertexIndex = null;
      _isCommitting = false;
      notifyListeners();
    }
  }

  bool get _canAddSketchVertex {
    if (_isCommitting ||
        _editingFeature != null ||
        _tool == AgusDrawTool.none) {
      return false;
    }
    if (_tool == AgusDrawTool.segment && _vertices.length >= 2) return false;
    return true;
  }

  Future<void> _addSketchVertex(Offset localPosition) async {
    if (!_canAddSketchVertex) return;
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
    _renderNativeInteractionGeometry();
    notifyListeners();
  }

  void _renderNativeInteractionGeometry() {
    final render = nativeEditGeometryRenderer;
    if (render == null) return;

    if (_editingFeature != null) {
      render(
        AgusDrapeInteractionMode.editingFeature,
        _vertices.isEmpty ? null : _buildInteractionWkt(_vertices),
      );
      return;
    }

    if (_tool != AgusDrawTool.none) {
      render(
        AgusDrapeInteractionMode.drawing,
        _vertices.isEmpty ? null : _buildInteractionWkt(_vertices),
      );
      return;
    }

    render(AgusDrapeInteractionMode.inactive, null);
  }

  void _clearNativeInteractionGeometry() {
    nativeEditGeometryRenderer?.call(AgusDrapeInteractionMode.inactive, null);
  }

  @override
  void dispose() {
    _clearNativeInteractionGeometry();
    super.dispose();
  }

  AgusDrawTool _drawToolForFeature(AgusLayerFeature feature) {
    return switch (feature.geometryKind) {
      AgusGeometryKind.point => AgusDrawTool.pin,
      AgusGeometryKind.segment => AgusDrawTool.segment,
      AgusGeometryKind.line => AgusDrawTool.line,
      AgusGeometryKind.polygon => AgusDrawTool.polygon,
      _ => throw ArgumentError.value(
          feature.geometryKind.databaseValue,
          'feature.geometryKind',
          'Only point, segment, line, and polygon feature editing is supported.',
        ),
    };
  }

  List<AgusDrawPoint> _drawPointsForFeature(AgusLayerFeature feature) {
    final projectCoordinate = coordinateProjector;
    if (projectCoordinate == null) {
      throw StateError('Coordinate-to-screen projection is unavailable.');
    }

    final coordinates = _parseEditableWkt(feature);
    if (coordinates.isEmpty) {
      throw FormatException('No editable vertices found.', feature.geometryWkt);
    }

    return [
      for (final coordinate in coordinates)
        AgusDrawPoint(
          coordinate: coordinate,
          screenPosition: projectCoordinate(coordinate) ??
              (throw StateError('Feature vertex is outside the current map.')),
        ),
    ];
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

String _buildFeatureWkt(
  AgusGeometryKind geometryKind,
  List<AgusDrawPoint> vertices,
) {
  final coordinateText = switch (geometryKind) {
    AgusGeometryKind.point => _wktCoordinate(vertices.first),
    AgusGeometryKind.segment ||
    AgusGeometryKind.line =>
      vertices.map(_wktCoordinate).join(', '),
    AgusGeometryKind.polygon =>
      _closedPolygonVertices(vertices).map(_wktCoordinate).join(', '),
    _ => throw ArgumentError.value(
        geometryKind.databaseValue,
        'geometryKind',
        'Only point, segment, line, and polygon feature editing is supported.',
      ),
  };

  return switch (geometryKind) {
    AgusGeometryKind.point => 'POINT ($coordinateText)',
    AgusGeometryKind.segment ||
    AgusGeometryKind.line =>
      'LINESTRING ($coordinateText)',
    AgusGeometryKind.polygon => 'POLYGON (($coordinateText))',
    _ => 'GEOMETRYCOLLECTION EMPTY',
  };
}

String _buildInteractionWkt(List<AgusDrawPoint> vertices) {
  final coordinateText = vertices.map(_wktCoordinate).join(', ');
  if (vertices.length == 1) {
    return 'POINT ($coordinateText)';
  }
  return 'LINESTRING ($coordinateText)';
}

List<AgusLatLon> _parseEditableWkt(AgusLayerFeature feature) {
  final coordinates = _parseWktCoordinatePairs(feature.geometryWkt);
  if (feature.geometryKind == AgusGeometryKind.polygon &&
      coordinates.length > 1) {
    final first = coordinates.first;
    final last = coordinates.last;
    if (first.lat == last.lat && first.lon == last.lon) {
      return coordinates.sublist(0, coordinates.length - 1);
    }
  }
  return coordinates;
}

List<AgusLatLon> _parseWktCoordinatePairs(String wkt) {
  final matches = RegExp(
    r'[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?',
  ).allMatches(wkt).map((match) => match.group(0)!).toList(growable: false);

  if (matches.length.isOdd) {
    throw FormatException('Invalid WKT coordinate pair count.', wkt);
  }

  final coordinates = <AgusLatLon>[];
  for (var index = 0; index < matches.length; index += 2) {
    final lon = double.parse(matches[index]);
    final lat = double.parse(matches[index + 1]);
    coordinates.add(AgusLatLon(lat: lat, lon: lon));
  }
  return coordinates;
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
