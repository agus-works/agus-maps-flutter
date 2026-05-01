# skin_generator_tool

A cross-platform Dart-based utility for generating packed texture atlases (skins) and XML metadata (`.sdf` files) from individual SVG and PNG symbols. This replaces the legacy C++ Qt-based tool and bash scripts, offering a native, dependency-free (beyond Flutter) workflow that works seamlessly on Windows, macOS, and Linux.

## Usage

This tool is executed headlessly via Flutter test to gain access to `dart:ui` for rasterizing SVGs.

From the `tool/skin_generator_tool` directory:

```bash
flutter test test/generate_test.dart
```

This will automatically loop through the themes (`light`, `dark`) and resolutions (`mdpi`, `hdpi`, `xhdpi`, `xxhdpi`, `xxxhdpi`, `6plus`) inside `thirdparty/comaps/data/styles` and output the packed textures to `thirdparty/comaps/data/symbols`.

## Dependencies
- **Flutter SDK**
- **OptiPNG (Optional)**: Automatically used if installed to compress the final PNGs.
  - Windows: `winget install -e --id=OptiPNG.OptiPNG`
  - macOS: `brew install optipng`
  - Linux: `sudo apt install optipng`
