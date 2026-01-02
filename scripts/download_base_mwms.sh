#!/usr/bin/env bash
# Download base MWM files required for the example app.
#
# This script fetches World.mwm, WorldCoasts.mwm, and Gibraltar.mwm from
# CoMaps mirror servers. These files are required for the map to display.
#
# Usage:
#   ./scripts/download_base_mwms.sh [snapshot_version]
#
# Arguments:
#   snapshot_version  Optional. e.g., "251209". If not provided, fetches latest.
#
# The script:
#   1. Queries available mirrors for latency
#   2. Selects the fastest available mirror
#   3. Downloads World.mwm, WorldCoasts.mwm, and Gibraltar.mwm
#   4. Places them in example/assets/maps/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ASSETS_DIR="$PROJECT_ROOT/example/assets/maps"

# Mirror servers (same as mirror_service.dart)
MIRRORS=(
  "https://omaps.wfr.software/maps/"
  "https://omaps.webfreak.org/maps/"
)

# Base MWM files to download
BASE_MWMS=(
  "World.mwm"
  "WorldCoasts.mwm"
  "Gibraltar.mwm"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
  echo -e "${GREEN}[INFO]${NC} $1" >&2
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Find the fastest available mirror
find_fastest_mirror() {
  local fastest_mirror=""
  local fastest_time=999999

  for mirror in "${MIRRORS[@]}"; do
    log_info "Testing mirror: $mirror"
    local start_time
    start_time=$(python3 -c 'import time; print(int(time.time()*1000))')
    
    if curl -sf --max-time 10 -I "$mirror" > /dev/null 2>&1; then
      local end_time
      end_time=$(python3 -c 'import time; print(int(time.time()*1000))')
      local latency=$((end_time - start_time))
      log_info "  Latency: ${latency}ms"
      
      if [ "$latency" -lt "$fastest_time" ]; then
        fastest_time=$latency
        fastest_mirror=$mirror
      fi
    else
      log_warn "  Mirror unavailable"
    fi
  done

  echo "$fastest_mirror"
}

# Get the latest snapshot version from a mirror
get_latest_snapshot() {
  local mirror=$1
  
  # Fetch directory listing and extract 6-digit version folders
  # Handles both href="250608/" and href="./250608/" formats
  curl -sf "$mirror" | grep -oE 'href="\.?/?[0-9]{6}/"' | grep -oE '[0-9]{6}' | sort -rn | head -1
}

# Download a single file
download_file() {
  local url=$1
  local output=$2
  
  log_info "Downloading: $url"
  log_info "  -> $output"
  
  if curl -fL --progress-bar -o "$output" "$url"; then
    log_info "  Downloaded successfully ($(du -h "$output" | cut -f1))"
    return 0
  else
    log_error "  Download failed!"
    return 1
  fi
}

main() {
  local snapshot_version="${1:-}"
  
  log_info "=== CoMaps Base MWM Downloader ==="
  
  # Ensure assets directory exists
  mkdir -p "$ASSETS_DIR"
  
  # Find fastest mirror
  log_info "Finding fastest mirror..."
  local mirror
  mirror=$(find_fastest_mirror)
  
  if [ -z "$mirror" ]; then
    log_error "No mirrors available!"
    exit 1
  fi
  
  log_info "Using mirror: $mirror"
  
  # Get snapshot version
  if [ -z "$snapshot_version" ]; then
    log_info "Fetching latest snapshot version..."
    snapshot_version=$(get_latest_snapshot "$mirror")
    
    if [ -z "$snapshot_version" ]; then
      log_error "Could not determine latest snapshot version!"
      exit 1
    fi
  fi
  
  log_info "Using snapshot: $snapshot_version"
  
  # Download each base MWM file
  local success=0
  local failed=0
  
  for mwm in "${BASE_MWMS[@]}"; do
    local url="${mirror}${snapshot_version}/${mwm}"
    local output="$ASSETS_DIR/$mwm"
    
    if download_file "$url" "$output"; then
      ((success++))
    else
      ((failed++))
    fi
  done
  
  # Also ensure icudt75l.dat exists (copy from comaps if available)
  local icu_source="$PROJECT_ROOT/thirdparty/comaps/data/icudt75l.dat"
  local icu_dest="$ASSETS_DIR/icudt75l.dat"
  if [ -f "$icu_source" ] && [ ! -f "$icu_dest" ]; then
    log_info "Copying icudt75l.dat from thirdparty/comaps..."
    cp "$icu_source" "$icu_dest"
  fi
  
  # Summary
  echo ""
  log_info "=== Download Summary ==="
  log_info "  Successful: $success"
  if [ "$failed" -gt 0 ]; then
    log_error "  Failed: $failed"
    exit 1
  fi
  
  log_info "Base MWM files downloaded to: $ASSETS_DIR"
  log_info "Snapshot version: $snapshot_version"
  
  # Store version for reference
  echo "$snapshot_version" > "$ASSETS_DIR/.mwm_version"
}

main "$@"
