#!/usr/bin/env bash
set -euo pipefail

# Build CoMaps native binaries for macOS
#
# This script builds the CoMaps C++ libraries for macOS (arm64 + x86_64)
# and packages them into a universal XCFramework.
#
# Prerequisites:
#   - Xcode 15+ with macOS 12.0+ SDK
#   - CMake 3.22+
#   - Ninja build system
#   - CoMaps source in thirdparty/comaps (run fetch_comaps.sh first)
#
# Environment variables:
#   MACOS_DEPLOYMENT_TARGET: macOS version (default: 12.0)
#   BUILD_TYPE: Debug or Release (default: Release)
#
# Output:
#   build/agus-binaries-macos/CoMaps.xcframework

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMAPS_DIR="$ROOT_DIR/thirdparty/comaps"
BUILD_DIR="$ROOT_DIR/build/macos"
OUTPUT_DIR="$ROOT_DIR/build/agus-binaries-macos"

MACOS_DEPLOYMENT_TARGET="${MACOS_DEPLOYMENT_TARGET:-12.0}"
BUILD_TYPE="${BUILD_TYPE:-Release}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v cmake &> /dev/null; then
        log_error "CMake not found. Install with: brew install cmake"
        exit 1
    fi
    
    if ! command -v ninja &> /dev/null; then
        log_warn "Ninja not found. Install with: brew install ninja (using Make instead)"
        CMAKE_GENERATOR="Unix Makefiles"
    else
        CMAKE_GENERATOR="Ninja"
    fi
    
    if ! command -v xcodebuild &> /dev/null; then
        log_error "Xcode not found. Install from App Store."
        exit 1
    fi
    
    if [[ ! -d "$COMAPS_DIR" ]]; then
        log_error "CoMaps source not found at $COMAPS_DIR"
        log_error "Run: ./scripts/fetch_comaps.sh"
        exit 1
    fi
    
    log_info "Prerequisites OK"
}

# Get SDK path
get_sdk_path() {
    xcrun --sdk macosx --show-sdk-path
}

# Build for a specific architecture
build_for_arch() {
    local arch=$1
    local build_path="$BUILD_DIR/${arch}"
    
    log_info "Building for macOS ($arch)..."
    
    local sdk_path
    sdk_path=$(get_sdk_path)
    
    mkdir -p "$build_path"
    
    cmake -S "$COMAPS_DIR" -B "$build_path" \
        -G "$CMAKE_GENERATOR" \
        -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
        -DCMAKE_SYSTEM_NAME=Darwin \
        -DCMAKE_OSX_ARCHITECTURES="$arch" \
        -DCMAKE_OSX_SYSROOT="$sdk_path" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET" \
        -DPLATFORM_IPHONE=OFF \
        -DPLATFORM_DESKTOP=ON \
        -DSKIP_TESTS=ON \
        -DSKIP_QT=ON \
        -DSKIP_QT_GUI=ON \
        -DSKIP_TOOLS=ON \
        -DSKIP_PROTOBUF_CHECK=ON \
        -DWITH_SYSTEM_PROVIDED_3PARTY=OFF \
        2>&1 | tee "$build_path/cmake_configure.log"
    
    # Build only the 'map' target and its dependencies (not executables)
    cmake --build "$build_path" --config "$BUILD_TYPE" --target map -j "$(sysctl -n hw.ncpu)" \
        2>&1 | tee "$build_path/cmake_build.log"
    
    log_info "Build complete for $arch"
}

# Merge all static libraries into one
merge_static_libs() {
    local build_path=$1
    local output_lib=$2
    
    log_info "Merging static libraries in $build_path..."
    
    # Find all .a files (excluding CMake internal libs)
    local libs=()
    while IFS= read -r -d '' lib; do
        # Skip CMake internal libraries
        if [[ "$lib" != *"CMakeFiles"* ]]; then
            libs+=("$lib")
        fi
    done < <(find "$build_path" -name "*.a" -print0)
    
    if [[ ${#libs[@]} -eq 0 ]]; then
        log_error "No static libraries found in $build_path"
        exit 1
    fi
    
    log_info "Found ${#libs[@]} libraries to merge"
    
    # Use libtool to merge all static libraries
    libtool -static -o "$output_lib" "${libs[@]}"
    
    log_info "Merged library: $output_lib ($(du -h "$output_lib" | cut -f1))"
}

# Create universal (fat) binary from arm64 and x86_64
create_universal_binary() {
    local arm64_lib="$BUILD_DIR/arm64/libcomaps.a"
    local x86_64_lib="$BUILD_DIR/x86_64/libcomaps.a"
    local universal_lib="$BUILD_DIR/universal/libcomaps.a"
    
    log_info "Creating universal binary..."
    
    mkdir -p "$BUILD_DIR/universal"
    
    lipo -create \
        "$arm64_lib" \
        "$x86_64_lib" \
        -output "$universal_lib"
    
    log_info "Universal binary created: $universal_lib"
    lipo -info "$universal_lib"
}

# Create XCFramework from universal library
create_xcframework() {
    log_info "Creating XCFramework..."
    
    mkdir -p "$OUTPUT_DIR"
    
    local xcframework_path="$OUTPUT_DIR/CoMaps.xcframework"
    
    # Remove existing XCFramework
    rm -rf "$xcframework_path"
    
    # Create XCFramework with universal macOS library
    xcodebuild -create-xcframework \
        -library "$BUILD_DIR/universal/libcomaps.a" \
        -output "$xcframework_path"
    
    log_info "XCFramework created: $xcframework_path"
    
    # Show structure
    log_info "XCFramework structure:"
    find "$xcframework_path" -type f -name "*.a" -exec du -h {} \;
}

# Copy Metal shaders to output
copy_shaders() {
    log_info "Copying Metal shaders..."
    
    # Metal shaders are built as part of the iOS build but are compatible with macOS
    # Check if we have pre-built shaders from iOS
    local ios_shaders="$ROOT_DIR/ios/Resources/shaders_metal.metallib"
    local macos_shaders="$ROOT_DIR/macos/Resources/shaders_metal.metallib"
    
    mkdir -p "$ROOT_DIR/macos/Resources"
    
    if [[ -f "$ios_shaders" ]]; then
        cp "$ios_shaders" "$macos_shaders"
        log_info "Copied Metal shaders from iOS"
    elif [[ -f "$ROOT_DIR/build/metal_shaders/shaders_metal.metallib" ]]; then
        cp "$ROOT_DIR/build/metal_shaders/shaders_metal.metallib" "$macos_shaders"
        log_info "Copied Metal shaders from build"
    else
        log_warn "Metal shaders not found. They will need to be built separately."
    fi
}

# Main build process
main() {
    log_info "========================================="
    log_info "Building CoMaps Binaries for macOS"
    log_info "========================================="
    log_info "macOS Deployment Target: $MACOS_DEPLOYMENT_TARGET"
    log_info "Build Type: $BUILD_TYPE"
    log_info "CoMaps Source: $COMAPS_DIR"
    log_info "Output: $OUTPUT_DIR/CoMaps.xcframework"
    log_info "========================================="
    
    check_prerequisites
    
    # Clean previous builds
    log_info "Cleaning previous builds..."
    rm -rf "$BUILD_DIR"
    rm -rf "$OUTPUT_DIR"
    mkdir -p "$BUILD_DIR"
    mkdir -p "$OUTPUT_DIR"
    
    # Build for arm64 (Apple Silicon)
    build_for_arch "arm64"
    merge_static_libs "$BUILD_DIR/arm64" "$BUILD_DIR/arm64/libcomaps.a"
    
    # Build for x86_64 (Intel)
    build_for_arch "x86_64"
    merge_static_libs "$BUILD_DIR/x86_64" "$BUILD_DIR/x86_64/libcomaps.a"
    
    # Create universal binary
    create_universal_binary
    
    # Create XCFramework
    create_xcframework
    
    # Copy shaders
    copy_shaders
    
    log_info "========================================="
    log_info "Build complete!"
    log_info "========================================="
    log_info "XCFramework: $OUTPUT_DIR/CoMaps.xcframework"
    log_info ""
    log_info "To create a release artifact:"
    log_info "  cd $OUTPUT_DIR && tar -czvf agus-binaries-macos.tar.gz CoMaps.xcframework"
}

main "$@"
