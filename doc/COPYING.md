# Copying the Project Directory

When copying the `agus-maps-flutter` directory, you may encounter errors due to:

1. **Cyclic symlinks** — Flutter creates symlinks in the example app that point back to the parent plugin
2. **Broken symlinks** — The `thirdparty/comaps` submodule contains symlinks to files not present in the clone (e.g., `.mwm` map data, release notes)

## Cyclic Symlinks

These Flutter-generated symlinks cause "directory causes a cycle" errors:

```
example/macos/Flutter/ephemeral/.symlinks/plugins/agus_maps_flutter
example/ios/.symlinks/plugins/agus_maps_flutter
example/linux/flutter/ephemeral/.plugin_symlinks/agus_maps_flutter
example/windows/flutter/ephemeral/.plugin_symlinks/agus_maps_flutter
```

## Broken Symlinks

The `thirdparty/comaps` directory contains symlinks pointing to files that don't exist:

- `android/app/src/*/assets/World.mwm` → `../../../../../data/World.mwm` (not fetched)
- `android/app/src/*/assets/WorldCoasts.mwm` → similar
- Various `release-notes/*/default.txt` files

These are expected — large map data files are not checked into git.

---

## Solutions

### macOS / Linux

Use `rsync` to copy the project:

```bash
# Preserve symlinks as-is (recommended)
rsync -a agus-maps-flutter/ agus1/

# Or exclude the cyclic plugin symlinks entirely
rsync -a \
  --exclude='.symlinks' \
  --exclude='.plugin_symlinks' \
  agus-maps-flutter/ agus1/

# Or convert symlinks to actual files (will fail on broken symlinks)
rsync -a --copy-links \
  --exclude='.symlinks' \
  --exclude='.plugin_symlinks' \
  agus-maps-flutter/ agus1/
```

### Windows (PowerShell)

Use `robocopy` which handles symlinks gracefully:

```powershell
# Copy directory, preserving symlinks as junctions/symlinks
robocopy agus-maps-flutter agus1 /E /SL /XJ

# Options:
#   /E   - Copy subdirectories, including empty ones
#   /SL  - Copy symbolic links as links (not as files)
#   /XJ  - Exclude junction points (avoids cycles)
```

Or exclude the problematic directories explicitly:

```powershell
robocopy agus-maps-flutter agus1 /E /SL `
  /XD ".symlinks" ".plugin_symlinks"
```

### Windows (Git Bash / MSYS2)

If you have Git Bash or MSYS2 installed, `rsync` is available:

```bash
rsync -a agus-maps-flutter/ agus1/
```

### Windows (WSL)

From Windows Subsystem for Linux:

```bash
rsync -a /mnt/c/path/to/agus-maps-flutter/ /mnt/c/path/to/agus1/
```

---

## Notes

- The broken symlinks in `thirdparty/comaps` are intentional — map data (`.mwm` files) must be downloaded separately
- After copying, run `flutter pub get` in the example directory to regenerate the plugin symlinks
- Consider using `git clone` instead of copying if you need a fresh working copy
