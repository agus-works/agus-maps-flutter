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
#   bootstrap_full "platform"  # Full bootstrap with caching
#   bootstrap_comaps           # Fetch and patch CoMaps
#   bootstrap_boost            # Build boost headers
#   bootstrap_data             # Copy CoMaps data files
#
# Caching:
#   The bootstrap_full function implements a caching mechanism:
#   - After fresh git clone, thirdparty is compressed to .thirdparty.tar.bz2
#   - Cache is created BEFORE patches are applied (pristine state)
#   - If thirdparty is deleted and cache exists, it will be extracted
#   - This allows iterating on patches without re-cloning from git
#   - Use NO_CACHE=true to disable caching behavior
#   - Caching is automatically disabled in CI environments ($CI=true)
#     to avoid interfering with CI-specific caching (e.g., Bitrise cache steps)
#
# Environment variables:
#   COMAPS_TAG: git tag/commit to checkout (defaults to v2025.12.11-2)
#   COMAPS_USE_HTTPS: if set to "true", uses HTTPS instead of SSH (for CI)
#   SKIP_PATCHES: if set to "true", skips applying patches
#   NO_CACHE: if set to "true", disables caching (no create/use of archive)
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
# Thirdparty Caching Configuration
# ============================================================================
# Cache archive name (stored in repo root, should be in .gitignore)
THIRDPARTY_ARCHIVE=".thirdparty.tar.bz2"

# ============================================================================
# test_thirdparty_archive - Check if cached archive exists
# ============================================================================
test_thirdparty_archive() {
  [[ -f "$BOOTSTRAP_ROOT_DIR/$THIRDPARTY_ARCHIVE" ]]
}

# ============================================================================
# compress_thirdparty - Create cache archive from thirdparty directory
# ============================================================================
compress_thirdparty() {
  local archive_path="$BOOTSTRAP_ROOT_DIR/$THIRDPARTY_ARCHIVE"
  local thirdparty_dir="$BOOTSTRAP_ROOT_DIR/thirdparty"
  
  if [[ ! -d "$thirdparty_dir" ]]; then
    log_warn "Thirdparty directory not found - nothing to compress"
    return 1
  fi
  
  log_header "Creating Cache Archive"
  log_info "Compressing thirdparty to $THIRDPARTY_ARCHIVE (max bzip2 compression)..."
  log_info "This may take several minutes..."
  
  # Remove existing archive if present
  [[ -f "$archive_path" ]] && rm -f "$archive_path"
  
  local start_time
  start_time=$(date +%s)
  
  # Use bzip2 with max compression (-9), no verbose output
  BZIP2=-9 tar -cjf "$archive_path" -C "$BOOTSTRAP_ROOT_DIR" thirdparty
  
  local end_time
  end_time=$(date +%s)
  local elapsed=$((end_time - start_time))
  
  # Get size in MB (works on both macOS and Linux)
  local size_bytes
  size_bytes=$(stat -f%z "$archive_path" 2>/dev/null || stat -c%s "$archive_path" 2>/dev/null)
  local size_mb=$((size_bytes / 1024 / 1024))
  
  log_info "Cache archive created: ${size_mb} MB in ${elapsed} seconds"
  return 0
}

# ============================================================================
# expand_thirdparty - Extract thirdparty from cache archive
# ============================================================================
expand_thirdparty() {
  local archive_path="$BOOTSTRAP_ROOT_DIR/$THIRDPARTY_ARCHIVE"
  local thirdparty_dir="$BOOTSTRAP_ROOT_DIR/thirdparty"
  
  if [[ ! -f "$archive_path" ]]; then
    log_warn "No cached archive found at $archive_path"
    return 1
  fi
  
  log_header "Extracting Cache Archive"
  log_info "Extracting $THIRDPARTY_ARCHIVE..."
  log_info "This may take a few minutes..."
  
  # Remove existing thirdparty directory if present
  [[ -d "$thirdparty_dir" ]] && rm -rf "$thirdparty_dir"
  
  local start_time
  start_time=$(date +%s)
  
  # Extract with bzip2 (no verbose)
  tar -xjf "$archive_path" -C "$BOOTSTRAP_ROOT_DIR"
  
  local end_time
  end_time=$(date +%s)
  local elapsed=$((end_time - start_time))
  
  log_info "Extracted in ${elapsed} seconds"
  return 0
}

# ============================================================================
# bootstrap_comaps_fetch - Fetch CoMaps source (no patches)
# ============================================================================
# This is the internal function that only handles git operations.
# Use bootstrap_comaps for the full workflow including patches.
# Returns: 0 on success, sets COMAPS_FRESH_CLONE=true if this was a fresh clone
bootstrap_comaps_fetch() {
  log_header "Fetching CoMaps Source"
  
  local thirdparty_dir="$BOOTSTRAP_ROOT_DIR/thirdparty"
  local comaps_dir="$thirdparty_dir/comaps"
  
  # Track if this is a fresh clone
  COMAPS_FRESH_CLONE=false
  
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
    COMAPS_FRESH_CLONE=true
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
  
  log_info "CoMaps source fetched successfully"
}

# ============================================================================
# bootstrap_comaps - Fetch CoMaps and apply patches
# ============================================================================
# This is the main entry point that fetches source and applies patches.
# For cache-aware bootstrapping, use bootstrap_full instead.
bootstrap_comaps() {
  bootstrap_comaps_fetch
  
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
  # --batch: Skip patches that can't be applied cleanly (non-interactive)
  # --forward: Only apply if not already applied (no reverse prompt)
  
  pushd "$base_dir" >/dev/null
  
  if patch -p1 --batch --forward --dry-run < "$patch_file" >/dev/null 2>&1; then
    patch -p1 --batch --forward < "$patch_file" >/dev/null 2>&1
    popd >/dev/null
    return 0
  fi
  
  popd >/dev/null
  return 1
}

# ============================================================================
# bootstrap_generate_data - Generate CoMaps data files (classificator, types, etc.)
# ============================================================================
# Runs the generation scripts that create classificator.txt, types.txt,
# visibility.txt, categories.txt, and drules_proto*.bin files.
# These files are NOT stored in the CoMaps git repo - they are generated
# from mapcss styles and categories-strings JSON files.
bootstrap_generate_data() {
  log_header "Generating CoMaps Data Files"
  
  local comaps_dir="$BOOTSTRAP_ROOT_DIR/thirdparty/comaps"
  local data_dir="$comaps_dir/data"
  
  if [[ ! -d "$comaps_dir" ]]; then
    log_error "CoMaps directory not found at $comaps_dir"
    return 1
  fi
  
  # Check if files already exist (cached state)
  if [[ -f "$data_dir/classificator.txt" ]] && [[ -f "$data_dir/types.txt" ]] && \
     [[ -f "$data_dir/visibility.txt" ]] && [[ -f "$data_dir/categories.txt" ]] && \
     [[ -f "$data_dir/symbols/xxhdpi/light/symbols.sdf" ]]; then
    log_info "Data files already generated - skipping"
    return 0
  fi
  
  pushd "$comaps_dir" >/dev/null
  
  # Set protobuf compatibility mode for newer protobuf packages (>= 4.x)
  # The CoMaps _pb2.py files were generated with older protoc and need this workaround
  export PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=python
  
  # Generate drawing rules (classificator.txt, types.txt, visibility.txt, drules_proto*.bin)
  if [[ -x "tools/unix/generate_drules.sh" ]]; then
    log_info "Generating drawing rules and classificator..."
    OMIM_PATH="$comaps_dir" DATA_PATH="$data_dir" bash tools/unix/generate_drules.sh
  else
    log_warn "generate_drules.sh not found or not executable"
  fi
  
  # Generate categories.txt from JSON
  if [[ -x "tools/unix/generate_categories.sh" ]]; then
    log_info "Generating categories.txt..."
    bash tools/unix/generate_categories.sh
  else
    log_warn "generate_categories.sh not found or not executable"
  fi
  
  # Download pre-built symbol textures from Organic Maps
  # These are generated by skin_generator_tool which requires building desktop tools
  log_info "Downloading symbol textures..."
  local resolutions=(mdpi hdpi xhdpi xxhdpi xxxhdpi 6plus)
  local themes=(light dark)
  for res in "${resolutions[@]}"; do
    for theme in "${themes[@]}"; do
      local symbol_dir="$data_dir/symbols/$res/$theme"
      if [[ ! -f "$symbol_dir/symbols.sdf" ]]; then
        log_info "  Downloading $res/$theme symbols..."
        curl -sL "https://raw.githubusercontent.com/organicmaps/organicmaps/master/data/symbols/$res/$theme/symbols.sdf" -o "$symbol_dir/symbols.sdf" || log_warn "Failed to download $res/$theme/symbols.sdf"
        curl -sL "https://raw.githubusercontent.com/organicmaps/organicmaps/master/data/symbols/$res/$theme/symbols.png" -o "$symbol_dir/symbols.png" || log_warn "Failed to download $res/$theme/symbols.png"
      fi
    done
  done
  
  popd >/dev/null
  
  # Verify files were created
  local generated=0
  local missing_files=()
  for file in classificator.txt types.txt visibility.txt categories.txt; do
    if [[ -f "$data_dir/$file" ]]; then
      ((generated++))
    else
      missing_files+=("$file")
    fi
  done
  
  if [[ ${#missing_files[@]} -gt 0 ]]; then
    log_warn "Some files were not generated: ${missing_files[*]}"
  fi
  
  log_info "Generated $generated data files"
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
  local no_cache="${NO_CACHE:-false}"
  
  # Automatically disable local caching in CI environments
  # CI systems (Bitrise, GitHub Actions, etc.) have their own caching mechanisms
  if [[ "${CI:-}" == "true" ]]; then
    no_cache="true"
  fi
  
  log_header "Full Bootstrap for agus_maps_flutter"
  log_info "Platform: $platform"
  log_info "CoMaps tag: $COMAPS_TAG"
  
  local comaps_dir="$BOOTSTRAP_ROOT_DIR/thirdparty/comaps"
  local used_cache=false
  
  # Show cache status
  if [[ "$no_cache" == "true" ]]; then
    if [[ "${CI:-}" == "true" ]]; then
      log_info "Local cache disabled (CI environment detected)"
    else
      log_info "Cache disabled by --no-cache flag"
    fi
  elif test_thirdparty_archive; then
    local archive_path="$BOOTSTRAP_ROOT_DIR/$THIRDPARTY_ARCHIVE"
    local size_bytes
    size_bytes=$(stat -f%z "$archive_path" 2>/dev/null || stat -c%s "$archive_path" 2>/dev/null)
    local size_mb=$((size_bytes / 1024 / 1024))
    log_info "Cache archive found: $THIRDPARTY_ARCHIVE (${size_mb} MB)"
  else
    log_info "No cache archive found - will create after fresh clone"
  fi
  
  # Try to restore from cache if thirdparty doesn't exist
  if [[ "$no_cache" != "true" ]] && [[ ! -d "$comaps_dir" ]] && test_thirdparty_archive; then
    log_info "Restoring from cache instead of cloning..."
    if expand_thirdparty; then
      used_cache=true
      log_info "Successfully restored from cache"
    else
      log_warn "Cache extraction failed, will clone from git"
    fi
  fi
  
  # Step 1: Fetch CoMaps source (no patches yet)
  bootstrap_comaps_fetch
  
  # Create cache after fresh clone but BEFORE patches
  # This ensures patches can be iterated on without re-cloning
  if [[ "$COMAPS_FRESH_CLONE" == "true" ]] && [[ "$used_cache" != "true" ]] && [[ "$no_cache" != "true" ]]; then
    log_info "Creating cache from fresh clone (before patches)..."
    compress_thirdparty || log_warn "Failed to create cache archive"
  fi
  
  # Step 2: Apply patches
  if [[ "${SKIP_PATCHES:-}" != "true" ]]; then
    bootstrap_apply_patches
  else
    log_warn "Skipping patches (SKIP_PATCHES=true)"
  fi
  
  # Step 3: Build boost headers
  bootstrap_boost
  
  # Step 4: Generate CoMaps data files (classificator, types, visibility, categories)
  bootstrap_generate_data
  
  # Step 5: Copy data files (needed for all platforms)
  bootstrap_data
  
  # Platform-specific steps
  case "$platform" in
    android|all)
      bootstrap_android_assets
      ;;
  esac
  
  log_header "Bootstrap Complete!"
  
  # Show cache status at end
  if [[ "$no_cache" != "true" ]]; then
    if test_thirdparty_archive; then
      local archive_path="$BOOTSTRAP_ROOT_DIR/$THIRDPARTY_ARCHIVE"
      local size_bytes
      size_bytes=$(stat -f%z "$archive_path" 2>/dev/null || stat -c%s "$archive_path" 2>/dev/null)
      local size_mb=$((size_bytes / 1024 / 1024))
      log_info "Cache archive available: $THIRDPARTY_ARCHIVE (${size_mb} MB)"
      log_info "Tip: Delete 'thirdparty' folder and re-run bootstrap to use cache"
    fi
  fi
}

# Export functions for use in other scripts
export -f log_info log_warn log_error log_header
export -f test_thirdparty_archive compress_thirdparty expand_thirdparty
export -f bootstrap_comaps_fetch bootstrap_comaps bootstrap_apply_patches
export -f bootstrap_generate_data bootstrap_boost
export -f bootstrap_data bootstrap_android_assets bootstrap_full
