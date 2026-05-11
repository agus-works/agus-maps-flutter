import 'package:agus_maps_flutter/mwm_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('MWM Storage', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('should support multiple versions per region', () async {
      final storage = await MwmStorage.create();

      await storage.upsert(
        MwmMetadata(
          regionName: 'Gibraltar',
          snapshotVersion: '250608',
          fileSize: 2048,
          downloadDate: DateTime(2025, 6, 8),
          filePath: '/maps/Gibraltar_250608.mwm',
          isBundled: false,
        ),
      );

      await storage.upsert(
        MwmMetadata(
          regionName: 'Gibraltar',
          snapshotVersion: '250710',
          fileSize: 2100,
          downloadDate: DateTime(2025, 7, 10),
          filePath: '/maps/Gibraltar_250710.mwm',
          isBundled: false,
        ),
      );

      final all = storage.getAll();
      expect(all.length, 2, reason: 'Should store multiple versions');

      final versions = storage.getAllVersions('Gibraltar');
      expect(versions.length, 2);
      expect(versions[0].snapshotVersion, '250710');
      expect(versions[1].snapshotVersion, '250608');
    });

    test('should mark latest version as active by default', () async {
      final storage = await MwmStorage.create();

      await storage.upsert(
        MwmMetadata(
          regionName: 'Gibraltar',
          snapshotVersion: '250608',
          fileSize: 2048,
          downloadDate: DateTime(2025, 6, 8),
          filePath: '/maps/Gibraltar_250608.mwm',
          isBundled: false,
        ),
      );

      await storage.upsert(
        MwmMetadata(
          regionName: 'Gibraltar',
          snapshotVersion: '250710',
          fileSize: 2100,
          downloadDate: DateTime(2025, 7, 10),
          filePath: '/maps/Gibraltar_250710.mwm',
          isBundled: false,
        ),
      );

      final active = storage.getActiveVersion('Gibraltar');
      expect(active, isNotNull);
      expect(active!.snapshotVersion, '250710');
      expect(active.isActive, isTrue);

      final old = storage.getByRegionAndVersion('Gibraltar', '250608');
      expect(old, isNotNull);
      expect(old!.isActive, isFalse);
    });
  });
}
