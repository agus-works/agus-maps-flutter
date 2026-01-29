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
