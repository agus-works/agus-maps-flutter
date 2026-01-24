#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint agus_maps_flutter.podspec` to validate before publishing.
#
require 'fileutils'

# ==============================================================================
# Development Helper: Copy headers and frameworks from AGUS_MAPS_HOME
# This runs during `pod install` to support Development Pods (path dependency)
# where prepare_command is skipped.
#
# Uses a marker file (.sdk_source) to track the SDK that was used, and re-copies
# headers/frameworks when AGUS_MAPS_HOME changes or when files are missing.
# ==============================================================================
if ENV['AGUS_MAPS_HOME']
  agus_maps_home = ENV['AGUS_MAPS_HOME']
  pod_dir = File.dirname(__FILE__)
  
  # Headers Config
  headers_dir = File.join(pod_dir, 'Headers')
  target_headers = File.join(headers_dir, 'comaps')
  source_headers = File.join(agus_maps_home, 'headers')
  
  # Resources Config
  target_resources = File.join(pod_dir, 'Resources')
  source_resources = File.join(agus_maps_home, 'macos', 'Frameworks', 'Resources')
  if !File.directory?(source_resources)
     source_resources = File.join(agus_maps_home, 'macos', 'Resources')
  end

  marker_file = File.join(headers_dir, '.sdk_source')
  
  # Check update conditions:
  # 1. Artifacts missing
  # 2. Marker missing or changed
  needs_update = false
  if !File.directory?(target_headers) || !File.directory?(target_resources)
    needs_update = true
    puts "[agus_maps_flutter] Missing artifacts, will copy from SDK"
  elsif !File.exist?(marker_file)
    needs_update = true
    puts "[agus_maps_flutter] SDK marker missing, will refresh"
  else
    previous_sdk = File.read(marker_file).strip
    if previous_sdk != agus_maps_home
      needs_update = true
      puts "[agus_maps_flutter] SDK changed from #{previous_sdk} to #{agus_maps_home}"
    end
  end
  
  if needs_update
    puts "[agus_maps_flutter] AGUS_MAPS_HOME detected: #{agus_maps_home}"
    
    # Copy Headers
    if File.directory?(source_headers)
        FileUtils.rm_rf(target_headers)
        FileUtils.mkdir_p(target_headers)
        FileUtils.cp_r(Dir.glob("#{source_headers}/*"), target_headers)
        puts "[agus_maps_flutter] Copied headers"
    else
        puts "[agus_maps_flutter] WARNING: Headers not found in #{source_headers}"
    end

    # Copy Resources (Metal shaders)
    if File.directory?(source_resources)
        # Only overwrite Resources if they exist in SDK
        FileUtils.mkdir_p(target_resources)
        FileUtils.cp_r(Dir.glob("#{source_resources}/*"), target_resources)
        puts "[agus_maps_flutter] Copied resources from #{source_resources}"
    else 
        puts "[agus_maps_flutter] WARNING: Resources not found in #{source_resources}"
    end

    # Update marker
    FileUtils.mkdir_p(headers_dir)
    File.write(marker_file, agus_maps_home)
  elsif !needs_update
     puts "[agus_maps_flutter] Artifacts up-to-date from #{agus_maps_home}"
  end
end
Pod::Spec.new do |s|
  s.name             = 'agus_maps_flutter'
  s.version          = '0.1.22'
  s.summary          = 'High-performance offline maps for Flutter using CoMaps engine.'
  s.description      = <<-DESC
A Flutter plugin that provides high-performance offline vector map rendering
using the CoMaps (Organic Maps fork) C++ engine. Features zero-copy GPU texture
sharing via Metal and CVPixelBuffer for optimal performance on macOS devices.
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
    
    FRAMEWORK_NAME="CoMaps.xcframework"
    
    # Check if framework already exists (in-repo build or CI)
    if [ -d "Frameworks/${FRAMEWORK_NAME}" ]; then
      echo "[agus_maps_flutter] Found existing ${FRAMEWORK_NAME} in plugin directory"
      exit 0
    fi
    
    # Check for CI environment (GitHub Actions, etc.)
    if [ -n "$CI" ]; then
      echo "[agus_maps_flutter] CI environment detected, framework will be copied by CI workflow"
      # CI workflow copies frameworks before pod install, so this is a timing issue
      # Create placeholder to allow pod install to proceed
      mkdir -p Frameworks
      echo "[agus_maps_flutter] WARNING: Framework not yet available, CI should copy it before build"
      exit 0
    fi
    
    # Check AGUS_MAPS_HOME for consumer builds
    if [ -n "$AGUS_MAPS_HOME" ]; then
      echo "[agus_maps_flutter] AGUS_MAPS_HOME set to $AGUS_MAPS_HOME"
      SDK_FRAMEWORK="$AGUS_MAPS_HOME/macos/Frameworks/${FRAMEWORK_NAME}"
      if [ -d "$SDK_FRAMEWORK" ]; then
         echo "[agus_maps_flutter] Found ${FRAMEWORK_NAME} in AGUS_MAPS_HOME"
         mkdir -p Frameworks
         cp -R "$SDK_FRAMEWORK" Frameworks/
         echo "[agus_maps_flutter] Copied from AGUS_MAPS_HOME"
         
         # Copy headers
         SDK_HEADERS="$AGUS_MAPS_HOME/headers"
         if [ -d "$SDK_HEADERS" ]; then
             echo "[agus_maps_flutter] Found headers in AGUS_MAPS_HOME"
             rm -rf Headers/comaps
             mkdir -p Headers/comaps
             # Copy contents of headers folder to Headers/comaps using /." syntax
             cp -R "$SDK_HEADERS/." Headers/comaps/
             echo "[agus_maps_flutter] Copied headers from AGUS_MAPS_HOME"
         else
             echo "[agus_maps_flutter] WARNING: headers not found in $AGUS_MAPS_HOME/headers"
         fi
         
         exit 0
      else
         echo "[agus_maps_flutter] WARNING: ${FRAMEWORK_NAME} not found in $AGUS_MAPS_HOME/macos/Frameworks"
      fi

      # Copy Resources (Metal shaders)
      # Check both Frameworks/Resources (if unzipped into Frameworks) and Resources/ (if sibling)
      SDK_RESOURCES="$AGUS_MAPS_HOME/macos/Frameworks/Resources"
      if [ ! -d "$SDK_RESOURCES" ]; then
          SDK_RESOURCES="$AGUS_MAPS_HOME/macos/Resources"
      fi
      
      if [ -d "$SDK_RESOURCES" ]; then
          echo "[agus_maps_flutter] Found resources in $SDK_RESOURCES"
          mkdir -p Resources
          cp -R "$SDK_RESOURCES/." Resources/
          echo "[agus_maps_flutter] Copied resources from AGUS_MAPS_HOME"
      else
          echo "[agus_maps_flutter] WARNING: Resources not found in AGUS_MAPS_HOME (shaders may be missing)"
      fi
    fi
    
    echo ""
    echo "========================================================================"
    echo "[agus_maps_flutter] ERROR: Pre-built binaries not found."
    echo "========================================================================"
    echo ""
    echo "For app consumers:"
    echo "  1. Download agus-maps-sdk-vX.Y.Z.zip from GitHub Releases"
    echo "     https://github.com/agus-works/agus-maps-flutter/releases"
    echo "  2. Extract the archive"
    echo "  3. Set environment variable: export AGUS_MAPS_HOME=/path/to/agus-maps-sdk-vX.Y.Z"
    echo "  4. Copy SDK assets/ contents to your Flutter app's assets/ folder"
    echo "  5. Rebuild your app"
    echo ""
    echo "For plugin contributors:"
    echo "  Use scripts/build_all.sh (macOS/Linux) or scripts/build_all.ps1 (Windows)"
    echo ""
    echo "========================================================================"
    exit 1
  CMD

  # ============================================================================
  # Pre-built XCFramework Required
  # ============================================================================
  # Download the unified binary package from GitHub Releases and extract it to
  # your Flutter app root BEFORE running pod install:
  #
  #   1. Download: https://github.com/agus-works/agus-maps-flutter/releases
  #   2. Extract to your app root: unzip agus-maps-binaries-vX.Y.Z.zip -d my_app/
  #   3. This creates: my_app/macos/Frameworks/CoMaps.xcframework/
  #
  # The build will fail if macos/Frameworks/CoMaps.xcframework is not present.
  # ============================================================================

  # Source files - Swift plugin + Objective-C++ native code
  s.source_files = [
    'Classes/**/*.{h,m,mm,swift}',
    '../src/agus_maps_flutter.h',
  ]
  
  # Public headers for FFI - only C-compatible headers!
  # C++ headers must NOT be exposed to Swift module
  s.public_header_files = [
    'Classes/AgusPlatformMacOS.h',
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
  
  # Build settings for C++ interop
  s.xcconfig = {
    # Force load all symbols including C++ static initializers
    'OTHER_LDFLAGS' => '-ObjC'
  }

  # Required macOS frameworks
  s.frameworks = [
    'Metal',
    'MetalKit', 
    'CoreVideo',
    'CoreGraphics',
    'CoreFoundation',
    'QuartzCore',
    'AppKit',
    'Foundation',
    'Security',
    'SystemConfiguration',
    'CoreLocation'
  ]

  # System libraries
  s.libraries = 'c++', 'z', 'sqlite3'

  # Flutter dependency
  s.dependency 'FlutterMacOS'
  
  # macOS platform version (matches CoMaps requirement)
  s.platform = :osx, '12.0'

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
    
    # Linker flags - force load all symbols from static libraries
    'OTHER_LDFLAGS' => '-ObjC -all_load',
    
    # Header search paths for CoMaps includes
    # Include both thirdparty (in-repo) and Headers (downloaded) paths
    # The compiler will use whichever paths exist
    'HEADER_SEARCH_PATHS' => [
      '"$(PODS_TARGET_SRCROOT)/../src"',
      # Downloaded headers paths (fallback - prioritized now)
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
    ].join(' '),
    
    # Preprocessor definitions
    # CoMaps requires either DEBUG or RELEASE/NDEBUG to be defined (see base/base.hpp)
    # Base definitions that apply to all configurations
    # OMIM_METAL_AVAILABLE is defined in drape_global.hpp (Apple-specific), so we don't need it here.
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) PLATFORM_MAC=1 PLATFORM_DESKTOP=1',
    # Debug configuration needs DEBUG explicitly defined
    'GCC_PREPROCESSOR_DEFINITIONS[config=Debug]' => '$(inherited) PLATFORM_MAC=1 PLATFORM_DESKTOP=1 DEBUG=1',
    # Release configuration needs RELEASE and NDEBUG explicitly
    'GCC_PREPROCESSOR_DEFINITIONS[config=Release]' => '$(inherited) PLATFORM_MAC=1 PLATFORM_DESKTOP=1 RELEASE=1 NDEBUG=1',
    'GCC_PREPROCESSOR_DEFINITIONS[config=Profile]' => '$(inherited) PLATFORM_MAC=1 PLATFORM_DESKTOP=1 RELEASE=1 NDEBUG=1',
  }

  s.swift_version = '5.0'
end
