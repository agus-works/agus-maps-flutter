#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# fetch_comaps.sh - Fetches CoMaps source code
# ============================================================================
#
# Fetches CoMaps into ./thirdparty/comaps and initializes ALL submodules.
# This is critical for patches that target submodule files (e.g., gflags).
#
# Environment variables:
#   COMAPS_TAG: git tag/commit to checkout (defaults to v2025.12.11-2)
#   COMAPS_USE_HTTPS: if set to "true", uses HTTPS instead of SSH (for CI)
#
# ============================================================================

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THIRDPARTY_DIR="$ROOT_DIR/thirdparty"
COMAPS_DIR="$THIRDPARTY_DIR/comaps"

# Use HTTPS in CI environments (GitHub Actions sets CI=true)
if [[ "${COMAPS_USE_HTTPS:-}" == "true" ]] || [[ "${CI:-}" == "true" ]]; then
  COMAPS_REPO="https://github.com/comaps/comaps.git"
else
  COMAPS_REPO="git@github.com:comaps/comaps.git"
fi

COMAPS_TAG_DEFAULT="v2025.12.11-2"
COMAPS_TAG="${COMAPS_TAG:-$COMAPS_TAG_DEFAULT}"

mkdir -p "$THIRDPARTY_DIR"

if [[ ! -d "$COMAPS_DIR/.git" ]]; then
  echo "[fetch_comaps] cloning $COMAPS_REPO -> $COMAPS_DIR"
  # Clone without depth to allow full submodule initialization
  git clone "$COMAPS_REPO" "$COMAPS_DIR"
else
  echo "[fetch_comaps] updating existing checkout: $COMAPS_DIR"
fi

pushd "$COMAPS_DIR" >/dev/null

git fetch --tags --prune

echo "[fetch_comaps] checking out COMAPS_TAG=$COMAPS_TAG (default=$COMAPS_TAG_DEFAULT)"
# Use detached HEAD so switching tags is explicit and clean.
git checkout --detach "$COMAPS_TAG"

# Initialize ALL submodules recursively - required for patches like gflags
echo "[fetch_comaps] initializing submodules (recursive - this may take a while)..."
git submodule update --init --recursive

echo "[fetch_comaps] at $(git rev-parse --short HEAD) ($(git describe --tags --always --dirty))"

popd >/dev/null
