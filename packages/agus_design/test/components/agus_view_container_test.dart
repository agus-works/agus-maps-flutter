import 'dart:ui' show Tristate;

import 'package:agus_design/agus_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  testWidgets('view container renders initially expanded views and counts', (
    tester,
  ) async {
    await pumpAgusWidget(
      tester,
      const AgusViewContainer(
        views: [
          AgusView(
            id: 'open-editors',
            title: 'Open Editors',
            countLabel: '2',
            child: Text('Map.dart'),
          ),
          AgusView(
            id: 'outline',
            title: 'Outline',
            initiallyExpanded: false,
            child: Text('build'),
          ),
        ],
      ),
    );

    expect(find.text('OPEN EDITORS'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Map.dart'), findsOneWidget);
    expect(find.text('OUTLINE'), findsOneWidget);
    expect(find.text('build'), findsNothing);
  });

  testWidgets('view container toggles expansion and reports next ids', (
    tester,
  ) async {
    Set<String>? expandedIds;
    String? toggledId;

    await pumpAgusWidget(
      tester,
      AgusViewContainer(
        views: const [
          AgusView(id: 'projects', title: 'Projects', child: Text('Layer A')),
          AgusView(id: 'timeline', title: 'Timeline', child: Text('Created')),
        ],
        onToggle: (id) => toggledId = id,
        onExpandedIdsChanged: (ids) => expandedIds = ids,
      ),
    );

    await tester.tap(find.text('PROJECTS'));
    await tester.pump();

    expect(toggledId, 'projects');
    expect(expandedIds, {'timeline'});
    expect(find.text('Layer A'), findsNothing);
    expect(find.text('Created'), findsOneWidget);
  });

  testWidgets('view container can be controlled and single-expanded', (
    tester,
  ) async {
    var expanded = <String>{'projects'};

    await pumpAgusWidget(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          return AgusViewContainer(
            allowMultipleExpanded: false,
            expandedIds: expanded,
            onExpandedIdsChanged: (ids) => setState(() => expanded = ids),
            views: const [
              AgusView(
                id: 'projects',
                title: 'Projects',
                child: Text('Layer A'),
              ),
              AgusView(id: 'outline', title: 'Outline', child: Text('build')),
            ],
          );
        },
      ),
    );

    await tester.tap(find.text('OUTLINE'));
    await tester.pump();

    expect(expanded, {'outline'});
    expect(find.text('Layer A'), findsNothing);
    expect(find.text('build'), findsOneWidget);
  });

  testWidgets('view container invokes header actions without toggling', (
    tester,
  ) async {
    var actionPressed = false;

    await pumpAgusWidget(
      tester,
      AgusViewContainer(
        views: [
          AgusView(
            id: 'npm',
            title: 'NPM Scripts',
            actions: [
              IconButton(
                tooltip: 'Refresh scripts',
                onPressed: () => actionPressed = true,
                icon: const Icon(Icons.refresh),
              ),
            ],
            child: const Text('test'),
          ),
        ],
      ),
    );

    await tester.tap(find.byTooltip('Refresh scripts'));
    await tester.pump();

    expect(actionPressed, isTrue);
    expect(find.text('test'), findsOneWidget);
  });

  testWidgets('view container handles zero views and zero header height', (
    tester,
  ) async {
    await pumpAgusWidget(
      tester,
      const Column(
        children: [
          Expanded(child: AgusViewContainer(views: [])),
          AgusViewContainer(
            headerHeight: 0,
            views: [
              AgusView(id: 'empty', title: 'Empty', child: SizedBox.shrink()),
            ],
          ),
        ],
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('No views available.'), findsOneWidget);
  });

  testWidgets('view container exposes expanded semantics', (tester) async {
    await pumpAgusWidget(
      tester,
      const AgusViewContainer(
        views: [
          AgusView(id: 'outline', title: 'Outline', child: Text('build')),
        ],
      ),
    );

    final semantics = tester.getSemantics(find.text('OUTLINE'));
    expect(semantics.flagsCollection.isExpanded, Tristate.isTrue);
    expect(semantics.flagsCollection.isButton, isTrue);
  });

  test('view container rejects negative header height', () {
    expect(
      () => AgusViewContainer(views: const [], headerHeight: -1),
      throwsAssertionError,
    );
  });
}
