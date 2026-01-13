#!/usr/bin/env bash
# Download base MWM files required for the example app.
#
# This script uses the Dart map_downloader.dart tool to fetch MWM files from
# CoMaps CDN servers. This wrapper provides a convenient shell interface.
#
# Usage:
#   ./scripts/download_base_mwms.sh [options]
#
# Options:
#   --snapshot VERSION    Use specific snapshot version (e.g., "260113")
#   --output-dir DIR      Output directory (default: example/assets/maps)
#   --files "a,b,c"       Comma-separated list of MWM files
#   --report PATH         Generate JSON report file
#   --list-regions        List all available regions and exit
#   --list-mirrors        List all mirrors and their status
#   --verbose             Enable verbose output
#
# Examples:
#   ./scripts/download_base_mwms.sh
#   ./scripts/download_base_mwms.sh --snapshot 260113
#   ./scripts/download_base_mwms.sh --files "World.mwm,Germany_Berlin.mwm"
#   ./scripts/download_base_mwms.sh --list-mirrors

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
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

log_header() {
  echo -e "${CYAN}=== $1 ===${NC}" >&2
}

# Default values
OUTPUT_DIR="$PROJECT_ROOT/example/assets/maps"
FILES="World.mwm,WorldCoasts.mwm,Gibraltar.mwm"
SNAPSHOT=""
REPORT=""
LIST_REGIONS=false
LIST_MIRRORS=false
VERBOSE=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --snapshot|-s)
      SNAPSHOT="$2"
      shift 2
      ;;
    --output-dir|-o)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --files|-f)
      FILES="$2"
      shift 2
      ;;
    --report|-r)
      REPORT="$2"
      shift 2
      ;;
    --list-regions)
      LIST_REGIONS=true
      shift
      ;;
    --list-mirrors)
      LIST_MIRRORS=true
      shift
      ;;
    --verbose|-v)
      VERBOSE=true
      shift
      ;;
    --help|-h)
      echo "Usage: $0 [options]"
      echo ""
      echo "Options:"
      echo "  --snapshot VERSION    Use specific snapshot version (e.g., '260113')"
      echo "  --output-dir DIR      Output directory (default: example/assets/maps)"
      echo "  --files 'a,b,c'       Comma-separated list of MWM files"
      echo "  --report PATH         Generate JSON report file"
      echo "  --list-regions        List all available regions and exit"
      echo "  --list-mirrors        List all mirrors and their status"
      echo "  --verbose             Enable verbose output"
      echo ""
      echo "Examples:"
      echo "  $0"
      echo "  $0 --snapshot 260113"
      echo "  $0 --files 'World.mwm,Germany_Berlin.mwm'"
      exit 0
      ;;
    *)
      log_error "Unknown option: $1"
      exit 1
      ;;
  esac
done

log_header "CoMaps MWM Map Downloader (Shell Wrapper)"

# Check for Dart
if ! command -v dart &>/dev/null; then
  log_error "Dart is not installed. Please install Dart to use this tool."
  log_error "Install Dart: https://dart.dev/get-dart"
  exit 1
fi

# Build Dart command
cd "$PROJECT_ROOT"

DART_ARGS=()

if [ -n "$OUTPUT_DIR" ]; then
  DART_ARGS+=("--output-dir" "$OUTPUT_DIR")
fi

if [ -n "$FILES" ]; then
  DART_ARGS+=("--files" "$FILES")
fi

if [ -n "$SNAPSHOT" ]; then
  DART_ARGS+=("--snapshot" "$SNAPSHOT")
fi

if [ -n "$REPORT" ]; then
  DART_ARGS+=("--report" "$REPORT")
fi

if [ "$LIST_REGIONS" = true ]; then
  DART_ARGS+=("--list-regions")
fi

if [ "$LIST_MIRRORS" = true ]; then
  DART_ARGS+=("--list-mirrors")
fi

if [ "$VERBOSE" = true ]; then
  DART_ARGS+=("--verbose")
fi

log_info "Running: dart run tool/map_downloader.dart ${DART_ARGS[*]}"

# Run the Dart tool
dart run tool/map_downloader.dart "${DART_ARGS[@]}"
exit_code=$?

# Copy ICU data if available (after successful download)
if [ $exit_code -eq 0 ] && [ "$LIST_REGIONS" = false ] && [ "$LIST_MIRRORS" = false ]; then
  ICU_SOURCE="$PROJECT_ROOT/thirdparty/comaps/data/icudt75l.dat"
  ICU_DEST="$OUTPUT_DIR/icudt75l.dat"
  if [ -f "$ICU_SOURCE" ] && [ ! -f "$ICU_DEST" ]; then
    log_info "Copying icudt75l.dat from thirdparty/comaps..."
    cp "$ICU_SOURCE" "$ICU_DEST"
  fi
fi

exit $exit_code
