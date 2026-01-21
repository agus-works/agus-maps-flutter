#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# build_all.sh - Build All Platforms Using Dart Hooks
# ============================================================================
#
# This script builds agus_maps_flutter for all platforms supported on macOS:
# Android, iOS, and macOS.
#
# It uses the Dart build hooks (tool/build.dart) which handle:
# - Bootstrap (CoMaps clone, patches, Boost headers, data generation)
# - Building native binaries (Android, iOS, macOS)
# - Metal shader compilation (iOS/macOS)
# - CocoaPods setup (iOS/macOS)
#
# Usage:
#   ./scripts/build_all.sh
#
# ============================================================================

# ============================================================================
# Configuration
# ============================================================================

FLUTTER_VERSION="3.38.7"

# ============================================================================
# Derived paths
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"

# ============================================================================
# Colors and logging
# ============================================================================

if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    CYAN=''
    BLUE=''
    NC=''
fi

log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_header()  { echo -e "${CYAN}=== $1 ===${NC}"; }
log_step()    { echo -e "${BLUE}[STEP]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

# ============================================================================
# Platform check
# ============================================================================

check_platform() {
    log_header "Checking Platform"
    
    case "$(uname -s)" in
        Darwin)
            log_info "Platform: macOS $(sw_vers -productVersion)"
            log_info "Architecture: $(uname -m)"
            ;;
        Linux)
            log_info "Platform: Linux"
            log_info "Architecture: $(uname -m)"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            log_info "Platform: Windows (Git Bash)"
            log_info "Architecture: $(uname -m)"
            ;;
        *)
            log_error "Unsupported platform: $(uname -s)"
            exit 1
            ;;
    esac
}

# ============================================================================
# Dependency checks
# ============================================================================

check_dart() {
    if ! command -v dart &>/dev/null; then
        log_error "Dart is not installed."
        log_error "Install Dart: https://dart.dev/get-dart"
        exit 1
    fi
    log_info "Dart: $(dart --version 2>&1 | head -1)"
}

check_flutter() {
    if ! command -v flutter &>/dev/null; then
        log_error "Flutter is not installed."
        log_error "Install Flutter: https://docs.flutter.dev/get-started/install"
        exit 1
    fi
    log_info "Flutter: $(flutter --version 2>/dev/null | head -1 || echo 'installed')"
    
    # Accept licenses
    yes | flutter doctor --android-licenses 2>/dev/null || true
}

check_python_protobuf() {
    local python_cmd=""
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
            if command -v python &>/dev/null; then
                python_cmd="python"
            elif command -v py &>/dev/null; then
                python_cmd="py -3"
            elif command -v python3 &>/dev/null; then
                python_cmd="python3"
            else
                log_error "Python 3 is not installed."
                log_error "Install Python 3 to run CoMaps build tools (protobuf required)."
                exit 1
            fi
            ;;
        *)
            if command -v python3 &>/dev/null; then
                python_cmd="python3"
            elif command -v python &>/dev/null; then
                python_cmd="python"
            elif command -v py &>/dev/null; then
                python_cmd="py -3"
            else
                log_error "Python 3 is not installed."
                log_error "Install Python 3 to run CoMaps build tools (protobuf required)."
                exit 1
            fi
            ;;
    esac

    if ! $python_cmd -c "import google.protobuf" &>/dev/null; then
        log_error "Python 'protobuf' module is not installed."
        case "$(uname -s)" in
            Darwin)
                log_error "Install: python3 -m pip install --user protobuf"
                ;;
            Linux)
                log_error "Install: sudo apt-get install -y python3-protobuf (or python3 -m pip install --user protobuf)"
                ;;
            MINGW*|MSYS*|CYGWIN*)
                log_error "Install: python -m pip install --user protobuf (or py -3 -m pip install --user protobuf)"
                ;;
            *)
                log_error "Install: python3 -m pip install --user protobuf"
                ;;
        esac
        exit 1
    fi
}

check_dependencies() {
    log_header "Checking Dependencies"
    check_dart
    check_flutter
    check_python_protobuf
    log_success "Dependencies check passed"
}

# ============================================================================
# Download MWM files using Dart tool
# ============================================================================

download_base_mwms() {
    log_header "Downloading Base MWM Files"
    
    local maps_dir="$ROOT_DIR/example/assets/maps"
    
    # Use the Dart map downloader tool
    log_step "Running Dart map downloader..."
    pushd "$ROOT_DIR" >/dev/null
    dart run tool/map_downloader.dart \
        --output-dir "$maps_dir" \
        --files "World.mwm,WorldCoasts.mwm,Gibraltar.mwm" \
        --report "$maps_dir/download_report.json" \
        --verbose
    popd >/dev/null
    
    # Copy ICU data if available
    local icu_source="$ROOT_DIR/thirdparty/comaps/data/icudt75l.dat"
    local icu_dest="$maps_dir/icudt75l.dat"
    if [[ -f "$icu_source" ]] && [[ ! -f "$icu_dest" ]]; then
        cp "$icu_source" "$icu_dest"
        log_info "Copied ICU data to assets/maps/"
    fi
    
    log_success "Base MWM files ready"
}

# ============================================================================
# Flutter setup
# ============================================================================

setup_flutter() {
    log_header "Setting Up Flutter"
    
    pushd "$ROOT_DIR" >/dev/null
    flutter pub get
    popd >/dev/null
    
    pushd "$ROOT_DIR/example" >/dev/null
    flutter pub get
    popd >/dev/null
    
    log_success "Flutter dependencies installed"
}

# ============================================================================
# Build Flutter apps
# ============================================================================

build_flutter_apps() {
    log_header "Building Flutter Example Apps"
    
    pushd "$ROOT_DIR/example" >/dev/null
    
    # Build Android
    log_step "Building Android APK..."
    flutter build apk --release || log_warn "Android build failed"
    
    # Build iOS (if on macOS)
    if [[ "$(uname -s)" == "Darwin" ]]; then
        log_step "Building iOS app (simulator, debug)..."
        # Note: iOS simulator does not support release mode
        flutter build ios --simulator --debug || log_warn "iOS build failed"
        
        log_step "Building macOS app..."
        flutter build macos --release || log_warn "macOS build failed"
    fi
    
    # Build Linux (if on Linux)
    if [[ "$(uname -s)" == "Linux" ]]; then
        log_step "Building Linux app..."
        flutter build linux --release || log_warn "Linux build failed"
    fi
    
    popd >/dev/null
    
    log_success "Flutter apps built"
}

# ============================================================================
# Main
# ============================================================================

print_banner() {
    echo ""
    echo "========================================="
    echo "agus_maps_flutter - Build All"
    echo "========================================="
    echo ""
    local platform="$(uname -s)"
    echo "Platform: $platform"
    echo ""
    echo "This script uses Dart hooks (tool/build.dart) for:"
    echo "  - Bootstrap (CoMaps, patches, Boost, data)"
    echo "  - Native binary building (all platforms supported on $platform)"
    echo "  - Metal shader compilation (iOS/macOS only)"
    echo "  - CocoaPods setup (iOS/macOS only)"
    echo ""
    case "$platform" in
        Darwin)
            echo "Targets: Android, iOS, macOS"
            ;;
        Linux)
            echo "Targets: Android, Linux"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            echo "Targets: Android"
            ;;
        *)
            echo "Targets: Android (and platform-specific if supported)"
            ;;
    esac
    echo ""
}

print_summary() {
    echo ""
    echo "========================================="
    echo "BUILD COMPLETE"
    echo "========================================="
    echo ""
    local platform="$(uname -s)"
    
    echo "Native binaries (built for $platform):"
    case "$platform" in
        Darwin)
            echo "  - Android: android/prebuilt/"
            echo "  - iOS:     ios/Frameworks/"
            echo "  - macOS:   macos/Frameworks/"
            ;;
        Linux)
            echo "  - Android: android/prebuilt/"
            echo "  - Linux:   linux/prebuilt/"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            echo "  - Android: android/prebuilt/"
            ;;
        *)
            echo "  - Android: android/prebuilt/"
            ;;
    esac
    echo ""
    
    echo "Flutter apps:"
    echo "  - Android: example/build/app/outputs/flutter-apk/app-release.apk"
    case "$platform" in
        Darwin)
            echo "  - iOS:     example/build/ios/iphonesimulator/Runner.app"
            echo "  - macOS:   example/build/macos/Build/Products/Release/agus_maps_flutter_example.app"
            ;;
        Linux)
            echo "  - Linux:   example/build/linux/x64/release/bundle/"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            :
            ;;
    esac
    echo ""
    
    echo "To run the example app:"
    echo "  cd example"
    echo "  flutter run -d <device>"
    echo ""
}

main() {
    print_banner
    
    # Platform check
    check_platform
    
    # Check dependencies
    check_dependencies
    
    # Setup Flutter (early to fail fast)
    setup_flutter
    
    # Download MWM files (uses Dart tool)
    download_base_mwms
    
    # Build native binaries using Dart hooks
    # This handles: bootstrap, building binaries, Metal shaders, CocoaPods
    # Dart tool automatically builds all default platforms for current OS
    log_header "Building Native Binaries (Dart Hooks)"
    
    export AGUS_MAPS_BUILD_MODE=contributor
    
    # Build all default platforms for current OS (no --platform flags = use defaults)
    log_step "Building native binaries for all supported platforms on $(uname -s)..."
    dart run tool/build.dart --build-binaries
    
    log_success "Native binaries built"
    
    # Build Flutter apps
    build_flutter_apps
    
    print_summary
}

# Run
main "$@"
