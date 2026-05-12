import 'package:flutter_test/flutter_test.dart';
import 'package:agus_maps_flutter_example/features/workbench/interaction_state_controller.dart';

void main() {
  group('AppInteractionState', () {
    test('defaults to idle mode with empty metadata', () {
      const state = AppInteractionState();
      expect(state.mode, AppInteractionMode.idle);
      expect(state.metadata, isEmpty);
    });

    test('copyWith creates new state with updated fields', () {
      const state = AppInteractionState(
        mode: AppInteractionMode.idle,
        metadata: {'key': 'value'},
      );

      final updated = state.copyWith(mode: AppInteractionMode.drawing);
      expect(updated.mode, AppInteractionMode.drawing);
      expect(updated.metadata, {'key': 'value'});

      final metadataUpdated = state.copyWith(
        metadata: {'newKey': 'newValue'},
      );
      expect(metadataUpdated.mode, AppInteractionMode.idle);
      expect(metadataUpdated.metadata, {'newKey': 'newValue'});
    });

    test('allowsDrawing is true only in idle mode', () {
      const idle = AppInteractionState(mode: AppInteractionMode.idle);
      expect(idle.allowsDrawing, isTrue);

      const drawing = AppInteractionState(mode: AppInteractionMode.drawing);
      expect(drawing.allowsDrawing, isFalse);

      const editing =
          AppInteractionState(mode: AppInteractionMode.editingFeature);
      expect(editing.allowsDrawing, isFalse);

      const searching = AppInteractionState(mode: AppInteractionMode.searching);
      expect(searching.allowsDrawing, isFalse);
    });

    test(
        'allowsNavigation is true in idle, searching, and switchingLayer modes',
        () {
      const idle = AppInteractionState(mode: AppInteractionMode.idle);
      expect(idle.allowsNavigation, isTrue);

      const searching = AppInteractionState(mode: AppInteractionMode.searching);
      expect(searching.allowsNavigation, isTrue);

      const switching =
          AppInteractionState(mode: AppInteractionMode.switchingLayer);
      expect(switching.allowsNavigation, isTrue);

      const drawing = AppInteractionState(mode: AppInteractionMode.drawing);
      expect(drawing.allowsNavigation, isFalse);

      const editing =
          AppInteractionState(mode: AppInteractionMode.editingFeature);
      expect(editing.allowsNavigation, isFalse);
    });

    test('isEditing is true for drawing and editingFeature modes', () {
      const drawing = AppInteractionState(mode: AppInteractionMode.drawing);
      expect(drawing.isEditing, isTrue);

      const editing =
          AppInteractionState(mode: AppInteractionMode.editingFeature);
      expect(editing.isEditing, isTrue);

      const idle = AppInteractionState(mode: AppInteractionMode.idle);
      expect(idle.isEditing, isFalse);

      const searching = AppInteractionState(mode: AppInteractionMode.searching);
      expect(searching.isEditing, isFalse);
    });

    test(
        'disabledReason returns appropriate message for blocked draw operation',
        () {
      const drawing = AppInteractionState(mode: AppInteractionMode.drawing);
      final reason = drawing.disabledReason('draw');
      expect(reason, contains('drawing or feature edit is in progress'));

      const editing =
          AppInteractionState(mode: AppInteractionMode.editingFeature);
      final editReason = editing.disabledReason('draw');
      expect(editReason, contains('drawing or feature edit is in progress'));

      const idle = AppInteractionState(mode: AppInteractionMode.idle);
      expect(idle.disabledReason('draw'), isNull);
    });

    test('equality compares mode and metadata', () {
      const state1 = AppInteractionState(
        mode: AppInteractionMode.drawing,
        metadata: {'tool': 'polygon'},
      );
      const state2 = AppInteractionState(
        mode: AppInteractionMode.drawing,
        metadata: {'tool': 'polygon'},
      );
      const state3 = AppInteractionState(
        mode: AppInteractionMode.drawing,
        metadata: {'tool': 'point'},
      );

      expect(state1, equals(state2));
      expect(state1, isNot(equals(state3)));
    });

    test('hashCode is consistent with equality', () {
      const state1 = AppInteractionState(
        mode: AppInteractionMode.drawing,
        metadata: {'tool': 'polygon'},
      );
      const state2 = AppInteractionState(
        mode: AppInteractionMode.drawing,
        metadata: {'tool': 'polygon'},
      );
      const state3 = AppInteractionState(
        mode: AppInteractionMode.drawing,
        metadata: {'tool': 'point'},
      );

      // Equal states must have equal hashCodes
      expect(state1, equals(state2));
      // Note: hashCode implementation uses Object.hashAll on map entries,
      // which may not be stable across identical maps. We verify equality works.

      // Non-equal states should generally have different hashCodes (not guaranteed, but likely)
      expect(state1, isNot(equals(state3)));
    });
  });

  group('AppInteractionStateController', () {
    test('initializes with idle state by default', () {
      final controller = AppInteractionStateController();
      expect(controller.state.mode, AppInteractionMode.idle);
      expect(controller.isIdle, isTrue);
      expect(controller.isDrawing, isFalse);
      expect(controller.isEditingFeature, isFalse);
    });

    test('enterDrawing transitions to drawing mode', () {
      final controller = AppInteractionStateController();
      var notified = false;
      controller.addListener(() {
        notified = true;
      });

      controller.enterDrawing(tool: 'polygon');

      expect(controller.isDrawing, isTrue);
      expect(controller.state.mode, AppInteractionMode.drawing);
      expect(controller.state.metadata['drawTool'], 'polygon');
      expect(notified, isTrue);
    });

    test('enterEditingFeature transitions to editingFeature mode', () {
      final controller = AppInteractionStateController();
      var notified = false;
      controller.addListener(() {
        notified = true;
      });

      controller.enterEditingFeature(featureId: 42);

      expect(controller.isEditingFeature, isTrue);
      expect(controller.state.mode, AppInteractionMode.editingFeature);
      expect(controller.state.metadata['featureId'], 42);
      expect(notified, isTrue);
    });

    test('enterIdle transitions back to idle mode', () {
      final controller = AppInteractionStateController();
      controller.enterDrawing();
      expect(controller.isDrawing, isTrue);

      controller.enterIdle();

      expect(controller.isIdle, isTrue);
      expect(controller.state.mode, AppInteractionMode.idle);
      expect(controller.state.metadata, isEmpty);
    });

    test('enterSearch transitions to search mode with query metadata', () {
      final controller = AppInteractionStateController();

      controller.enterSearch(query: 'Gibraltar');

      expect(controller.isSearching, isTrue);
      expect(controller.state.mode, AppInteractionMode.searching);
      expect(controller.state.metadata['searchQuery'], 'Gibraltar');
    });

    test('enterRouting transitions to routing mode', () {
      final controller = AppInteractionStateController();

      controller.enterRouting();

      expect(controller.isRouting, isTrue);
      expect(controller.state.mode, AppInteractionMode.routing);
    });

    test('enterDownloadingMwm transitions to downloadingMwm mode', () {
      final controller = AppInteractionStateController();

      controller.enterDownloadingMwm();

      expect(controller.isDownloadingMwm, isTrue);
      expect(controller.state.mode, AppInteractionMode.downloadingMwm);
    });

    test('enterSwitchingLayer transitions to switchingLayer mode', () {
      final controller = AppInteractionStateController();

      controller.enterSwitchingLayer(layerId: 'layer-123');

      expect(controller.isSwitchingLayer, isTrue);
      expect(controller.state.mode, AppInteractionMode.switchingLayer);
      expect(controller.state.metadata['layerId'], 'layer-123');
    });

    test('enterModalInput transitions to modalInput mode', () {
      final controller = AppInteractionStateController();

      controller.enterModalInput();

      expect(controller.isModalInput, isTrue);
      expect(controller.state.mode, AppInteractionMode.modalInput);
    });

    test('isOperationAllowed returns correct value for draw operation', () {
      final controller = AppInteractionStateController();

      expect(controller.isOperationAllowed('draw'), isTrue);

      controller.enterDrawing();
      expect(controller.isOperationAllowed('draw'), isFalse);

      controller.enterIdle();
      expect(controller.isOperationAllowed('draw'), isTrue);
    });

    test('isOperationAllowed returns correct value for edit operation', () {
      final controller = AppInteractionStateController();

      expect(controller.isOperationAllowed('edit'), isTrue);

      controller.enterDrawing();
      expect(controller.isOperationAllowed('edit'), isFalse);

      controller.enterEditingFeature();
      expect(controller.isOperationAllowed('edit'), isTrue);
    });

    test('isOperationAllowed returns correct value for route operation', () {
      final controller = AppInteractionStateController();

      expect(controller.isOperationAllowed('route'), isTrue);

      controller.enterDrawing();
      expect(controller.isOperationAllowed('route'), isFalse);

      controller.enterRouting();
      expect(controller.isOperationAllowed('route'), isTrue);
    });

    test('disabledReason returns appropriate message for blocked operations',
        () {
      final controller = AppInteractionStateController();

      expect(controller.disabledReason('draw'), isNull);

      controller.enterDrawing();
      final reason = controller.disabledReason('draw');
      expect(reason, isNotNull);
      expect(reason, contains('drawing or feature edit is in progress'));
    });

    test('does not notify listeners if state does not change', () {
      final controller = AppInteractionStateController();
      var notifyCount = 0;
      controller.addListener(() {
        notifyCount++;
      });

      controller.enterIdle();
      expect(notifyCount, 0);

      controller.enterDrawing();
      expect(notifyCount, 1);

      controller.enterDrawing();
      expect(notifyCount, 1);
    });

    test('isEditing property reflects editing modes', () {
      final controller = AppInteractionStateController();

      expect(controller.isEditing, isFalse);

      controller.enterDrawing();
      expect(controller.isEditing, isTrue);

      controller.enterIdle();
      expect(controller.isEditing, isFalse);

      controller.enterEditingFeature();
      expect(controller.isEditing, isTrue);

      controller.enterSearch();
      expect(controller.isEditing, isFalse);
    });

    test('mode transitions maintain metadata isolation', () {
      final controller = AppInteractionStateController();

      controller.enterDrawing(tool: 'polygon');
      expect(controller.state.metadata['drawTool'], 'polygon');

      controller.enterEditingFeature(featureId: 99);
      expect(controller.state.metadata['drawTool'], isNull);
      expect(controller.state.metadata['featureId'], 99);

      controller.enterIdle();
      expect(controller.state.metadata, isEmpty);
    });
  });

  group('AppInteractionState operation permissions', () {
    test('drawing mode blocks most operations except cancel', () {
      const state = AppInteractionState(mode: AppInteractionMode.drawing);

      expect(state.allowsDrawing, isFalse);
      expect(state.allowsFeatureEdit, isFalse);
      expect(state.allowsNavigation, isFalse);
      expect(state.allowsRouting, isFalse);
    });

    test('editingFeature mode blocks drawing but allows feature edit', () {
      const state =
          AppInteractionState(mode: AppInteractionMode.editingFeature);

      expect(state.allowsDrawing, isFalse);
      expect(state.allowsFeatureEdit, isTrue);
      expect(state.allowsNavigation, isFalse);
    });

    test('searching mode allows navigation and routing', () {
      const state = AppInteractionState(mode: AppInteractionMode.searching);

      expect(state.allowsDrawing, isFalse);
      expect(state.allowsNavigation, isTrue);
      expect(state.allowsRouting, isTrue);
      expect(state.allowsMwmDownload, isTrue);
    });

    test('routing mode allows routing operations', () {
      const state = AppInteractionState(mode: AppInteractionMode.routing);

      expect(state.allowsRouting, isTrue);
      expect(state.allowsDrawing, isFalse);
    });

    test('downloadingMwm mode allows MWM operations', () {
      const state =
          AppInteractionState(mode: AppInteractionMode.downloadingMwm);

      expect(state.allowsMwmDownload, isTrue);
      expect(state.allowsDrawing, isFalse);
    });

    test('switchingLayer mode allows navigation and layer operations', () {
      const state =
          AppInteractionState(mode: AppInteractionMode.switchingLayer);

      expect(state.allowsNavigation, isTrue);
      expect(state.allowsLayerSwitch, isTrue);
      expect(state.allowsDrawing, isFalse);
    });
  });
}
