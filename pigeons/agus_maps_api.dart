// Copyright 2026 Agus Maps Flutter.
//
// Pigeon definitions for typed platform channels.

import 'package:pigeon/pigeon.dart';

/// Rendering activity state for low-frequency notifications.
enum RenderState {
  /// Rendering is active (frames expected).
  active,

  /// Rendering is idle (no frames expected).
  idle,
}

/// Request payload for creating a map surface.
class CreateMapSurfaceRequest {
  CreateMapSurfaceRequest({
    this.width,
    this.height,
    this.density,
  });

  final int? width;
  final int? height;
  final double? density;
}

/// Request payload for resizing a map surface.
class ResizeMapSurfaceRequest {
  ResizeMapSurfaceRequest({
    required this.width,
    required this.height,
    this.density,
  });

  final int width;
  final int height;
  final double? density;
}

/// Pointer position in the native map surface's physical pixel space.
class MapPointerUpdateRequest {
  MapPointerUpdateRequest({
    required this.physicalX,
    required this.physicalY,
    required this.insideMap,
  });

  final double physicalX;
  final double physicalY;
  final bool insideMap;
}

/// Native map-space pointer projection result.
class MapPointerCoordinate {
  MapPointerCoordinate({
    required this.physicalX,
    required this.physicalY,
    required this.insideMap,
    required this.lat,
    required this.lon,
  });

  final double physicalX;
  final double physicalY;
  final bool insideMap;
  final double lat;
  final double lon;
}

/// Native interaction line style for transient draw/edit geometry.
class DrapeInteractionLineStyle {
  DrapeInteractionLineStyle({
    required this.colorRed,
    required this.colorGreen,
    required this.colorBlue,
    required this.opacity,
    required this.width,
    required this.dashed,
    required this.dashLength,
    required this.gapLength,
  });

  /// Red channel, 0-255.
  final int colorRed;

  /// Green channel, 0-255.
  final int colorGreen;

  /// Blue channel, 0-255.
  final int colorBlue;

  /// Alpha opacity, 0.0-1.0.
  final double opacity;

  /// Stroke width in physical pixels.
  final double width;

  /// Whether the native renderer should split the line into dash segments.
  final bool dashed;

  /// Dash length in physical pixels when [dashed] is true.
  final double dashLength;

  /// Gap length in physical pixels when [dashed] is true.
  final double gapLength;
}

/// Native interaction geometry payload.
class DrapeInteractionGeometryRequest {
  DrapeInteractionGeometryRequest({
    required this.mode,
    this.geometryWkt,
    required this.lineStyle,
  });

  /// 0 inactive, 1 drawing, 2 editing feature.
  final int mode;

  /// WKT geometry, or null to clear.
  final String? geometryWkt;

  /// Style for line/edge geometry.
  final DrapeInteractionLineStyle lineStyle;
}

/// Stable identifier for a place page feature.
class PlacePageFeatureId {
  PlacePageFeatureId({
    required this.mwmName,
    required this.mwmVersion,
    required this.index,
  });

  final String mwmName;
  final int mwmVersion;
  final int index;
}

/// Formatted coordinates variants for a place page.
class PlacePageCoordinates {
  PlacePageCoordinates({
    this.decimal,
    this.dms,
    this.osm,
    this.olc,
    this.utm,
    this.mgrs,
  });

  final String? decimal;
  final String? dms;
  final String? osm;
  final String? olc;
  final String? utm;
  final String? mgrs;
}

/// Integer-keyed metadata entry.
class PlacePageIntMetadataEntry {
  PlacePageIntMetadataEntry({
    required this.key,
    required this.value,
  });

  final int key;
  final String value;
}

/// String-keyed metadata entry.
class PlacePageStringMetadataEntry {
  PlacePageStringMetadataEntry({
    required this.key,
    required this.value,
  });

  final String key;
  final String value;
}

/// Structured place page payload.
class PlacePageData {
  PlacePageData({
    required this.featureId,
    required this.objectType,
    required this.openingMode,
    required this.title,
    required this.secondaryTitle,
    required this.subtitle,
    required this.address,
    required this.lat,
    required this.lon,
    required this.wikiDescriptionHtml,
    required this.roadType,
    required this.isRoutePoint,
    required this.coordinates,
    required this.rawTypes,
    required this.metadata,
    required this.metadataTags,
    this.bookmarkId,
    this.bookmarkCategoryId,
    this.trackId,
  });

  final PlacePageFeatureId featureId;
  final int objectType;
  final int openingMode;
  final String title;
  final String secondaryTitle;
  final String subtitle;
  final String address;
  final double lat;
  final double lon;
  final String wikiDescriptionHtml;
  final int roadType;
  final bool isRoutePoint;
  final PlacePageCoordinates coordinates;
  final List<String> rawTypes;
  final List<PlacePageIntMetadataEntry> metadata;
  final List<PlacePageStringMetadataEntry> metadataTags;
  final int? bookmarkId;
  final int? bookmarkCategoryId;
  final int? trackId;
}

/// Host API implemented by native platforms.
@HostApi()
abstract class AgusMapsHostApi {
  @async
  String extractMap(String assetPath);

  @async
  String extractDataFiles();

  @async
  String getApkPath();

  @async
  int createMapSurface(CreateMapSurfaceRequest request);

  @async
  bool resizeMapSurface(ResizeMapSurfaceRequest request);

  @async
  bool destroyMapSurface();

  /// Updates the native global pointer tracker and returns the projected map
  /// coordinate when the pointer is inside a ready map surface.
  @async
  MapPointerCoordinate? updateMapPointer(MapPointerUpdateRequest request);

  /// Updates native draw/edit interaction geometry with caller-provided styling.
  @async
  bool updateDrapeInteractionGeometry(DrapeInteractionGeometryRequest request);

  /// Returns the current place page payload if available.
  @async
  PlacePageData? getCurrentPlacePage();

  /// Clears the active place page selection.
  @async
  bool clearPlacePageSelection();
}

/// Flutter API implemented by Dart for low-frequency notifications.
@FlutterApi()
abstract class AgusMapsFlutterApi {
  void onMapReady(int surfaceId);

  void onRenderStateChanged(RenderState state, int? surfaceId);

  void onPlacePageChanged(PlacePageData? placePage);
}
