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
    # Copy mdpi symbols for initial testing
    if [ -d "$COMAPS_DATA/symbols/mdpi" ]; then
        cp -r "$COMAPS_DATA/symbols/mdpi" "$DEST_DATA/symbols/"
        echo "  ✓ symbols/mdpi/"
    fi
    if [ -d "$COMAPS_DATA/symbols/xhdpi" ]; then
        cp -r "$COMAPS_DATA/symbols/xhdpi" "$DEST_DATA/symbols/"
        echo "  ✓ symbols/xhdpi/"
    fi
fi

echo ""
echo "Data files copied to: $DEST_DATA"
echo ""
echo "Don't forget to add assets to pubspec.yaml:"
echo "  assets:"
echo "    - assets/comaps_data/"
echo ""
