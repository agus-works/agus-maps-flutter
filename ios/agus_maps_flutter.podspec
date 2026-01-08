#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint agus_maps_flutter.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'agus_maps_flutter'
  s.version          = '0.1.6'
  s.summary          = 'High-performance offline maps for Flutter using CoMaps engine.'
  s.description      = <<-DESC
A Flutter plugin that provides high-performance offline vector map rendering
using the CoMaps (Organic Maps fork) C++ engine. Features zero-copy GPU texture
sharing via Metal and CVPixelBuffer for optimal performance on iOS devices.
                       DESC
  s.homepage         = 'https://github.com/agus-works/agus-maps-flutter'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Agus Maps' => 'agus@example.com' }
  s.source           = { :path => '.' }

  # ============================================================================
  # Prepare Command - Find or Download XCFramework
  # ============================================================================
  # Priority:
  # 1. Framework already exists in plugin directory (in-repo/CI builds)
  # 2. Framework found via relative paths (vendored plugin)
  # 3. Auto-download from GitHub releases (pub.dev consumers)
  #
  # NOTE: Even with auto-download, consumers MUST still extract the unified
  # binary package to their app root for assets (maps, ICU data, etc.)
  # ============================================================================
  s.prepare_command = <<-CMD
    set -e
    
    PLUGIN_VERSION="0.1.6"
    FRAMEWORK_NAME="CoMaps.xcframework"
    
    # Check if framework already exists (in-repo build or CI)
    if [ -d "Frameworks/${FRAMEWORK_NAME}" ]; then
      echo "[agus_maps_flutter] Found existing ${FRAMEWORK_NAME} in plugin directory"
      exit 0
    fi
    
    echo "[agus_maps_flutter] Searching for ${FRAMEWORK_NAME}..."
    
    # Search relative paths (vendored plugin scenario)
    SEARCH_PATHS=(
      "../../../../../Frameworks"
      "../../../../Frameworks"
      "../../../Frameworks"
      "../../Frameworks"
      "../ios/Frameworks"
      "../../ios/Frameworks"
    )
    
    for path in "${SEARCH_PATHS[@]}"; do
      if [ -d "${path}/${FRAMEWORK_NAME}" ]; then
        echo "[agus_maps_flutter] Found ${FRAMEWORK_NAME} at ${path}"
        mkdir -p Frameworks
        cp -R "${path}/${FRAMEWORK_NAME}" Frameworks/
        echo "[agus_maps_flutter] Copied ${FRAMEWORK_NAME} to plugin Frameworks/"
        exit 0
      fi
    done
    
    # Not found locally - download from GitHub releases
    echo "[agus_maps_flutter] ${FRAMEWORK_NAME} not found locally, downloading from GitHub releases..."
    
    DOWNLOAD_URL="https://github.com/agus-works/agus-maps-flutter/releases/download/v${PLUGIN_VERSION}/agus-binaries-ios-v${PLUGIN_VERSION}.zip"
    TEMP_DIR=$(mktemp -d)
    TEMP_ZIP="${TEMP_DIR}/ios-binaries.zip"
    
    echo "[agus_maps_flutter] Downloading from: ${DOWNLOAD_URL}"
    
    if command -v curl &> /dev/null; then
      curl -fsSL "${DOWNLOAD_URL}" -o "${TEMP_ZIP}"
    elif command -v wget &> /dev/null; then
      wget -q "${DOWNLOAD_URL}" -O "${TEMP_ZIP}"
    else
      echo "[agus_maps_flutter] ERROR: Neither curl nor wget found!"
      rm -rf "${TEMP_DIR}"
      exit 1
    fi
    
    if [ ! -f "${TEMP_ZIP}" ]; then
      echo "[agus_maps_flutter] ERROR: Download failed!"
      rm -rf "${TEMP_DIR}"
      exit 1
    fi
    
    echo "[agus_maps_flutter] Extracting ${FRAMEWORK_NAME}..."
    mkdir -p Frameworks
    unzip -q "${TEMP_ZIP}" -d Frameworks/
    
    rm -rf "${TEMP_DIR}"
    
    if [ -d "Frameworks/${FRAMEWORK_NAME}" ]; then
      echo "[agus_maps_flutter] Successfully downloaded and extracted ${FRAMEWORK_NAME}"
      echo ""
      echo "======================================================================="
      echo "IMPORTANT: You still need to download assets for your app!"
      echo "======================================================================="
      echo ""
      echo "The XCFramework was auto-downloaded, but you must still:"
      echo "  1. Download: https://github.com/agus-works/agus-maps-flutter/releases/download/v${PLUGIN_VERSION}/agus-maps-binaries-v${PLUGIN_VERSION}.zip"
      echo "  2. Extract to your app root to get assets/comaps_data/ and assets/maps/"
      echo "  3. Add assets to your pubspec.yaml"
      echo ""
      exit 0
    else
      echo "[agus_maps_flutter] ERROR: Extraction failed - ${FRAMEWORK_NAME} not found!"
      exit 1
    fi
  CMD

  # ============================================================================
  # Pre-built XCFramework Required
  # ============================================================================
  # Download the unified binary package from GitHub Releases and extract it to
  # your Flutter app root BEFORE running pod install:
  #
  #   1. Download: https://github.com/agus-works/agus-maps-flutter/releases
  #   2. Extract to your app root: unzip agus-maps-binaries-vX.Y.Z.zip -d my_app/
  #   3. This creates: my_app/ios/Frameworks/CoMaps.xcframework/
  #
  # The build will fail if ios/Frameworks/CoMaps.xcframework is not present.
  # ============================================================================

  # Source files - Swift plugin + Objective-C++ native code
  s.source_files = [
    'Classes/**/*.{h,m,mm,swift}',
    '../src/agus_maps_flutter.h',
  ]
  
  # Public headers for FFI - only C-compatible headers!
  # C++ headers must NOT be exposed to Swift module
  s.public_header_files = [
    'Classes/AgusPlatformIOS.h',
    'Classes/AgusBridge.h',
    '../src/agus_maps_flutter.h'
  ]
  
  # Private headers - C++ headers that should not be in umbrella header
  s.private_header_files = [
    'Classes/AgusMetalContextFactory.h'
  ]

  # Resource bundles for Metal shaders
  # Use resource_bundles to ensure shaders end up in the app's main bundle
  s.resource_bundles = {
    'agus_maps_flutter_shaders' => ['Resources/shaders_metal.metallib']
  }

  # Vendored CoMaps XCFramework - must be manually placed before pod install
  # Download from GitHub Releases: agus-maps-binaries-vX.Y.Z.zip
  s.vendored_frameworks = 'Frameworks/CoMaps.xcframework'

  # Required iOS frameworks
  s.frameworks = [
    'Metal',
    'MetalKit', 
    'CoreVideo',
    'CoreGraphics',
    'CoreFoundation',
    'QuartzCore',
    'UIKit',
    'Foundation',
    'Security',
    'SystemConfiguration',
    'CoreLocation'
  ]

  # System libraries
  s.libraries = 'c++', 'z', 'sqlite3'

  # Flutter dependency
  s.dependency 'Flutter'
  
  # iOS platform version (matches CoMaps requirement)
  s.platform = :ios, '15.6'

  # ============================================================================
  # Dual-path header detection for in-repo vs external consumers
  # ============================================================================
  # In-repo (example app): thirdparty/comaps exists → use local headers
  # External consumer: thirdparty/comaps doesn't exist → use downloaded Headers/
  # We include BOTH paths to handle CI environments where detection may vary
  # ============================================================================
  
  # Always define both path sets - compiler will use whichever exists
  thirdparty_base = '$(PODS_TARGET_SRCROOT)/../thirdparty/comaps'
  thirdparty_3party = "#{thirdparty_base}/3party"
  headers_base = '$(PODS_TARGET_SRCROOT)/Headers/comaps'
  headers_3party = "#{headers_base}/3party"

  # Build settings
  s.pod_target_xcconfig = {
    # C++ language standard
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++23',
    'CLANG_CXX_LIBRARY' => 'libc++',
    
    # Enable C++ exceptions and RTTI (required by CoMaps)
    'GCC_ENABLE_CPP_EXCEPTIONS' => 'YES',
    'GCC_ENABLE_CPP_RTTI' => 'YES',
    
    # Module settings
    'DEFINES_MODULE' => 'YES',
    
    # Exclude i386 (Flutter doesn't support it)
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    
    # Linker flags - force load all symbols from static libraries
    'OTHER_LDFLAGS' => '-ObjC -all_load',
    
    # Header search paths for CoMaps includes
    # Include both thirdparty (in-repo) and Headers (downloaded) paths
    # The compiler will use whichever paths exist
    'HEADER_SEARCH_PATHS' => [
      '"$(PODS_TARGET_SRCROOT)/../src"',
      # Thirdparty paths (in-repo development)
      "\"#{thirdparty_base}\"",
      "\"#{thirdparty_base}/libs\"",
      "\"#{thirdparty_3party}/boost\"",
      "\"#{thirdparty_3party}/glm\"",
      "\"#{thirdparty_3party}\"",
      "\"#{thirdparty_3party}/utfcpp/source\"",
      "\"#{thirdparty_3party}/jansson/jansson/src\"",
      "\"#{thirdparty_3party}/jansson\"",
      "\"#{thirdparty_3party}/expat/expat/lib\"",
      "\"#{thirdparty_3party}/icu/icu/source/common\"",
      "\"#{thirdparty_3party}/icu/icu/source/i18n\"",
      "\"#{thirdparty_3party}/freetype/include\"",
      "\"#{thirdparty_3party}/harfbuzz/harfbuzz/src\"",
      "\"#{thirdparty_3party}/minizip/minizip\"",
      "\"#{thirdparty_3party}/pugixml/pugixml/src\"",
      "\"#{thirdparty_3party}/protobuf/protobuf/src\"",
      # Downloaded headers paths (external consumers / CI)
      "\"#{headers_base}\"",
      "\"#{headers_base}/libs\"",
      "\"#{headers_3party}/boost\"",
      "\"#{headers_3party}/glm\"",
      "\"#{headers_3party}\"",
      "\"#{headers_3party}/utfcpp/source\"",
      "\"#{headers_3party}/jansson/jansson/src\"",
      "\"#{headers_3party}/jansson\"",
      "\"#{headers_3party}/expat/expat/lib\"",
      "\"#{headers_3party}/icu/icu/source/common\"",
      "\"#{headers_3party}/icu/icu/source/i18n\"",
      "\"#{headers_3party}/freetype/include\"",
      "\"#{headers_3party}/harfbuzz/harfbuzz/src\"",
      "\"#{headers_3party}/minizip/minizip\"",
      "\"#{headers_3party}/pugixml/pugixml/src\"",
      "\"#{headers_3party}/protobuf/protobuf/src\"",
    ].join(' '),
    
    # Preprocessor definitions
    # CoMaps requires either DEBUG or RELEASE/NDEBUG to be defined (see base/base.hpp)
    # Base definitions that apply to all configurations
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) OMIM_METAL_AVAILABLE=1 PLATFORM_IPHONE=1',
  }
  
  # User target settings
  s.user_target_xcconfig = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }

  s.swift_version = '5.0'
end
