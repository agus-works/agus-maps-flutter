#!/usr/bin/env bash
set -euo pipefail

# Fetches CoMaps into ./thirdparty/comaps.
#
# Environment variables:
#   COMAPS_TAG: git tag/commit to checkout.
#              Defaults to v2025.12.11-2.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THIRDPARTY_DIR="$ROOT_DIR/thirdparty"
COMAPS_DIR="$THIRDPARTY_DIR/comaps"

COMAPS_REPO="git@github.com:comaps/comaps.git"
COMAPS_TAG_DEFAULT="v2025.12.11-2"
COMAPS_TAG="${COMAPS_TAG:-$COMAPS_TAG_DEFAULT}"

mkdir -p "$THIRDPARTY_DIR"

if [[ ! -d "$COMAPS_DIR/.git" ]]; then
  echo "[fetch_comaps] cloning $COMAPS_REPO -> $COMAPS_DIR"
  git clone "$COMAPS_REPO" "$COMAPS_DIR"
else
  echo "[fetch_comaps] updating existing checkout: $COMAPS_DIR"
fi

pushd "$COMAPS_DIR" >/dev/null

git fetch --tags --prune

echo "[fetch_comaps] checking out COMAPS_TAG=$COMAPS_TAG (default=$COMAPS_TAG_DEFAULT)"
# Use detached HEAD so switching tags is explicit and clean.
git checkout --detach "$COMAPS_TAG"

echo "[fetch_comaps] updating submodules (recursive)"
git submodule update --init --recursive

echo "[fetch_comaps] at $(git rev-parse --short HEAD) ($(git describe --tags --always --dirty))"

popd >/dev/null
