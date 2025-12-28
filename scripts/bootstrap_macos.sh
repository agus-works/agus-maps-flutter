#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# bootstrap_macos.sh - Bootstrap macOS Development Environment
# ============================================================================
#
# This script sets up everything needed to build and run the agus_maps_flutter
# plugin on macOS. It uses the shared bootstrap_common.sh for core logic.
#
# What it does:
#   1. Fetch CoMaps source code
#   2. Apply patches (superset for all platforms)
#   3. Build Boost headers
#   4. Copy CoMaps data files
#   5. Build or download XCFramework
#   6. Copy Metal shaders
#
# Usage:
#   ./scripts/bootstrap_macos.sh [--build-xcframework]
#
# Options:
#   --build-xcframework    Build XCFramework from source (slow, ~30 min)
#                          Without this flag, downloads pre-built binaries
#
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source common bootstrap functions
# shellcheck source=bootstrap_common.sh
source "$SCRIPT_DIR/bootstrap_common.sh"

# Parse arguments
BUILD_XCFRAMEWORK=false
for arg in "$@"; do
    case $arg in
        --build-xcframework)
            BUILD_XCFRAMEWORK=true
            shift
            ;;
    esac
done

echo "========================================="
echo "Bootstrap macOS Development Environment"
echo "========================================="
echo ""

# Run common bootstrap (fetch, patch, boost, data)
bootstrap_full "macos"

# macOS-specific: Get XCFramework
log_header "Getting macOS XCFramework"

XCFRAMEWORK_PATH="$ROOT_DIR/macos/Frameworks/CoMaps.xcframework"

if [[ -d "$XCFRAMEWORK_PATH" ]]; then
    log_info "XCFramework already exists at $XCFRAMEWORK_PATH"
elif [[ "$BUILD_XCFRAMEWORK" == true ]]; then
    log_info "Building XCFramework from source (this may take ~30 minutes)..."
    
    if [[ -x "$SCRIPT_DIR/build_binaries_macos.sh" ]]; then
        "$SCRIPT_DIR/build_binaries_macos.sh"
        
        # Copy to macos/Frameworks
        mkdir -p "$ROOT_DIR/macos/Frameworks"
        if [[ -d "$ROOT_DIR/build/agus-binaries-macos/CoMaps.xcframework" ]]; then
            cp -R "$ROOT_DIR/build/agus-binaries-macos/CoMaps.xcframework" "$ROOT_DIR/macos/Frameworks/"
        fi
    else
        log_error "build_binaries_macos.sh not found"
        exit 1
    fi
else
    log_info "Downloading pre-built XCFramework..."
    
    if [[ -x "$SCRIPT_DIR/download_libs.sh" ]]; then
        "$SCRIPT_DIR/download_libs.sh" macos || {
            log_warn "Download failed, falling back to building from source"
            BUILD_XCFRAMEWORK=true
            if [[ -x "$SCRIPT_DIR/build_binaries_macos.sh" ]]; then
                "$SCRIPT_DIR/build_binaries_macos.sh"
            fi
        }
    else
        log_warn "download_libs.sh not found, falling back to building from source"
        if [[ -x "$SCRIPT_DIR/build_binaries_macos.sh" ]]; then
            "$SCRIPT_DIR/build_binaries_macos.sh"
        fi
    fi
fi

# macOS-specific: Copy Metal shaders
log_header "Copying Metal Shaders"

MACOS_SHADERS="$ROOT_DIR/macos/Resources/shaders_metal.metallib"

if [[ -f "$MACOS_SHADERS" ]]; then
    log_info "Metal shaders already exist"
else
    mkdir -p "$ROOT_DIR/macos/Resources"
    
    # Try to copy from iOS (shared shaders)
    IOS_SHADERS="$ROOT_DIR/ios/Resources/shaders_metal.metallib"
    if [[ -f "$IOS_SHADERS" ]]; then
        cp "$IOS_SHADERS" "$MACOS_SHADERS"
        log_info "Copied Metal shaders from iOS"
    else
        # Try to copy from build output
        BUILD_SHADERS="$ROOT_DIR/build/metal_shaders/shaders_metal.metallib"
        if [[ -f "$BUILD_SHADERS" ]]; then
            cp "$BUILD_SHADERS" "$MACOS_SHADERS"
            log_info "Copied Metal shaders from build"
        else
            log_warn "Metal shaders not found. Run iOS bootstrap first or build shaders manually."
        fi
    fi
fi

echo ""
echo "========================================="
echo "macOS Bootstrap Complete!"
echo "========================================="
echo ""
echo "Next steps:"
echo "  1. cd example/macos && pod install"
echo "  2. cd .. && flutter run -d macos"
echo ""
