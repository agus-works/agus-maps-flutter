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
#   ./scripts/bootstrap.sh [--build-binaries] [--build-example-app] [--no-cache]
#
# Options:
#   --build-binaries       Build all native binaries from source:
#                          - Android: .so libraries (~15 min)
#                          - iOS: XCFramework (~30 min)
#                          - macOS: XCFramework (~30 min)
#                          Without this flag, downloads pre-built binaries
#   --build-example-app    Build Flutter example apps in release mode:
#                          - Android: APK and AAB
#                          - iOS: Simulator .app
#                          - macOS: .app bundle
#                          Requires native binaries to be present.
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

BUILD_BINARIES="${BUILD_BINARIES:-false}"
BUILD_EXAMPLE_APP="${BUILD_EXAMPLE_APP:-false}"
NO_CACHE="${NO_CACHE:-false}"

for arg in "$@"; do
    case $arg in
        --build-binaries)
            BUILD_BINARIES=true
            ;;
        --build-example-app)
            BUILD_EXAMPLE_APP=true
            ;;
        --no-cache)
            NO_CACHE=true
            export NO_CACHE
            ;;
        --help|-h)
            echo "Usage: $0 [--build-binaries] [--build-example-app] [--no-cache]"
            echo ""
            echo "Options:"
            echo "  --build-binaries     Build all native binaries from source:"
            echo "                         - Android: .so libraries (~15 min)"
            echo "                         - iOS: XCFramework (~30 min)"
            echo "                         - macOS: XCFramework (~30 min)"
            echo "  --build-example-app  Build Flutter example apps in release mode:"
            echo "                         - Android: APK and AAB"
            echo "                         - iOS: Simulator .app"
            echo "                         - macOS: .app bundle"
            echo "                         Requires native binaries to be present."
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
# Android Native Libraries
# ============================================================================

log_header "Setting up Android Native Libraries"

ANDROID_PREBUILT_PATH="$ROOT_DIR/android/prebuilt"
ANDROID_LIBS_EXIST=false

# Check if all Android ABIs exist (library is named libagus_maps_flutter.so)
if [[ -f "$ANDROID_PREBUILT_PATH/arm64-v8a/libagus_maps_flutter.so" ]] && \
   [[ -f "$ANDROID_PREBUILT_PATH/armeabi-v7a/libagus_maps_flutter.so" ]] && \
   [[ -f "$ANDROID_PREBUILT_PATH/x86_64/libagus_maps_flutter.so" ]]; then
    ANDROID_LIBS_EXIST=true
fi

if [[ "$ANDROID_LIBS_EXIST" == "true" ]]; then
    log_info "Android native libraries already exist"
elif [[ "$BUILD_BINARIES" == "true" ]]; then
    log_info "Building Android native libraries from source (this may take ~15 minutes)..."
    if [[ -f "$SCRIPT_DIR/build_binaries_android.sh" ]]; then
        chmod +x "$SCRIPT_DIR/build_binaries_android.sh"
        "$SCRIPT_DIR/build_binaries_android.sh"
        
        # Copy to android/prebuilt
        mkdir -p "$ANDROID_PREBUILT_PATH"
        if [[ -d "$ROOT_DIR/build/agus-binaries-android" ]]; then
            cp -R "$ROOT_DIR/build/agus-binaries-android"/* "$ANDROID_PREBUILT_PATH/"
            log_info "Android native libraries installed"
        fi
    else
        log_error "build_binaries_android.sh not found"
        exit 1
    fi
else
    log_info "Downloading pre-built Android native libraries..."
    if [[ -x "$SCRIPT_DIR/download_libs.sh" ]]; then
        FORCE_DOWNLOAD=true "$SCRIPT_DIR/download_libs.sh" android || {
            log_warn "Download failed. Use --build-binaries to build from source."
        }
    else
        log_warn "download_libs.sh not found. Use --build-binaries to build from source."
    fi
fi

# ============================================================================
# iOS XCFramework
# ============================================================================

log_header "Setting up iOS XCFramework"

IOS_XCFRAMEWORK_PATH="$ROOT_DIR/ios/Frameworks/CoMaps.xcframework"

if [[ -d "$IOS_XCFRAMEWORK_PATH" ]]; then
    log_info "iOS XCFramework already exists"
elif [[ "$BUILD_BINARIES" == "true" ]]; then
    log_info "Building iOS XCFramework from source (this may take ~30 minutes)..."
    if [[ -f "$SCRIPT_DIR/build_binaries_ios.sh" ]]; then
        chmod +x "$SCRIPT_DIR/build_binaries_ios.sh"
        "$SCRIPT_DIR/build_binaries_ios.sh"
        
        # Copy to ios/Frameworks
        mkdir -p "$ROOT_DIR/ios/Frameworks"
        if [[ -d "$ROOT_DIR/build/agus-binaries-ios/CoMaps.xcframework" ]]; then
            cp -R "$ROOT_DIR/build/agus-binaries-ios/CoMaps.xcframework" "$ROOT_DIR/ios/Frameworks/"
            log_info "iOS XCFramework installed"
        fi
    else
        log_error "build_binaries_ios.sh not found"
        exit 1
    fi
else
    log_info "Downloading pre-built iOS XCFramework..."
    if [[ -x "$SCRIPT_DIR/download_libs.sh" ]]; then
        FORCE_DOWNLOAD=true "$SCRIPT_DIR/download_libs.sh" ios || {
            log_warn "Download failed. Use --build-binaries to build from source."
        }
    else
        log_warn "download_libs.sh not found. Use --build-binaries to build from source."
    fi
fi

# ============================================================================
# macOS XCFramework
# ============================================================================

log_header "Setting up macOS XCFramework"

MACOS_XCFRAMEWORK_PATH="$ROOT_DIR/macos/Frameworks/CoMaps.xcframework"

if [[ -d "$MACOS_XCFRAMEWORK_PATH" ]]; then
    log_info "macOS XCFramework already exists"
elif [[ "$BUILD_BINARIES" == "true" ]]; then
    log_info "Building macOS XCFramework from source (this may take ~30 minutes)..."
    if [[ -f "$SCRIPT_DIR/build_binaries_macos.sh" ]]; then
        chmod +x "$SCRIPT_DIR/build_binaries_macos.sh"
        "$SCRIPT_DIR/build_binaries_macos.sh"
        
        # Copy to macos/Frameworks
        mkdir -p "$ROOT_DIR/macos/Frameworks"
        if [[ -d "$ROOT_DIR/build/agus-binaries-macos/CoMaps.xcframework" ]]; then
            cp -R "$ROOT_DIR/build/agus-binaries-macos/CoMaps.xcframework" "$ROOT_DIR/macos/Frameworks/"
            log_info "macOS XCFramework installed"
        fi
    else
        log_error "build_binaries_macos.sh not found"
        exit 1
    fi
else
    log_info "Downloading pre-built macOS XCFramework..."
    if [[ -x "$SCRIPT_DIR/download_libs.sh" ]]; then
        FORCE_DOWNLOAD=true "$SCRIPT_DIR/download_libs.sh" macos || {
            log_warn "Download failed. Use --build-binaries to build from source."
        }
    else
        log_warn "download_libs.sh not found. Use --build-binaries to build from source."
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
# Build Example Apps (optional)
# ============================================================================

if [[ "$BUILD_EXAMPLE_APP" == "true" ]]; then
    log_header "Building Example Apps (Release Mode)"
    
    # Check if binaries are present
    MISSING_BINARIES=()
    
    if [[ ! -f "$ANDROID_PREBUILT_PATH/arm64-v8a/libagus_maps_flutter.so" ]]; then
        MISSING_BINARIES+=("Android native libraries")
    fi
    
    if [[ ! -d "$IOS_XCFRAMEWORK_PATH" ]]; then
        MISSING_BINARIES+=("iOS XCFramework")
    fi
    
    if [[ ! -d "$MACOS_XCFRAMEWORK_PATH" ]]; then
        MISSING_BINARIES+=("macOS XCFramework")
    fi
    
    if [[ ${#MISSING_BINARIES[@]} -gt 0 ]]; then
        log_error "Cannot build example apps - missing binaries:"
        for missing in "${MISSING_BINARIES[@]}"; do
            echo "  - $missing"
        done
        echo ""
        echo "Run with --build-binaries first, or ensure binaries are downloaded."
        exit 1
    fi
    
    # Change to example directory
    cd "$ROOT_DIR/example"
    
    # Get Flutter dependencies
    log_info "Getting Flutter dependencies..."
    flutter pub get
    
    # Build Android APK and AAB
    log_info "Building Android APK (release)..."
    flutter build apk --release 2>&1 | tee "$ROOT_DIR/build-android.log" || {
        log_error "Android APK build failed. See build-android.log for details."
        exit 1
    }
    
    log_info "Building Android App Bundle (release)..."
    flutter build appbundle --release 2>&1 | tee -a "$ROOT_DIR/build-android.log" || {
        log_error "Android AAB build failed. See build-android.log for details."
        exit 1
    }
    
    # Build iOS Simulator app
    log_info "Building iOS Simulator app (release)..."
    cd ios && pod install && cd ..
    flutter build ios --simulator --release 2>&1 | tee "$ROOT_DIR/build-ios.log" || {
        log_error "iOS build failed. See build-ios.log for details."
        exit 1
    }
    
    # Build macOS app
    log_info "Building macOS app (release)..."
    cd macos && pod install && cd ..
    flutter build macos --release 2>&1 | tee "$ROOT_DIR/build-macos.log" || {
        log_error "macOS build failed. See build-macos.log for details."
        exit 1
    }
    
    cd "$ROOT_DIR"
    
    log_info "All example apps built successfully!"
    echo ""
    echo "Build outputs:"
    echo "  Android APK: example/build/app/outputs/flutter-apk/app-release.apk"
    echo "  Android AAB: example/build/app/outputs/bundle/release/app-release.aab"
    echo "  iOS Simulator: example/build/ios/iphonesimulator/Runner.app"
    echo "  macOS: example/build/macos/Build/Products/Release/agus_maps_flutter_example.app"
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

# Android status
if [[ -f "$ANDROID_PREBUILT_PATH/arm64-v8a/libagus_maps_flutter.so" ]]; then
    echo "  ✓ Android native libraries"
else
    echo "  ○ Android native libraries (not installed - use --build-binaries)"
fi

# iOS status
if [[ -d "$IOS_XCFRAMEWORK_PATH" ]]; then
    echo "  ✓ iOS XCFramework"
else
    echo "  ○ iOS XCFramework (not installed - use --build-binaries)"
fi

# macOS status
if [[ -d "$MACOS_XCFRAMEWORK_PATH" ]]; then
    echo "  ✓ macOS XCFramework"
else
    echo "  ○ macOS XCFramework (not installed - use --build-binaries)"
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
echo "To build all native libraries from source (~1 hour total):"
echo "    ./scripts/bootstrap.sh --build-binaries"
echo ""
echo "To build example apps (requires binaries):"
echo "    ./scripts/bootstrap.sh --build-example-app"
echo ""
echo "To do a full build (binaries + example apps):"
echo "    ./scripts/bootstrap.sh --build-binaries --build-example-app"
echo ""
