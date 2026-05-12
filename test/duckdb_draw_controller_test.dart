import 'package:agus_maps_flutter/agus_maps_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DuckDB native interaction style', () {
    test('uses dashed thin blue edges for new geometry', () {
      final style = defaultDuckDBInteractionLineStyle();

      expect(style.colorRed, 37);
      expect(style.colorGreen, 99);
      expect(style.colorBlue, 235);
      expect(style.opacity, inInclusiveRange(0, 1));
      expect(style.width, inInclusiveRange(0.5, 4));
      expect(style.dashed, isTrue);
      expect(style.dashLength, greaterThan(0));
      expect(style.gapLength, greaterThan(0));
    });

    test('uses solid thin amber edges for active edits and selections', () {
      final style = defaultDuckDBInteractionLineStyle(
        AgusDrapeInteractionMode.editingFeature,
      );

      expect(style.colorRed, 245);
      expect(style.colorGreen, 158);
      expect(style.colorBlue, 11);
      expect(style.opacity, inInclusiveRange(0, 1));
      expect(style.width, inInclusiveRange(0.5, 4));
      expect(style.dashed, isFalse);
      expect(style.dashLength, greaterThan(0));
      expect(style.gapLength, greaterThan(0));
    });
  });

  group('DuckDBLayerDrawController', () {
    test('renders line preview edges after each added vertex', () async {
      final rendered = <_RenderedGeometry>[];
      final controller = _newController(
        rendered: rendered,
      )..setTool(AgusDrawTool.line);

      expect(controller.handleMapTap(Offset.zero), isTrue);
      await pumpEventQueue();
      expect(rendered.last.geometryWkt, 'LINESTRING (0.0 0.0)');

      await controller.handlePointerMove(const Offset(10, 10));
      expect(
        rendered.last.geometryWkt,
        'LINESTRING (0.0 0.0, 10.0 10.0)',
      );

      expect(controller.handleMapTap(const Offset(5, 5)), isTrue);
      await pumpEventQueue();
      expect(
        rendered.last.geometryWkt,
        'LINESTRING (0.0 0.0, 5.0 5.0)',
      );

      await controller.handlePointerMove(const Offset(8, 8));
      expect(
        rendered.last.geometryWkt,
        'LINESTRING (0.0 0.0, 5.0 5.0, 8.0 8.0)',
      );
    });

    test('does not extend segment preview after the second vertex', () async {
      final rendered = <_RenderedGeometry>[];
      final controller = _newController(
        rendered: rendered,
      )..setTool(AgusDrawTool.segment);

      expect(controller.handleMapTap(Offset.zero), isTrue);
      await pumpEventQueue();
      await controller.handlePointerMove(const Offset(1, 1));
      expect(
        rendered.last.geometryWkt,
        'LINESTRING (0.0 0.0, 1.0 1.0)',
      );

      expect(controller.handleMapTap(const Offset(2, 2)), isTrue);
      await pumpEventQueue();
      expect(
        rendered.last.geometryWkt,
        'LINESTRING (0.0 0.0, 2.0 2.0)',
      );

      await controller.handlePointerMove(const Offset(3, 3));
      expect(
        rendered.last.geometryWkt,
        'LINESTRING (0.0 0.0, 2.0 2.0)',
      );
    });

    test('closes polygon preview and committed drawing geometry', () async {
      final rendered = <_RenderedGeometry>[];
      final controller = _newController(
        rendered: rendered,
      )..setTool(AgusDrawTool.polygon);

      expect(controller.handleMapTap(Offset.zero), isTrue);
      await pumpEventQueue();
      expect(controller.handleMapTap(const Offset(1, 0)), isTrue);
      await pumpEventQueue();
      expect(controller.handleMapTap(const Offset(1, 1)), isTrue);
      await pumpEventQueue();

      expect(
        rendered.last.geometryWkt,
        'POLYGON ((0.0 0.0, 1.0 0.0, 1.0 1.0, 0.0 0.0))',
      );

      await controller.handlePointerMove(const Offset(0, 1));
      expect(
        rendered.last.geometryWkt,
        'POLYGON ((0.0 0.0, 1.0 0.0, 1.0 1.0, 0.0 1.0, 0.0 0.0))',
      );
    });

    test('display vertices include live preview for visible sketch edges',
        () async {
      final controller = _newController()..setTool(AgusDrawTool.line);
      var notifications = 0;
      controller.addListener(() {
        notifications++;
      });

      expect(controller.handleMapTap(Offset.zero), isTrue);
      await pumpEventQueue();
      notifications = 0;
      await controller.handlePointerMove(const Offset(6, 8));

      expect(
        controller.displayVertices.map((point) => point.screenPosition),
        <Offset>[Offset.zero, const Offset(6, 8)],
      );
      expect(notifications, 1);
    });

    test('commit while editing updates the existing feature id', () async {
      final store = _RecordingDuckDBLayerStore();
      final rendered = <_RenderedGeometry>[];
      final controller = _newController(
        store: store,
        rendered: rendered,
      );
      final feature = _lineFeature();

      controller.beginEditFeature(feature);
      expect(controller.handlePointerDown(const Offset(1, 1)), isTrue);
      await controller.handlePointerMove(const Offset(2, 2));

      final committedFeatureId = await controller.commit();

      expect(committedFeatureId, 'feature-1');
      expect(store.features, hasLength(1));
      expect(store.features.single.featureId, 'feature-1');
      expect(
        store.features.single.geometryWkt,
        'LINESTRING (0.0 0.0, 2.0 2.0)',
      );
      expect(controller.isEditing, isFalse);
      expect(rendered.last.mode, AgusDrapeInteractionMode.inactive);
      expect(rendered.last.geometryWkt, isNull);
    });

    test(
        'pointer-up editing keeps editing the same feature without duplication',
        () async {
      final store = _RecordingDuckDBLayerStore();
      final controller = _newController(store: store);

      controller.beginEditFeature(_lineFeature());
      expect(controller.handlePointerDown(const Offset(1, 1)), isTrue);
      await controller.handlePointerMove(const Offset(3, 3));
      await controller.handlePointerUp();

      expect(store.features, hasLength(1));
      expect(store.features.single.featureId, 'feature-1');
      expect(
        store.features.single.geometryWkt,
        'LINESTRING (0.0 0.0, 3.0 3.0)',
      );
      expect(controller.isEditingFeature, isTrue);
    });

    test('polygon edit commit preserves closure and original feature id',
        () async {
      final store = _RecordingDuckDBLayerStore();
      final controller = _newController(store: store);

      controller.beginEditFeature(_polygonFeature());
      expect(controller.handlePointerDown(const Offset(100, 100)), isTrue);
      await controller.handlePointerMove(const Offset(200, 200));

      final committedFeatureId = await controller.commit();

      expect(committedFeatureId, 'polygon-1');
      expect(store.features, hasLength(1));
      expect(store.features.single.featureId, 'polygon-1');
      expect(
        store.features.single.geometryWkt,
        'POLYGON ((0.0 0.0, 200.0 200.0, 100.0 0.0, 0.0 0.0))',
      );
    });
  });
}

DuckDBLayerDrawController _newController({
  _RecordingDuckDBLayerStore? store,
  List<_RenderedGeometry>? rendered,
}) {
  return DuckDBLayerDrawController(
    store: store ?? _RecordingDuckDBLayerStore(),
    layerId: 'layer-1',
    projector: (position) => AgusLatLon(
      lat: position.dy,
      lon: position.dx,
    ),
    coordinateProjector: (coordinate) => Offset(
      coordinate.lon,
      coordinate.lat,
    ),
    nativeEditGeometryRenderer: rendered == null
        ? null
        : (mode, geometryWkt) {
            rendered.add(_RenderedGeometry(mode, geometryWkt));
          },
  );
}

AgusLayerFeature _lineFeature() {
  return AgusLayerFeature(
    layerId: 'layer-1',
    featureId: 'feature-1',
    geometryWkt: 'LINESTRING (0 0, 1 1)',
    geometryKind: AgusGeometryKind.line,
    properties: const <String, Object?>{'title': 'Existing line'},
    style: const <String, Object?>{'color': '#00ff00'},
    boundingBox: const AgusBoundingBox(
      minLon: 0,
      minLat: 0,
      maxLon: 1,
      maxLat: 1,
    ),
    zIndex: 7,
    minZoom: 3,
    maxZoom: 18,
    createdAt: DateTime.utc(2024),
    updatedAt: DateTime.utc(2024, 1, 2),
    deletedAt: null,
  );
}

AgusLayerFeature _polygonFeature() {
  return AgusLayerFeature(
    layerId: 'layer-1',
    featureId: 'polygon-1',
    geometryWkt: 'POLYGON ((0 0, 100 100, 100 0, 0 0))',
    geometryKind: AgusGeometryKind.polygon,
    properties: const <String, Object?>{'title': 'Existing polygon'},
    style: const <String, Object?>{'color': '#00ff00'},
    boundingBox: const AgusBoundingBox(
      minLon: 0,
      minLat: 0,
      maxLon: 100,
      maxLat: 100,
    ),
    zIndex: 7,
    minZoom: 3,
    maxZoom: 18,
    createdAt: DateTime.utc(2024),
    updatedAt: DateTime.utc(2024, 1, 2),
    deletedAt: null,
  );
}

class _RecordingDuckDBLayerStore extends DuckDBLayerStore {
  _RecordingDuckDBLayerStore() : super(writablePath: 'memory');

  final List<AgusLayerFeatureDraft> features = <AgusLayerFeatureDraft>[];

  @override
  void upsertFeature(AgusLayerFeatureDraft feature) {
    features.add(feature);
  }
}

class _RenderedGeometry {
  const _RenderedGeometry(this.mode, this.geometryWkt);

  final AgusDrapeInteractionMode mode;
  final String? geometryWkt;
}
