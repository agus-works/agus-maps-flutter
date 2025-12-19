#!/usr/bin/env bash
set -euo pipefail

# Regenerates patch files from the current state of ./thirdparty/comaps.
#
# This script creates individual patch files for each modified file, preserving
# the original patch naming convention where possible.
#
# Usage:
#   ./scripts/regenerate_patches.sh [--dry-run]
#
# Options:
#   --dry-run    Show what would be done without actually creating patches

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMAPS_DIR="$ROOT_DIR/thirdparty/comaps"
PATCH_DIR="$ROOT_DIR/patches/comaps"
DRY_RUN=false

# Color output helpers
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

usage() {
    echo "Usage: $0 [--dry-run]"
    echo ""
    echo "Regenerates patch files from current thirdparty/comaps modifications."
    echo ""
    echo "Options:"
    echo "  --dry-run    Show what would be done without creating patches"
    echo "  --help       Show this help message"
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

if [[ ! -d "$COMAPS_DIR/.git" ]]; then
    log_error "CoMaps checkout not found at $COMAPS_DIR"
    exit 1
fi

cd "$COMAPS_DIR"

# Check for modifications
MODIFIED_FILES=$(git diff --name-only)
if [[ -z "$MODIFIED_FILES" ]]; then
    log_success "No modifications found in thirdparty/comaps"
    exit 0
fi

log_info "Modified files:"
echo "$MODIFIED_FILES" | while read -r file; do
    echo "  - $file"
done
echo ""

# Define file-to-patch mappings based on existing convention
# This allows the script to update existing patches rather than create new ones
get_patch_for_file() {
    local file="$1"
    case "$file" in
        "CMakeLists.txt") echo "0001-fix-cmake.patch" ;;
        "libs/platform/platform_android.cpp") echo "0002-platform-directory-resources.patch" ;;
        "libs/indexer/transliteration_loader.cpp") echo "0003-transliteration-directory-resources.patch" ;;
        "libs/drape/gl_functions.cpp") echo "0004-fix-android-gl-function-pointers.patch" ;;
        *) echo "" ;;
    esac
}

# Track new files that need patches
NEW_PATCH_NUM=5
TIMESTAMP=$(date +%Y%m%d)

if $DRY_RUN; then
    log_info "=== DRY RUN - No changes will be made ==="
    echo ""
fi

# Process each modified file
while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    
    existing_patch=$(get_patch_for_file "$file")
    
    if [[ -n "$existing_patch" ]]; then
        # Known file - update existing patch
        patch_file="$existing_patch"
        log_info "Would update existing patch: $patch_file <- $file"
    else
        # New file - needs new patch
        # Generate a sensible name based on the file path
        safe_name=$(echo "$file" | sed 's/[\/\.]/-/g' | sed 's/--*/-/g')
        patch_file=$(printf "%04d-%s.patch" $NEW_PATCH_NUM "$safe_name")
        log_warning "Would create NEW patch: $patch_file <- $file"
        NEW_PATCH_NUM=$((NEW_PATCH_NUM + 1))
    fi
    
    if ! $DRY_RUN; then
        # Generate the patch for this file
        git diff "$file" > "$PATCH_DIR/$patch_file.new"
        
        if [[ -s "$PATCH_DIR/$patch_file.new" ]]; then
            mv "$PATCH_DIR/$patch_file.new" "$PATCH_DIR/$patch_file"
            log_success "Generated: $patch_file"
        else
            rm -f "$PATCH_DIR/$patch_file.new"
            log_warning "No diff output for: $file (skipped)"
        fi
    fi
done <<< "$MODIFIED_FILES"

echo ""

if $DRY_RUN; then
    log_info "Run without --dry-run to actually generate patches"
else
    log_success "Patches regenerated successfully"
    log_info "Review the changes with: git -C $PATCH_DIR diff"
    log_info "Don't forget to update $PATCH_DIR/README.md"
fi

# Show combined patch that can be used for all-in-one application
echo ""
log_info "To generate a single combined patch instead:"
echo "  cd $COMAPS_DIR && git diff > $PATCH_DIR/all-changes.patch"
