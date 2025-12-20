#!/usr/bin/env bash
set -euo pipefail

# Applies optional patch files from ./patches/comaps/*.patch onto ./thirdparty/comaps.
#
# Patch files are part of this repo's IP. They are only used if a clean bridge
# is not possible.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMAPS_DIR="$ROOT_DIR/thirdparty/comaps"
PATCH_DIR="$ROOT_DIR/patches/comaps"

if [[ ! -d "$COMAPS_DIR/.git" ]]; then
  echo "[apply_comaps_patches] missing CoMaps checkout at $COMAPS_DIR"
  echo "[apply_comaps_patches] run: ./scripts/fetch_comaps.sh"
  exit 1
fi

shopt -s nullglob
PATCHES=("$PATCH_DIR"/*.patch)

if [[ ${#PATCHES[@]} -eq 0 ]]; then
  echo "[apply_comaps_patches] no patches found in $PATCH_DIR; skipping"
  exit 0
fi

pushd "$COMAPS_DIR" >/dev/null

# Reset any existing modifications before applying patches
# This ensures a clean slate when re-running the script
echo "[apply_comaps_patches] resetting working tree to HEAD..."
git reset HEAD -- . >/dev/null 2>&1 || true
git checkout -- .
git clean -fd

for patch in "${PATCHES[@]}"; do
  echo "[apply_comaps_patches] applying $(basename "$patch")"
  # --3way helps across tags when context is close; fail loudly if it can't apply.
  git apply --3way --whitespace=nowarn "$patch"
done

echo "[apply_comaps_patches] done"

popd >/dev/null
