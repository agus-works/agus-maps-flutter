## 0.1.2

### Release Packaging Improvements

* **Unified binary package**: Introduced `agus-maps-binaries-vX.Y.Z.zip` containing all platform binaries, assets, and headers in a single download.
* **Simplified plugin installation**: Plugin consumers can now download one zip and extract it into the plugin root - all binaries fall into the correct locations automatically.
* **Versioned artifact filenames**: All release artifacts now include the version tag (e.g., `agus-maps-android-vX.Y.Z.apk`).
* **Streamlined release artifacts**: Removed individual platform binary zips (`agus-binaries-android.zip`, `agus-binaries-ios.zip`, etc.) from releases - they are now consolidated in the unified package.
* **Headers included**: C++ headers are now bundled in the unified package for developers who need to build from source (not required for typical plugin consumers using pre-built binaries).

### Unified Package Structure

After extracting `agus-maps-binaries-vX.Y.Z.zip` into the plugin root:

```
agus_maps_flutter/
├── android/prebuilt/{arm64-v8a,armeabi-v7a,x86_64}/
├── ios/Frameworks/CoMaps.xcframework/
├── macos/Frameworks/CoMaps.xcframework/
├── windows/prebuilt/x64/
├── linux/prebuilt/x86_64/
├── assets/comaps_data/, assets/maps/
└── headers/ (optional, for building from source)
```

### Documentation

* Updated `doc/RELEASE.md` with comprehensive installation guide for the unified binary package.
* Added notes clarifying that headers are optional for plugin consumers.

---

## 0.1.1

* CI/CD improvements for multi-platform builds.
* Azure Blob Storage caching for CoMaps source.
* Build workflow optimizations.

---

## 0.1.0

* Initial release of Agus Maps Flutter.
* Zero-copy rendering architecture.
* Offline maps support via CoMaps engine.
* Experimental support for linux, macos, windows, ios and android targets.
* This is an experimental release, do not use on production apps.