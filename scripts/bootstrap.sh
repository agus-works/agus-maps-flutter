#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# bootstrap.sh - Unified Bootstrap for macOS Development
# ============================================================================
#
# This script sets up the complete development environment for agus_maps_flutter
# on macOS. It prepares ALL target platforms that can be built from macOS:
#   - Android (arm64-v8a, armeabi-v7a, x86_64)
#   - iOS (arm64 device, arm64+x86_64 simulator)
#   - macOS (arm64, x86_64)
#
# IMPORTANT: This script only runs on macOS. Linux is not yet supported.
# For Windows development, use bootstrap.ps1 instead.
#
# What it does:
#   1. Verify macOS environment
#   2. Fetch CoMaps source code (or restore from local cache)
#   3. Create cache archive after fresh clone (before patches)
#   4. Apply patches (superset for all platforms)
#   5. Build Boost headers
#   6. Generate CoMaps data files (classificator, types, etc.)
#   7. Copy CoMaps data files to example assets
#   8. Download base MWM samples (World, Gibraltar)
#   9. Copy Android-specific assets (fonts)
#  10. Download or build iOS XCFramework
#  11. Download or build macOS XCFramework
#  12. Copy Metal shaders for macOS
#
# Usage:
#   ./scripts/bootstrap.sh [--build-xcframework] [--no-cache]
#
# Options:
#   --build-xcframework    Build XCFrameworks from source (~30 min each)
#                          Without this flag, downloads pre-built binaries
#   --no-cache             Disable local cache (don't use/create .thirdparty.tar.bz2)
#
# Environment variables:
#   COMAPS_TAG:      Git tag/commit to checkout (default: v2025.12.11-2)
#   SKIP_PATCHES:    Set to "true" to skip applying patches
#   SKIP_BASE_MWMS:  Set to "true" to skip downloading base MWM samples
#   NO_CACHE:        Set to "true" to disable caching (same as --no-cache)
#   CI:              Auto-detected; disables local caching in CI environments
#
# Local Cache Mechanism (development only):
#   - After fresh clone, thirdparty is compressed to .thirdparty.tar.bz2
#   - Cache is created BEFORE patches are applied (pristine state)
#   - If thirdparty is deleted and cache exists, it will be extracted
#   - This allows iterating on patches without re-cloning from git
#   - Caching is automatically disabled in CI environments ($CI=true)
#
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ============================================================================
# Check Platform - macOS Only
# ============================================================================

check_platform() {
    case "$(uname -s)" in
        Darwin)
            # macOS - supported
            ;;
        Linux)
            echo ""
            echo "ERROR: Linux builds are not yet supported."
            echo ""
            echo "The agus_maps_flutter bootstrap currently only runs on macOS."
            echo "We are still evaluating which Linux distributions to support"
            echo "and the best process for Linux development."
            echo ""
            echo "For more information, see docs/CONTRIBUTING.md"
            echo ""
            exit 1
            ;;
        MINGW*|MSYS*|CYGWIN*)
            echo ""
            echo "ERROR: This script is for macOS only."
            echo ""
            echo "For Windows development, use PowerShell:"
            echo "  .\\scripts\\bootstrap.ps1"
            echo ""
            exit 1
            ;;
        *)
            echo "ERROR: Unsupported platform: $(uname -s)"
            exit 1
            ;;
    esac
}

# Run platform check immediately
check_platform

# Source common bootstrap functions
# shellcheck source=bootstrap_common.sh
source "$SCRIPT_DIR/bootstrap_common.sh"

# ============================================================================
# Parse Arguments
# ============================================================================

BUILD_XCFRAMEWORK="${BUILD_XCFRAMEWORK:-false}"
NO_CACHE="${NO_CACHE:-false}"

for arg in "$@"; do
    case $arg in
        --build-xcframework)
            BUILD_XCFRAMEWORK=true
            ;;
        --no-cache)
            NO_CACHE=true
            export NO_CACHE
            ;;
        --help|-h)
            echo "Usage: $0 [--build-xcframework] [--no-cache]"
            echo ""
            echo "Options:"
            echo "  --build-xcframework  Build XCFrameworks from source (~30 min each)"
            echo "  --no-cache           Disable local cache mechanism"
            echo "  --help, -h           Show this help message"
            echo ""
            echo "This script bootstraps ALL target platforms from macOS:"
            echo "  - Android (arm64-v8a, armeabi-v7a, x86_64)"
            echo "  - iOS (device + simulator)"
            echo "  - macOS (arm64 + x86_64)"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# ============================================================================
# Main Bootstrap
# ============================================================================

echo ""
echo "========================================="
echo "Agus Maps Flutter - Unified Bootstrap"
echo "========================================="
echo ""
echo "Build Machine: macOS $(sw_vers -productVersion)"
echo "Target Platforms: Android, iOS, macOS"
echo ""

# Run full bootstrap for all platforms (handles CoMaps fetch, patches, boost, data)
bootstrap_full "all"

# ============================================================================
# iOS XCFramework
# ============================================================================

log_header "Setting up iOS XCFramework"

IOS_XCFRAMEWORK_PATH="$ROOT_DIR/ios/Frameworks/CoMaps.xcframework"

if [[ -d "$IOS_XCFRAMEWORK_PATH" ]]; then
    log_info "iOS XCFramework already exists"
elif [[ "$BUILD_XCFRAMEWORK" == "true" ]]; then
    log_info "Building iOS XCFramework from source (this may take ~30 minutes)..."
    if [[ -x "$SCRIPT_DIR/build_binaries_ios.sh" ]]; then
        "$SCRIPT_DIR/build_binaries_ios.sh"
        
        # Copy to ios/Frameworks
        mkdir -p "$ROOT_DIR/ios/Frameworks"
        if [[ -d "$ROOT_DIR/build/agus-binaries-ios/CoMaps.xcframework" ]]; then
            cp -R "$ROOT_DIR/build/agus-binaries-ios/CoMaps.xcframework" "$ROOT_DIR/ios/Frameworks/"
            log_info "iOS XCFramework installed"
        fi
    else
        log_error "build_binaries_ios.sh not found"
    fi
else
    log_info "Downloading pre-built iOS XCFramework..."
    if [[ -x "$SCRIPT_DIR/download_libs.sh" ]]; then
        "$SCRIPT_DIR/download_libs.sh" ios || {
            log_warn "Download failed. Use --build-xcframework to build from source."
        }
    else
        log_warn "download_libs.sh not found. Use --build-xcframework to build from source."
    fi
fi

# ============================================================================
# macOS XCFramework
# ============================================================================

log_header "Setting up macOS XCFramework"

MACOS_XCFRAMEWORK_PATH="$ROOT_DIR/macos/Frameworks/CoMaps.xcframework"

if [[ -d "$MACOS_XCFRAMEWORK_PATH" ]]; then
    log_info "macOS XCFramework already exists"
elif [[ "$BUILD_XCFRAMEWORK" == "true" ]]; then
    log_info "Building macOS XCFramework from source (this may take ~30 minutes)..."
    if [[ -x "$SCRIPT_DIR/build_binaries_macos.sh" ]]; then
        "$SCRIPT_DIR/build_binaries_macos.sh"
        
        # Copy to macos/Frameworks
        mkdir -p "$ROOT_DIR/macos/Frameworks"
        if [[ -d "$ROOT_DIR/build/agus-binaries-macos/CoMaps.xcframework" ]]; then
            cp -R "$ROOT_DIR/build/agus-binaries-macos/CoMaps.xcframework" "$ROOT_DIR/macos/Frameworks/"
            log_info "macOS XCFramework installed"
        fi
    else
        log_error "build_binaries_macos.sh not found"
    fi
else
    log_info "Downloading pre-built macOS XCFramework..."
    if [[ -x "$SCRIPT_DIR/download_libs.sh" ]]; then
        "$SCRIPT_DIR/download_libs.sh" macos || {
            log_warn "Download failed. Use --build-xcframework to build from source."
        }
    else
        log_warn "download_libs.sh not found. Use --build-xcframework to build from source."
    fi
fi

# ============================================================================
# macOS Metal Shaders
# ============================================================================

log_header "Setting up Metal Shaders"

MACOS_SHADERS="$ROOT_DIR/macos/Resources/shaders_metal.metallib"

if [[ -f "$MACOS_SHADERS" ]]; then
    log_info "macOS Metal shaders already exist"
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
            log_warn "Metal shaders not found. They will be built during XCFramework build."
        fi
    fi
fi

# ============================================================================
# Complete
# ============================================================================

echo ""
echo "========================================="
echo "Bootstrap Complete!"
echo "========================================="
echo ""
echo "This bootstrap has prepared:"
echo "  ✓ CoMaps source code and patches"
echo "  ✓ Boost headers"
echo "  ✓ CoMaps data files"
echo "  ✓ Android assets (fonts)"

if [[ -d "$IOS_XCFRAMEWORK_PATH" ]]; then
    echo "  ✓ iOS XCFramework"
else
    echo "  ○ iOS XCFramework (not installed - use --build-xcframework or download)"
fi

if [[ -d "$MACOS_XCFRAMEWORK_PATH" ]]; then
    echo "  ✓ macOS XCFramework"
else
    echo "  ○ macOS XCFramework (not installed - use --build-xcframework or download)"
fi

# Show cache status
if [[ "${NO_CACHE:-}" != "true" ]] && [[ "${CI:-}" != "true" ]]; then
    if test_thirdparty_archive; then
        archive_path="$ROOT_DIR/$THIRDPARTY_ARCHIVE"
        size_bytes=$(stat -f%z "$archive_path" 2>/dev/null || stat -c%s "$archive_path" 2>/dev/null)
        size_mb=$((size_bytes / 1024 / 1024))
        echo "  ✓ Local cache: $THIRDPARTY_ARCHIVE (${size_mb} MB)"
    fi
fi

echo ""
echo "Next steps:"
echo ""
echo "  Android:"
echo "    cd example && flutter run -d <android-device>"
echo ""
echo "  iOS:"
echo "    cd example/ios && pod install"
echo "    cd .. && flutter run -d 'iPhone 15 Pro'"
echo ""
echo "  macOS:"
echo "    cd example/macos && pod install"
echo "    cd .. && flutter run -d macos"
echo ""
echo "To build native libraries from source:"
echo "    ./scripts/build_binaries_android.sh"
echo "    ./scripts/build_binaries_ios.sh"
echo "    ./scripts/build_binaries_macos.sh"
echo ""
