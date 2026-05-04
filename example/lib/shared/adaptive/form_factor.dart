import 'dart:math' as math;

import 'package:flutter/material.dart';

/// High-level UI buckets used by the example app.
enum ExampleFormFactor {
  mobile,
  tablet,
  desktop;

  bool get isMobile => this == ExampleFormFactor.mobile;
  bool get isTablet => this == ExampleFormFactor.tablet;
  bool get isDesktop => this == ExampleFormFactor.desktop;
}

/// Shared spacing and density decisions for a resolved [ExampleFormFactor].
@immutable
class ExampleUiSpec {
  const ExampleUiSpec._({
    required this.formFactor,
    required this.searchOverlayWidth,
    required this.dockedPanelWidth,
    required this.navigationRailExtended,
    required this.visualDensity,
    required this.treeRowPadding,
    required this.mapToolbarAxis,
  });

  /// Creates the active UI spec for the current layout constraints.
  factory ExampleUiSpec.of(BuildContext context) {
    final formFactor = resolveExampleFormFactor(context);
    return switch (formFactor) {
      ExampleFormFactor.mobile => const ExampleUiSpec._(
          formFactor: ExampleFormFactor.mobile,
          searchOverlayWidth: 0,
          dockedPanelWidth: 0,
          navigationRailExtended: false,
          visualDensity: VisualDensity.standard,
          treeRowPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          mapToolbarAxis: Axis.horizontal,
        ),
      ExampleFormFactor.tablet => const ExampleUiSpec._(
          formFactor: ExampleFormFactor.tablet,
          searchOverlayWidth: 420,
          dockedPanelWidth: 360,
          navigationRailExtended: false,
          visualDensity: VisualDensity.standard,
          treeRowPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          mapToolbarAxis: Axis.horizontal,
        ),
      ExampleFormFactor.desktop => const ExampleUiSpec._(
          formFactor: ExampleFormFactor.desktop,
          searchOverlayWidth: 380,
          dockedPanelWidth: 320,
          navigationRailExtended: true,
          visualDensity: VisualDensity.compact,
          treeRowPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          mapToolbarAxis: Axis.vertical,
        ),
    };
  }

  final ExampleFormFactor formFactor;
  final double searchOverlayWidth;
  final double dockedPanelWidth;
  final bool navigationRailExtended;
  final VisualDensity visualDensity;
  final EdgeInsets treeRowPadding;
  final Axis mapToolbarAxis;
}

/// Resolves the current form factor from available Flutter layout data.
///
/// Width and shortest-side are the primary signals so Android and iPad tablets
/// can opt into the larger-shell UI without relying on brittle native checks.
ExampleFormFactor resolveExampleFormFactor(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  final shortestSide = math.min(size.width, size.height);
  final platform = Theme.of(context).platform;
  final isDesktopPlatform = switch (platform) {
    TargetPlatform.macOS ||
    TargetPlatform.linux ||
    TargetPlatform.windows =>
      true,
    _ => false,
  };

  if (shortestSide < 600 || size.width < 700) {
    return ExampleFormFactor.mobile;
  }

  if (isDesktopPlatform && size.width >= 1100) {
    return ExampleFormFactor.desktop;
  }

  if (size.width >= 1400) {
    return ExampleFormFactor.desktop;
  }

  return ExampleFormFactor.tablet;
}

extension ExampleAdaptiveContext on BuildContext {
  /// Returns the resolved adaptive form factor for this context.
  ExampleFormFactor get exampleFormFactor => resolveExampleFormFactor(this);

  /// Returns shared adaptive sizing and density values.
  ExampleUiSpec get exampleUiSpec => ExampleUiSpec.of(this);
}
