import 'package:flutter/material.dart';

import '../adaptive/form_factor.dart';
import 'adaptive_body_safe_area.dart';

/// Navigation metadata for [AdaptiveAppScaffold].
class AdaptiveScaffoldDestination {
  const AdaptiveScaffoldDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final Widget icon;
  final Widget selectedIcon;
}

/// App shell that swaps bottom navigation for a larger-screen side rail.
class AdaptiveAppScaffold extends StatelessWidget {
  const AdaptiveAppScaffold({
    super.key,
    required this.title,
    required this.selectedIndex,
    required this.destinations,
    required this.onDestinationSelected,
    required this.body,
    this.bodySafeAreaTop = true,
    this.bodySafeAreaLeft = true,
    this.bodySafeAreaRight = true,
    this.bodySafeAreaBottom = true,
    this.resizeToAvoidBottomInset = true,
  });

  final String title;
  final int selectedIndex;
  final List<AdaptiveScaffoldDestination> destinations;
  final ValueChanged<int> onDestinationSelected;
  final Widget body;
  final bool bodySafeAreaTop;
  final bool bodySafeAreaLeft;
  final bool bodySafeAreaRight;
  final bool bodySafeAreaBottom;
  final bool resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    final uiSpec = context.exampleUiSpec;
    final size = MediaQuery.sizeOf(context);
    final mobileLandscape =
        uiSpec.formFactor.isMobile && size.width > size.height;
    final bodyChild = AdaptiveBodySafeArea(
      top: bodySafeAreaTop,
      left: bodySafeAreaLeft,
      right: bodySafeAreaRight,
      bottom: bodySafeAreaBottom,
      child: body,
    );

    if (mobileLandscape) {
      return Scaffold(
        resizeToAvoidBottomInset: resizeToAvoidBottomInset,
        body: Row(
          children: [
            _MobileLandscapeNavigationStrip(
              selectedIndex: selectedIndex,
              destinations: destinations,
              onDestinationSelected: onDestinationSelected,
            ),
            Expanded(child: bodyChild),
          ],
        ),
      );
    }

    if (uiSpec.formFactor.isMobile) {
      return Scaffold(
        resizeToAvoidBottomInset: resizeToAvoidBottomInset,
        body: bodyChild,
        bottomNavigationBar: NavigationBar(
          selectedIndex: selectedIndex,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
          onDestinationSelected: onDestinationSelected,
          destinations: [
            for (final destination in destinations)
              NavigationDestination(
                icon: destination.icon,
                selectedIcon: destination.selectedIcon,
                label: destination.label,
              ),
          ],
        ),
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      body: Row(
        children: [
          SafeArea(
            child: _AdaptiveNavigationRail(
              title: title,
              selectedIndex: selectedIndex,
              destinations: destinations,
              onDestinationSelected: onDestinationSelected,
              extended: uiSpec.navigationRailExtended,
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: bodyChild),
        ],
      ),
    );
  }
}

class _MobileLandscapeNavigationStrip extends StatelessWidget {
  const _MobileLandscapeNavigationStrip({
    required this.selectedIndex,
    required this.destinations,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final List<AdaptiveScaffoldDestination> destinations;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final padding = MediaQuery.paddingOf(context);
    final stripWidth = padding.left + 58;

    return Material(
      color: colorScheme.surface.withValues(alpha: 0.94),
      child: SizedBox(
        width: stripWidth,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: padding.left,
            top: padding.top + 8,
            bottom: padding.bottom + 8,
          ),
          child: Column(
            children: [
              for (var index = 0; index < destinations.length; index++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: IconButton(
                    tooltip: destinations[index].label,
                    isSelected: selectedIndex == index,
                    selectedIcon: destinations[index].selectedIcon,
                    icon: destinations[index].icon,
                    style: IconButton.styleFrom(
                      backgroundColor: selectedIndex == index
                          ? colorScheme.primaryContainer
                          : Colors.transparent,
                      foregroundColor: selectedIndex == index
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurfaceVariant,
                      minimumSize: const Size.square(46),
                    ),
                    onPressed: () => onDestinationSelected(index),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdaptiveNavigationRail extends StatelessWidget {
  const _AdaptiveNavigationRail({
    required this.title,
    required this.selectedIndex,
    required this.destinations,
    required this.onDestinationSelected,
    required this.extended,
  });

  final String title;
  final int selectedIndex;
  final List<AdaptiveScaffoldDestination> destinations;
  final ValueChanged<int> onDestinationSelected;
  final bool extended;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: colorScheme.surfaceContainerLow,
      child: NavigationRail(
        extended: extended,
        minWidth: 84,
        minExtendedWidth: 216,
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        useIndicator: false,
        backgroundColor: Colors.transparent,
        leading: Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
          child: extended
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.layers_clear,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                )
              : Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.layers_clear,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
        ),
        destinations: [
          for (final destination in destinations)
            NavigationRailDestination(
              icon: destination.icon,
              selectedIcon: destination.selectedIcon,
              label: Text(destination.label),
            ),
        ],
      ),
    );
  }
}
