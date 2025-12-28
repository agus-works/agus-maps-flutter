#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# apply_comaps_patches.sh - Apply patches to CoMaps checkout
# ============================================================================
#
# Applies optional patch files from ./patches/comaps/*.patch onto
# ./thirdparty/comaps. Patches that target non-existent files (e.g., 
# uninitialized submodules) are skipped with a warning.
#
# Patch files are part of this repo's IP. They are only used if a clean
# bridge is not possible.
#
# ============================================================================

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMAPS_DIR="$ROOT_DIR/thirdparty/comaps"
PATCH_DIR="$ROOT_DIR/patches/comaps"

# Colors for output
if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  NC='\033[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  NC=''
fi

log_info() { echo -e "${GREEN}[apply_comaps_patches]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[apply_comaps_patches]${NC} $1"; }
log_error() { echo -e "${RED}[apply_comaps_patches]${NC} $1"; }

if [[ ! -d "$COMAPS_DIR/.git" ]]; then
  log_error "missing CoMaps checkout at $COMAPS_DIR"
  log_error "run: ./scripts/fetch_comaps.sh"
  exit 1
fi

shopt -s nullglob
PATCHES=("$PATCH_DIR"/*.patch)

if [[ ${#PATCHES[@]} -eq 0 ]]; then
  log_info "no patches found in $PATCH_DIR; skipping"
  exit 0
fi

pushd "$COMAPS_DIR" >/dev/null

# Reset any existing modifications before applying patches
# This ensures a clean slate when re-running the script
log_info "resetting working tree to HEAD..."
git reset HEAD -- . >/dev/null 2>&1 || true
git checkout -- .
git clean -fd

# Reset submodules as well
git submodule foreach --recursive 'git checkout -- . 2>/dev/null || true' 2>/dev/null || true
git submodule foreach --recursive 'git clean -fd 2>/dev/null || true' 2>/dev/null || true

applied=0
skipped=0
failed=0

for patch in "${PATCHES[@]}"; do
  patch_name="$(basename "$patch")"
  
  # Extract the target file from the patch to check if it exists
  target_file=$(grep -m1 "^diff --git" "$patch" | sed 's|diff --git a/||; s| b/.*||' || true)
  
  # Check if target file exists (skip patches for uninitialized submodules)
  if [[ -n "$target_file" ]] && [[ ! -e "$target_file" ]]; then
    log_warn "skipping $patch_name (target '$target_file' does not exist)"
    ((skipped++))
    continue
  fi
  
  log_info "applying $patch_name"
  
  # Try direct apply first (fastest, works when blob hashes match)
  if git apply --whitespace=nowarn "$patch" 2>/dev/null; then
    echo "Applied patch to '$target_file' cleanly."
    ((applied++))
  # Try 3-way merge as fallback (helps across tags when context is close)
  elif git apply --3way --whitespace=nowarn "$patch" 2>/dev/null; then
    echo "Applied patch to '$target_file' cleanly."
    ((applied++))
  # Check if already applied
  elif git apply --check --reverse "$patch" 2>/dev/null; then
    log_warn "already applied, skipping $patch_name"
    ((skipped++))
  else
    # Final fallback: try using patch command for submodule files
    echo "Falling back to direct application..."
    if patch -p1 --dry-run < "$patch" >/dev/null 2>&1; then
      patch -p1 < "$patch" >/dev/null 2>&1
      echo "Applied patch to '$target_file' cleanly."
      ((applied++))
    else
      log_error "failed to apply $patch_name"
      ((failed++))
    fi
  fi
done

log_info "done (applied=$applied, skipped=$skipped, failed=$failed)"

popd >/dev/null

# Return non-zero only if there were critical failures
if [[ $failed -gt 0 ]]; then
  log_warn "Some patches failed. Build may still succeed if patches were optional."
fi
