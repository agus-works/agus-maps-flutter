#!/usr/bin/env bash
# 
# Copy essential CoMaps data files to example app assets.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
COMAPS_DATA="$ROOT_DIR/thirdparty/comaps/data"
DEST_DATA="$ROOT_DIR/example/assets/comaps_data"

echo "Copying CoMaps data files to example assets..."

# Create destination directory
mkdir -p "$DEST_DATA"

# Essential files for Framework initialization
ESSENTIAL_FILES=(
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

for file in "${ESSENTIAL_FILES[@]}"; do
    if [ -f "$COMAPS_DATA/$file" ]; then
        cp "$COMAPS_DATA/$file" "$DEST_DATA/"
        echo "  ✓ $file"
    else
        echo "  ✗ $file (not found)"
    fi
done

# Copy categories-strings (needed for search)
if [ -d "$COMAPS_DATA/categories-strings" ]; then
    mkdir -p "$DEST_DATA/categories-strings"
    cp -r "$COMAPS_DATA/categories-strings/"* "$DEST_DATA/categories-strings/"
    echo "  ✓ categories-strings/"
fi

# Copy countries-strings (needed for localization)
if [ -d "$COMAPS_DATA/countries-strings" ]; then
    mkdir -p "$DEST_DATA/countries-strings"
    cp -r "$COMAPS_DATA/countries-strings/"* "$DEST_DATA/countries-strings/"
    echo "  ✓ countries-strings/"
fi

# Copy symbols (needed for rendering)
if [ -d "$COMAPS_DATA/symbols" ]; then
    mkdir -p "$DEST_DATA/symbols"
    cp -r "$COMAPS_DATA/symbols/"* "$DEST_DATA/symbols/"
    echo "  ✓ symbols/"
fi

# Copy styles (needed for rendering)
if [ -d "$COMAPS_DATA/styles" ]; then
    mkdir -p "$DEST_DATA/styles"
    cp -r "$COMAPS_DATA/styles/"* "$DEST_DATA/styles/"
    echo "  ✓ styles/"
fi

echo ""
echo "Data files copied to: $DEST_DATA"
echo ""
echo "Don't forget to add assets to pubspec.yaml:"
echo "  assets:"
echo "    - assets/comaps_data/"
echo ""
