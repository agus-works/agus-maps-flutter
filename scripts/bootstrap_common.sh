#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# bootstrap_common.sh - Shared Bootstrap Logic for All Platforms
# ============================================================================
#
# This script provides common functions for bootstrapping the agus_maps_flutter
# development environment across all platforms (macOS, Linux, Windows via Git Bash).
#
# Usage:
#   source ./scripts/bootstrap_common.sh
#   bootstrap_comaps   # Fetch and patch CoMaps
#   bootstrap_boost    # Build boost headers
#   bootstrap_data     # Copy CoMaps data files
#
# Environment variables:
#   COMAPS_TAG: git tag/commit to checkout (defaults to v2025.12.11-2)
#   COMAPS_USE_HTTPS: if set to "true", uses HTTPS instead of SSH (for CI)
#   SKIP_PATCHES: if set to "true", skips applying patches
#
# ============================================================================

# Determine script and repo root directories
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
  BOOTSTRAP_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  BOOTSTRAP_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
fi
BOOTSTRAP_ROOT_DIR="$(cd "$BOOTSTRAP_SCRIPT_DIR/.." && pwd)"

# Default configuration
COMAPS_TAG_DEFAULT="v2025.12.11-2"
COMAPS_TAG="${COMAPS_TAG:-$COMAPS_TAG_DEFAULT}"

# Colors for output (disabled if not a tty)
if [[ -t 1 ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  CYAN='\033[0;36m'
  NC='\033[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  CYAN=''
  NC=''
fi

# Logging functions
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_header() { echo -e "${CYAN}=== $1 ===${NC}"; }

# ============================================================================
# bootstrap_comaps - Fetch CoMaps and apply patches
# ============================================================================
bootstrap_comaps() {
  log_header "Bootstrapping CoMaps"
  
  local thirdparty_dir="$BOOTSTRAP_ROOT_DIR/thirdparty"
  local comaps_dir="$thirdparty_dir/comaps"
  
  # Use HTTPS in CI environments
  local comaps_repo
  if [[ "${COMAPS_USE_HTTPS:-}" == "true" ]] || [[ "${CI:-}" == "true" ]]; then
    comaps_repo="https://github.com/comaps/comaps.git"
  else
    comaps_repo="git@github.com:comaps/comaps.git"
  fi
  
  mkdir -p "$thirdparty_dir"
  
  # Clone or update repository
  if [[ ! -d "$comaps_dir/.git" ]]; then
    log_info "Cloning CoMaps from $comaps_repo"
    git clone "$comaps_repo" "$comaps_dir"
  else
    log_info "Updating existing CoMaps checkout"
  fi
  
  pushd "$comaps_dir" >/dev/null
  
  # Fetch tags
  log_info "Fetching tags..."
  git fetch --tags --prune
  
  # Checkout specific tag
  log_info "Checking out $COMAPS_TAG"
  git checkout --detach "$COMAPS_TAG"
  
  # Initialize ALL submodules recursively - this is critical for patches
  log_info "Initializing submodules (this may take a while)..."
  git submodule update --init --recursive
  
  log_info "At $(git rev-parse --short HEAD) ($(git describe --tags --always --dirty))"
  
  popd >/dev/null
  
  # Apply patches unless skipped
  if [[ "${SKIP_PATCHES:-}" != "true" ]]; then
    bootstrap_apply_patches
  else
    log_warn "Skipping patches (SKIP_PATCHES=true)"
  fi
  
  log_info "CoMaps bootstrap complete"
}

# ============================================================================
# bootstrap_apply_patches - Apply patches to CoMaps
# ============================================================================
bootstrap_apply_patches() {
  log_header "Applying CoMaps Patches"
  
  local comaps_dir="$BOOTSTRAP_ROOT_DIR/thirdparty/comaps"
  local patch_dir="$BOOTSTRAP_ROOT_DIR/patches/comaps"
  
  if [[ ! -d "$comaps_dir/.git" ]]; then
    log_error "CoMaps checkout not found at $comaps_dir"
    return 1
  fi
  
  shopt -s nullglob
  local patches=("$patch_dir"/*.patch)
  
  if [[ ${#patches[@]} -eq 0 ]]; then
    log_warn "No patches found in $patch_dir"
    return 0
  fi
  
  pushd "$comaps_dir" >/dev/null
  
  # Reset working tree to clean state
  log_info "Resetting working tree to HEAD..."
  git reset HEAD -- . >/dev/null 2>&1 || true
  git checkout -- .
  git clean -fd
  
  # Reset submodules as well
  log_info "Resetting submodules..."
  git submodule foreach --recursive 'git checkout -- . 2>/dev/null || true' 2>/dev/null || true
  git submodule foreach --recursive 'git clean -fd 2>/dev/null || true' 2>/dev/null || true
  
  local applied=0
  local skipped=0
  local failed=0
  
  for patch in "${patches[@]}"; do
    local patch_name
    patch_name="$(basename "$patch")"
    
    # Extract the target file from the patch to check if it exists
    local target_file
    target_file=$(grep -m1 "^diff --git" "$patch" | sed 's|diff --git a/||; s| b/.*||' || true)
    
    if [[ -n "$target_file" ]] && [[ ! -e "$target_file" ]]; then
      log_warn "Skipping $patch_name (target file '$target_file' does not exist - possibly a submodule not initialized)"
      ((skipped++))
      continue
    fi
    
    log_info "Applying $patch_name"
    
    # Try direct apply first (fastest)
    if git apply --whitespace=nowarn "$patch" 2>/dev/null; then
      echo "  Applied successfully"
      ((applied++))
    # Try 3-way merge as fallback
    elif git apply --3way --whitespace=nowarn "$patch" 2>/dev/null; then
      echo "  Applied successfully (3-way merge)"
      ((applied++))
    # Check if already applied
    elif git apply --check --reverse "$patch" 2>/dev/null; then
      log_warn "  Already applied (skipping)"
      ((skipped++))
    else
      # Final fallback: try direct file application for submodules
      log_warn "  Falling back to direct application..."
      if apply_patch_directly "$patch" "$comaps_dir"; then
        echo "  Applied via direct method"
        ((applied++))
      else
        log_error "  Failed to apply $patch_name"
        ((failed++))
      fi
    fi
  done
  
  popd >/dev/null
  
  log_info "Patch summary: Applied=$applied, Skipped=$skipped, Failed=$failed"
  
  if [[ $failed -gt 0 ]]; then
    log_warn "Some patches failed to apply. Build may still succeed."
  fi
}

# ============================================================================
# apply_patch_directly - Apply patch by directly modifying files
# ============================================================================
apply_patch_directly() {
  local patch_file="$1"
  local base_dir="$2"
  
  # Simple patch application for cases where git apply fails
  # This handles submodule patches where git apply may have issues
  
  pushd "$base_dir" >/dev/null
  
  if patch -p1 --dry-run < "$patch_file" >/dev/null 2>&1; then
    patch -p1 < "$patch_file" >/dev/null 2>&1
    popd >/dev/null
    return 0
  fi
  
  popd >/dev/null
  return 1
}

# ============================================================================
# bootstrap_boost - Build Boost headers
# ============================================================================
bootstrap_boost() {
  log_header "Building Boost Headers"
  
  local boost_dir="$BOOTSTRAP_ROOT_DIR/thirdparty/comaps/3party/boost"
  local boost_headers="$boost_dir/boost"
  
  if [[ -f "$boost_headers/config.hpp" ]]; then
    log_info "Boost headers already built"
    return 0
  fi
  
  if [[ ! -d "$boost_dir" ]]; then
    log_error "Boost directory not found at $boost_dir"
    return 1
  fi
  
  pushd "$boost_dir" >/dev/null
  
  if [[ -x "./bootstrap.sh" ]]; then
    log_info "Running bootstrap.sh..."
    ./bootstrap.sh
    
    log_info "Building headers with b2..."
    ./b2 headers
  else
    log_error "bootstrap.sh not found or not executable"
    popd >/dev/null
    return 1
  fi
  
  popd >/dev/null
  
  log_info "Boost headers built successfully"
}

# ============================================================================
# bootstrap_data - Copy CoMaps data files to example assets
# ============================================================================
bootstrap_data() {
  log_header "Copying CoMaps Data Files"
  
  local comaps_data="$BOOTSTRAP_ROOT_DIR/thirdparty/comaps/data"
  local dest_data="$BOOTSTRAP_ROOT_DIR/example/assets/comaps_data"
  
  if [[ ! -d "$comaps_data" ]]; then
    log_error "CoMaps data directory not found at $comaps_data"
    return 1
  fi
  
  mkdir -p "$dest_data"
  
  # Essential files for Framework initialization
  local essential_files=(
    "classificator.txt"
    "types.txt"
    "categories.txt"
    "visibility.txt"
    "countries.txt"
    "countries_meta.txt"
    "packed_polygons.bin"
    "drules_proto.bin"
    "drules_proto_default_light.bin"
    "drules_proto_default_dark.bin"
    "drules_proto_outdoors_light.bin"
    "drules_proto_outdoors_dark.bin"
    "drules_proto_vehicle_light.bin"
    "drules_proto_vehicle_dark.bin"
    "drules_hash"
    "transit_colors.txt"
    "colors.txt"
    "patterns.txt"
    "editor.config"
  )
  
  for file in "${essential_files[@]}"; do
    if [[ -f "$comaps_data/$file" ]]; then
      cp "$comaps_data/$file" "$dest_data/"
      echo "  ✓ $file"
    else
      echo "  ✗ $file (not found)"
    fi
  done
  
  # Copy directories
  local dirs_to_copy=("categories-strings" "countries-strings" "fonts" "symbols" "styles")
  
  for dir in "${dirs_to_copy[@]}"; do
    if [[ -d "$comaps_data/$dir" ]]; then
      mkdir -p "$dest_data/$dir"
      cp -r "$comaps_data/$dir/"* "$dest_data/$dir/"
      echo "  ✓ $dir/"
    fi
  done
  
  log_info "Data files copied to: $dest_data"
}

# ============================================================================
# bootstrap_android_assets - Copy fonts to Android assets
# ============================================================================
bootstrap_android_assets() {
  log_header "Copying Android Assets"
  
  local fonts_source="$BOOTSTRAP_ROOT_DIR/thirdparty/comaps/data/fonts"
  local fonts_dest="$BOOTSTRAP_ROOT_DIR/example/android/app/src/main/assets/fonts"
  
  if [[ -d "$fonts_source" ]]; then
    mkdir -p "$(dirname "$fonts_dest")"
    rm -rf "$fonts_dest"
    cp -r "$fonts_source" "$fonts_dest"
    local count
    count=$(find "$fonts_dest" -name '*.ttf' 2>/dev/null | wc -l | tr -d ' ')
    log_info "Copied $count font files to Android assets"
  else
    log_warn "Fonts directory not found at $fonts_source"
  fi
}

# ============================================================================
# bootstrap_full - Run full bootstrap for current platform
# ============================================================================
bootstrap_full() {
  local platform="${1:-all}"
  
  log_header "Full Bootstrap for agus_maps_flutter"
  log_info "Platform: $platform"
  log_info "CoMaps tag: $COMAPS_TAG"
  
  # Step 1: Always fetch CoMaps and apply patches
  bootstrap_comaps
  
  # Step 2: Always build boost headers
  bootstrap_boost
  
  # Step 3: Copy data files (needed for all platforms)
  bootstrap_data
  
  # Platform-specific steps
  case "$platform" in
    android|all)
      bootstrap_android_assets
      ;;
  esac
  
  log_header "Bootstrap Complete!"
}

# Export functions for use in other scripts
export -f log_info log_warn log_error log_header
export -f bootstrap_comaps bootstrap_apply_patches bootstrap_boost
export -f bootstrap_data bootstrap_android_assets bootstrap_full
