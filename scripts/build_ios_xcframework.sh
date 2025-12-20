#!/usr/bin/env bash
set -euo pipefail

# Build CoMaps XCFramework for iOS
#
# This script builds the CoMaps C++ libraries for iOS (device + simulator)
# and packages them into a universal XCFramework.
#
# Prerequisites:
#   - Xcode 15+ with iOS 15.6+ SDK
#   - CMake 3.22+
#   - Ninja build system
#   - CoMaps source in thirdparty/comaps (run fetch_comaps.sh first)
#
# Environment variables:
#   IOS_DEPLOYMENT_TARGET: iOS version (default: 15.6)
#   BUILD_TYPE: Debug or Release (default: Release)
#
# Output:
#   ios/Frameworks/CoMaps.xcframework

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMAPS_DIR="$ROOT_DIR/thirdparty/comaps"
BUILD_DIR="$ROOT_DIR/build/ios"
OUTPUT_DIR="$ROOT_DIR/ios/Frameworks"

IOS_DEPLOYMENT_TARGET="${IOS_DEPLOYMENT_TARGET:-15.6}"
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

# Get SDK path for a platform
get_sdk_path() {
    local sdk=$1
    xcrun --sdk "$sdk" --show-sdk-path
}

# Build for a specific platform/architecture
build_for_platform() {
    local platform=$1      # iphoneos or iphonesimulator
    local archs=$2         # arm64 or "arm64;x86_64"
    local build_path="$BUILD_DIR/${platform}"
    
    log_info "Building for $platform ($archs)..."
    
    local sdk_path
    sdk_path=$(get_sdk_path "$platform")
    
    # Determine if this is simulator
    local is_simulator="OFF"
    if [[ "$platform" == "iphonesimulator" ]]; then
        is_simulator="ON"
    fi
    
    mkdir -p "$build_path"
    
    cmake -S "$COMAPS_DIR" -B "$build_path" \
        -G "$CMAKE_GENERATOR" \
        -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_ARCHITECTURES="$archs" \
        -DCMAKE_OSX_SYSROOT="$sdk_path" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="$IOS_DEPLOYMENT_TARGET" \
        -DCMAKE_IOS_INSTALL_COMBINED=NO \
        -DPLATFORM_IPHONE=ON \
        -DPLATFORM_DESKTOP=OFF \
        -DSKIP_TESTS=ON \
        -DSKIP_QT_GUI=ON \
        -DSKIP_TOOLS=ON \
        -DSKIP_PROTOBUF_CHECK=ON \
        -DWITH_SYSTEM_PROVIDED_3PARTY=OFF \
        -DCMAKE_C_FLAGS="-fembed-bitcode" \
        -DCMAKE_CXX_FLAGS="-fembed-bitcode" \
        2>&1 | tee "$build_path/cmake_configure.log"
    
    cmake --build "$build_path" --config "$BUILD_TYPE" -j "$(sysctl -n hw.ncpu)" \
        2>&1 | tee "$build_path/cmake_build.log"
    
    log_info "Build complete for $platform"
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

# Create XCFramework from platform libraries
create_xcframework() {
    log_info "Creating XCFramework..."
    
    mkdir -p "$OUTPUT_DIR"
    
    local xcframework_path="$OUTPUT_DIR/CoMaps.xcframework"
    
    # Remove existing XCFramework
    rm -rf "$xcframework_path"
    
    # Create XCFramework with device and simulator slices
    xcodebuild -create-xcframework \
        -library "$BUILD_DIR/iphoneos/libcomaps.a" \
        -library "$BUILD_DIR/iphonesimulator/libcomaps.a" \
        -output "$xcframework_path"
    
    log_info "XCFramework created: $xcframework_path"
    
    # Show structure
    log_info "XCFramework structure:"
    find "$xcframework_path" -type f -name "*.a" -exec du -h {} \;
}

# Main build process
main() {
    log_info "========================================="
    log_info "Building CoMaps XCFramework for iOS"
    log_info "========================================="
    log_info "iOS Deployment Target: $IOS_DEPLOYMENT_TARGET"
    log_info "Build Type: $BUILD_TYPE"
    log_info "CoMaps Source: $COMAPS_DIR"
    log_info "Output: $OUTPUT_DIR/CoMaps.xcframework"
    log_info "========================================="
    
    check_prerequisites
    
    # Clean previous builds
    log_info "Cleaning previous builds..."
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"
    
    # Build for device (arm64)
    build_for_platform "iphoneos" "arm64"
    merge_static_libs "$BUILD_DIR/iphoneos" "$BUILD_DIR/iphoneos/libcomaps.a"
    
    # Build for simulator (arm64 + x86_64 fat binary)
    build_for_platform "iphonesimulator" "arm64;x86_64"
    merge_static_libs "$BUILD_DIR/iphonesimulator" "$BUILD_DIR/iphonesimulator/libcomaps.a"
    
    # Create XCFramework
    create_xcframework
    
    log_info "========================================="
    log_info "Build complete!"
    log_info "========================================="
    log_info "XCFramework: $OUTPUT_DIR/CoMaps.xcframework"
    log_info ""
    log_info "To create a release artifact:"
    log_info "  cd $OUTPUT_DIR && zip -r CoMaps.xcframework.zip CoMaps.xcframework"
}

main "$@"
