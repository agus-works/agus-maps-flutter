# Swift Package Manager Support

## Status

Fixed for the `agus_maps_flutter` plugin code that this repository controls.

External Flutter plugins were not migrated. The remaining iOS SwiftPM warning is
for `storage_space`, which should be handled by that plugin's author.

## Findings

- GitHub Actions logs under `logs_70492780719` and the local
  `output.build-all.log` repeatedly reported:
  `Plugin agus_maps_flutter does not have Swift Package Manager support for ios`
  and the same warning for `macos`.
- Flutter's toolchain expects plugin Swift packages at:
  - `ios/<plugin_name>/Package.swift`
  - `macos/<plugin_name>/Package.swift`
- The Flutter example-app validation also checks that those manifests mention
  `FlutterFramework`.
- Our Apple source lived in `ios/Classes` and `macos/Classes`, which is
  compatible with CocoaPods but not enough for SwiftPM. SwiftPM requires build
  target sources and headers to be inside the package root.
- SwiftPM also cannot compile mixed Swift and Objective-C++ sources in a single
  target, so the plugin needed separate Swift and native targets.
- After adding manifests, iOS surfaced two additional SwiftPM-only issues:
  - Xcode local package override identity uses the normalized package identity
    `agus-maps-flutter`, while the Flutter plugin path remains
    `agus_maps_flutter`.
  - The example Runner target still declared iOS 13.0 while the plugin and
    podspec already require iOS 15.6.

Reference: Flutter's plugin-author SwiftPM guidance:
https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-plugin-authors

## Plan

1. Add SwiftPM manifests only for `agus_maps_flutter` on iOS and macOS.
2. Keep CocoaPods support intact for external plugins and for any consumer path
   that still uses pods.
3. Move plugin-owned Apple native sources into a SwiftPM-compatible nested
   source layout.
4. Split Apple native code into:
   - `agus_maps_flutter`: Swift plugin/Pigeon target.
   - `agus_maps_flutter_native`: Objective-C++/C header target.
5. Wire SwiftPM binary targets to the existing CoMaps and DuckDB XCFrameworks.
6. Validate with targeted Android, iOS simulator, and macOS builds.

## Steps Taken

- Added `ios/agus_maps_flutter/Package.swift`.
- Added `macos/agus_maps_flutter/Package.swift`.
- Moved iOS and macOS Apple sources from `Classes/` into:
  - `Sources/agus_maps_flutter`
  - `Sources/agus_maps_flutter_native`
- Moved the C-compatible bridge header into the native target's public include
  tree so SwiftPM can expose it to Swift.
- Added `#if SWIFT_PACKAGE` imports from the Swift plugin files to the native
  SwiftPM module.
- Added package-local symlinks for repository-owned inputs that SwiftPM needs
  inside the package root:
  - `Frameworks`
  - `SharedSrc`
  - `Headers`
  - `ThirdParty/comaps`
  - `ThirdParty/duckdb_include`
- Added hyphenated local override symlinks:
  - `ios/agus-maps-flutter`
  - `macos/agus-maps-flutter`
- Updated the example Xcode projects to use those hyphenated override paths.
- Updated the iOS Runner deployment target from 13.0 to 15.6 to match the
  plugin's existing iOS minimum.
- Removed the stale iOS C wrapper that referenced the non-existent
  `src/agus_maps_flutter.c`; the Apple implementation is in
  `agus_maps_flutter_ios.mm`.
- Updated the podspec source/header paths to the new source layout.
- Updated local and GitHub shader-copy steps so SwiftPM resource directories
  receive `shaders_metal.metallib`.
- Updated the Dart FFI loader to use `DynamicLibrary.process()` on macOS as
  well as iOS, because SwiftPM links the plugin symbols into the app image
  instead of producing `agus_maps_flutter.framework`.
- Updated the existing CoMaps patch
  `patches/comaps/0017-libs-shaders-metal_program_pool-mm.patch` so Metal
  shader lookup also searches SwiftPM app resource bundles.
- Hardened the local Dart build hook so Metal shader compilation failures stop
  the build instead of producing an app that builds but cannot render.

## Runtime Follow-up

The macOS debug run log at `output.debug-macos.log` showed that the app built
and launched, then failed during `initWithPaths()` with:

```text
Failed to load dynamic library 'agus_maps_flutter.framework/agus_maps_flutter'
```

The app bundle did not contain `Contents/Frameworks/agus_maps_flutter.framework`.
That is expected for the current SwiftPM integration: the plugin is linked into
the application image instead of embedded as a separate framework. The exported
FFI symbols were present in the debug app image, including:

- `_comaps_init_paths`
- `_comaps_load_map_path`
- `_agus_native_set_surface`
- `_agus_render_frame`

The fix was to resolve Apple-platform FFI symbols from the current process.
iOS already used `DynamicLibrary.process()`, and macOS now uses the same path.

After that fix, the macOS app reached native map initialization and exposed a
second runtime issue:

```text
shaders_metal.metallib not found in any bundle!
```

The local `output.build-all.log` showed why the asset was missing:

```text
Warning: No Metal shaders compiled successfully
```

On this Mac, `xcrun metal` failed because Xcode's optional Metal Toolchain was
not installed. The toolchain state was:

```text
xcodebuild -showComponent MetalToolchain -json
status: uninstalled
```

The component was installed with:

```shell
xcodebuild -downloadComponent MetalToolchain
```

After installation, `xcrun metal` compiled the shader sources successfully. The
build hook now treats this as a required step and suggests the Metal Toolchain
command if Xcode reports that compiler component missing.

SwiftPM then bundled the shader library at:

```text
example/build/macos/Build/Products/Debug/agus_maps_flutter_example.app/Contents/Resources/agus_maps_flutter_agus_maps_flutter.bundle/Contents/Resources/shaders_metal.metallib
```

The CoMaps Metal shader lookup patch now searches app resource bundles, so it
finds the SwiftPM resource bundle as well as the older CocoaPods framework
resource layouts.

## Validation

Commands run from the repository root:

- `flutter pub get`
  - No remaining SwiftPM warning for `agus_maps_flutter`.
  - Remaining warning is for external plugin `storage_space` on iOS.
- `dart run melos exec --scope=agus_maps_flutter_example -- flutter build ios --simulator --debug`
  - Passed.
  - Produced `example/build/ios/iphonesimulator/Runner.app`.
- `dart run melos exec --scope=agus_maps_flutter_example -- flutter build macos --release`
  - Passed.
  - Produced `example/build/macos/Build/Products/Release/agus_maps_flutter_example.app`.
  - Bundled `shaders_metal.metallib` in the SwiftPM resource bundle.
- `dart run melos exec --scope=agus_maps_flutter_example -- flutter build apk --release`
  - Passed.
  - Produced `example/build/app/outputs/flutter-apk/app-release.apk`.
- `AGUS_MAPS_BUILD_MODE=contributor dart run tool/build.dart --build-binaries --platform macos`
  - Passed after installing Xcode's Metal Toolchain.
  - Compiled 13 Metal shader files.
  - Produced and copied `shaders_metal.metallib` into iOS/macOS CocoaPods and
    SwiftPM resource directories.
- `dart run melos exec --scope=agus_maps_flutter_example -- flutter build macos --debug`
  - Passed.
  - Produced `example/build/macos/Build/Products/Debug/agus_maps_flutter_example.app`.
  - Bundled `shaders_metal.metallib` in the SwiftPM resource bundle.
- `cd example && perl -e 'alarm 25; exec @ARGV' build/macos/Build/Products/Debug/agus_maps_flutter_example.app/Contents/MacOS/agus_maps_flutter_example`
  - Reached `initWithPaths() complete`.
  - Reached `DrapeEngine created successfully`.
  - Found `shaders_metal.metallib` in
    `Contents/Resources/agus_maps_flutter_agus_maps_flutter.bundle`.
  - Reached `DuckDB layer rendering enabled: 20 visible features.`
  - No `agus_maps_flutter.framework` dynamic-library error remained.
  - No Metal shader assertion remained.

Artifact check:

```text
example/build/app/outputs/flutter-apk/app-release.apk
example/build/ios/iphonesimulator/Runner.app
example/build/macos/Build/Products/Release/agus_maps_flutter_example.app
```

## Remaining Work

- `storage_space` still does not support Swift Package Manager for iOS. This is
  intentionally left to the external plugin author.
- Flutter reports that the macOS example still has CocoaPods integration even
  though all macOS plugins are Swift packages. The project still builds, and a
  full CocoaPods deintegration should be handled separately because it changes
  app integration rather than this plugin's SwiftPM support.
- Android still emits Flutter's Kotlin Gradle Plugin migration warning for the
  app and external plugins. This is unrelated to SwiftPM and did not block the
  Android release build.
