#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# bootstrap_android.sh - Bootstrap Android Development Environment
# ============================================================================
#
# This script sets up everything needed to build the Android target of
# agus_maps_flutter. It uses the shared bootstrap_common.sh for core logic.
#
# What it does:
#   1. Fetch CoMaps source code
#   2. Apply patches (superset for all platforms)
#   3. Build Boost headers
#   4. Copy CoMaps data files
#   5. Copy Android-specific assets
#
# Usage:
#   ./scripts/bootstrap_android.sh
#
# Environment variables:
#   COMAPS_TAG: git tag/commit to checkout (defaults to v2025.12.11-2)
#   SKIP_PATCHES: if set to "true", skips applying patches
#
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source common bootstrap functions
# shellcheck source=bootstrap_common.sh
source "$SCRIPT_DIR/bootstrap_common.sh"

echo "========================================="
echo "Bootstrap Android Development Environment"
echo "========================================="
echo ""

# Run full bootstrap targeting Android
bootstrap_full "android"

echo ""
echo "Next steps:"
echo "  1. Run the example app:"
echo "     cd example && flutter run"
echo ""
echo "  2. Or build Android binaries:"
echo "     ./scripts/build_binaries_android.sh"
echo ""
