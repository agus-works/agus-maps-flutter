#!/usr/bin/env bash
set -euo pipefail

# Bootstrap iOS dependencies.
#
# What it does:
# - Ensures ./thirdparty/comaps is present at COMAPS_TAG (defaults to v2025.12.11-2)
# - Applies optional patch files from ./patches/comaps
# - Builds Boost headers
# - Downloads or builds CoMaps XCFramework
#
# Environment variables:
#   COMAPS_TAG: git tag/commit to checkout (defaults to v2025.12.11-2)
#   BUILD_XCFRAMEWORK: if "true", builds XCFramework locally instead of downloading

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Colors for output
GREEN='\033[0;32m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[bootstrap_ios]${NC} $1"; }

log_info "Starting iOS bootstrap..."

# Step 1: Fetch CoMaps source
"$ROOT_DIR/scripts/fetch_comaps.sh"

# Step 2: Apply patches
"$ROOT_DIR/scripts/apply_comaps_patches.sh"

# Step 3: Build Boost headers
log_info "Preparing boost headers..."
pushd "$ROOT_DIR/thirdparty/comaps/3party/boost" >/dev/null
if [[ ! -d "boost" ]]; then
  ./bootstrap.sh
  ./b2 headers
fi
popd >/dev/null

# Step 4: Get XCFramework
if [[ "${BUILD_XCFRAMEWORK:-}" == "true" ]]; then
  log_info "Building XCFramework locally..."
  "$ROOT_DIR/scripts/build_ios_xcframework.sh"
else
  log_info "Downloading pre-built XCFramework..."
  "$ROOT_DIR/scripts/download_ios_xcframework.sh" || {
    log_info "Download failed, building locally..."
    "$ROOT_DIR/scripts/build_ios_xcframework.sh"
  }
fi

# Step 5: Copy CoMaps data files
log_info "Copying CoMaps data files..."
chmod +x "$ROOT_DIR/scripts/copy_comaps_data.sh"
"$ROOT_DIR/scripts/copy_comaps_data.sh"

log_info "iOS bootstrap complete!"
log_info ""
log_info "Next steps:"
log_info "  cd example/ios && pod install"
log_info "  cd .. && flutter run -d 'iPhone 15 Pro'"
