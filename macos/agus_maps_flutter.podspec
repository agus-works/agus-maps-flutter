#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint agus_maps_flutter.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'agus_maps_flutter'
  s.version          = '0.0.1'
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
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) OMIM_METAL_AVAILABLE=1 PLATFORM_MAC=1 PLATFORM_DESKTOP=1',
    # Debug configuration needs DEBUG explicitly defined
    'GCC_PREPROCESSOR_DEFINITIONS[config=Debug]' => '$(inherited) OMIM_METAL_AVAILABLE=1 PLATFORM_MAC=1 PLATFORM_DESKTOP=1 DEBUG=1',
    # Release configuration needs RELEASE and NDEBUG explicitly
    'GCC_PREPROCESSOR_DEFINITIONS[config=Release]' => '$(inherited) OMIM_METAL_AVAILABLE=1 PLATFORM_MAC=1 PLATFORM_DESKTOP=1 RELEASE=1 NDEBUG=1',
    'GCC_PREPROCESSOR_DEFINITIONS[config=Profile]' => '$(inherited) OMIM_METAL_AVAILABLE=1 PLATFORM_MAC=1 PLATFORM_DESKTOP=1 RELEASE=1 NDEBUG=1',
  }

  s.swift_version = '5.0'
end
