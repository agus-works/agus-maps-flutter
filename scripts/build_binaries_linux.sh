#!/usr/bin/env bash
set -euo pipefail

# Build CoMaps native libraries for Linux (x86_64)
#
# This script compiles the CoMaps native code for Linux using CMake and Ninja.
# It produces a shared library (.so) that is used by the Flutter plugin.
#
# Prerequisites:
#   - thirdparty/comaps must exist (run fetch_comaps.sh first)
#   - CMake >= 3.22.1 must be installed
#   - Ninja build system must be installed
#   - Build dependencies: libgl-dev, libegl-dev, libgles-dev, libepoxy-dev
#
# Usage:
#   ./build_binaries_linux.sh
#
# Environment variables:
#   BUILD_TYPE: Release or Debug (default: Release)
#
# Output:
#   build/agus-binaries-linux/x86_64/libagus_maps_flutter.so
#
# The output directory structure is suitable for zipping as agus-binaries-linux.zip

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/build/agus-binaries-linux"

# Default configuration
BUILD_TYPE="${BUILD_TYPE:-Release}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# Validate prerequisites
validate_prerequisites() {
    log_step "Validating prerequisites..."
    
    # Check CoMaps source
    if [[ ! -d "$ROOT_DIR/thirdparty/comaps" ]]; then
        log_error "CoMaps source not found at: $ROOT_DIR/thirdparty/comaps"
        log_error "Run ./scripts/bootstrap.sh or fetch CoMaps first"
        exit 1
    fi
    
    # Check CMake
    if ! command -v cmake &> /dev/null; then
        log_error "CMake not found"
        log_error "Install with: sudo apt-get install cmake"
        exit 1
    fi
    CMAKE_PATH="cmake"
    log_info "CMake: $(cmake --version | head -1)"
    
    # Check Ninja
    if ! command -v ninja &> /dev/null; then
        log_error "Ninja not found"
        log_error "Install with: sudo apt-get install ninja-build"
        exit 1
    fi
    log_info "Ninja: $(ninja --version)"
    
    # Check for required development packages (informational)
    log_info "Checking for required development packages..."
    
    local missing_packages=()
    
    # Check pkg-config availability
    if ! command -v pkg-config &> /dev/null; then
        log_warn "pkg-config not found - cannot verify dependencies"
    else
        # Check essential packages via pkg-config
        pkg-config --exists gl 2>/dev/null || missing_packages+=("libgl-dev")
        pkg-config --exists egl 2>/dev/null || missing_packages+=("libegl-dev")
        pkg-config --exists epoxy 2>/dev/null || missing_packages+=("libepoxy-dev")
        pkg-config --exists gtk+-3.0 2>/dev/null || missing_packages+=("libgtk-3-dev")
    fi
    
    if [[ ${#missing_packages[@]} -gt 0 ]]; then
        log_warn "Some development packages may be missing:"
        for pkg in "${missing_packages[@]}"; do
            echo "  - $pkg"
        done
        log_warn "Install with: sudo apt-get install ${missing_packages[*]}"
        log_warn "Continuing anyway..."
    fi
    
    export CMAKE_PATH
}

# Bootstrap CoMaps dependencies (boost headers, etc)
bootstrap_comaps() {
    log_step "Bootstrapping CoMaps dependencies..."
    
    pushd "$ROOT_DIR/thirdparty/comaps/3party/boost" >/dev/null
    if [[ ! -d "boost" ]]; then
        log_info "Building boost headers..."
        ./bootstrap.sh
        ./b2 headers
    else
        log_info "Boost headers already built"
    fi
    popd >/dev/null
}

# Build for Linux x86_64
build_linux() {
    local arch="x86_64"
    local build_dir="$ROOT_DIR/build/linux-$arch"
    local arch_output_dir="$OUTPUT_DIR/$arch"
    
    log_step "Building for Linux $arch"
    
    # Clean and create build directory
    rm -rf "$build_dir"
    mkdir -p "$build_dir"
    
    # Run CMake configure
    log_info "Configuring CMake for Linux $arch..."
    "$CMAKE_PATH" \
        -B "$build_dir" \
        -S "$ROOT_DIR/src" \
        -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
        -DCMAKE_C_COMPILER=gcc \
        -DCMAKE_CXX_COMPILER=g++ \
        -G "Ninja"
    
    # Run build
    log_info "Building Linux $arch..."
    "$CMAKE_PATH" --build "$build_dir" --parallel
    
    # Copy output
    mkdir -p "$arch_output_dir"
    
    # Find and copy the shared library
    local lib_name="libagus_maps_flutter.so"
    local lib_path="$build_dir/$lib_name"
    
    if [[ -f "$lib_path" ]]; then
        cp "$lib_path" "$arch_output_dir/"
        local size
        size=$(du -h "$arch_output_dir/$lib_name" | cut -f1)
        log_info "Built: $arch_output_dir/$lib_name ($size)"
    else
        log_error "Build output not found: $lib_path"
        exit 1
    fi
}

# Create archive
create_archive() {
    log_step "Creating archive..."
    
    local archive_path="$ROOT_DIR/build/agus-binaries-linux.zip"
    
    pushd "$ROOT_DIR/build" >/dev/null
    rm -f "agus-binaries-linux.zip"
    zip -r "agus-binaries-linux.zip" "agus-binaries-linux"
    popd >/dev/null
    
    local size
    size=$(du -h "$archive_path" | cut -f1)
    log_info "Archive created: $archive_path ($size)"
}

# Print summary
print_summary() {
    log_info "========================================="
    log_info "Build complete!"
    log_info "========================================="
    log_info ""
    log_info "Output directory: $OUTPUT_DIR"
    log_info ""
    log_info "Built architectures:"
    local lib_path="$OUTPUT_DIR/x86_64/libagus_maps_flutter.so"
    if [[ -f "$lib_path" ]]; then
        local size
        size=$(du -h "$lib_path" | cut -f1)
        log_info "  - x86_64: $size"
    fi
    log_info ""
    log_info "Archive: $ROOT_DIR/build/agus-binaries-linux.zip"
    log_info ""
    log_info "To use in CI release, upload the zip to GitHub Releases"
    log_info "========================================="
}

# Main
main() {
    log_info "========================================="
    log_info "CoMaps Linux Native Library Build"
    log_info "========================================="
    log_info "Build type: $BUILD_TYPE"
    log_info "Target: x86_64"
    log_info ""
    
    validate_prerequisites
    bootstrap_comaps
    
    # Clean output directory
    rm -rf "$OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR"
    
    # Build for Linux x86_64
    build_linux
    
    create_archive
    print_summary
}

main "$@"
