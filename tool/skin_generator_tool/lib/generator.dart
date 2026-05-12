import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';
import 'packer.dart';

const double kMediumIconSize = 18.0;

class SymbolInfo {
  final ui.Image image;
  final String id;
  final int width;
  final int height;

  SymbolInfo(this.image, this.id, this.width, this.height);
}

class SkinGenerator {
  static int nextPowerOf2(int n) {
    n = n - 1;
    n |= (n >> 1);
    n |= (n >> 2);
    n |= (n >> 4);
    n |= (n >> 8);
    n |= (n >> 16);
    return n + 1;
  }

  static Future<void> generate({
    required String svgDir,
    required String pngDir,
    required String
    skinName, // Used as a prefix but actually we output to its dir
    required List<int> symbolSizes,
    required List<String> suffixes,
    int maxSize = 4096,
  }) async {
    for (int j = 0; j < symbolSizes.length; ++j) {
      final size = symbolSizes[j];
      final suffix = suffixes[j];

      final dirSvg = Directory(svgDir);
      final dirPng = Directory(pngDir);

      List<File> files = [];
      if (dirSvg.existsSync()) {
        files.addAll(dirSvg.listSync().whereType<File>());
      }
      if (dirPng.existsSync()) {
        files.addAll(dirPng.listSync().whereType<File>());
      }

      List<SymbolInfo> symbols = [];

      for (final file in files) {
        final fileName = p.basename(file.path);
        final symbolID = p.basenameWithoutExtension(fileName);

        if (fileName.toLowerCase().endsWith('.svg')) {
          final String svgString = await file.readAsString();

          final SvgStringLoader loader = SvgStringLoader(svgString);
          final PictureInfo pictureInfo = await vg.loadPicture(loader, null);

          double defaultWidth = pictureInfo.size.width;
          double defaultHeight = pictureInfo.size.height;

          try {
            final document = XmlDocument.parse(svgString);
            final svgElement = document.rootElement;
            final widthAttr = svgElement
                .getAttribute('width')
                ?.replaceAll('px', '');
            final heightAttr = svgElement
                .getAttribute('height')
                ?.replaceAll('px', '');

            if (widthAttr != null && heightAttr != null) {
              defaultWidth = double.parse(widthAttr);
              defaultHeight = double.parse(heightAttr);
            }
          } catch (e) {
            // fallback to pictureInfo.size
          }

          // Capping svg symbol to 24.0 maximum, keeping aspect ratio (matching C++ logic)
          if (defaultWidth > 24.0) {
            defaultHeight = defaultHeight * 24.0 / defaultWidth;
            defaultWidth = 24.0;
          }
          if (defaultHeight > 24.0) {
            defaultWidth = defaultWidth * 24.0 / defaultHeight;
            defaultHeight = 24.0;
          }

          // Scale symbol to required size
          final double scale = size / kMediumIconSize;
          final int targetWidth = (defaultWidth * scale).round() + 4;
          final int targetHeight = (defaultHeight * scale).round() + 4;

          // Actually, we need to scale the pictureInfo.picture to fit our target width/height.
          // pictureInfo.size is the viewBox size.
          final double scaleX = (defaultWidth / pictureInfo.size.width) * scale;
          final double scaleY =
              (defaultHeight / pictureInfo.size.height) * scale;

          final ui.PictureRecorder recorder = ui.PictureRecorder();
          final ui.Canvas canvas = ui.Canvas(recorder);

          canvas.save();
          canvas.translate(2, 2);
          canvas.scale(scaleX, scaleY);
          canvas.drawPicture(pictureInfo.picture);
          canvas.restore();

          final ui.Image image = await recorder.endRecording().toImage(
            targetWidth,
            targetHeight,
          );
          symbols.add(SymbolInfo(image, symbolID, targetWidth, targetHeight));

          pictureInfo.picture.dispose();
        } else if (fileName.toLowerCase().endsWith('.png')) {
          final Uint8List bytes = await file.readAsBytes();
          final ui.Codec codec = await ui.instantiateImageCodec(bytes);
          final ui.FrameInfo frame = await codec.getNextFrame();

          final int targetWidth = frame.image.width + 4;
          final int targetHeight = frame.image.height + 4;

          final ui.PictureRecorder recorder = ui.PictureRecorder();
          final ui.Canvas canvas = ui.Canvas(recorder);
          canvas.drawImage(frame.image, const ui.Offset(2, 2), ui.Paint());
          final ui.Image imageWithPadding = await recorder
              .endRecording()
              .toImage(targetWidth, targetHeight);

          symbols.add(
            SymbolInfo(imageWithPadding, symbolID, targetWidth, targetHeight),
          );
        }
      }

      // Sort symbols
      symbols.sort((a, b) {
        if (a.height == b.height) {
          return b.id.compareTo(a.id);
        }
        return b.height.compareTo(a.height);
      });

      int minWidth = 0;
      int minHeight = 0;
      for (final s in symbols) {
        if (s.width > minWidth) minWidth = s.width;
        if (s.height > minHeight) minHeight = s.height;
      }

      int width = nextPowerOf2(minWidth);
      int height = nextPowerOf2(minHeight);

      print(
        'Packing ${symbols.length} symbols (minWidth: $minWidth, minHeight: $minHeight) into max size $maxSize...',
      );

      Packer? packer;
      Map<SymbolInfo, Rect> packedSymbols = {};

      while (true) {
        packer = Packer(width, height);
        packedSymbols.clear();
        bool overflow = false;

        for (final s in symbols) {
          final rect = packer.pack(s.width, s.height);
          if (rect == null) {
            overflow = true;
            print(
              'Overflow packing symbol ${s.id} (${s.width}x${s.height}) into ${width}x${height}',
            );
            break;
          }
          packedSymbols[s] = rect;
        }

        if (overflow) {
          if (width == height) {
            width *= 2;
          } else {
            height *= 2;
          }

          if (width > maxSize) {
            width = maxSize;
            height *= 2;
            if (height > maxSize) {
              throw Exception(
                'Texture overflow, exceeded max size of $maxSize',
              );
            }
          }
          continue;
        }
        break;
      }

      final ui.PictureRecorder finalRecorder = ui.PictureRecorder();
      final ui.Canvas finalCanvas = ui.Canvas(finalRecorder);
      finalCanvas.drawColor(const ui.Color(0x00000000), ui.BlendMode.src);

      for (final s in symbols) {
        final rect = packedSymbols[s]!;
        finalCanvas.drawImage(
          s.image,
          ui.Offset(rect.x.toDouble(), rect.y.toDouble()),
          ui.Paint(),
        );
      }

      final ui.Image finalImage = await finalRecorder.endRecording().toImage(
        width,
        height,
      );
      final ByteData? byteData = await finalImage.toByteData(
        format: ui.ImageByteFormat.png,
      );

      final String skinDir = p.dirname(skinName);
      if (!Directory(skinDir).existsSync()) {
        Directory(skinDir).createSync(recursive: true);
      }

      final String outFileNameBase = p.join(skinDir, "symbols$suffix");

      final File pngFile = File('$outFileNameBase.png');
      await pngFile.writeAsBytes(byteData!.buffer.asUint8List());

      final builder = XmlBuilder();
      builder.element(
        'skin',
        nest: () {
          builder.element(
            'root',
            nest: () {
              builder.element(
                'file',
                attributes: {
                  'width': width.toString(),
                  'height': height.toString(),
                },
                nest: () {
                  for (final s in symbols) {
                    final rect = packedSymbols[s]!;
                    builder.element(
                      'symbol',
                      attributes: {
                        'minX': rect.x.toString(),
                        'minY': rect.y.toString(),
                        'maxX': rect.right.toString(),
                        'maxY': rect.bottom.toString(),
                        'name': s.id.toLowerCase(),
                      },
                    );
                  }
                },
              );
            },
          );
        },
      );

      final File xmlFile = File('$outFileNameBase.sdf');
      await xmlFile.writeAsString(
        builder.buildDocument().toXmlString(pretty: true),
      );

      print('Saved skin image into: ${pngFile.path}');
    }
  }
}
