#!/usr/bin/env bash
set -euo pipefail

# Validates that patches in ./patches/comaps accurately capture all modifications
# currently applied to ./thirdparty/comaps.
#
# This script:
# 1. Creates a temporary clean clone of CoMaps at the same tag
# 2. Applies all patches from ./patches/comaps
# 3. Compares the patched state with the current ./thirdparty/comaps
# 4. Reports any differences (files modified but not covered by patches, or
#    patches that don't match current modifications)
#
# Usage:
#   ./scripts/validate_patches.sh [--update-patches]
#
# Options:
#   --update-patches    Generate new patch files for any differences found

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMAPS_DIR="$ROOT_DIR/thirdparty/comaps"
PATCH_DIR="$ROOT_DIR/patches/comaps"
TEMP_DIR=""
UPDATE_PATCHES=false

# Color output helpers
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

cleanup() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        log_info "Cleaning up temporary directory..."
        rm -rf "$TEMP_DIR"
    fi
}

trap cleanup EXIT

usage() {
    echo "Usage: $0 [--update-patches]"
    echo ""
    echo "Validates that patches accurately capture all modifications to thirdparty/comaps."
    echo ""
    echo "Options:"
    echo "  --update-patches    Generate new patch files for any differences found"
    echo "  --help              Show this help message"
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --update-patches)
            UPDATE_PATCHES=true
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

# Check prerequisites
if [[ ! -d "$COMAPS_DIR/.git" ]]; then
    log_error "CoMaps checkout not found at $COMAPS_DIR"
    log_error "Run: ./scripts/fetch_comaps.sh"
    exit 1
fi

# Get the current CoMaps tag/commit
cd "$COMAPS_DIR"
COMAPS_TAG=$(git describe --tags --always 2>/dev/null || git rev-parse --short HEAD)
COMAPS_REMOTE=$(git remote get-url origin)
log_info "Current CoMaps version: $COMAPS_TAG"
log_info "CoMaps remote: $COMAPS_REMOTE"

# Get list of modified files in current checkout
CURRENT_MODIFIED_FILES=$(git diff --name-only)
if [[ -z "$CURRENT_MODIFIED_FILES" ]]; then
    log_success "No modifications in thirdparty/comaps - nothing to validate"
    exit 0
fi

log_info "Modified files in current checkout:"
echo "$CURRENT_MODIFIED_FILES" | while read -r file; do
    echo "  - $file"
done

# Create temporary directory for clean checkout
TEMP_DIR=$(mktemp -d)
TEMP_COMAPS_DIR="$TEMP_DIR/comaps"
log_info "Creating temporary clean checkout at $TEMP_DIR..."

# Clone CoMaps at the same tag
cd "$TEMP_DIR"
git clone --depth 1 --branch "$COMAPS_TAG" "$COMAPS_REMOTE" comaps 2>/dev/null || \
    git clone --depth 1 "$COMAPS_REMOTE" comaps

cd "$TEMP_COMAPS_DIR"

# Apply all patches to the clean checkout
log_info "Applying patches to clean checkout..."
shopt -s nullglob
PATCHES=("$PATCH_DIR"/*.patch)
PATCH_FAILED=false

if [[ ${#PATCHES[@]} -eq 0 ]]; then
    log_warning "No patches found in $PATCH_DIR"
else
    for patch in "${PATCHES[@]}"; do
        patch_name=$(basename "$patch")
        # First try --check to validate, then apply
        if git apply --check "$patch" 2>/dev/null; then
            if git apply --whitespace=nowarn "$patch" 2>/dev/null; then
                log_success "Applied: $patch_name"
            else
                log_error "Failed to apply (after check passed): $patch_name"
                PATCH_FAILED=true
            fi
        else
            log_error "Failed validation: $patch_name"
            # Show the actual error
            git apply --check "$patch" 2>&1 | head -5 | sed 's/^/    /'
            PATCH_FAILED=true
        fi
    done
fi

if $PATCH_FAILED; then
    log_error "Some patches failed to apply - patches may need updating for current CoMaps version"
fi

# Get list of modified files after applying patches
PATCHED_MODIFIED_FILES=$(git diff --name-only)
log_info "Files modified by patches:"
if [[ -z "$PATCHED_MODIFIED_FILES" ]]; then
    echo "  (none)"
else
    echo "$PATCHED_MODIFIED_FILES" | while read -r file; do
        echo "  - $file"
    done
fi

# Compare the two sets of modified files
log_info ""
log_info "=== Comparing modified files ==="

# Files modified in current but not covered by patches
echo ""
log_info "Files modified in current checkout:"
MISSING_IN_PATCHES=""
while IFS= read -r file; do
    if [[ -n "$file" ]]; then
        if echo "$PATCHED_MODIFIED_FILES" | grep -q "^${file}$"; then
            log_success "  $file (covered by patches)"
        else
            log_error "  $file (NOT covered by patches)"
            MISSING_IN_PATCHES="$MISSING_IN_PATCHES$file\n"
        fi
    fi
done <<< "$CURRENT_MODIFIED_FILES"

# Files in patches but not modified in current checkout (shouldn't happen normally)
EXTRA_IN_PATCHES=""
while IFS= read -r file; do
    if [[ -n "$file" ]]; then
        if ! echo "$CURRENT_MODIFIED_FILES" | grep -q "^${file}$"; then
            log_warning "  $file (in patches but not modified in current checkout)"
            EXTRA_IN_PATCHES="$EXTRA_IN_PATCHES$file\n"
        fi
    fi
done <<< "$PATCHED_MODIFIED_FILES"

# For files covered by patches, compare actual content
log_info ""
log_info "=== Comparing file contents ==="
CONTENT_MISMATCH=false

while IFS= read -r file; do
    if [[ -n "$file" ]] && echo "$PATCHED_MODIFIED_FILES" | grep -q "^${file}$"; then
        # Compare the file content
        if diff -q "$COMAPS_DIR/$file" "$TEMP_COMAPS_DIR/$file" > /dev/null 2>&1; then
            log_success "  $file - content matches patches"
        else
            log_error "  $file - content DIFFERS from patches"
            CONTENT_MISMATCH=true
            
            # Show the diff
            echo "    --- Difference ---"
            diff -u "$TEMP_COMAPS_DIR/$file" "$COMAPS_DIR/$file" 2>/dev/null | head -30 | sed 's/^/    /'
            if [[ $(diff -u "$TEMP_COMAPS_DIR/$file" "$COMAPS_DIR/$file" 2>/dev/null | wc -l) -gt 30 ]]; then
                echo "    ... (truncated, showing first 30 lines)"
            fi
            echo ""
        fi
    fi
done <<< "$CURRENT_MODIFIED_FILES"

# Summary
echo ""
log_info "=== Summary ==="

HAS_ISSUES=false

if [[ -n "$MISSING_IN_PATCHES" ]]; then
    HAS_ISSUES=true
    log_error "Files modified but NOT covered by patches:"
    echo -e "$MISSING_IN_PATCHES" | while read -r file; do
        [[ -n "$file" ]] && echo "  - $file"
    done
    echo ""
fi

if $CONTENT_MISMATCH; then
    HAS_ISSUES=true
    log_error "Some patched files have content that differs from the current checkout"
    echo ""
fi

if $PATCH_FAILED; then
    HAS_ISSUES=true
    log_error "Some patches failed to apply to clean checkout"
    echo ""
fi

if $HAS_ISSUES; then
    log_error "VALIDATION FAILED: Patches are out of sync with thirdparty/comaps modifications"
    echo ""
    
    if $UPDATE_PATCHES; then
        log_info "Generating updated patches..."
        
        # Generate a comprehensive patch from the current state
        cd "$COMAPS_DIR"
        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        
        # Get files not covered by existing patches
        if [[ -n "$MISSING_IN_PATCHES" ]]; then
            NEXT_PATCH_NUM=$(ls "$PATCH_DIR"/*.patch 2>/dev/null | wc -l | tr -d ' ')
            NEXT_PATCH_NUM=$((NEXT_PATCH_NUM + 1))
            NEXT_PATCH_NUM=$(printf "%04d" $NEXT_PATCH_NUM)
            
            NEW_PATCH_FILE="$PATCH_DIR/${NEXT_PATCH_NUM}-missing-changes-${TIMESTAMP}.patch"
            
            echo -e "$MISSING_IN_PATCHES" | while read -r file; do
                if [[ -n "$file" ]]; then
                    git diff "$file"
                fi
            done > "$NEW_PATCH_FILE"
            
            log_success "Generated: $NEW_PATCH_FILE"
            log_info "Review and rename the patch file appropriately, then update README.md"
        fi
        
        echo ""
        log_info "To regenerate all patches from scratch, run:"
        echo "  cd $COMAPS_DIR && git diff > $PATCH_DIR/all-changes.patch"
    else
        log_info "Run with --update-patches to generate patches for missing changes"
        log_info "Or manually create patches for the missing files:"
        echo ""
        echo "  cd $COMAPS_DIR"
        if [[ -n "$MISSING_IN_PATCHES" ]]; then
            echo -e "$MISSING_IN_PATCHES" | while read -r file; do
                [[ -n "$file" ]] && echo "  git diff $file > \$ROOT/patches/comaps/XXXX-description.patch"
            done
        fi
    fi
    
    exit 1
else
    log_success "VALIDATION PASSED: All modifications are accurately captured in patches"
    exit 0
fi
