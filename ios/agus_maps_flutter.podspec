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
sharing via Metal and CVPixelBuffer for optimal performance on iOS devices.
                       DESC
  s.homepage         = 'https://github.com/bangonkali/agus-maps-flutter'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Agus Maps' => 'agus@example.com' }
  s.source           = { :path => '.' }

  # Download pre-built XCFramework before pod install
  s.prepare_command = <<-CMD
    cd "$(dirname "$0")/.."
    if [ -x "./scripts/download_ios_xcframework.sh" ]; then
      ./scripts/download_ios_xcframework.sh
    else
      echo "Warning: download_ios_xcframework.sh not found or not executable"
    fi
  CMD

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

  # Vendored CoMaps XCFramework (downloaded by prepare_command)
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
    'HEADER_SEARCH_PATHS' => [
      '"$(PODS_TARGET_SRCROOT)/../src"',
      '"$(PODS_TARGET_SRCROOT)/../thirdparty/comaps"',
      '"$(PODS_TARGET_SRCROOT)/../thirdparty/comaps/libs"',
      '"$(PODS_TARGET_SRCROOT)/../thirdparty/comaps/3party/boost"',
      '"$(PODS_TARGET_SRCROOT)/../thirdparty/comaps/3party/glm"',
      '"$(PODS_TARGET_SRCROOT)/../thirdparty/comaps/3party"',
      '"$(PODS_TARGET_SRCROOT)/../thirdparty/comaps/3party/utfcpp/source"',
      '"$(PODS_TARGET_SRCROOT)/../thirdparty/comaps/3party/jansson/jansson/src"',
      '"$(PODS_TARGET_SRCROOT)/../thirdparty/comaps/3party/jansson"',
      '"$(PODS_TARGET_SRCROOT)/../thirdparty/comaps/3party/expat/expat/lib"',
      '"$(PODS_TARGET_SRCROOT)/../thirdparty/comaps/3party/icu/icu/source/common"',
      '"$(PODS_TARGET_SRCROOT)/../thirdparty/comaps/3party/icu/icu/source/i18n"',
      '"$(PODS_TARGET_SRCROOT)/../thirdparty/comaps/3party/freetype/include"',
      '"$(PODS_TARGET_SRCROOT)/../thirdparty/comaps/3party/harfbuzz/harfbuzz/src"',
      '"$(PODS_TARGET_SRCROOT)/../thirdparty/comaps/3party/minizip/minizip"',
      '"$(PODS_TARGET_SRCROOT)/../thirdparty/comaps/3party/pugixml/pugixml/src"',
      '"$(PODS_TARGET_SRCROOT)/../thirdparty/comaps/3party/protobuf/protobuf/src"',
    ].join(' '),
    
    # Preprocessor definitions
    'GCC_PREPROCESSOR_DEFINITIONS' => [
      'OMIM_METAL_AVAILABLE=1',
      'PLATFORM_IPHONE=1',
      '$(inherited)'
    ].join(' '),
  }
  
  # User target settings
  s.user_target_xcconfig = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }

  s.swift_version = '5.0'
end
