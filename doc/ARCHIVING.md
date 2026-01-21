# Archiving the Project

When archiving `agus-maps-flutter`, use `tar.gz` format to preserve symbolic links correctly. This format works across all platforms and maintains relative symlinks that remain valid when extracted elsewhere.

## Why tar.gz?

| Format | Symlink Support | Cross-Platform | Recommended |
|--------|-----------------|----------------|-------------|
| `.tar.gz` | ✅ Full support | ✅ Yes | ✅ **Yes** |
| `.zip` | ⚠️ Limited | ⚠️ Varies | ❌ No |

- **tar** stores symlinks as symlinks (not as copies of files)
- **zip** has inconsistent symlink handling across tools and platforms
- Archives created on any platform can be extracted on any other platform

---

## Creating Archives

### macOS / Linux

```bash
# Archive the project (preserves symlinks)
tar -czvf agus-maps-flutter.tar.gz agus-maps-flutter/

# Archive with exclusions (optional - skip build artifacts)
tar -czvf agus-maps-flutter.tar.gz \
  --exclude='*.o' \
  --exclude='*.so' \
  --exclude='build/' \
  --exclude='.dart_tool/' \
  agus-maps-flutter/
```

### Windows (PowerShell with tar)

Windows 10/11 includes `tar` natively:

```powershell
# Archive the project
tar -czvf agus-maps-flutter.tar.gz agus-maps-flutter/

# With exclusions
tar -czvf agus-maps-flutter.tar.gz --exclude="build" --exclude=".dart_tool" agus-maps-flutter/
```

### Windows (Git Bash / MSYS2)

```bash
# Same as macOS/Linux
tar -czvf agus-maps-flutter.tar.gz agus-maps-flutter/
```

### Windows (7-Zip)

7-Zip supports tar.gz creation with symlink preservation:

```powershell
# First create .tar, then compress to .gz
7z a -ttar agus-maps-flutter.tar agus-maps-flutter/
7z a -tgzip agus-maps-flutter.tar.gz agus-maps-flutter.tar
del agus-maps-flutter.tar
```

Or use the GUI: Right-click → 7-Zip → Add to archive → Format: tar → then compress the .tar to .gz

---

## Extracting Archives

### macOS / Linux

```bash
tar -xzvf agus-maps-flutter.tar.gz
```

### Windows (PowerShell with tar)

```powershell
tar -xzvf agus-maps-flutter.tar.gz
```

### Windows (Git Bash / MSYS2)

```bash
tar -xzvf agus-maps-flutter.tar.gz
```

### Windows (7-Zip)

```powershell
7z x agus-maps-flutter.tar.gz
7z x agus-maps-flutter.tar
```

Or use the GUI: Right-click → 7-Zip → Extract Here (twice: once for .gz, once for .tar)

---

## Cross-Platform Compatibility

Archives created on any platform will extract correctly on any other platform because:

1. **Relative symlinks are preserved** — e.g., `../../../../../data/World.mwm` stays as-is
2. **Path separators are normalized** — tar handles `/` vs `\` automatically
3. **Symlinks remain symlinks** — they're not converted to file copies

### Important Notes

- **Broken symlinks are preserved** — The archive will include symlinks even if their targets don't exist (e.g., `.mwm` files). This is correct behavior.
- **Cyclic symlinks are safe** — tar stores symlinks as metadata, so cycles don't cause infinite loops during archiving.
- **Windows symlink extraction** — Requires either:
  - Administrator privileges, or
  - Developer Mode enabled (Settings → Privacy & Security → For developers → Developer Mode)
  - Without these, symlinks may be extracted as small text files containing the target path

### Enabling Developer Mode on Windows (for symlink support)

```powershell
# Check if Developer Mode is enabled
reg query "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /v AllowDevelopmentWithoutDevLicense

# Enable via Settings UI:
# Settings → Privacy & Security → For developers → Developer Mode → On
```

---

## Verifying Archive Contents

To inspect the archive without extracting:

```bash
# List contents
tar -tzvf agus-maps-flutter.tar.gz

# List only symlinks
tar -tzvf agus-maps-flutter.tar.gz | grep '^l'
```

On Windows with 7-Zip:

```powershell
7z l agus-maps-flutter.tar.gz
```

---

## Quick Reference

| Task | Command |
|------|---------|
| Create archive | `tar -czvf agus-maps-flutter.tar.gz agus-maps-flutter/` |
| Extract archive | `tar -xzvf agus-maps-flutter.tar.gz` |
| List contents | `tar -tzvf agus-maps-flutter.tar.gz` |
| List symlinks only | `tar -tzvf agus-maps-flutter.tar.gz \| grep '^l'` |
