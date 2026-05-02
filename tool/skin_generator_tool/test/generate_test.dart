import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:skin_generator_tool/generator.dart';
import 'package:path/path.dart' as p;

void main() {
  test('Generate all skins', () async {
    final workspacePath = p.normalize(
      p.join(Directory.current.path, '..', '..'),
    );
    final dataPath = p.join(workspacePath, 'thirdparty', 'comaps', 'data');

    Future<void> buildSkin({
      required String styleType,
      required String styleName,
      required String resourceName,
      required int symbolSize,
      required String suffix,
      required String symbolsFolder,
      String symbolsSuffix = '',
    }) async {
      print('Building skin for $styleName/$resourceName');

      final stylePath = p.join(dataPath, 'styles', styleType, styleName);
      final svgDir = p.join(stylePath, symbolsFolder);
      final pngDir = p.join(stylePath, '$resourceName$symbolsSuffix');

      final skinName = p.join(
        dataPath,
        'symbols',
        resourceName,
        suffix,
        'basic',
      );

      await SkinGenerator.generate(
        svgDir: svgDir,
        pngDir: pngDir,
        skinName: skinName,
        symbolSizes: [symbolSize],
        suffixes: [symbolsSuffix],
      );
    }

    // Clear old symbols
    final symbolsDir = Directory(p.join(dataPath, 'symbols'));
    if (symbolsDir.existsSync()) {
      for (final entity in symbolsDir.listSync(recursive: true)) {
        if (entity is File && entity.path.contains('symbols.')) {
          entity.deleteSync();
        }
      }
    }

    // dark
    await buildSkin(
      styleType: 'default',
      styleName: 'dark',
      resourceName: 'mdpi',
      symbolSize: 18,
      suffix: 'dark',
      symbolsFolder: 'symbols',
    );
    await buildSkin(
      styleType: 'default',
      styleName: 'dark',
      resourceName: 'hdpi',
      symbolSize: 27,
      suffix: 'dark',
      symbolsFolder: 'symbols',
    );
    await buildSkin(
      styleType: 'default',
      styleName: 'dark',
      resourceName: 'xhdpi',
      symbolSize: 36,
      suffix: 'dark',
      symbolsFolder: 'symbols',
    );
    await buildSkin(
      styleType: 'default',
      styleName: 'dark',
      resourceName: '6plus',
      symbolSize: 43,
      suffix: 'dark',
      symbolsFolder: 'symbols',
    );
    await buildSkin(
      styleType: 'default',
      styleName: 'dark',
      resourceName: 'xxhdpi',
      symbolSize: 54,
      suffix: 'dark',
      symbolsFolder: 'symbols',
    );
    await buildSkin(
      styleType: 'default',
      styleName: 'dark',
      resourceName: 'xxxhdpi',
      symbolSize: 64,
      suffix: 'dark',
      symbolsFolder: 'symbols',
    );

    // light
    await buildSkin(
      styleType: 'default',
      styleName: 'light',
      resourceName: 'mdpi',
      symbolSize: 18,
      suffix: 'light',
      symbolsFolder: 'symbols',
    );
    await buildSkin(
      styleType: 'default',
      styleName: 'light',
      resourceName: 'hdpi',
      symbolSize: 27,
      suffix: 'light',
      symbolsFolder: 'symbols',
    );
    await buildSkin(
      styleType: 'default',
      styleName: 'light',
      resourceName: 'xhdpi',
      symbolSize: 36,
      suffix: 'light',
      symbolsFolder: 'symbols',
    );
    await buildSkin(
      styleType: 'default',
      styleName: 'light',
      resourceName: '6plus',
      symbolSize: 43,
      suffix: 'light',
      symbolsFolder: 'symbols',
    );
    await buildSkin(
      styleType: 'default',
      styleName: 'light',
      resourceName: 'xxhdpi',
      symbolSize: 54,
      suffix: 'light',
      symbolsFolder: 'symbols',
    );
    await buildSkin(
      styleType: 'default',
      styleName: 'light',
      resourceName: 'xxxhdpi',
      symbolSize: 64,
      suffix: 'light',
      symbolsFolder: 'symbols',
    );

    final symbolsName = ['6plus', 'mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi'];

    bool hasOptiPng = false;
    try {
      final res = await Process.run('optipng', ['-v']);
      if (res.exitCode == 0) hasOptiPng = true;
    } catch (_) {}

    if (hasOptiPng) {
      for (final i in symbolsName) {
        for (final theme in ['light', 'dark']) {
          final pngPath = p.join(dataPath, 'symbols', i, theme, 'symbols.png');
          if (File(pngPath).existsSync()) {
            await Process.run('optipng', [
              '-zc9',
              '-zm8',
              '-zs0',
              '-f0',
              pngPath,
            ]);
            print('Optimized $pngPath');
          }
        }
      }
    } else {
      print(
        '[WARN] optipng could not be found; generated symbol atlases will not be optimized.',
      );
    }

    // Cleanup design folder and copy light to design
    for (final i in symbolsName) {
      final designDir = Directory(p.join(dataPath, 'symbols', i, 'design'));
      if (designDir.existsSync()) {
        designDir.deleteSync(recursive: true);
      }
      final lightDir = Directory(p.join(dataPath, 'symbols', i, 'light'));
      if (lightDir.existsSync()) {
        designDir.createSync(recursive: true);
        for (final entity in lightDir.listSync()) {
          if (entity is File) {
            entity.copySync(p.join(designDir.path, p.basename(entity.path)));
          }
        }
      }
    }

    print('Skin generation completed successfully.');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
