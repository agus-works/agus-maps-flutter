import 'package:flutter/material.dart';

import '../adaptive/form_factor.dart';

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
    this.resizeToAvoidBottomInset = true,
  });

  final String title;
  final int selectedIndex;
  final List<AdaptiveScaffoldDestination> destinations;
  final ValueChanged<int> onDestinationSelected;
  final Widget body;
  final bool resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    final uiSpec = context.exampleUiSpec;
    final bodyChild = SafeArea(child: body);

    if (uiSpec.formFactor.isMobile) {
      return Scaffold(
        resizeToAvoidBottomInset: resizeToAvoidBottomInset,
        body: bodyChild,
        bottomNavigationBar: NavigationBar(
          selectedIndex: selectedIndex,
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
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 0, 12),
              child: _AdaptiveNavigationRail(
                title: title,
                selectedIndex: selectedIndex,
                destinations: destinations,
                onDestinationSelected: onDestinationSelected,
                extended: uiSpec.navigationRailExtended,
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: bodyChild),
        ],
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
      elevation: 1,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: NavigationRail(
        extended: extended,
        minWidth: 84,
        minExtendedWidth: 216,
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        useIndicator: true,
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
                        borderRadius: BorderRadius.circular(14),
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
                    borderRadius: BorderRadius.circular(14),
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
