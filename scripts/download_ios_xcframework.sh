#!/usr/bin/env bash
set -euo pipefail

# Download CoMaps XCFramework from GitHub Releases
#
# This script is called by the podspec's prepare_command to download
# the pre-built CoMaps XCFramework before pod install.
#
# Environment variables:
#   XCFRAMEWORK_VERSION: Version tag to download (default: from pubspec.yaml)
#   GITHUB_REPO: Repository URL (default: bangonkali/agus-maps-flutter)
#
# Output:
#   ios/Frameworks/CoMaps.xcframework

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/ios/Frameworks"
XCFRAMEWORK_PATH="$OUTPUT_DIR/CoMaps.xcframework"
XCFRAMEWORK_ZIP="$OUTPUT_DIR/CoMaps.xcframework.zip"

GITHUB_REPO="${GITHUB_REPO:-bangonkali/agus-maps-flutter}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

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
        log_error "Failed to download XCFramework from $download_url"
        log_error "Make sure the release exists and contains CoMaps.xcframework.zip"
        exit 1
    fi
    
    log_info "Download complete: $(du -h "$XCFRAMEWORK_ZIP" | cut -f1)"
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

# Check if XCFramework already exists and is valid
check_existing() {
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

# Main
main() {
    log_info "========================================="
    log_info "CoMaps XCFramework Download"
    log_info "========================================="
    
    # Check if already exists
    if check_existing; then
        log_info "Using existing XCFramework"
        exit 0
    fi
    
    # Get version
    local version
    version=$(get_version)
    log_info "Version: $version"
    
    # Download and extract
    download_xcframework "$version"
    extract_xcframework
    
    log_info "========================================="
    log_info "XCFramework ready!"
    log_info "========================================="
}

main "$@"
