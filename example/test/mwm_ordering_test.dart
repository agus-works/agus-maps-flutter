import 'package:agus_maps_flutter/mwm_storage.dart';
import 'package:agus_maps_flutter_example/features/map/widgets/adaptive_layer_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('MWM ordering', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('should support multiple versions per region', () async {
      final storage = await MwmStorage.create();

      // Add old version
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

      // Add new version
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
    });

    test('should order by map name then version', () async {
      final storage = await MwmStorage.create();

      await storage.upsert(
        MwmMetadata(
          regionName: 'World',
          snapshotVersion: '250608',
          fileSize: 4096,
          downloadDate: DateTime(2025, 6, 8),
          filePath: '/maps/World.mwm',
          isBundled: true,
        ),
      );

      await storage.upsert(
        MwmMetadata(
          regionName: 'Gibraltar',
          snapshotVersion: '250710',
          fileSize: 2048,
          downloadDate: DateTime(2025, 7, 10),
          filePath: '/maps/Gibraltar.mwm',
          isBundled: false,
        ),
      );

      await storage.upsert(
        MwmMetadata(
          regionName: 'Gibraltar',
          snapshotVersion: '250608',
          fileSize: 2000,
          downloadDate: DateTime(2025, 6, 8),
          filePath: '/maps/Gibraltar_old.mwm',
          isBundled: false,
        ),
      );

      final ordered = storage.getAllOrdered(MwmLayerOrderMode.byMap);
      expect(ordered.length, 3);
      expect(ordered[0].regionName, 'Gibraltar');
      expect(ordered[0].snapshotVersion, '250710');
      expect(ordered[1].regionName, 'Gibraltar');
      expect(ordered[1].snapshotVersion, '250608');
      expect(ordered[2].regionName, 'World');
    });

    test('should order by date then map name', () async {
      final storage = await MwmStorage.create();

      await storage.upsert(
        MwmMetadata(
          regionName: 'World',
          snapshotVersion: '250608',
          fileSize: 4096,
          downloadDate: DateTime(2025, 6, 8),
          filePath: '/maps/World.mwm',
          isBundled: true,
        ),
      );

      await storage.upsert(
        MwmMetadata(
          regionName: 'Gibraltar',
          snapshotVersion: '250710',
          fileSize: 2048,
          downloadDate: DateTime(2025, 7, 10),
          filePath: '/maps/Gibraltar.mwm',
          isBundled: false,
        ),
      );

      await storage.upsert(
        MwmMetadata(
          regionName: 'Gibraltar',
          snapshotVersion: '250608',
          fileSize: 2000,
          downloadDate: DateTime(2025, 6, 8),
          filePath: '/maps/Gibraltar_old.mwm',
          isBundled: false,
        ),
      );

      final ordered = storage.getAllOrdered(MwmLayerOrderMode.byDate);
      expect(ordered.length, 3);
      expect(ordered[0].snapshotVersion, '250710');
      expect(ordered[0].regionName, 'Gibraltar');
      expect(ordered[1].snapshotVersion, '250608');
      expect(ordered[1].regionName, 'Gibraltar');
      expect(ordered[2].snapshotVersion, '250608');
      expect(ordered[2].regionName, 'World');
    });

    test('should preserve old version metadata during upgrade', () async {
      final storage = await MwmStorage.create();

      // Add old version
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

      // Upgrade to new version
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

      final old = storage.getByRegionAndVersion('Gibraltar', '250608');
      expect(old, isNotNull, reason: 'Old version should be preserved');

      final active = storage.getActiveVersion('Gibraltar');
      expect(active!.snapshotVersion, '250710', reason: 'Latest should be active');
    });
  });
}
