# Surgical Patching Guide

This document describes techniques for creating, debugging, and fixing patch files used in the CoMaps patching mechanism. The techniques are generic and applicable to any unified diff patching workflow.

## Table of Contents

1. [Patch File Anatomy](#patch-file-anatomy)
2. [Common Patch Failures](#common-patch-failures)
3. [Isolation Testing](#isolation-testing)
4. [Surgical Fix Techniques](#surgical-fix-techniques)
5. [Patch Generation Best Practices](#patch-generation-best-practices)

---

## Patch File Anatomy

A unified diff patch consists of:

```diff
diff --git a/path/to/file.cpp b/path/to/file.cpp
index abc1234..def5678 100644
--- a/path/to/file.cpp
+++ b/path/to/file.cpp
@@ -10,6 +10,8 @@ optional_function_context()
 context line (unchanged)
 context line (unchanged)
+added line
+another added line
 context line (unchanged)
 
 context line after blank
```

### Critical Format Rules

| Element | Rule |
|---------|------|
| Context lines | MUST start with a single space character |
| Added lines | MUST start with `+` |
| Removed lines | MUST start with `-` |
| Blank lines in hunks | MUST start with a space (` `), not be truly empty |
| Line endings | Should be LF (`\n`), not CRLF (`\r\n`) |
| File encoding | UTF-8 without BOM |

### Hunk Header Format

```
@@ -OLD_START,OLD_COUNT +NEW_START,NEW_COUNT @@ optional_context
```

- `OLD_START`: Line number in the original file where the hunk begins
- `OLD_COUNT`: Number of lines from the original file in this hunk
- `NEW_START`: Line number in the new file where the hunk begins
- `NEW_COUNT`: Number of lines in the new file for this hunk

---

## Common Patch Failures

### Error: "corrupt patch at line N"

**Causes:**
1. Blank line in hunk missing leading space character
2. UTF-8 BOM at file start
3. Mixed or incorrect line endings
4. Malformed hunk header

**Diagnosis:**
```powershell
# Check line N and surrounding lines for formatting issues
Get-Content "patch.patch" | Select-Object -Skip (N-3) -First 6

# Check for BOM
[byte[]](Get-Content "patch.patch" -Encoding Byte -TotalCount 3)
# BOM present if output is: 239 187 191 (UTF-8 BOM)

# Check line endings
(Get-Content "patch.patch" -Raw) -match "`r`n"  # True = CRLF present
```

### Error: "patch does not apply"

**Causes:**
1. Context lines don't match the target file
2. Line numbers in hunk header are incorrect
3. Target file has been modified since patch was created

**Diagnosis:**
```powershell
# Find the actual line numbers in target file
Select-String -Path "target.cpp" -Pattern "unique_context_string"

# Compare context with target file
$hunkStart = 1760  # From hunk header
Get-Content "target.cpp" | Select-Object -Skip ($hunkStart - 1) -First 10
```

### Error: "patch fragment without header"

**Cause:** Missing or malformed `@@` hunk header line.

---

## Isolation Testing

**CRITICAL:** Always test patches in isolation before running full builds.

### Single Patch Test

```powershell
# Navigate to repository
Set-Location "path/to/thirdparty/comaps"

# Reset to clean state
git reset --hard HEAD
git clean -fd
git submodule foreach --recursive "git checkout -- .; git clean -fd"

# Apply single patch
git apply --whitespace=nowarn "path/to/patches/0043-example.patch"
```

### Verbose Testing

```powershell
# Dry-run with verbose output
git apply --check -v "path/to/patch.patch"

# Show what would be applied
git apply --stat "path/to/patch.patch"
```

### Test with Context Adjustment

```powershell
# Allow fuzzy matching (use sparingly)
git apply -C1 "path/to/patch.patch"  # Reduce context requirements
```

---

## Surgical Fix Techniques

### Technique 1: Let Git Generate the Patch

**When to use:** Patch is severely corrupted or manual fixes are failing.

**Procedure:**

```powershell
# 1. Reset to clean state
cd "thirdparty/comaps"
git reset --hard HEAD

# 2. Make the intended changes directly to the file
$file = "libs/drape_frontend/frontend_renderer.cpp"
$content = Get-Content $file -Raw

# Example: Add include after first line
$content = $content -replace `
    '(#include "drape_frontend/frontend_renderer.hpp")', `
    "`$1`n#include `"drape_frontend/active_frame_callback.hpp`""

Set-Content $file -Value $content -NoNewline

# 3. Generate patch from git diff
git diff > "path/to/patches/0043-fixed.patch"

# 4. Reset and verify
git reset --hard HEAD
git apply --whitespace=nowarn "path/to/patches/0043-fixed.patch"
```

### Technique 2: Fix Blank Line Formatting

**When to use:** "corrupt patch" error pointing to a blank line in the hunk.

**Problem:** Unified diff requires blank lines within hunks to have a leading space.

```diff
# WRONG (empty line)
   }

   bool const canSuspend

# CORRECT (space before blank line)
   }
 
   bool const canSuspend
```

**Fix:**
```powershell
# Read patch, fix blank lines, write with Unix line endings
$content = Get-Content "patch.patch" -Raw
# Ensure blank lines in hunks have leading space
$content = $content -replace "(`n)(`n[^-+ @])", "`$1 `$2"
[System.IO.File]::WriteAllText("patch.patch", $content.Replace("`r`n", "`n"))
```

### Technique 3: Adjust Hunk Line Numbers

**When to use:** "patch does not apply" due to line number mismatch.

**Procedure:**

```powershell
# 1. Find actual line number in target file
$pattern = "m_frameData.m_inactiveFramesCounter = 0"
Select-String -Path "target.cpp" -Pattern $pattern

# 2. Calculate offset and update hunk header
# If pattern is at line 1762 but patch says 1758, offset is +4
```

**Manual edit:** Change `@@ -1758,7 +1758,9 @@` to `@@ -1762,7 +1762,9 @@`

### Technique 4: Reduce Context for Resilience

**When to use:** Context lines have minor whitespace differences.

Reduce context from 3 lines (default) to 1-2 lines:

```powershell
# Generate patch with minimal context
git diff -U1 > "patch-minimal-context.patch"
```

### Technique 5: Binary-Safe File Writing

**When to use:** Encoding issues persist despite text-based fixes.

```powershell
$lines = @(
    "diff --git a/file.cpp b/file.cpp",
    "--- a/file.cpp",
    "+++ b/file.cpp",
    "@@ -1,3 +1,4 @@",
    " #include `"header.hpp`"",
    "+#include `"new_header.hpp`"",
    " #include `"other.hpp`"",
    " "  # Blank line with space
)
$content = ($lines -join "`n") + "`n"
[System.IO.File]::WriteAllText("patch.patch", $content)
```

---

## Patch Generation Best Practices

### DO

1. **Let git generate patches** whenever possible
2. **Test in isolation** before committing patch changes
3. **Use meaningful patch names** with numeric prefixes for ordering
4. **Document patch purpose** in README.md
5. **Keep patches minimal** - one logical change per patch

### DON'T

1. **Don't manually edit patches** unless absolutely necessary
2. **Don't use text editors** that auto-convert line endings
3. **Don't add UTF-8 BOM** when saving patch files
4. **Don't combine unrelated changes** in a single patch
5. **Don't forget to update README.md** when adding/removing patches
6. **NEVER create multiple patches for the same file** - if two patches modify the same file, merge them into one. Multiple patches for the same file cause context mismatches because patch N+1 expects the original file, not the post-patch-N state.

### Patch Naming Convention

```
NNNN-path-to-file-description.patch
```

Examples:
- `0012-libs-drape_frontend-active_frame_callback.patch`
- `0043-libs-drape_frontend-frontend_renderer-cpp.patch`
- `0059-libs-platform-flutter-plugin-support.patch`

---

## Troubleshooting Checklist

When a patch fails, work through this checklist:

- [ ] Run isolation test to confirm the specific patch that fails
- [ ] Check error message for line number hint
- [ ] Verify target file exists and hasn't changed upstream
- [ ] Check for BOM in patch file
- [ ] Check line endings (should be LF)
- [ ] Verify blank lines in hunks have leading space
- [ ] Confirm hunk line numbers match target file
- [ ] If all else fails, regenerate patch using git diff

---

## Quick Reference Commands

```powershell
# Full isolation test
Set-Location "thirdparty/comaps"
git reset --hard HEAD; git clean -fd
git submodule foreach --recursive "git checkout -- .; git clean -fd"
git apply --whitespace=nowarn "path/to/patch.patch"

# Check patch stats
git apply --stat "patch.patch"

# Dry-run check
git apply --check "patch.patch"

# Apply with whitespace fixes
git apply --whitespace=fix "patch.patch"

# Apply ignoring whitespace
git apply --whitespace=nowarn "patch.patch"

# Find line in target file
Select-String -Path "file.cpp" -Pattern "search_term"

# Generate patch from staged changes
git diff --cached > "new.patch"

# Generate patch from working tree
git diff > "new.patch"
```
