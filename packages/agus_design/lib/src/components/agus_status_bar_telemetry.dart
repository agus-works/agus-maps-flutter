import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'agus_notification.dart';
import 'agus_status_bar.dart';

/// Map telemetry data for status bar display.
@immutable
class MapTelemetry {
  const MapTelemetry({
    required this.zoom,
    required this.centerLat,
    required this.centerLon,
    required this.bearing,
    this.selectedPointLat,
    this.selectedPointLon,
  });

  /// Current zoom level (draw scale).
  final int zoom;

  /// Current map center latitude.
  final double centerLat;

  /// Current map center longitude.
  final double centerLon;

  /// Current map bearing in degrees (0 = north-up).
  final double bearing;

  /// Selected point latitude if any.
  final double? selectedPointLat;

  /// Selected point longitude if any.
  final double? selectedPointLon;

  /// Format latitude for display.
  String get formattedLat => '${centerLat.toStringAsFixed(6)}°';

  /// Format longitude for display.
  String get formattedLon => '${centerLon.toStringAsFixed(6)}°';

  /// Format bearing for display.
  String get formattedBearing {
    final normalized = bearing % 360;
    return '${normalized.toStringAsFixed(1)}°';
  }

  /// Format zoom for display.
  String get formattedZoom => 'z$zoom';

  /// Format selected point for display.
  String? get formattedSelectedPoint {
    if (selectedPointLat == null || selectedPointLon == null) {
      return null;
    }
    return '${selectedPointLat!.toStringAsFixed(6)}°, ${selectedPointLon!.toStringAsFixed(6)}°';
  }

  /// Format full center coordinate for clipboard.
  String get centerForClipboard =>
      '${centerLat.toStringAsFixed(6)}, ${centerLon.toStringAsFixed(6)}';

  /// Format selected point for clipboard.
  String? get selectedPointForClipboard {
    if (selectedPointLat == null || selectedPointLon == null) {
      return null;
    }
    return '${selectedPointLat!.toStringAsFixed(6)}, ${selectedPointLon!.toStringAsFixed(6)}';
  }
}

/// Creates status bar items for map telemetry with copy-to-clipboard support.
class MapTelemetryStatusBarBuilder {
  /// Creates status bar items for map telemetry.
  ///
  /// Shows zoom, bearing, center, and selected point (if any) with
  /// double-click and long-press copy-to-clipboard support.
  static List<AgusStatusBarItem> buildItems({
    required BuildContext context,
    required MapTelemetry telemetry,
  }) {
    return [
      // Zoom level
      AgusStatusBarItem(
        id: 'map-zoom',
        label: telemetry.formattedZoom,
        icon: Icons.zoom_out_map,
        tooltip: 'Zoom level: ${telemetry.zoom}\nDouble-click or long-press to copy',
        copyValue: telemetry.zoom.toString(),
        onDoubleTap: () => _copyToClipboard(
          context,
          telemetry.zoom.toString(),
          'Zoom level copied',
        ),
        onLongPress: () => _copyToClipboard(
          context,
          telemetry.zoom.toString(),
          'Zoom level copied',
        ),
      ),

      // Bearing/rotation
      AgusStatusBarItem(
        id: 'map-bearing',
        label: telemetry.formattedBearing,
        icon: Icons.explore,
        tooltip: 'Bearing: ${telemetry.formattedBearing}\nDouble-click or long-press to copy',
        copyValue: telemetry.bearing.toStringAsFixed(1),
        onDoubleTap: () => _copyToClipboard(
          context,
          telemetry.bearing.toStringAsFixed(1),
          'Bearing copied',
        ),
        onLongPress: () => _copyToClipboard(
          context,
          telemetry.bearing.toStringAsFixed(1),
          'Bearing copied',
        ),
      ),

      // Center point
      AgusStatusBarItem(
        id: 'map-center',
        label: '${telemetry.formattedLat}, ${telemetry.formattedLon}',
        icon: Icons.my_location,
        tooltip: 'Center: ${telemetry.centerForClipboard}\nDouble-click or long-press to copy',
        copyValue: telemetry.centerForClipboard,
        onDoubleTap: () => _copyToClipboard(
          context,
          telemetry.centerForClipboard,
          'Center coordinates copied',
        ),
        onLongPress: () => _copyToClipboard(
          context,
          telemetry.centerForClipboard,
          'Center coordinates copied',
        ),
      ),

      // Selected point (if any)
      if (telemetry.formattedSelectedPoint != null &&
          telemetry.selectedPointForClipboard != null)
        AgusStatusBarItem(
          id: 'map-selected-point',
          label: telemetry.formattedSelectedPoint!,
          icon: Icons.place,
          tooltip: 'Selected: ${telemetry.selectedPointForClipboard}\nDouble-click or long-press to copy',
          copyValue: telemetry.selectedPointForClipboard,
          onDoubleTap: () => _copyToClipboard(
            context,
            telemetry.selectedPointForClipboard!,
            'Selected point copied',
          ),
          onLongPress: () => _copyToClipboard(
            context,
            telemetry.selectedPointForClipboard!,
            'Selected point copied',
          ),
        ),
    ];
  }

  /// Copies text to clipboard and shows a notification toast.
  static void _copyToClipboard(
    BuildContext context,
    String text,
    String message,
  ) {
    Clipboard.setData(ClipboardData(text: text));
    AgusNotificationManager.instance.show(
      context: context,
      notification: AgusNotification(
        id: 'status-bar-copy-${DateTime.now().millisecondsSinceEpoch}',
        message: message,
        severity: AgusNotificationSeverity.success,
      ),
      duration: const Duration(seconds: 2),
    );
  }
}
