import 'package:agus_design/agus_design.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_helpers.dart';

void main() {
  testWidgets('editor tabs emit close callbacks', (tester) async {
    String? closedId;

    await pumpAgusWidget(
      tester,
      AgusEditorTabBar(
        selectedId: 'a',
        onClose: (id) => closedId = id,
        tabs: const [
          AgusEditorTab(id: 'a', label: 'main.dart', icon: Icons.code),
        ],
      ),
    );

    await tester.tap(find.byIcon(Icons.close));

    expect(closedId, 'a');
  });

  testWidgets('editor tabs emit selection callbacks', (tester) async {
    String? selectedId;

    await pumpAgusWidget(
      tester,
      AgusEditorTabBar(
        selectedId: 'a',
        onSelected: (id) => selectedId = id,
        tabs: const [
          AgusEditorTab(id: 'a', label: 'main.dart', icon: Icons.code),
          AgusEditorTab(id: 'b', label: 'README.md', icon: Icons.description),
        ],
      ),
    );

    await tester.tap(find.text('README.md'));

    expect(selectedId, 'b');
  });

  testWidgets(
    'editor tabs render pinned, preview, dirty, and closable states',
    (tester) async {
      await pumpAgusWidget(
        tester,
        const AgusEditorTabBar(
          selectedId: 'preview',
          tabs: [
            AgusEditorTab(id: 'dirty', label: 'Dirty', dirty: true),
            AgusEditorTab(id: 'pinned', label: 'Pinned', pinned: true),
            AgusEditorTab(id: 'preview', label: 'Preview', preview: true),
            AgusEditorTab(id: 'fixed', label: 'Fixed', closable: false),
          ],
        ),
      );

      expect(find.byIcon(Icons.push_pin), findsOneWidget);
      expect(find.byIcon(Icons.close), findsNWidgets(2));

      final previewText = tester.widget<Text>(find.text('Preview'));
      expect(previewText.style?.fontStyle, FontStyle.italic);
    },
  );

  testWidgets('editor tab button emits selection and close events', (
    tester,
  ) async {
    String? selectedId;
    String? closedId;

    await pumpAgusWidget(
      tester,
      AgusEditorTabButton(
        tab: const AgusEditorTab(
          id: 'workbench',
          label: 'agus_workbench.dart',
          icon: Icons.code,
        ),
        selected: false,
        onSelected: (id) => selectedId = id,
        onClose: (id) => closedId = id,
      ),
      size: const Size(240, 60),
    );

    await tester.tap(find.text('agus_workbench.dart'));
    await tester.tap(find.byIcon(Icons.close));

    expect(selectedId, 'workbench');
    expect(closedId, 'workbench');
  });

  testWidgets('editor tab bar reveals an initially selected overflow tab', (
    tester,
  ) async {
    await pumpAgusWidget(
      tester,
      const SizedBox(
        width: 260,
        child: AgusEditorTabBar(
          selectedId: 'tab-5',
          tabs: [
            AgusEditorTab(id: 'tab-1', label: 'Tab 1'),
            AgusEditorTab(id: 'tab-2', label: 'Tab 2'),
            AgusEditorTab(id: 'tab-3', label: 'Tab 3'),
            AgusEditorTab(id: 'tab-4', label: 'Tab 4'),
            AgusEditorTab(id: 'tab-5', label: 'Tab 5'),
          ],
        ),
      ),
      size: const Size(320, 80),
    );
    await tester.pumpAndSettle();

    final tabBarRect = tester.getRect(find.byType(AgusEditorTabBar));
    final selectedRect = tester.getRect(find.text('Tab 5'));

    expect(selectedRect.left, greaterThanOrEqualTo(tabBarRect.left));
    expect(selectedRect.right, lessThanOrEqualTo(tabBarRect.right));
  });

  testWidgets('editor tab bar lets users scroll and select hidden tabs', (
    tester,
  ) async {
    String? selectedId;

    await pumpAgusWidget(
      tester,
      SizedBox(
        width: 260,
        child: AgusEditorTabBar(
          selectedId: 'tab-1',
          onSelected: (id) => selectedId = id,
          tabs: const [
            AgusEditorTab(id: 'tab-1', label: 'Tab 1'),
            AgusEditorTab(id: 'tab-2', label: 'Tab 2'),
            AgusEditorTab(id: 'tab-3', label: 'Tab 3'),
            AgusEditorTab(id: 'tab-4', label: 'Tab 4'),
            AgusEditorTab(id: 'tab-5', label: 'Tab 5'),
          ],
        ),
      ),
      size: const Size(320, 80),
    );
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('Tab 5'),
      find.byType(SingleChildScrollView),
      const Offset(-120, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tab 5'));

    expect(selectedId, 'tab-5');
  });

  testWidgets('editor tab bar supports wheel scrolling and subtle scrollbar', (
    tester,
  ) async {
    await pumpAgusWidget(
      tester,
      const SizedBox(
        width: 260,
        child: AgusEditorTabBar(
          selectedId: 'tab-1',
          tabs: [
            AgusEditorTab(id: 'tab-1', label: 'Tab 1'),
            AgusEditorTab(id: 'tab-2', label: 'Tab 2'),
            AgusEditorTab(id: 'tab-3', label: 'Tab 3'),
            AgusEditorTab(id: 'tab-4', label: 'Tab 4'),
            AgusEditorTab(id: 'tab-5', label: 'Tab 5'),
          ],
        ),
      ),
      size: const Size(320, 80),
    );
    await tester.pumpAndSettle();

    final scrollbar = tester.widget<Scrollbar>(find.byType(Scrollbar));
    expect(scrollbar.interactive, isTrue);
    expect(scrollbar.thickness, 3);

    final scrollView = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(scrollView.scrollDirection, Axis.horizontal);
    expect(find.byType(Listener), findsWidgets);
  });
}
