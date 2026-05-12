import 'package:agus_maps_flutter_example/features/search/map_search_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers.dart';

class _SearchResult {
  const _SearchResult(this.title, this.subtitle, {this.routeDisabled = false});

  final String title;
  final String subtitle;
  final bool routeDisabled;
}

void main() {
  testWidgets('search panel shows empty, loading, and result states', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await pumpExampleWidget(
      tester,
      MapSearchPanel<_SearchResult>(
        controller: controller,
        focusNode: focusNode,
        results: const [],
        titleFor: (result) => result.title,
        subtitleFor: (result) => result.subtitle,
        iconFor: (_) => Icons.place_outlined,
        searching: true,
        onOpen: () {},
        onChanged: (_) {},
        onSubmitted: (_) {},
        onResultSelected: (_) {},
      ),
      size: const Size(360, 300),
    );

    expect(find.text('Search'), findsWidgets);
    expect(
      find.text('Type to search places, coordinates, or favorites.'),
      findsOneWidget,
    );

    controller.text = 'gibraltar';
    await pumpExampleWidget(
      tester,
      MapSearchPanel<_SearchResult>(
        controller: controller,
        focusNode: focusNode,
        results: const [],
        titleFor: (result) => result.title,
        subtitleFor: (result) => result.subtitle,
        iconFor: (_) => Icons.place_outlined,
        searching: true,
        onOpen: () {},
        onChanged: (_) {},
        onSubmitted: (_) {},
        onResultSelected: (_) {},
      ),
      size: const Size(360, 300),
    );

    expect(find.text('Search results'), findsOneWidget);
    expect(find.text('Searching...'), findsOneWidget);

    await pumpExampleWidget(
      tester,
      MapSearchPanel<_SearchResult>(
        controller: controller,
        focusNode: focusNode,
        results: const [
          _SearchResult('Gibraltar', 'Saved map target'),
        ],
        titleFor: (result) => result.title,
        subtitleFor: (result) => result.subtitle,
        iconFor: (_) => Icons.favorite_border,
        onOpen: () {},
        onChanged: (_) {},
        onSubmitted: (_) {},
        onResultSelected: (_) {},
      ),
      size: const Size(360, 300),
    );

    expect(find.text('Gibraltar'), findsOneWidget);
    expect(find.text('Saved map target'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
  });

  testWidgets('search panel emits submit, select, and route callbacks', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'gibraltar');
    final focusNode = FocusNode();
    final selected = <String>[];
    final routed = <String>[];
    String? submitted;
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await pumpExampleWidget(
      tester,
      MapSearchPanel<_SearchResult>(
        controller: controller,
        focusNode: focusNode,
        results: const [
          _SearchResult('Gibraltar', 'Saved map target'),
          _SearchResult('Suggestion', 'Native suggestion', routeDisabled: true),
        ],
        titleFor: (result) => result.title,
        subtitleFor: (result) => result.subtitle,
        iconFor: (_) => Icons.place_outlined,
        routeDisabledFor: (result) => result.routeDisabled,
        onOpen: () {},
        onChanged: (_) {},
        onSubmitted: (value) => submitted = value,
        onResultSelected: (result) => selected.add(result.title),
        onResultRoute: (result) => routed.add(result.title),
      ),
      size: const Size(420, 360),
    );

    await tester.tap(find.byType(TextField));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.tap(find.text('Gibraltar'));
    await tester.tap(find.byTooltip('Route').first);
    await tester.pump();

    final disabledRouteButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.alt_route).last,
    );

    expect(submitted, 'gibraltar');
    expect(selected, ['Gibraltar']);
    expect(routed, ['Gibraltar']);
    expect(disabledRouteButton.onPressed, isNull);
  });
}
