#!/usr/bin/env bash
set -euo pipefail

# Build CoMaps native libraries for Android (all ABIs)
#
# This script compiles the CoMaps native code for Android using the NDK and CMake.
# It produces static libraries (.a) for each supported ABI that are packaged into
# a shared library by the final Gradle build.
#
# Prerequisites:
#   - thirdparty/comaps must exist (run fetch_comaps.sh first)
#   - Android NDK must be installed
#   - CMake must be installed
#
# Usage:
#   ./build_binaries_android.sh
#
# Environment variables:
#   NDK_VERSION: Android NDK version (default: 27.2.12479018)
#   CMAKE_VERSION: CMake version to use (default: 3.22.1)
#   ANDROID_HOME: Path to Android SDK (auto-detected if not set)
#   BUILD_TYPE: Release or Debug (default: Release)
#   ABIS: Space-separated list of ABIs to build (default: "arm64-v8a armeabi-v7a x86_64")
#
# Output:
#   build/agus-binaries-android/<abi>/libagus_maps_flutter.so
#
# The output directory structure is suitable for zipping as agus-binaries-android.zip

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/build/agus-binaries-android"

# Default configuration
NDK_VERSION="${NDK_VERSION:-27.2.12479018}"
CMAKE_VERSION="${CMAKE_VERSION:-3.22.1}"
BUILD_TYPE="${BUILD_TYPE:-Release}"
ABIS="${ABIS:-arm64-v8a armeabi-v7a x86_64}"
MIN_SDK="${MIN_SDK:-24}"

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

# Detect Android SDK location
detect_android_sdk() {
    if [[ -n "${ANDROID_HOME:-}" ]]; then
        echo "$ANDROID_HOME"
        return
    fi
    
    if [[ -n "${ANDROID_SDK_ROOT:-}" ]]; then
        echo "$ANDROID_SDK_ROOT"
        return
    fi
    
    # Common locations
    local common_paths=(
        "$HOME/Library/Android/sdk"  # macOS
        "$HOME/Android/Sdk"          # Linux
        "/usr/local/lib/android/sdk" # Bitrise Linux
    )
    
    for path in "${common_paths[@]}"; do
        if [[ -d "$path" ]]; then
            echo "$path"
            return
        fi
    done
    
    log_error "Could not detect Android SDK location"
    log_error "Please set ANDROID_HOME or ANDROID_SDK_ROOT environment variable"
    exit 1
}

# Validate prerequisites
validate_prerequisites() {
    log_step "Validating prerequisites..."
    
    # Check CoMaps source
    if [[ ! -d "$ROOT_DIR/thirdparty/comaps" ]]; then
        log_error "CoMaps source not found at: $ROOT_DIR/thirdparty/comaps"
        log_error "Run ./scripts/fetch_comaps.sh first"
        exit 1
    fi
    
    # Detect SDK
    ANDROID_SDK=$(detect_android_sdk)
    log_info "Android SDK: $ANDROID_SDK"
    
    # Check NDK
    NDK_PATH="$ANDROID_SDK/ndk/$NDK_VERSION"
    if [[ ! -d "$NDK_PATH" ]]; then
        log_warn "NDK $NDK_VERSION not found at $NDK_PATH"
        log_info "Attempting to find any available NDK..."
        
        # Try to find any available NDK
        if [[ -d "$ANDROID_SDK/ndk" ]]; then
            local found_ndk
            found_ndk=$(ls -1 "$ANDROID_SDK/ndk" | head -1)
            if [[ -n "$found_ndk" ]]; then
                NDK_PATH="$ANDROID_SDK/ndk/$found_ndk"
                log_info "Using NDK: $found_ndk"
            fi
        fi
        
        if [[ ! -d "$NDK_PATH" ]]; then
            log_error "No Android NDK found"
            log_error "Install NDK using: sdkmanager \"ndk;$NDK_VERSION\""
            exit 1
        fi
    fi
    log_info "NDK path: $NDK_PATH"
    
    # Find CMake
    CMAKE_PATH="$ANDROID_SDK/cmake/$CMAKE_VERSION/bin/cmake"
    if [[ ! -f "$CMAKE_PATH" ]]; then
        # Try system cmake
        if command -v cmake &> /dev/null; then
            CMAKE_PATH="cmake"
            log_info "Using system CMake"
        else
            log_error "CMake not found"
            log_error "Install CMake using: sdkmanager \"cmake;$CMAKE_VERSION\""
            exit 1
        fi
    else
        log_info "CMake: $CMAKE_PATH"
    fi
    
    # Export for later use
    export ANDROID_SDK
    export NDK_PATH
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

# Build for a single ABI
build_abi() {
    local abi=$1
    local build_dir="$ROOT_DIR/build/android-$abi"
    local abi_output_dir="$OUTPUT_DIR/$abi"
    
    log_step "Building for ABI: $abi"
    
    # Clean and create build directory
    rm -rf "$build_dir"
    mkdir -p "$build_dir"
    
    # Run CMake configure
    log_info "Configuring CMake for $abi..."
    "$CMAKE_PATH" \
        -B "$build_dir" \
        -S "$ROOT_DIR/src" \
        -DCMAKE_TOOLCHAIN_FILE="$NDK_PATH/build/cmake/android.toolchain.cmake" \
        -DANDROID_ABI="$abi" \
        -DANDROID_PLATFORM="android-$MIN_SDK" \
        -DANDROID_NDK="$NDK_PATH" \
        -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
        -DCMAKE_ANDROID_ARCH_ABI="$abi" \
        -DANDROID=ON \
        -G "Ninja"
    
    # Run build
    log_info "Building $abi..."
    "$CMAKE_PATH" --build "$build_dir" --parallel
    
    # Copy output
    mkdir -p "$abi_output_dir"
    
    # Find and copy the shared library
    local lib_name="libagus_maps_flutter.so"
    local lib_path="$build_dir/$lib_name"
    
    if [[ -f "$lib_path" ]]; then
        cp "$lib_path" "$abi_output_dir/"
        local size
        size=$(du -h "$abi_output_dir/$lib_name" | cut -f1)
        log_info "Built: $abi_output_dir/$lib_name ($size)"
    else
        log_error "Build output not found: $lib_path"
        exit 1
    fi
}

# Create archive
create_archive() {
    log_step "Creating archive..."
    
    local archive_path="$ROOT_DIR/build/agus-binaries-android.zip"
    
    pushd "$ROOT_DIR/build" >/dev/null
    rm -f "agus-binaries-android.zip"
    zip -r "agus-binaries-android.zip" "agus-binaries-android"
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
    log_info "Built ABIs:"
    for abi in $ABIS; do
        local lib_path="$OUTPUT_DIR/$abi/libagus_maps_flutter.so"
        if [[ -f "$lib_path" ]]; then
            local size
            size=$(du -h "$lib_path" | cut -f1)
            log_info "  - $abi: $size"
        fi
    done
    log_info ""
    log_info "Archive: $ROOT_DIR/build/agus-binaries-android.zip"
    log_info ""
    log_info "To use in CI release, upload the zip to GitHub Releases"
    log_info "========================================="
}

# Main
main() {
    log_info "========================================="
    log_info "CoMaps Android Native Library Build"
    log_info "========================================="
    log_info "Build type: $BUILD_TYPE"
    log_info "ABIs: $ABIS"
    log_info "Min SDK: $MIN_SDK"
    log_info ""
    
    validate_prerequisites
    bootstrap_comaps
    
    # Clean output directory
    rm -rf "$OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR"
    
    # Build each ABI
    for abi in $ABIS; do
        build_abi "$abi"
    done
    
    create_archive
    print_summary
}

main "$@"
