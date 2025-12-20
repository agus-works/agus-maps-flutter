#!/usr/bin/env bash
set -euo pipefail

# Download CoMaps XCFramework and Headers from GitHub Releases
#
# This script is called by the podspec's prepare_command to download
# the pre-built CoMaps XCFramework and headers before pod install.
#
# DUAL-MODE DETECTION:
#   - In-repo (example app): .git exists AND thirdparty/comaps exists
#     → Skip download, use local thirdparty headers
#   - External consumer: No .git or no thirdparty/comaps
#     → Download from GitHub Releases, fail loudly on error
#
# Environment variables:
#   XCFRAMEWORK_VERSION: Version tag to download (default: from pubspec.yaml)
#   GITHUB_REPO: Repository URL (default: bangonkali/agus-maps-flutter)
#   FORCE_DOWNLOAD: Set to "true" to force re-download even if files exist
#
# Output:
#   ios/Frameworks/CoMaps.xcframework
#   ios/Headers/comaps/  (external consumers only)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/ios/Frameworks"
HEADERS_DIR="$ROOT_DIR/ios/Headers"
XCFRAMEWORK_PATH="$OUTPUT_DIR/CoMaps.xcframework"
XCFRAMEWORK_ZIP="$OUTPUT_DIR/CoMaps.xcframework.zip"
HEADERS_TAR="$HEADERS_DIR/CoMaps-headers.tar.gz"

GITHUB_REPO="${GITHUB_REPO:-bangonkali/agus-maps-flutter}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if we're in the plugin repository (in-repo build)
# Returns 0 (true) if in-repo, 1 (false) if external consumer
is_in_repo() {
    # In-repo detection: .git exists AND thirdparty/comaps exists
    if [[ -d "$ROOT_DIR/.git" && -d "$ROOT_DIR/thirdparty/comaps" ]]; then
        return 0
    fi
    return 1
}

# Get version from pubspec.yaml if not specified
get_version() {
    if [[ -n "${XCFRAMEWORK_VERSION:-}" ]]; then
        echo "$XCFRAMEWORK_VERSION"
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
    
    # Fallback to latest
    log_warn "Could not determine version, using 'latest'"
    echo "latest"
}

# Download XCFramework from GitHub Releases
download_xcframework() {
    local version=$1
    local download_url
    
    if [[ "$version" == "latest" ]]; then
        download_url="https://github.com/$GITHUB_REPO/releases/latest/download/CoMaps.xcframework.zip"
    else
        download_url="https://github.com/$GITHUB_REPO/releases/download/$version/CoMaps.xcframework.zip"
    fi
    
    log_info "Downloading CoMaps.xcframework ($version)..."
    log_info "URL: $download_url"
    
    mkdir -p "$OUTPUT_DIR"
    
    # Download with curl (follow redirects, fail on error)
    if ! curl -L -f -o "$XCFRAMEWORK_ZIP" "$download_url"; then
        log_error "========================================="
        log_error "FATAL: Failed to download XCFramework"
        log_error "========================================="
        log_error ""
        log_error "URL: $download_url"
        log_error ""
        log_error "This plugin requires pre-built native libraries."
        log_error "Please ensure:"
        log_error "  1. Version $version exists as a GitHub Release"
        log_error "  2. The release contains CoMaps.xcframework.zip"
        log_error "  3. You have network access to github.com"
        log_error ""
        log_error "Repository: https://github.com/$GITHUB_REPO/releases"
        log_error "========================================="
        exit 1
    fi
    
    log_info "Download complete: $(du -h "$XCFRAMEWORK_ZIP" | cut -f1)"
}

# Download headers tarball from GitHub Releases
download_headers() {
    local version=$1
    local download_url
    
    if [[ "$version" == "latest" ]]; then
        download_url="https://github.com/$GITHUB_REPO/releases/latest/download/CoMaps-headers.tar.gz"
    else
        download_url="https://github.com/$GITHUB_REPO/releases/download/$version/CoMaps-headers.tar.gz"
    fi
    
    log_info "Downloading CoMaps-headers.tar.gz ($version)..."
    log_info "URL: $download_url"
    
    mkdir -p "$HEADERS_DIR"
    
    # Download with curl (follow redirects, fail on error)
    if ! curl -L -f -o "$HEADERS_TAR" "$download_url"; then
        log_error "========================================="
        log_error "FATAL: Failed to download headers"
        log_error "========================================="
        log_error ""
        log_error "URL: $download_url"
        log_error ""
        log_error "This plugin requires header files for compilation."
        log_error "Please ensure:"
        log_error "  1. Version $version exists as a GitHub Release"
        log_error "  2. The release contains CoMaps-headers.tar.gz"
        log_error "  3. You have network access to github.com"
        log_error ""
        log_error "Repository: https://github.com/$GITHUB_REPO/releases"
        log_error "========================================="
        exit 1
    fi
    
    log_info "Download complete: $(du -h "$HEADERS_TAR" | cut -f1)"
}

# Extract XCFramework
extract_xcframework() {
    log_info "Extracting XCFramework..."
    
    # Remove existing XCFramework
    rm -rf "$XCFRAMEWORK_PATH"
    
    # Extract
    unzip -q -o "$XCFRAMEWORK_ZIP" -d "$OUTPUT_DIR"
    
    # Clean up zip
    rm -f "$XCFRAMEWORK_ZIP"
    
    # Verify extraction
    if [[ ! -d "$XCFRAMEWORK_PATH" ]]; then
        log_error "XCFramework extraction failed - directory not found"
        exit 1
    fi
    
    log_info "Extracted to: $XCFRAMEWORK_PATH"
}

# Extract headers tarball
extract_headers() {
    log_info "Extracting headers..."
    
    # Remove existing headers (except the tarball itself)
    find "$HEADERS_DIR" -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} \; 2>/dev/null || true
    
    # Extract tarball (contains 'comaps/' directory)
    tar -xzf "$HEADERS_TAR" -C "$HEADERS_DIR"
    
    # Clean up tarball
    rm -f "$HEADERS_TAR"
    
    # Verify extraction
    if [[ ! -d "$HEADERS_DIR/comaps" ]]; then
        log_error "Headers extraction failed - comaps directory not found"
        exit 1
    fi
    
    log_info "Extracted to: $HEADERS_DIR/comaps"
}

# Check if XCFramework already exists and is valid
check_existing_xcframework() {
    if [[ -d "$XCFRAMEWORK_PATH" ]]; then
        # Check if it has the expected structure
        if [[ -f "$XCFRAMEWORK_PATH/Info.plist" ]]; then
            log_info "XCFramework already exists at $XCFRAMEWORK_PATH"
            
            # Check if force download is requested
            if [[ "${FORCE_DOWNLOAD:-}" == "true" ]]; then
                log_info "Force download requested, re-downloading..."
                return 1
            fi
            
            return 0
        fi
    fi
    return 1
}

# Check if headers already exist
check_existing_headers() {
    if [[ -d "$HEADERS_DIR/comaps" ]]; then
        log_info "Headers already exist at $HEADERS_DIR/comaps"
        
        # Check if force download is requested
        if [[ "${FORCE_DOWNLOAD:-}" == "true" ]]; then
            log_info "Force download requested, re-downloading..."
            return 1
        fi
        
        return 0
    fi
    return 1
}

# Main for in-repo builds (example app)
main_in_repo() {
    log_info "========================================="
    log_info "CoMaps iOS Setup (In-Repo Build)"
    log_info "========================================="
    log_info ""
    log_info "Detected in-repo development environment."
    log_info "Using local thirdparty headers from:"
    log_info "  $ROOT_DIR/thirdparty/comaps"
    log_info ""
    
    # Still need to check for XCFramework
    if check_existing_xcframework; then
        log_info "XCFramework ready!"
    else
        log_warn "XCFramework not found at $XCFRAMEWORK_PATH"
        log_warn ""
        log_warn "For in-repo builds, you can either:"
        log_warn "  1. Build locally: ./scripts/build_ios_xcframework.sh"
        log_warn "  2. Download: FORCE_DOWNLOAD=true ./scripts/download_ios_xcframework.sh"
        log_warn ""
        
        # For CI or convenience, attempt download
        local version
        version=$(get_version)
        log_info "Attempting to download XCFramework ($version)..."
        download_xcframework "$version"
        extract_xcframework
    fi
    
    log_info "========================================="
    log_info "In-repo setup complete!"
    log_info "========================================="
}

# Main for external consumers (pub.dev, git dependency)
main_external() {
    log_info "========================================="
    log_info "CoMaps iOS Setup (External Consumer)"
    log_info "========================================="
    log_info ""
    log_info "Installing agus_maps_flutter plugin..."
    log_info ""
    
    # Get version
    local version
    version=$(get_version)
    log_info "Plugin version: $version"
    
    local needs_xcframework=false
    local needs_headers=false
    
    # Check what needs to be downloaded
    if ! check_existing_xcframework; then
        needs_xcframework=true
    fi
    
    if ! check_existing_headers; then
        needs_headers=true
    fi
    
    # Download and extract as needed
    if [[ "$needs_xcframework" == "true" ]]; then
        download_xcframework "$version"
        extract_xcframework
    fi
    
    if [[ "$needs_headers" == "true" ]]; then
        download_headers "$version"
        extract_headers
    fi
    
    log_info "========================================="
    log_info "External consumer setup complete!"
    log_info "========================================="
}

# Entry point
main() {
    if is_in_repo; then
        main_in_repo
    else
        main_external
    fi
}

main "$@"

