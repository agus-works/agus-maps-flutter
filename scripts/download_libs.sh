#!/usr/bin/env bash
set -euo pipefail

# Download CoMaps pre-built libraries and headers from GitHub Releases
#
# This script downloads pre-built native libraries for the specified platform
# and shared headers. It's called by build systems (CocoaPods, Gradle) to
# fetch dependencies for external consumers.
#
# Usage:
#   ./download_libs.sh <platform>
#   ./download_libs.sh ios
#   ./download_libs.sh android
#
# DUAL-MODE DETECTION:
#   - In-repo (example app): .git exists AND thirdparty/comaps exists
#     → Skip download, use local thirdparty headers
#   - External consumer: No .git or no thirdparty/comaps
#     → Download from GitHub Releases, fail loudly on error
#
# Environment variables:
#   LIBS_VERSION: Version tag to download (default: from pubspec.yaml)
#   GITHUB_REPO: Repository URL (default: bangonkali/agus-maps-flutter)
#   FORCE_DOWNLOAD: Set to "true" to force re-download even if files exist
#
# Output (iOS):
#   ios/Frameworks/CoMaps.xcframework
#   ios/Headers/comaps/  (external consumers only)
#
# Output (Android):
#   android/prebuilt/<abi>/*.a
#   android/headers/comaps/  (external consumers only)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GITHUB_REPO="${GITHUB_REPO:-bangonkali/agus-maps-flutter}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Show usage
usage() {
    echo "Usage: $0 <platform>"
    echo ""
    echo "Platforms:"
    echo "  ios      Download iOS XCFramework and headers"
    echo "  android  Download Android static libraries and headers"
    echo ""
    echo "Environment variables:"
    echo "  LIBS_VERSION    Version tag to download (default: from pubspec.yaml)"
    echo "  GITHUB_REPO     Repository URL (default: bangonkali/agus-maps-flutter)"
    echo "  FORCE_DOWNLOAD  Set to 'true' to force re-download"
    exit 1
}

# Check if we're in the plugin repository (in-repo build)
# Returns 0 (true) if in-repo, 1 (false) if external consumer
is_in_repo() {
    if [[ -d "$ROOT_DIR/.git" && -d "$ROOT_DIR/thirdparty/comaps" ]]; then
        return 0
    fi
    return 1
}

# Get version from pubspec.yaml if not specified
get_version() {
    if [[ -n "${LIBS_VERSION:-}" ]]; then
        echo "$LIBS_VERSION"
        return
    fi
    
    local pubspec="$ROOT_DIR/pubspec.yaml"
    if [[ -f "$pubspec" ]]; then
        local version
        version=$(grep "^version:" "$pubspec" | sed 's/version: //' | tr -d '[:space:]')
        if [[ -n "$version" ]]; then
            echo "v$version"
            return
        fi
    fi
    
    log_warn "Could not determine version, using 'latest'"
    echo "latest"
}

# Download a file from GitHub Releases
download_file() {
    local version=$1
    local filename=$2
    local output_path=$3
    local download_url
    
    if [[ "$version" == "latest" ]]; then
        download_url="https://github.com/$GITHUB_REPO/releases/latest/download/$filename"
    else
        download_url="https://github.com/$GITHUB_REPO/releases/download/$version/$filename"
    fi
    
    log_info "Downloading $filename ($version)..."
    log_info "URL: $download_url"
    
    mkdir -p "$(dirname "$output_path")"
    
    if ! curl -L -f -o "$output_path" "$download_url"; then
        log_error "========================================="
        log_error "FATAL: Failed to download $filename"
        log_error "========================================="
        log_error ""
        log_error "URL: $download_url"
        log_error ""
        log_error "Please ensure:"
        log_error "  1. Version $version exists as a GitHub Release"
        log_error "  2. The release contains $filename"
        log_error "  3. You have network access to github.com"
        log_error ""
        log_error "Repository: https://github.com/$GITHUB_REPO/releases"
        log_error "========================================="
        exit 1
    fi
    
    log_info "Download complete: $(du -h "$output_path" | cut -f1)"
}

# ============================================================================
# iOS Platform Functions
# ============================================================================

setup_ios_paths() {
    IOS_OUTPUT_DIR="$ROOT_DIR/ios/Frameworks"
    IOS_HEADERS_DIR="$ROOT_DIR/ios/Headers"
    IOS_XCFRAMEWORK_PATH="$IOS_OUTPUT_DIR/CoMaps.xcframework"
    IOS_XCFRAMEWORK_ZIP="$IOS_OUTPUT_DIR/agus-binaries-ios.zip"
    IOS_HEADERS_TAR="$IOS_HEADERS_DIR/agus-headers.tar.gz"
}

download_ios_binaries() {
    local version=$1
    download_file "$version" "agus-binaries-ios.zip" "$IOS_XCFRAMEWORK_ZIP"
}

download_ios_headers() {
    local version=$1
    download_file "$version" "agus-headers.tar.gz" "$IOS_HEADERS_TAR"
}

extract_ios_binaries() {
    log_info "Extracting iOS XCFramework..."
    
    rm -rf "$IOS_XCFRAMEWORK_PATH"
    unzip -q -o "$IOS_XCFRAMEWORK_ZIP" -d "$IOS_OUTPUT_DIR"
    rm -f "$IOS_XCFRAMEWORK_ZIP"
    
    if [[ ! -d "$IOS_XCFRAMEWORK_PATH" ]]; then
        log_error "XCFramework extraction failed - directory not found"
        exit 1
    fi
    
    log_info "Extracted to: $IOS_XCFRAMEWORK_PATH"
}

extract_ios_headers() {
    log_info "Extracting headers..."
    
    find "$IOS_HEADERS_DIR" -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} \; 2>/dev/null || true
    tar -xzf "$IOS_HEADERS_TAR" -C "$IOS_HEADERS_DIR"
    rm -f "$IOS_HEADERS_TAR"
    
    if [[ ! -d "$IOS_HEADERS_DIR/comaps" ]]; then
        log_error "Headers extraction failed - comaps directory not found"
        exit 1
    fi
    
    log_info "Extracted to: $IOS_HEADERS_DIR/comaps"
}

check_existing_ios_binaries() {
    if [[ -d "$IOS_XCFRAMEWORK_PATH" && -f "$IOS_XCFRAMEWORK_PATH/Info.plist" ]]; then
        if [[ "${FORCE_DOWNLOAD:-}" != "true" ]]; then
            log_info "XCFramework already exists at $IOS_XCFRAMEWORK_PATH"
            return 0
        fi
        log_info "Force download requested, re-downloading..."
    fi
    return 1
}

check_existing_ios_headers() {
    if [[ -d "$IOS_HEADERS_DIR/comaps" ]]; then
        if [[ "${FORCE_DOWNLOAD:-}" != "true" ]]; then
            log_info "Headers already exist at $IOS_HEADERS_DIR/comaps"
            return 0
        fi
        log_info "Force download requested, re-downloading..."
    fi
    return 1
}

main_ios_in_repo() {
    log_info "========================================="
    log_info "CoMaps iOS Setup (In-Repo Build)"
    log_info "========================================="
    log_info ""
    log_info "Detected in-repo development environment."
    log_info "Using local thirdparty headers from:"
    log_info "  $ROOT_DIR/thirdparty/comaps"
    log_info ""
    
    setup_ios_paths
    
    if check_existing_ios_binaries; then
        log_info "XCFramework ready!"
    else
        local version
        version=$(get_version)
        log_info "Attempting to download XCFramework ($version)..."
        download_ios_binaries "$version"
        extract_ios_binaries
    fi
    
    log_info "========================================="
    log_info "In-repo iOS setup complete!"
    log_info "========================================="
}

main_ios_external() {
    log_info "========================================="
    log_info "CoMaps iOS Setup (External Consumer)"
    log_info "========================================="
    
    setup_ios_paths
    
    local version
    version=$(get_version)
    log_info "Plugin version: $version"
    
    local needs_binaries=false
    local needs_headers=false
    
    if ! check_existing_ios_binaries; then
        needs_binaries=true
    fi
    
    if ! check_existing_ios_headers; then
        needs_headers=true
    fi
    
    if [[ "$needs_binaries" == "true" ]]; then
        download_ios_binaries "$version"
        extract_ios_binaries
    fi
    
    if [[ "$needs_headers" == "true" ]]; then
        download_ios_headers "$version"
        extract_ios_headers
    fi
    
    log_info "========================================="
    log_info "External consumer iOS setup complete!"
    log_info "========================================="
}

# ============================================================================
# Android Platform Functions
# ============================================================================

setup_android_paths() {
    ANDROID_PREBUILT_DIR="$ROOT_DIR/android/prebuilt"
    ANDROID_HEADERS_DIR="$ROOT_DIR/android/headers"
    ANDROID_BINARIES_ZIP="$ANDROID_PREBUILT_DIR/agus-binaries-android.zip"
    ANDROID_HEADERS_TAR="$ANDROID_HEADERS_DIR/agus-headers.tar.gz"
}

download_android_binaries() {
    local version=$1
    download_file "$version" "agus-binaries-android.zip" "$ANDROID_BINARIES_ZIP"
}

download_android_headers() {
    local version=$1
    download_file "$version" "agus-headers.tar.gz" "$ANDROID_HEADERS_TAR"
}

extract_android_binaries() {
    log_info "Extracting Android binaries..."
    
    # Remove existing prebuilt libs (except the zip)
    find "$ANDROID_PREBUILT_DIR" -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} \; 2>/dev/null || true
    
    unzip -q -o "$ANDROID_BINARIES_ZIP" -d "$ANDROID_PREBUILT_DIR"
    rm -f "$ANDROID_BINARIES_ZIP"
    
    # Verify extraction - check for at least one ABI directory
    if [[ ! -d "$ANDROID_PREBUILT_DIR/arm64-v8a" && ! -d "$ANDROID_PREBUILT_DIR/agus-binaries-android/arm64-v8a" ]]; then
        log_error "Android binaries extraction failed - ABI directories not found"
        exit 1
    fi
    
    # If extracted with subdirectory, move contents up
    if [[ -d "$ANDROID_PREBUILT_DIR/agus-binaries-android" ]]; then
        mv "$ANDROID_PREBUILT_DIR/agus-binaries-android"/* "$ANDROID_PREBUILT_DIR/"
        rmdir "$ANDROID_PREBUILT_DIR/agus-binaries-android"
    fi
    
    log_info "Extracted to: $ANDROID_PREBUILT_DIR"
}

extract_android_headers() {
    log_info "Extracting headers..."
    
    find "$ANDROID_HEADERS_DIR" -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} \; 2>/dev/null || true
    tar -xzf "$ANDROID_HEADERS_TAR" -C "$ANDROID_HEADERS_DIR"
    rm -f "$ANDROID_HEADERS_TAR"
    
    if [[ ! -d "$ANDROID_HEADERS_DIR/comaps" ]]; then
        log_error "Headers extraction failed - comaps directory not found"
        exit 1
    fi
    
    log_info "Extracted to: $ANDROID_HEADERS_DIR/comaps"
}

check_existing_android_binaries() {
    if [[ -d "$ANDROID_PREBUILT_DIR/arm64-v8a" ]]; then
        if [[ "${FORCE_DOWNLOAD:-}" != "true" ]]; then
            log_info "Android binaries already exist at $ANDROID_PREBUILT_DIR"
            return 0
        fi
        log_info "Force download requested, re-downloading..."
    fi
    return 1
}

check_existing_android_headers() {
    if [[ -d "$ANDROID_HEADERS_DIR/comaps" ]]; then
        if [[ "${FORCE_DOWNLOAD:-}" != "true" ]]; then
            log_info "Headers already exist at $ANDROID_HEADERS_DIR/comaps"
            return 0
        fi
        log_info "Force download requested, re-downloading..."
    fi
    return 1
}

main_android_in_repo() {
    log_info "========================================="
    log_info "CoMaps Android Setup (In-Repo Build)"
    log_info "========================================="
    log_info ""
    log_info "Detected in-repo development environment."
    log_info "Building from source using:"
    log_info "  $ROOT_DIR/thirdparty/comaps"
    log_info ""
    log_info "========================================="
    log_info "In-repo Android setup complete!"
    log_info "========================================="
}

main_android_external() {
    log_info "========================================="
    log_info "CoMaps Android Setup (External Consumer)"
    log_info "========================================="
    
    setup_android_paths
    mkdir -p "$ANDROID_PREBUILT_DIR"
    mkdir -p "$ANDROID_HEADERS_DIR"
    
    local version
    version=$(get_version)
    log_info "Plugin version: $version"
    
    local needs_binaries=false
    local needs_headers=false
    
    if ! check_existing_android_binaries; then
        needs_binaries=true
    fi
    
    if ! check_existing_android_headers; then
        needs_headers=true
    fi
    
    if [[ "$needs_binaries" == "true" ]]; then
        download_android_binaries "$version"
        extract_android_binaries
    fi
    
    if [[ "$needs_headers" == "true" ]]; then
        download_android_headers "$version"
        extract_android_headers
    fi
    
    log_info "========================================="
    log_info "External consumer Android setup complete!"
    log_info "========================================="
}

# ============================================================================
# Main Entry Point
# ============================================================================

main() {
    local platform="${1:-}"
    
    if [[ -z "$platform" ]]; then
        usage
    fi
    
    case "$platform" in
        ios)
            if is_in_repo; then
                main_ios_in_repo
            else
                main_ios_external
            fi
            ;;
        android)
            if is_in_repo; then
                main_android_in_repo
            else
                main_android_external
            fi
            ;;
        *)
            log_error "Unknown platform: $platform"
            usage
            ;;
    esac
}

main "$@"

