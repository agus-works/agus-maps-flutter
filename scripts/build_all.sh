#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# build_all.sh - Self-Contained Build Script for macOS
# ============================================================================
#
# This is a completely self-contained script that builds agus_maps_flutter
# for all platforms supported on macOS: Android, iOS, and macOS.
#
# It does NOT call any other scripts in the scripts/ directory.
# It handles all setup, dependency installation, caching, and building.
#
# Usage:
#   ./scripts/build_all.sh
#
# ============================================================================

# ============================================================================
# Configuration (easily changeable)
# ============================================================================

# CoMaps/comaps git tag - MUST match .github/workflows/devops.yml
COMAPS_TAG="v2025.12.28-2"

# Tool versions - MUST match .github/workflows/devops.yml
FLUTTER_VERSION="3.38.5"
CMAKE_VERSION="3.31.10"
NDK_VERSION="27.3.13750724"

# Build configuration
BUILD_TYPE="Release"

# Android configuration
ANDROID_MIN_SDK="24"
ANDROID_ABIS="arm64-v8a armeabi-v7a x86_64"

# iOS configuration
IOS_DEPLOYMENT_TARGET="15.6"

# macOS configuration
MACOS_DEPLOYMENT_TARGET="12.0"

# Cache file naming (includes tag for versioning)
# Sanitize tag for filename (replace slashes and special chars)
CACHE_TAG_SAFE="${COMAPS_TAG//\//_}"
CACHE_TAG_SAFE="${CACHE_TAG_SAFE//[^a-zA-Z0-9._-]/_}"
THIRDPARTY_CACHE_FILE=".thirdparty-${CACHE_TAG_SAFE}.tar.bz2"

# ============================================================================
# Derived paths (do not modify)
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
THIRDPARTY_DIR="$ROOT_DIR/thirdparty"
COMAPS_DIR="$THIRDPARTY_DIR/comaps"
CACHE_FILE="$ROOT_DIR/$THIRDPARTY_CACHE_FILE"
BUILD_DIR="$ROOT_DIR/build"
PATCH_DIR="$ROOT_DIR/patches/comaps"

# ============================================================================
# Colors and logging
# ============================================================================

if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    CYAN=''
    BLUE=''
    NC=''
fi

log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_header()  { echo -e "${CYAN}=== $1 ===${NC}"; }
log_step()    { echo -e "${BLUE}[STEP]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

# ============================================================================
# Platform check
# ============================================================================

PLATFORM="unknown"
NUM_CORES=1
SED_INPLACE="sed -i"

check_platform() {
    log_header "Checking Platform"
    
    case "$(uname -s)" in
        Darwin)
            PLATFORM="macos"
            NUM_CORES=$(sysctl -n hw.ncpu)
            SED_INPLACE="sed -i ''"
            log_info "Platform: macOS $(sw_vers -productVersion)"
            log_info "Architecture: $(uname -m)"
            ;;
        Linux)
            PLATFORM="linux"
            NUM_CORES=$(nproc)
            SED_INPLACE="sed -i"
            log_info "Platform: Linux"
            log_info "Architecture: $(uname -m)"
            ;;
        *)
            log_error "Unsupported platform: $(uname -s)"
            exit 1
            ;;
    esac
}

# ============================================================================
# Dependency checks and installation
# ============================================================================

check_linux_dependencies() {
    log_header "Checking Linux Dependencies"
    
    local missing_deps=()
    
    # Check for commands (note: java is optional, only needed for Android builds)
    for cmd in git cmake ninja clang curl unzip zip patch; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    # Check for libraries (using pkg-config)
    if command -v pkg-config &>/dev/null; then
        local libs_to_check=(
            "gtk+-3.0:libgtk-3-dev"
            "libcurl:libcurl4-openssl-dev"
            "x11:libx11-dev"
        )
        for lib_pair in "${libs_to_check[@]}"; do
            local lib_name="${lib_pair%%:*}"
            local pkg_name="${lib_pair##*:}"
            if ! pkg-config --exists "$lib_name"; then
                 missing_deps+=("$pkg_name")
            fi
        done
        # glu includes gl usually, but let's check basic stuff
        # On Ubuntu, gl is provided by libgl1-mesa-dev, glu by libglu1-mesa-dev
        # We can't easily check for libraries without compilation or pkg-config if they don't have pc files
        # But development headers are usually what we need.
    else
         missing_deps+=("pkg-config")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        log_error "Please run the following command to install them:"
        log_error "sudo apt-get update && sudo apt-get install -y git cmake ninja-build build-essential pkg-config libgtk-3-dev libgl1-mesa-dev libglu1-mesa-dev liblz4-tool clang curl unzip zip python3-venv libcurl4-openssl-dev libx11-dev"
        exit 1
    fi
    
    log_success "Linux dependencies check passed"
}

check_homebrew() {
    if [[ "$PLATFORM" != "macos" ]]; then return; fi
    if ! command -v brew &>/dev/null; then
        log_info "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        
        # Add to PATH for current session
        if [[ -f "/opt/homebrew/bin/brew" ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [[ -f "/usr/local/bin/brew" ]]; then
            eval "$(/usr/local/bin/brew shellenv)"
        fi
    fi
    log_info "Homebrew: $(brew --version | head -1)"
}

check_xcode() {
    if [[ "$PLATFORM" != "macos" ]]; then return; fi
    if ! command -v xcodebuild &>/dev/null; then
        log_error "Xcode is not installed."
        log_error "Install from the App Store and run: xcode-select --install"
        exit 1
    fi
    
    # Check for command line tools
    if ! xcode-select -p &>/dev/null; then
        log_info "Installing Xcode Command Line Tools..."
        xcode-select --install
        log_error "Please run this script again after installing Xcode Command Line Tools."
        exit 1
    fi
    
    log_info "Xcode: $(xcodebuild -version | head -1)"
}

check_cmake() {
    local need_install=false
    
    if ! command -v cmake &>/dev/null; then
        need_install=true
    else
        local current_version
        current_version=$(cmake --version | head -1 | sed 's/cmake version //')
        if [[ "$current_version" != "$CMAKE_VERSION" ]]; then
            log_warn "CMake version mismatch: found $current_version, need $CMAKE_VERSION"
            if [[ "$PLATFORM" == "macos" ]]; then
                need_install=true
            fi
        fi
    fi
    
    if [[ "$need_install" == "true" ]]; then
        if [[ "$PLATFORM" == "macos" ]]; then
            log_info "Installing CMake $CMAKE_VERSION..."
            brew install cmake || brew upgrade cmake || true
        else
            log_error "CMake not found or version mismatch. Please install CMake $CMAKE_VERSION manually."
            exit 1
        fi
        
        # Verify installation
        if ! command -v cmake &>/dev/null; then
            log_error "Failed to install CMake"
            exit 1
        fi
    fi
    
    log_info "CMake: $(cmake --version | head -1)"
}

check_ninja() {
    if ! command -v ninja &>/dev/null; then
        log_info "Installing Ninja..."
        if [[ "$PLATFORM" == "macos" ]]; then
            brew install ninja
        else
            log_error "Ninja not found. Please install ninja-build."
            exit 1
        fi
    fi
    log_info "Ninja: $(ninja --version)"
}

check_git() {
    if ! command -v git &>/dev/null; then
        log_error "Git is not installed."
        exit 1
    fi
    log_info "Git: $(git --version)"
}

check_python() {
    if ! command -v python3 &>/dev/null; then
        log_info "Installing Python 3..."
        if [[ "$PLATFORM" == "macos" ]]; then
            brew install python3
        else
            log_error "Python 3 not found."
            exit 1
        fi
    fi
    log_info "Python: $(python3 --version)"
}

check_flutter() {
    local need_install=false
    
    if ! command -v flutter &>/dev/null; then
        need_install=true
        # Add local flutter to path if exists
        if [[ -d "$HOME/.flutter/bin" ]]; then
            export PATH="$HOME/.flutter/bin:$PATH"
            need_install=false
        fi
    else
        local current_version
        current_version=$(flutter --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
        if [[ "$current_version" != "$FLUTTER_VERSION" ]]; then
            log_warn "Flutter version mismatch: found $current_version, need $FLUTTER_VERSION"
            # Don't force reinstall, just warn
        fi
    fi
    
    if [[ "$need_install" == "true" ]]; then
        log_info "Installing Flutter $FLUTTER_VERSION..."
        
        # Try FVM first (recommended)
        if command -v fvm &>/dev/null; then
            fvm install "$FLUTTER_VERSION"
            fvm global "$FLUTTER_VERSION"
        else
            # Direct installation
            local flutter_dir="$HOME/.flutter"
            if [[ ! -d "$flutter_dir" ]]; then
                git clone https://github.com/flutter/flutter.git -b "$FLUTTER_VERSION" "$flutter_dir"
            fi
            export PATH="$flutter_dir/bin:$PATH"
        fi
    fi
    
    if ! command -v flutter &>/dev/null; then
        log_error "Flutter is not available. Please install Flutter $FLUTTER_VERSION manually."
        log_error "Visit: https://docs.flutter.dev/get-started/install"
        exit 1
    fi
    
    log_info "Flutter: $(flutter --version 2>/dev/null | head -1 || echo 'installed')"
    
    # Accept licenses
    yes | flutter doctor --android-licenses 2>/dev/null || true
    
    # Configure flutter
    if [[ "$PLATFORM" == "linux" ]]; then
        flutter config --enable-linux-desktop >/dev/null 2>&1 || true
    elif [[ "$PLATFORM" == "macos" ]]; then
        flutter config --enable-macos-desktop >/dev/null 2>&1 || true
    fi
}

check_android_sdk() {
    # Common locations for Android SDK
    # Use ${VAR:-} syntax to handle unset variables with set -u
    local sdk_paths=(
        "${ANDROID_HOME:-}"
        "${ANDROID_SDK_ROOT:-}"
        "$HOME/Library/Android/sdk"
        "$HOME/Android/Sdk"
    )
    
    ANDROID_SDK=""
    for path in "${sdk_paths[@]}"; do
        if [[ -n "$path" ]] && [[ -d "$path" ]]; then
            ANDROID_SDK="$path"
            break
        fi
    done
    
    if [[ -z "$ANDROID_SDK" ]]; then
        log_error "Android SDK not found."
        log_error "Install Android Studio from: https://developer.android.com/studio"
        log_error "Or install via brew: brew install --cask android-studio"
        exit 1
    fi
    
    export ANDROID_HOME="$ANDROID_SDK"
    export ANDROID_SDK_ROOT="$ANDROID_SDK"
    log_info "Android SDK: $ANDROID_SDK"
}

check_android_ndk() {
    local ndk_path="$ANDROID_SDK/ndk/$NDK_VERSION"
    
    if [[ ! -d "$ndk_path" ]]; then
        log_info "Installing Android NDK $NDK_VERSION..."
        
        local sdkmanager="$ANDROID_SDK/cmdline-tools/latest/bin/sdkmanager"
        if [[ ! -f "$sdkmanager" ]]; then
            sdkmanager="$ANDROID_SDK/tools/bin/sdkmanager"
        fi
        
        if [[ -f "$sdkmanager" ]]; then
            yes | "$sdkmanager" "ndk;$NDK_VERSION" 2>/dev/null || true
        else
            log_error "sdkmanager not found. Install NDK manually via Android Studio SDK Manager."
            exit 1
        fi
    fi
    
    if [[ -d "$ndk_path" ]]; then
        NDK_PATH="$ndk_path"
        log_info "Android NDK: $NDK_VERSION"
    else
        log_error "Failed to install Android NDK $NDK_VERSION"
        exit 1
    fi
}

check_android_cmake() {
    local cmake_path="$ANDROID_SDK/cmake/$CMAKE_VERSION"
    
    if [[ ! -d "$cmake_path" ]]; then
        log_info "Installing Android SDK CMake $CMAKE_VERSION..."
        
        local sdkmanager="$ANDROID_SDK/cmdline-tools/latest/bin/sdkmanager"
        if [[ ! -f "$sdkmanager" ]]; then
            sdkmanager="$ANDROID_SDK/tools/bin/sdkmanager"
        fi
        
        if [[ -f "$sdkmanager" ]]; then
            yes | "$sdkmanager" "cmake;$CMAKE_VERSION" 2>/dev/null || true
        fi
    fi
    
    # Use system cmake if Android SDK cmake not available
    if [[ -d "$cmake_path" ]]; then
        ANDROID_CMAKE="$cmake_path/bin/cmake"
    else
        ANDROID_CMAKE="cmake"
    fi
    log_info "Android CMake: $ANDROID_CMAKE"
}

check_cocoapods() {
    if [[ "$PLATFORM" != "macos" ]]; then return; fi
    if ! command -v pod &>/dev/null; then
        log_info "Installing CocoaPods..."
        # Try gem first (faster), then brew
        if command -v gem &>/dev/null; then
            sudo gem install cocoapods 2>/dev/null || brew install cocoapods
        else
            brew install cocoapods
        fi
    fi
    log_info "CocoaPods: $(pod --version)"
}

check_protobuf_python() {
    # Set up Python virtual environment for protobuf
    local venv_dir="$ROOT_DIR/.venv"
    
    if [[ ! -d "$venv_dir" ]]; then
        log_info "Creating Python virtual environment..."
        python3 -m venv "$venv_dir"
    fi
    
    # Activate venv
    source "$venv_dir/bin/activate"
    
    # Install protobuf (compatible version)
    if ! python3 -c "import google.protobuf" 2>/dev/null; then
        log_info "Installing protobuf Python package..."
        pip install --upgrade pip
        pip install 'protobuf<4.0'
    fi
    
    log_info "Python protobuf: installed"
}

install_dependencies() {
    log_header "Installing Dependencies"
    
    if [[ "$PLATFORM" == "macos" ]]; then
        check_homebrew
        check_xcode
    elif [[ "$PLATFORM" == "linux" ]]; then
        check_linux_dependencies
    fi
    
    check_git
    check_cmake
    check_ninja
    check_python
    check_protobuf_python
    check_cocoapods
    check_flutter
    check_android_sdk
    check_android_ndk
    check_android_cmake
    
    log_success "All dependencies installed"
}

# ============================================================================
# CoMaps caching
# ============================================================================

check_cache_exists() {
    [[ -f "$CACHE_FILE" ]]
}

create_cache() {
    log_header "Creating Cache Archive"
    log_info "Compressing thirdparty to $THIRDPARTY_CACHE_FILE..."
    log_info "This may take several minutes..."
    
    # Remove existing cache if present
    [[ -f "$CACHE_FILE" ]] && rm -f "$CACHE_FILE"
    
    local start_time
    start_time=$(date +%s)
    
    # Use bzip2 with max compression
    BZIP2=-9 tar -cjf "$CACHE_FILE" -C "$ROOT_DIR" thirdparty
    
    local end_time
    end_time=$(date +%s)
    local elapsed=$((end_time - start_time))
    
    local size_mb
    size_mb=$(($(stat -f%z "$CACHE_FILE" 2>/dev/null || stat -c%s "$CACHE_FILE") / 1024 / 1024))
    
    log_info "Cache created: ${size_mb} MB in ${elapsed} seconds"
    log_info "Cache file: $THIRDPARTY_CACHE_FILE (tag: $COMAPS_TAG)"
}

restore_from_cache() {
    log_header "Restoring from Cache"
    log_info "Extracting $THIRDPARTY_CACHE_FILE..."
    
    # Remove existing thirdparty if present
    [[ -d "$THIRDPARTY_DIR" ]] && rm -rf "$THIRDPARTY_DIR"
    
    local start_time
    start_time=$(date +%s)
    
    tar -xjf "$CACHE_FILE" -C "$ROOT_DIR"
    
    local end_time
    end_time=$(date +%s)
    local elapsed=$((end_time - start_time))
    
    log_info "Extracted in ${elapsed} seconds"
}

# ============================================================================
# CoMaps fetch and setup
# ============================================================================

fetch_comaps() {
    log_header "Fetching CoMaps Source"
    
    FRESH_CLONE=false
    
    mkdir -p "$THIRDPARTY_DIR"
    
    if [[ ! -d "$COMAPS_DIR/.git" ]]; then
        log_info "Cloning CoMaps from github.com/comaps/comaps..."
        log_info "Target tag: $COMAPS_TAG"
        log_info "This may take 5-10 minutes..."
        
        git clone https://github.com/comaps/comaps.git "$COMAPS_DIR"
        FRESH_CLONE=true
    fi
    
    pushd "$COMAPS_DIR" >/dev/null
    
    # Check if already at correct tag
    local current_hash target_hash
    target_hash=$(git rev-parse "$COMAPS_TAG" 2>/dev/null || echo "")
    current_hash=$(git rev-parse HEAD 2>/dev/null || echo "")
    
    if [[ -n "$target_hash" ]] && [[ "$target_hash" == "$current_hash" ]]; then
        log_info "Already at $COMAPS_TAG"
    else
        log_info "Checking out $COMAPS_TAG..."
        git fetch --tags --prune
        git checkout --detach "$COMAPS_TAG"
        FRESH_CLONE=true
    fi
    
    # Initialize ALL submodules recursively (critical for patches)
    log_info "Initializing submodules (this may take a while)..."
    
    # Fix Codeberg URLs (replace with Organic Maps GitHub mirrors) - Codeberg might be down/slow
    if [[ -f ".gitmodules" ]]; then
        log_info "Patching .gitmodules to use GitHub mirrors for stability..."
        $SED_INPLACE 's|https://codeberg.org/comaps/protobuf.git|https://github.com/organicmaps/protobuf.git|g' .gitmodules || true
        $SED_INPLACE 's|https://codeberg.org/comaps/kothic.git|https://github.com/organicmaps/kothic.git|g' .gitmodules || true
    fi
    
    git submodule update --init --recursive
    
    log_info "At $(git rev-parse --short HEAD) ($(git describe --tags --always --dirty 2>/dev/null || echo 'unknown'))"
    
    popd >/dev/null
    
    log_success "CoMaps source fetched"
}

apply_patches() {
    log_header "Applying Patches"
    
    if [[ ! -d "$PATCH_DIR" ]]; then
        log_warn "Patch directory not found: $PATCH_DIR"
        return 0
    fi
    
    shopt -s nullglob
    local patches=("$PATCH_DIR"/*.patch)
    
    if [[ ${#patches[@]} -eq 0 ]]; then
        log_warn "No patches found in $PATCH_DIR"
        return 0
    fi
    
    log_info "Found ${#patches[@]} patches to apply"
    
    pushd "$COMAPS_DIR" >/dev/null
    
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
        
        log_info "Processing patch: $patch_name"
        
        # Extract target file to check existence
        local target_file
        target_file=$(grep -m1 "^diff --git" "$patch" | sed 's|diff --git a/||; s| b/.*||' || true)
        
        if [[ -n "$target_file" ]]; then
             log_info "Target file: $target_file"
        else
             log_warn "Could not determine target file for $patch_name"
        fi
        
        if [[ -n "$target_file" ]] && [[ ! -e "$target_file" ]]; then
            log_warn "Skipping $patch_name (target '$target_file' not found)"
            ((++skipped)) || true
            continue
        fi
        
        # Try different application methods
        # Note: ((var++)) returns 1 when var was 0, so use || true to prevent set -e from exiting
        if git apply --whitespace=nowarn "$patch" 2>/dev/null; then
            log_info "Applied: $patch_name"
            ((++applied)) || true
        elif git apply --3way --whitespace=nowarn "$patch" 2>/dev/null; then
            log_info "Applied (3-way): $patch_name"
            ((++applied)) || true
        elif git apply --check --reverse "$patch" 2>/dev/null; then
            log_warn "Already applied: $patch_name"
            ((++skipped)) || true
        elif patch -p1 --batch --forward --dry-run < "$patch" >/dev/null 2>&1; then
            patch -p1 --batch --forward < "$patch" >/dev/null 2>&1
            log_info "Applied (patch): $patch_name"
            ((++applied)) || true
        else
            log_error "Failed: $patch_name"
            ((++failed)) || true
            # Fail fast to debug
            # exit 1
        fi
    done
    
    popd >/dev/null
    
    log_info "Patch summary: Applied=$applied, Skipped=$skipped, Failed=$failed"
    
    if [[ $failed -gt 0 ]]; then
        log_warn "Some patches failed - build may still succeed"
    fi
}

build_boost_headers() {
    log_header "Building Boost Headers"
    
    local boost_dir="$COMAPS_DIR/3party/boost"
    
    if [[ -f "$boost_dir/boost/config.hpp" ]]; then
        log_info "Boost headers already built"
        return 0
    fi
    
    if [[ ! -d "$boost_dir" ]]; then
        log_error "Boost directory not found: $boost_dir"
        return 1
    fi
    
    pushd "$boost_dir" >/dev/null
    
    log_info "Running bootstrap.sh..."
    ./bootstrap.sh
    
    log_info "Building headers with b2..."
    ./b2 headers
    
    popd >/dev/null
    
    log_success "Boost headers built"
}

generate_comaps_data() {
    log_header "Generating CoMaps Data Files"
    
    local data_dir="$COMAPS_DIR/data"
    
    # Check if files already exist
    if [[ -f "$data_dir/classificator.txt" ]] && \
       [[ -f "$data_dir/types.txt" ]] && \
       [[ -f "$data_dir/visibility.txt" ]] && \
       [[ -f "$data_dir/categories.txt" ]]; then
        log_info "Data files already generated"
        return 0
    fi
    
    pushd "$COMAPS_DIR" >/dev/null
    
    # Set protobuf compatibility mode
    export PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=python
    
    # Activate Python venv if available
    if [[ -f "$ROOT_DIR/.venv/bin/activate" ]]; then
        source "$ROOT_DIR/.venv/bin/activate"
    fi
    
    # Generate drawing rules
    if [[ -x "tools/unix/generate_drules.sh" ]]; then
        log_info "Generating drawing rules..."
        OMIM_PATH="$COMAPS_DIR" DATA_PATH="$data_dir" bash tools/unix/generate_drules.sh 2>&1 || log_warn "generate_drules.sh had warnings"
    fi
    
    # Generate categories
    if [[ -x "tools/unix/generate_categories.sh" ]]; then
        log_info "Generating categories..."
        bash tools/unix/generate_categories.sh 2>&1 || log_warn "generate_categories.sh had warnings"
    fi

    # Generate desktop UI strings (required for indexer lib)
    if [[ -x "tools/unix/generate_desktop_ui_strings.sh" ]]; then
        log_info "Generating desktop UI strings..."
        bash tools/unix/generate_desktop_ui_strings.sh 2>&1 || log_warn "generate_desktop_ui_strings.sh had warnings"
    fi
    
    # Download symbol textures
    log_info "Downloading symbol textures..."
    local resolutions=(mdpi hdpi xhdpi xxhdpi xxxhdpi 6plus)
    local themes=(light dark)
    for res in "${resolutions[@]}"; do
        for theme in "${themes[@]}"; do
            local symbol_dir="$data_dir/symbols/$res/$theme"
            mkdir -p "$symbol_dir"
            if [[ ! -f "$symbol_dir/symbols.sdf" ]]; then
                curl -sL "https://raw.githubusercontent.com/organicmaps/organicmaps/master/data/symbols/$res/$theme/symbols.sdf" -o "$symbol_dir/symbols.sdf" 2>/dev/null || true
                curl -sL "https://raw.githubusercontent.com/organicmaps/organicmaps/master/data/symbols/$res/$theme/symbols.png" -o "$symbol_dir/symbols.png" 2>/dev/null || true
            fi
        done
    done
    
    popd >/dev/null
    
    log_success "CoMaps data generated"
}

copy_data_to_example() {
    log_header "Copying Data to Example Assets"
    
    local src="$COMAPS_DIR/data"
    local dst="$ROOT_DIR/example/assets/comaps_data"
    
    mkdir -p "$dst"
    
    # Essential files
    local files=(
        classificator.txt types.txt categories.txt visibility.txt
        countries.txt countries_meta.txt packed_polygons.bin
        drules_proto.bin drules_proto_default_light.bin drules_proto_default_dark.bin
        drules_proto_outdoors_light.bin drules_proto_outdoors_dark.bin
        drules_proto_vehicle_light.bin drules_proto_vehicle_dark.bin
        drules_hash transit_colors.txt colors.txt patterns.txt editor.config
    )
    
    for file in "${files[@]}"; do
        if [[ -f "$src/$file" ]]; then
            cp "$src/$file" "$dst/"
        fi
    done
    
    # Copy directories
    for dir in categories-strings countries-strings fonts symbols styles; do
        if [[ -d "$src/$dir" ]]; then
            mkdir -p "$dst/$dir"
            cp -r "$src/$dir/"* "$dst/$dir/" 2>/dev/null || true
        fi
    done
    
    # ICU data file
    local maps_dir="$ROOT_DIR/example/assets/maps"
    mkdir -p "$maps_dir"
    if [[ -f "$src/icudt75l.dat" ]]; then
        cp "$src/icudt75l.dat" "$maps_dir/"
    fi
    
    log_success "Data copied to example assets"
}

copy_android_assets() {
    log_header "Copying Android Assets"
    
    local fonts_src="$COMAPS_DIR/data/fonts"
    local fonts_dst="$ROOT_DIR/example/android/app/src/main/assets/fonts"
    
    if [[ -d "$fonts_src" ]]; then
        mkdir -p "$(dirname "$fonts_dst")"
        rm -rf "$fonts_dst"
        cp -r "$fonts_src" "$fonts_dst"
        local count
        count=$(find "$fonts_dst" -name '*.ttf' 2>/dev/null | wc -l | tr -d ' ')
        log_info "Copied $count font files to Android assets"
    fi
}

download_base_mwms() {
    log_header "Downloading Base MWM Files"
    
    local maps_dir="$ROOT_DIR/example/assets/maps"
    mkdir -p "$maps_dir"
    
    # Mirror and snapshot
    local mirror="https://omaps.wfr.software/maps/"
    
    # Fetch latest snapshot
    local html
    html=$(curl -sL "$mirror" 2>/dev/null || echo "")
    local snapshot
    snapshot=$(echo "$html" | grep -oE '[0-9]{6}' | sort -rn | head -1 || true)
    
    if [[ -z "$snapshot" ]]; then
        log_warn "Could not determine latest snapshot, using default"
        snapshot="251212"
    fi
    
    log_info "Using snapshot: $snapshot"
    
    # Download essential MWMs
    local mwms=("World" "WorldCoasts" "Gibraltar")
    
    for mwm in "${mwms[@]}"; do
        local dest="$maps_dir/${mwm}.mwm"
        if [[ ! -f "$dest" ]]; then
            log_info "Downloading ${mwm}.mwm..."
            mkdir -p "$(dirname "$dest")"
            curl -fL "${mirror}${snapshot}/${mwm}.mwm" -o "$dest" 2>/dev/null || log_warn "Failed to download ${mwm}.mwm"
        else
            log_info "${mwm}.mwm already exists"
        fi
    done
    
    log_success "Base MWM files ready"
}

# ============================================================================
# Platform builds
# ============================================================================

build_android() {
    log_header "Building Android Native Libraries"
    
    local output_dir="$BUILD_DIR/agus-binaries-android"
    rm -rf "$output_dir"
    mkdir -p "$output_dir"
    
    for abi in $ANDROID_ABIS; do
        log_step "Building for ABI: $abi"
        
        local build_path="$BUILD_DIR/android-$abi"
        rm -rf "$build_path"
        mkdir -p "$build_path"
        
        # CMake configure
        log_info "Configuring CMake for $abi..."
        "$ANDROID_CMAKE" \
            -B "$build_path" \
            -S "$ROOT_DIR/src" \
            -DCMAKE_TOOLCHAIN_FILE="$NDK_PATH/build/cmake/android.toolchain.cmake" \
            -DANDROID_ABI="$abi" \
            -DANDROID_PLATFORM="android-$ANDROID_MIN_SDK" \
            -DANDROID_NDK="$NDK_PATH" \
            -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
            -DANDROID=ON \
            -G "Ninja" \
            2>&1 | tee "$build_path/cmake_configure.log"
        
        # Build
        log_info "Building $abi..."
        "$ANDROID_CMAKE" --build "$build_path" --parallel "$NUM_CORES" \
            2>&1 | tee "$build_path/cmake_build.log"
        
        # Copy output
        mkdir -p "$output_dir/$abi"
        local lib_path="$build_path/libagus_maps_flutter.so"
        if [[ -f "$lib_path" ]]; then
            cp "$lib_path" "$output_dir/$abi/"
            log_info "Built: $output_dir/$abi/libagus_maps_flutter.so"
        else
            log_error "Build output not found: $lib_path"
            exit 1
        fi
    done
    
    # Create archive
    log_info "Creating archive..."
    pushd "$BUILD_DIR" >/dev/null
    zip -r "agus-binaries-android.zip" "agus-binaries-android"
    popd >/dev/null
    
    # Copy to android/prebuilt
    local prebuilt_dir="$ROOT_DIR/android/prebuilt"
    mkdir -p "$prebuilt_dir"
    cp -R "$output_dir"/* "$prebuilt_dir/"
    
    log_success "Android build complete: $BUILD_DIR/agus-binaries-android.zip"
}

build_ios() {
    log_header "Building iOS XCFramework"
    
    local output_dir="$BUILD_DIR/agus-binaries-ios"
    local ios_build_dir="$BUILD_DIR/ios"
    rm -rf "$output_dir" "$ios_build_dir"
    mkdir -p "$output_dir"
    
    local generator="Ninja"
    if ! command -v ninja &>/dev/null; then
        generator="Unix Makefiles"
    fi
    
    # Build for device (arm64)
    log_step "Building for iOS device (arm64)..."
    local device_build="$ios_build_dir/iphoneos"
    mkdir -p "$device_build"
    
    local device_sdk
    device_sdk=$(xcrun --sdk iphoneos --show-sdk-path)
    
    cmake -S "$COMAPS_DIR" -B "$device_build" \
        -G "$generator" \
        -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_ARCHITECTURES="arm64" \
        -DCMAKE_OSX_SYSROOT="$device_sdk" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="$IOS_DEPLOYMENT_TARGET" \
        -DPLATFORM_IPHONE=ON \
        -DPLATFORM_DESKTOP=OFF \
        -DSKIP_TESTS=ON \
        -DSKIP_QT=ON \
        -DSKIP_QT_GUI=ON \
        -DSKIP_TOOLS=ON \
        -DSKIP_PROTOBUF_CHECK=ON \
        -DWITH_SYSTEM_PROVIDED_3PARTY=OFF \
        2>&1 | tee "$device_build/cmake_configure.log"
    
    cmake --build "$device_build" --config "$BUILD_TYPE" -j "$NUM_CORES" \
        2>&1 | tee "$device_build/cmake_build.log"
    
    # Build for simulator (arm64 + x86_64)
    log_step "Building for iOS simulator (arm64, x86_64)..."
    local sim_build="$ios_build_dir/iphonesimulator"
    mkdir -p "$sim_build"
    
    local sim_sdk
    sim_sdk=$(xcrun --sdk iphonesimulator --show-sdk-path)
    
    cmake -S "$COMAPS_DIR" -B "$sim_build" \
        -G "$generator" \
        -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
        -DCMAKE_OSX_SYSROOT="$sim_sdk" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="$IOS_DEPLOYMENT_TARGET" \
        -DPLATFORM_IPHONE=ON \
        -DPLATFORM_DESKTOP=OFF \
        -DSKIP_TESTS=ON \
        -DSKIP_QT=ON \
        -DSKIP_QT_GUI=ON \
        -DSKIP_TOOLS=ON \
        -DSKIP_PROTOBUF_CHECK=ON \
        -DWITH_SYSTEM_PROVIDED_3PARTY=OFF \
        2>&1 | tee "$sim_build/cmake_configure.log"
    
    cmake --build "$sim_build" --config "$BUILD_TYPE" -j "$NUM_CORES" \
        2>&1 | tee "$sim_build/cmake_build.log"
    
    # Merge static libraries for each platform
    log_step "Merging static libraries..."
    
    merge_static_libs() {
        local build_path=$1
        local output_lib=$2
        
        local libs=()
        while IFS= read -r -d '' lib; do
            if [[ "$lib" != *"CMakeFiles"* ]]; then
                libs+=("$lib")
            fi
        done < <(find "$build_path" -name "*.a" -print0)
        
        if [[ ${#libs[@]} -gt 0 ]]; then
            libtool -static -o "$output_lib" "${libs[@]}"
            log_info "Merged: $output_lib ($(du -h "$output_lib" | cut -f1))"
        fi
    }
    
    mkdir -p "$ios_build_dir/device"
    mkdir -p "$ios_build_dir/simulator"
    
    merge_static_libs "$device_build" "$ios_build_dir/device/libcomaps.a"
    merge_static_libs "$sim_build" "$ios_build_dir/simulator/libcomaps.a"
    
    # Create XCFramework
    log_step "Creating XCFramework..."
    xcodebuild -create-xcframework \
        -library "$ios_build_dir/device/libcomaps.a" \
        -library "$ios_build_dir/simulator/libcomaps.a" \
        -output "$output_dir/CoMaps.xcframework"
    
    # Copy to ios/Frameworks
    local frameworks_dir="$ROOT_DIR/ios/Frameworks"
    mkdir -p "$frameworks_dir"
    cp -R "$output_dir/CoMaps.xcframework" "$frameworks_dir/"
    
    # Create archive
    pushd "$output_dir" >/dev/null
    zip -r "$BUILD_DIR/agus-binaries-ios.zip" "CoMaps.xcframework"
    popd >/dev/null
    
    log_success "iOS build complete: $BUILD_DIR/agus-binaries-ios.zip"
}

build_macos() {
    log_header "Building macOS XCFramework"
    
    local output_dir="$BUILD_DIR/agus-binaries-macos"
    local macos_build_dir="$BUILD_DIR/macos"
    rm -rf "$output_dir" "$macos_build_dir"
    mkdir -p "$output_dir"
    
    local generator="Ninja"
    if ! command -v ninja &>/dev/null; then
        generator="Unix Makefiles"
    fi
    
    local sdk_path
    sdk_path=$(xcrun --sdk macosx --show-sdk-path)
    
    # Build arm64
    log_step "Building for macOS arm64..."
    local arm64_build="$macos_build_dir/arm64"
    mkdir -p "$arm64_build"
    
    cmake -S "$COMAPS_DIR" -B "$arm64_build" \
        -G "$generator" \
        -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
        -DCMAKE_SYSTEM_NAME=Darwin \
        -DCMAKE_OSX_ARCHITECTURES="arm64" \
        -DCMAKE_OSX_SYSROOT="$sdk_path" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET" \
        -DPLATFORM_IPHONE=OFF \
        -DPLATFORM_DESKTOP=ON \
        -DSKIP_TESTS=ON \
        -DSKIP_QT=ON \
        -DSKIP_QT_GUI=ON \
        -DSKIP_TOOLS=ON \
        -DSKIP_PROTOBUF_CHECK=ON \
        -DWITH_SYSTEM_PROVIDED_3PARTY=OFF \
        2>&1 | tee "$arm64_build/cmake_configure.log"
    
    cmake --build "$arm64_build" --config "$BUILD_TYPE" --target map -j "$NUM_CORES" \
        2>&1 | tee "$arm64_build/cmake_build.log"
    
    # Build x86_64
    log_step "Building for macOS x86_64..."
    local x64_build="$macos_build_dir/x86_64"
    mkdir -p "$x64_build"
    
    cmake -S "$COMAPS_DIR" -B "$x64_build" \
        -G "$generator" \
        -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
        -DCMAKE_SYSTEM_NAME=Darwin \
        -DCMAKE_OSX_ARCHITECTURES="x86_64" \
        -DCMAKE_OSX_SYSROOT="$sdk_path" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET" \
        -DPLATFORM_IPHONE=OFF \
        -DPLATFORM_DESKTOP=ON \
        -DSKIP_TESTS=ON \
        -DSKIP_QT=ON \
        -DSKIP_QT_GUI=ON \
        -DSKIP_TOOLS=ON \
        -DSKIP_PROTOBUF_CHECK=ON \
        -DWITH_SYSTEM_PROVIDED_3PARTY=OFF \
        2>&1 | tee "$x64_build/cmake_build.log"
    
    cmake --build "$x64_build" --config "$BUILD_TYPE" --target map -j "$NUM_CORES" \
        2>&1 | tee "$x64_build/cmake_build.log"
    
    # Merge static libraries
    log_step "Merging static libraries..."
    
    merge_static_libs() {
        local build_path=$1
        local output_lib=$2
        
        local libs=()
        while IFS= read -r -d '' lib; do
            if [[ "$lib" != *"CMakeFiles"* ]]; then
                libs+=("$lib")
            fi
        done < <(find "$build_path" -name "*.a" -print0)
        
        if [[ ${#libs[@]} -gt 0 ]]; then
            libtool -static -o "$output_lib" "${libs[@]}"
            log_info "Merged: $output_lib ($(du -h "$output_lib" | cut -f1))"
        fi
    }
    
    merge_static_libs "$arm64_build" "$macos_build_dir/libcomaps-arm64.a"
    merge_static_libs "$x64_build" "$macos_build_dir/libcomaps-x86_64.a"
    
    # Create universal binary
    log_step "Creating universal binary..."
    mkdir -p "$macos_build_dir/universal"
    lipo -create \
        "$macos_build_dir/libcomaps-arm64.a" \
        "$macos_build_dir/libcomaps-x86_64.a" \
        -output "$macos_build_dir/universal/libcomaps.a"
    
    # Create XCFramework
    log_step "Creating XCFramework..."
    xcodebuild -create-xcframework \
        -library "$macos_build_dir/universal/libcomaps.a" \
        -output "$output_dir/CoMaps.xcframework"
    
    # Copy to macos/Frameworks
    local frameworks_dir="$ROOT_DIR/macos/Frameworks"
    mkdir -p "$frameworks_dir"
    cp -R "$output_dir/CoMaps.xcframework" "$frameworks_dir/"
    
    # Create archive
    pushd "$output_dir" >/dev/null
    zip -r "$BUILD_DIR/agus-binaries-macos.zip" "CoMaps.xcframework"
    popd >/dev/null
    
    log_success "macOS build complete: $BUILD_DIR/agus-binaries-macos.zip"
}

build_linux() {
    log_header "Building Linux Native Library"
    
    if [[ "$PLATFORM" != "linux" ]]; then return; fi
    
    local output_dir="$BUILD_DIR/agus-binaries-linux"
    rm -rf "$output_dir"
    mkdir -p "$output_dir"
    
    local linux_build_dir="$BUILD_DIR/linux"
    rm -rf "$linux_build_dir"
    mkdir -p "$linux_build_dir"
    
    # We build the shared library using src/CMakeLists.txt, but we need to set up the build context
    # correctly since src/CMakeLists.txt expects to be part of a larger build or needs
    # proper variable setup.
    # However, src/CMakeLists.txt is designed to be included.
    # Let's use a temporary CMakeLists.txt to build it as a standalone lib for verification/bundling.
    
    local tmp_cmake="$linux_build_dir/CMakeLists.txt"
    cat > "$tmp_cmake" <<EOF
cmake_minimum_required(VERSION 3.10)
project(agus_maps_flutter_linux_wrapper LANGUAGES CXX C)
set(CMAKE_CXX_STANDARD 23)
add_subdirectory("${ROOT_DIR}/src" "src")
EOF
    
    # Needs Clang for C++23 if available
    local cxx_compiler="clang++"
    local c_compiler="clang"
    if ! command -v clang++ &>/dev/null; then
         log_warn "Clang not found, trying g++ (might fail if too old)"
         cxx_compiler="g++"
         c_compiler="gcc"
    fi

    log_step "Configuring CMake for Linux..."
    cmake -S "$linux_build_dir" -B "$linux_build_dir/build" \
        -G "Ninja" \
        -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
        -DCMAKE_CXX_COMPILER="$cxx_compiler" \
        -DCMAKE_C_COMPILER="$c_compiler" \
        2>&1 | tee "$linux_build_dir/cmake_configure.log"
        
    log_step "Building Linux library..."
    cmake --build "$linux_build_dir/build" --parallel "$NUM_CORES" \
        2>&1 | tee "$linux_build_dir/cmake_build.log"
        
    # Find and copy the library
    local lib_path
    lib_path=$(find "$linux_build_dir/build" -name "libagus_maps_flutter.so" | head -1)
    
    if [[ -f "$lib_path" ]]; then
        cp "$lib_path" "$output_dir/"
        log_info "Built: $output_dir/libagus_maps_flutter.so"
    else
        log_error "Build failed or library not found in expected location"
        # Don't exit, just warn, as the main flutter build might still work if this was just a check
    fi
    
    # Create archive
    pushd "$BUILD_DIR" >/dev/null
    zip -r "agus-binaries-linux.zip" "agus-binaries-linux"
    popd >/dev/null
    
    log_success "Linux build complete: $BUILD_DIR/agus-binaries-linux.zip"
}

# ============================================================================
# Flutter setup
# ============================================================================

setup_flutter() {
    log_header "Setting Up Flutter"
    
    pushd "$ROOT_DIR" >/dev/null
    flutter pub get
    popd >/dev/null
    
    pushd "$ROOT_DIR/example" >/dev/null
    flutter pub get
    popd >/dev/null
    
    log_success "Flutter dependencies installed"
}

setup_cocoapods_ios() {
    log_header "Installing iOS CocoaPods"
    
    pushd "$ROOT_DIR/example/ios" >/dev/null
    pod install
    popd >/dev/null
    
    log_success "iOS CocoaPods installed"
}

setup_cocoapods_macos() {
    log_header "Installing macOS CocoaPods"
    
    pushd "$ROOT_DIR/example/macos" >/dev/null
    pod install
    popd >/dev/null
    
    log_success "macOS CocoaPods installed"
}

# ============================================================================
# Main
# ============================================================================

print_banner() {
    echo ""
    echo "========================================="
    echo "agus_maps_flutter - Build All (macOS)"
    echo "========================================="
    echo ""
    echo "Configuration:"
    echo "  CoMaps Tag:     $COMAPS_TAG"
    echo "  Flutter:        $FLUTTER_VERSION"
    echo "  CMake:          $CMAKE_VERSION"
    echo "  NDK:            $NDK_VERSION"
    echo "  Build Type:     $BUILD_TYPE"
    echo "  Cache File:     $THIRDPARTY_CACHE_FILE"
    echo ""
    echo "Targets: Android, iOS, macOS"
    echo ""
}

print_summary() {
    echo ""
    echo "========================================="
    echo "BUILD COMPLETE"
    echo "========================================="
    echo ""
    echo "Build outputs:"
    echo "  - Android: $BUILD_DIR/agus-binaries-android.zip"
    if [[ "$PLATFORM" == "macos" ]]; then
        echo "  - iOS:     $BUILD_DIR/agus-binaries-ios.zip"
        echo "  - macOS:   $BUILD_DIR/agus-binaries-macos.zip"
    elif [[ "$PLATFORM" == "linux" ]]; then
        echo "  - Linux:   $BUILD_DIR/agus-binaries-linux.zip"
    fi
    echo ""
    echo "Native libraries installed to:"
    echo "  - android/prebuilt/"
    if [[ "$PLATFORM" == "macos" ]]; then
        echo "  - ios/Frameworks/"
        echo "  - macos/Frameworks/"
    fi
    echo ""
    echo "To run the example app:"
    echo "  cd example"
    echo "  flutter run -d <device>"
    echo ""
    if check_cache_exists; then
        local size_mb
        size_mb=$(($(stat -f%z "$CACHE_FILE" 2>/dev/null || stat -c%s "$CACHE_FILE") / 1024 / 1024))
        echo "Cache available: $THIRDPARTY_CACHE_FILE (${size_mb} MB)"
        echo "  Tip: Delete 'thirdparty' folder and re-run to use cache"
    fi
    echo ""
}

build_metal_shaders() {
    log_header "Building Metal Shaders"
    
    local shaders_dir="$COMAPS_DIR/libs/shaders/Metal"
    local temp_dir="$ROOT_DIR/build/metal_temp"
    local output_lib="$ROOT_DIR/build/metal_shaders/shaders_metal.metallib"
    
    mkdir -p "$temp_dir"
    mkdir -p "$(dirname "$output_lib")"
    
    log_info "Compiling Metal shaders from $shaders_dir..."
    
    # Check if we have source files
    if [[ ! -d "$shaders_dir" ]]; then
        log_error "Shaders directory not found: $shaders_dir"
        exit 1
    fi
    
    # Compile each .metal file to .air
    local air_files=()
    for src in "$shaders_dir"/*.metal; do
        local filename=$(basename "$src")
        local name="${filename%.*}"
        local output="$temp_dir/${name}.air"
        
        # Note: We use macosx SDK but the resulting library works for both macOS and iOS 
        # because we use standard Metal 2.0 features.
        xcrun -sdk macosx metal -c -std=osx-metal2.0 \
            -I "$shaders_dir" \
            -o "$output" \
            "$src"
            
        if [[ $? -ne 0 ]]; then
            log_error "Failed to compile $filename"
            exit 1
        fi
        
        air_files+=("$output")
    done
    
    # Link .air files to .metallib
    log_info "Linking ${#air_files[@]} shaders..."
    xcrun -sdk macosx metallib -o "$output_lib" "${air_files[@]}"
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to link Metal library"
        exit 1
    fi
    
    log_success "Created $(basename "$output_lib")"
    
    # Copy to platform resource directories
    local destinations=(
        "$ROOT_DIR/ios/Resources"
        "$ROOT_DIR/macos/Resources"
        "$ROOT_DIR/example/macos/Runner/Resources" # Ensure example app gets it too just in case
    )
    
    for dest in "${destinations[@]}"; do
        mkdir -p "$dest"
        cp "$output_lib" "$dest/"
        log_info "Copied to $dest"
    done
}

main() {
    print_banner
    
    # Platform check
    check_platform
    
    # Install dependencies
    install_dependencies
    
    # Download assets and setup Flutter dependencies early to fail fast
    download_base_mwms
    setup_flutter
    
    # Handle caching and CoMaps setup
    local used_cache=false
    
    if [[ ! -d "$COMAPS_DIR" ]] && check_cache_exists; then
        log_info "Found cache for tag $COMAPS_TAG"
        restore_from_cache
        used_cache=true
    fi
    
    # Fetch/update CoMaps
    fetch_comaps
    
    # Create cache after fresh clone (before patches)
    if [[ "$FRESH_CLONE" == "true" ]] && [[ "$used_cache" != "true" ]]; then
        create_cache
    fi
    
    # Apply patches
    apply_patches
    
    # Build dependencies
    build_boost_headers
    generate_comaps_data
    
    # Copy assets
    copy_data_to_example
    copy_android_assets
    if [[ "$PLATFORM" == "macos" ]]; then
        build_metal_shaders
    fi
    
    # Build all platforms
    build_android
    if [[ "$PLATFORM" == "macos" ]]; then
        build_ios
        build_macos
    elif [[ "$PLATFORM" == "linux" ]]; then
        build_linux
    fi
    
    # CocoaPods setup (requires built frameworks)
    if [[ "$PLATFORM" == "macos" ]]; then
        setup_cocoapods_ios
        setup_cocoapods_macos
    fi
    
    print_summary
}

# Run
main "$@"
