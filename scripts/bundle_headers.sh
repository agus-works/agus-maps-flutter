#!/usr/bin/env bash
set -euo pipefail

# Bundle CoMaps headers for all platforms
#
# This script collects all header files from thirdparty/comaps/ and packages
# them into a tarball for external consumers who don't have access to the
# full thirdparty source checkout.
#
# The headers are platform-agnostic and shared across iOS, Android, Linux,
# Windows, and macOS builds.
#
# Output:
#   build/agus-headers.tar.gz (ready for upload to GitHub Releases)
#   Intermediate staging at: build/headers_staging/

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMAPS_DIR="$ROOT_DIR/thirdparty/comaps"
STAGING_DIR="$ROOT_DIR/build/headers_staging"
OUTPUT_FILE="$ROOT_DIR/build/agus-headers.tar.gz"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Verify CoMaps source exists
check_comaps_source() {
    if [[ ! -d "$COMAPS_DIR" ]]; then
        log_error "CoMaps source not found at $COMAPS_DIR"
        log_error "Run ./scripts/fetch_comaps.sh first"
        exit 1
    fi
    
    if [[ ! -d "$COMAPS_DIR/libs" ]]; then
        log_error "CoMaps libs directory not found - source may be incomplete"
        exit 1
    fi
}

# Clean and create staging directory
prepare_staging() {
    log_info "Preparing staging directory..."
    rm -rf "$STAGING_DIR"
    mkdir -p "$STAGING_DIR"
}

# Copy headers from a source directory to staging
# Usage: copy_headers <source_dir> <dest_subdir>
copy_headers() {
    local src="$1"
    local dest="$STAGING_DIR/$2"
    
    if [[ ! -d "$src" ]]; then
        log_warn "Source directory not found: $src"
        return 0
    fi
    
    mkdir -p "$dest"
    
    # Copy all header files preserving directory structure
    # Include: .h, .hpp, .hxx, .inc, .inl files
    # Use -L to follow symlinks (important for Boost headers which are symlinked)
    # Note: .inl files are used by GLM for inline implementations
    find -L "$src" -type f \( -name "*.h" -o -name "*.hpp" -o -name "*.hxx" -o -name "*.inc" -o -name "*.inl" \) \
        -exec sh -c '
            src_base="$1"
            dest_base="$2"
            file="$3"
            rel_path="${file#$src_base/}"
            dest_file="$dest_base/$rel_path"
            mkdir -p "$(dirname "$dest_file")"
            cp "$file" "$dest_file"
        ' _ "$src" "$dest" {} \;
}

# Copy specific top-level files
copy_toplevel_files() {
    log_info "Copying top-level CoMaps files..."
    
    # Copy defines.hpp and config headers if they exist
    for file in defines.hpp omim_config.h std/target_os.hpp; do
        local src_file="$COMAPS_DIR/$file"
        if [[ -f "$src_file" ]]; then
            local dest_file="$STAGING_DIR/comaps/$file"
            mkdir -p "$(dirname "$dest_file")"
            cp "$src_file" "$dest_file"
        fi
    done
}

# Bundle all CoMaps headers
bundle_comaps_headers() {
    log_info "Bundling CoMaps library headers..."
    
    # Main library directories (all headers needed for compilation)
    local libs=(
        "base"
        "coding"
        "drape"
        "drape_frontend"
        "editor"
        "ge0"
        "generator"
        "geometry"
        "indexer"
        "kml"
        "map"
        "platform"
        "routing"
        "routing_common"
        "search"
        "shaders"
        "std"
        "storage"
        "tracking"
        "traffic"
        "transit"
    )
    
    for lib in "${libs[@]}"; do
        if [[ -d "$COMAPS_DIR/libs/$lib" ]]; then
            copy_headers "$COMAPS_DIR/libs/$lib" "comaps/libs/$lib"
        elif [[ -d "$COMAPS_DIR/$lib" ]]; then
            copy_headers "$COMAPS_DIR/$lib" "comaps/$lib"
        fi
    done
}

# Bundle third-party headers
bundle_3party_headers() {
    log_info "Bundling third-party headers..."
    
    # Boost (header-only library - copy the entire boost directory)
    if [[ -d "$COMAPS_DIR/3party/boost/boost" ]]; then
        log_info "  Copying Boost headers (this may take a moment)..."
        copy_headers "$COMAPS_DIR/3party/boost/boost" "comaps/3party/boost/boost"
    else
        log_warn "  Boost headers not found - run 'cd thirdparty/comaps/3party/boost && ./bootstrap.sh && ./b2 headers' first"
    fi
    
    # GLM (header-only math library)
    copy_headers "$COMAPS_DIR/3party/glm/glm" "comaps/3party/glm/glm"
    
    # utfcpp (header-only UTF conversion)
    copy_headers "$COMAPS_DIR/3party/utfcpp/source" "comaps/3party/utfcpp/source"
    
    # Jansson (JSON library)
    copy_headers "$COMAPS_DIR/3party/jansson/jansson/src" "comaps/3party/jansson/jansson/src"
    if [[ -f "$COMAPS_DIR/3party/jansson/jansson_config.h" ]]; then
        cp "$COMAPS_DIR/3party/jansson/jansson_config.h" "$STAGING_DIR/comaps/3party/jansson/"
    fi
    
    # Expat (XML parser)
    copy_headers "$COMAPS_DIR/3party/expat/expat/lib" "comaps/3party/expat/expat/lib"
    
    # ICU (Unicode support)
    copy_headers "$COMAPS_DIR/3party/icu/icu/source/common" "comaps/3party/icu/icu/source/common"
    copy_headers "$COMAPS_DIR/3party/icu/icu/source/i18n" "comaps/3party/icu/icu/source/i18n"
    
    # FreeType (font rendering)
    copy_headers "$COMAPS_DIR/3party/freetype/include" "comaps/3party/freetype/include"
    
    # HarfBuzz (text shaping)
    copy_headers "$COMAPS_DIR/3party/harfbuzz/harfbuzz/src" "comaps/3party/harfbuzz/harfbuzz/src"
    
    # MiniZip (ZIP handling)
    copy_headers "$COMAPS_DIR/3party/minizip/minizip" "comaps/3party/minizip/minizip"
    
    # PugiXML (XML DOM)
    copy_headers "$COMAPS_DIR/3party/pugixml/pugixml/src" "comaps/3party/pugixml/pugixml/src"
    
    # Protobuf
    copy_headers "$COMAPS_DIR/3party/protobuf/protobuf/src" "comaps/3party/protobuf/protobuf/src"
    
    # Succinct (compressed data structures)
    copy_headers "$COMAPS_DIR/3party/succinct" "comaps/3party/succinct"
    
    # Skarupke (hash maps)
    copy_headers "$COMAPS_DIR/3party/skarupke" "comaps/3party/skarupke"
    
    # kdtree++ (spatial indexing)
    copy_headers "$COMAPS_DIR/3party/kdtree++" "comaps/3party/kdtree++"
    
    # opening_hours (OSM opening hours parser)
    copy_headers "$COMAPS_DIR/3party/opening_hours" "comaps/3party/opening_hours"
    
    # just_gtfs (GTFS parser)
    copy_headers "$COMAPS_DIR/3party/just_gtfs" "comaps/3party/just_gtfs"
    
    # GL headers
    copy_headers "$COMAPS_DIR/3party/GL" "comaps/3party/GL"
    
    # Other 3party headers at root level
    for item in "$COMAPS_DIR/3party"/*.h "$COMAPS_DIR/3party"/*.hpp; do
        if [[ -f "$item" ]]; then
            cp "$item" "$STAGING_DIR/comaps/3party/" 2>/dev/null || true
        fi
    done
}

# Create the tarball
create_tarball() {
    log_info "Creating tarball..."
    
    # Remove old tarball if exists
    rm -f "$OUTPUT_FILE"
    
    # Create tarball from staging directory
    # The tarball will have 'comaps/' as the root directory
    tar -czvf "$OUTPUT_FILE" -C "$STAGING_DIR" comaps
    
    log_info "Created: $OUTPUT_FILE"
    log_info "Size: $(du -h "$OUTPUT_FILE" | cut -f1)"
}

# Show statistics
show_stats() {
    log_info "Header bundle statistics:"
    
    local header_count
    header_count=$(find "$STAGING_DIR" -type f \( -name "*.h" -o -name "*.hpp" -o -name "*.hxx" -o -name "*.inc" \) | wc -l | tr -d ' ')
    log_info "  Total header files: $header_count"
    
    local staging_size
    staging_size=$(du -sh "$STAGING_DIR" | cut -f1)
    log_info "  Staging directory size: $staging_size"
}

# Main
main() {
    log_info "========================================="
    log_info "CoMaps Headers Bundler"
    log_info "========================================="
    
    check_comaps_source
    prepare_staging
    copy_toplevel_files
    bundle_comaps_headers
    bundle_3party_headers
    show_stats
    create_tarball
    
    # Cleanup staging (optional - keep for debugging)
    # rm -rf "$STAGING_DIR"
    
    log_info "========================================="
    log_info "Headers bundled successfully!"
    log_info "Output: $OUTPUT_FILE"
    log_info "========================================="
}

main "$@"
