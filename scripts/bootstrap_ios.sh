#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# bootstrap_ios.sh - Bootstrap iOS Development Environment
# ============================================================================
#
# This script sets up everything needed to build the iOS target of
# agus_maps_flutter. It uses the shared bootstrap_common.sh for core logic.
#
# What it does:
#   1. Fetch CoMaps source code (or restore from cache)
#   2. Create cache archive after fresh clone (before patches)
#   3. Apply patches (superset for all platforms)
#   4. Build Boost headers
#   5. Copy CoMaps data files
#   6. Download or build CoMaps XCFramework
#
# Usage:
#   ./scripts/bootstrap_ios.sh [--build-xcframework] [--no-cache]
#
# Options:
#   --build-xcframework    Build XCFramework from source (slow, ~30 min)
#                          Without this flag, downloads pre-built binaries
#   --no-cache             Disable cache - don't use or create .thirdparty.tar.bz2
#
# Environment variables:
#   COMAPS_TAG: git tag/commit to checkout (defaults to v2025.12.11-2)
#   BUILD_XCFRAMEWORK: if "true", builds XCFramework locally instead of downloading
#   NO_CACHE: if set to "true", disables caching (same as --no-cache)
#
# Cache mechanism:
#   - After fresh clone, thirdparty is compressed to .thirdparty.tar.bz2
#   - If thirdparty is deleted and cache exists, it will be extracted
#   - This skips network calls and speeds up subsequent bootstraps
#
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source common bootstrap functions
# shellcheck source=bootstrap_common.sh
source "$SCRIPT_DIR/bootstrap_common.sh"

# Parse arguments
BUILD_XCFRAMEWORK="${BUILD_XCFRAMEWORK:-false}"
NO_CACHE=false
for arg in "$@"; do
    case $arg in
        --build-xcframework)
            BUILD_XCFRAMEWORK=true
            shift
            ;;
        --no-cache)
            NO_CACHE=true
            export NO_CACHE
            shift
            ;;
    esac
done

echo "========================================="
echo "Bootstrap iOS Development Environment"
echo "========================================="
echo ""

# Run common bootstrap (fetch, patch, boost, data)
bootstrap_full "ios"

# iOS-specific: Get XCFramework
log_header "Getting iOS XCFramework"

XCFRAMEWORK_PATH="$ROOT_DIR/ios/Frameworks/CoMaps.xcframework"

if [[ -d "$XCFRAMEWORK_PATH" ]]; then
    log_info "XCFramework already exists at $XCFRAMEWORK_PATH"
elif [[ "$BUILD_XCFRAMEWORK" == "true" ]]; then
    log_info "Building XCFramework from source (this may take ~30 minutes)..."
    if [[ -x "$SCRIPT_DIR/build_ios_xcframework.sh" ]]; then
        "$SCRIPT_DIR/build_ios_xcframework.sh"
    else
        log_error "build_ios_xcframework.sh not found"
        exit 1
    fi
else
    log_info "Downloading pre-built XCFramework..."
    if [[ -x "$SCRIPT_DIR/download_ios_xcframework.sh" ]]; then
        "$SCRIPT_DIR/download_ios_xcframework.sh" || {
            log_warn "Download failed, building locally..."
            if [[ -x "$SCRIPT_DIR/build_ios_xcframework.sh" ]]; then
                "$SCRIPT_DIR/build_ios_xcframework.sh"
            else
                log_error "Neither download nor build available"
                exit 1
            fi
        }
    elif [[ -x "$SCRIPT_DIR/download_libs.sh" ]]; then
        "$SCRIPT_DIR/download_libs.sh" ios || {
            log_warn "Download failed"
        }
    else
        log_warn "No download script available, you may need to build manually"
    fi
fi

echo ""
echo "========================================="
echo "iOS Bootstrap Complete!"
echo "========================================="
echo ""
echo "Next steps:"
echo "  cd example/ios && pod install"
echo "  cd .. && flutter run -d 'iPhone 15 Pro'"
echo ""
