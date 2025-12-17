#!/usr/bin/env bash
set -euo pipefail

# Bootstrap Android dependencies.
#
# What it does:
# - Ensures ./thirdparty/comaps is present at COMAPS_TAG (defaults to v2025.12.11-2)
# - Applies optional patch files from ./patches/comaps
#
# Environment variables:
#   COMAPS_TAG: git tag/commit to checkout (defaults to v2025.12.11-2)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT_DIR/scripts/fetch_comaps.sh"
"$ROOT_DIR/scripts/apply_comaps_patches.sh"

echo "[bootstrap_android] preparing boost headers"
pushd "$ROOT_DIR/thirdparty/comaps/3party/boost" >/dev/null
if [[ ! -d "boost" ]]; then
  ./bootstrap.sh
  ./b2 headers
fi
popd >/dev/null

echo "[bootstrap_android] copying assets (fonts)"
mkdir -p "$ROOT_DIR/example/android/app/src/main/assets"
cp -r "$ROOT_DIR/thirdparty/comaps/data/fonts" "$ROOT_DIR/example/android/app/src/main/assets/"

echo "[bootstrap_android] done"
