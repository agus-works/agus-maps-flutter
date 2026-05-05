import 'package:flutter/material.dart';

import '../adaptive/form_factor.dart';

/// Applies body safe-area padding according to the active app shell.
///
/// Mobile landscape has a dedicated left navigation strip that already owns the
/// left unsafe region. The body should not add left or bottom safe-area padding
/// again in that orientation, otherwise tab pages appear shifted inward.
class AdaptiveBodySafeArea extends StatelessWidget {
  /// Creates an orientation-aware body safe-area wrapper.
  const AdaptiveBodySafeArea({
    super.key,
    required this.child,
    this.top = true,
    this.left = true,
    this.right = true,
    this.bottom = true,
  });

  /// Body content to wrap.
  final Widget child;

  /// Whether the caller wants top safe-area padding when the shell allows it.
  final bool top;

  /// Whether the caller wants left safe-area padding when the shell allows it.
  final bool left;

  /// Whether the caller wants right safe-area padding when the shell allows it.
  final bool right;

  /// Whether the caller wants bottom safe-area padding when the shell allows it.
  final bool bottom;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final mobileLandscape =
        context.exampleFormFactor.isMobile && size.width > size.height;

    return SafeArea(
      top: top,
      left: mobileLandscape ? false : left,
      right: right,
      bottom: mobileLandscape ? false : bottom,
      child: child,
    );
  }
}
