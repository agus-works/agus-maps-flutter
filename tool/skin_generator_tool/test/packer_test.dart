import 'package:flutter_test/flutter_test.dart';
import 'package:skin_generator_tool/packer.dart';

void main() {
  group('Packer', () {
    test('Packs simple rectangles', () {
      final packer = Packer(128, 128);
      
      final r1 = packer.pack(32, 32);
      expect(r1, isNotNull);
      expect(r1!.width, 32);
      expect(r1.height, 32);
      
      final r2 = packer.pack(64, 64);
      expect(r2, isNotNull);
      expect(r2!.width, 64);
      expect(r2.height, 64);
      
      // Should not overlap
      expect(_overlaps(r1, r2), false);
    });

    test('Overflows when full', () {
      final packer = Packer(64, 64);
      
      final r1 = packer.pack(64, 64);
      expect(r1, isNotNull);
      
      final r2 = packer.pack(1, 1);
      expect(r2, isNull);
      expect(packer.overflowDetected, true);
    });
    
    test('Packs many small rectangles efficiently', () {
      final packer = Packer(256, 256);
      
      // We should be able to pack 64 of 32x32 into 256x256
      for (int i = 0; i < 64; i++) {
        expect(packer.pack(32, 32), isNotNull);
      }
      
      // The 65th should overflow
      expect(packer.pack(32, 32), isNull);
      expect(packer.overflowDetected, true);
    });
  });
}

bool _overlaps(Rect a, Rect b) {
  if (a.x >= b.right || b.x >= a.right) return false;
  if (a.y >= b.bottom || b.y >= a.bottom) return false;
  return true;
}
