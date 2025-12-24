#!/usr/bin/env bash
set -euo pipefail

# Bootstrap script for macOS development
#
# This script sets up everything needed to build and run the agus_maps_flutter
# plugin on macOS.
#
# Steps:
#   1. Fetch CoMaps source code
#   2. Apply patches
#   3. Build Boost headers
#   4. Build or download XCFramework
#   5. Copy Metal shaders
#   6. Copy CoMaps data files
#
# Usage:
#   ./scripts/bootstrap_macos.sh [--build-xcframework]
#
# Options:
#   --build-xcframework    Build XCFramework from source (slow, ~30 min)
#                          Without this flag, downloads pre-built binaries

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS_DIR="$ROOT_DIR/scripts"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

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

# Step 1: Fetch CoMaps source
fetch_comaps() {
    log_info "Step 1: Fetching CoMaps source..."
    
    if [[ -x "$SCRIPTS_DIR/fetch_comaps.sh" ]]; then
        "$SCRIPTS_DIR/fetch_comaps.sh"
    else
        log_error "fetch_comaps.sh not found or not executable"
        exit 1
    fi
}

# Step 2: Apply patches
apply_patches() {
    log_info "Step 2: Applying CoMaps patches..."
    
    if [[ -x "$SCRIPTS_DIR/apply_comaps_patches.sh" ]]; then
        "$SCRIPTS_DIR/apply_comaps_patches.sh"
    else
        log_warn "apply_comaps_patches.sh not found, skipping patches"
    fi
}

# Step 3: Build Boost headers
build_boost() {
    log_info "Step 3: Building Boost headers..."
    
    local boost_dir="$ROOT_DIR/thirdparty/comaps/3party/boost"
    
    if [[ -f "$boost_dir/boost/config.hpp" ]]; then
        log_info "Boost headers already built"
        return
    fi
    
    if [[ -d "$boost_dir" ]]; then
        cd "$boost_dir"
        if [[ -x "./bootstrap.sh" ]]; then
            ./bootstrap.sh
            ./b2 headers
        else
            log_warn "Boost bootstrap.sh not found"
        fi
        cd "$ROOT_DIR"
    else
        log_warn "Boost directory not found at $boost_dir"
    fi
}

# Step 4: Get XCFramework (build or download)
get_xcframework() {
    log_info "Step 4: Getting CoMaps XCFramework..."
    
    local xcframework_path="$ROOT_DIR/macos/Frameworks/CoMaps.xcframework"
    
    if [[ -d "$xcframework_path" ]]; then
        log_info "XCFramework already exists at $xcframework_path"
        return
    fi
    
    if [[ "$BUILD_XCFRAMEWORK" == true ]]; then
        log_info "Building XCFramework from source (this may take ~30 minutes)..."
        
        if [[ -x "$SCRIPTS_DIR/build_binaries_macos.sh" ]]; then
            "$SCRIPTS_DIR/build_binaries_macos.sh"
            
            # Copy to macos/Frameworks
            mkdir -p "$ROOT_DIR/macos/Frameworks"
            cp -R "$ROOT_DIR/build/agus-binaries-macos/CoMaps.xcframework" "$ROOT_DIR/macos/Frameworks/"
        else
            log_error "build_binaries_macos.sh not found"
            exit 1
        fi
    else
        log_info "Downloading pre-built XCFramework..."
        
        if [[ -x "$SCRIPTS_DIR/download_libs.sh" ]]; then
            "$SCRIPTS_DIR/download_libs.sh" macos
        else
            log_warn "download_libs.sh not found, falling back to building from source"
            BUILD_XCFRAMEWORK=true
            get_xcframework
        fi
    fi
}

# Step 5: Copy Metal shaders
copy_shaders() {
    log_info "Step 5: Copying Metal shaders..."
    
    local macos_shaders="$ROOT_DIR/macos/Resources/shaders_metal.metallib"
    
    if [[ -f "$macos_shaders" ]]; then
        log_info "Metal shaders already exist"
        return
    fi
    
    mkdir -p "$ROOT_DIR/macos/Resources"
    
    # Try to copy from iOS (shared shaders)
    local ios_shaders="$ROOT_DIR/ios/Resources/shaders_metal.metallib"
    if [[ -f "$ios_shaders" ]]; then
        cp "$ios_shaders" "$macos_shaders"
        log_info "Copied Metal shaders from iOS"
        return
    fi
    
    # Try to copy from build output
    local build_shaders="$ROOT_DIR/build/metal_shaders/shaders_metal.metallib"
    if [[ -f "$build_shaders" ]]; then
        cp "$build_shaders" "$macos_shaders"
        log_info "Copied Metal shaders from build"
        return
    fi
    
    log_warn "Metal shaders not found. Run iOS bootstrap first or build shaders manually."
}

# Step 6: Copy CoMaps data files
copy_data_files() {
    log_info "Step 6: Copying CoMaps data files..."
    
    if [[ -x "$SCRIPTS_DIR/copy_comaps_data.sh" ]]; then
        "$SCRIPTS_DIR/copy_comaps_data.sh"
    else
        log_warn "copy_comaps_data.sh not found"
    fi
}

# Main
main() {
    log_info "========================================="
    log_info "Bootstrap macOS Development Environment"
    log_info "========================================="
    
    cd "$ROOT_DIR"
    
    fetch_comaps
    apply_patches
    build_boost
    get_xcframework
    copy_shaders
    copy_data_files
    
    log_info "========================================="
    log_info "Bootstrap complete!"
    log_info "========================================="
    log_info ""
    log_info "Next steps:"
    log_info "  1. cd example/macos && pod install"
    log_info "  2. cd .. && flutter run -d macos"
}

main "$@"
