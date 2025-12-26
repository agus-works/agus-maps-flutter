cmake_minimum_required(VERSION 3.22.1)

# Force CMake Re-run 2
project(agus_maps_flutter_library LANGUAGES C CXX)

# Match CoMaps C++ standard
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# ============================================================================
# Build Mode Detection
# ============================================================================
# USE_PREBUILT_COMAPS: Set by Gradle for external consumers with pre-built libs
# PREBUILT_DIR: Path to pre-built libraries (e.g., android/prebuilt/<abi>)
# COMAPS_HEADERS_DIR: Path to downloaded headers (e.g., android/headers)
option(USE_PREBUILT_COMAPS "Use pre-built CoMaps libraries instead of building from source" OFF)
set(PREBUILT_DIR "" CACHE PATH "Path to pre-built CoMaps libraries")
set(COMAPS_HEADERS_DIR "" CACHE PATH "Path to downloaded CoMaps headers")

if(USE_PREBUILT_COMAPS)
  message(STATUS "=== Using pre-built CoMaps libraries ===")
  message(STATUS "PREBUILT_DIR: ${PREBUILT_DIR}")
  message(STATUS "COMAPS_HEADERS_DIR: ${COMAPS_HEADERS_DIR}")
else()
  message(STATUS "=== Building CoMaps from source ===")
endif()

# ============================================================================
# CoMaps Configuration
# ============================================================================
if(NOT USE_PREBUILT_COMAPS)
  # CoMaps source directory - needed for OMIM_ROOT
  set(COMAPS_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../thirdparty/comaps")
  get_filename_component(COMAPS_SOURCE_DIR "${COMAPS_SOURCE_DIR}" ABSOLUTE)
  
  # Set OMIM_ROOT before including CoMaps - this is required for CMake module path
  set(OMIM_ROOT "${COMAPS_SOURCE_DIR}" CACHE PATH "" FORCE)
  list(APPEND CMAKE_MODULE_PATH "${COMAPS_SOURCE_DIR}/cmake")
  
  # CoMaps Options - only needed when building from source
  set(SKIP_TESTS ON CACHE BOOL "" FORCE)
  set(SKIP_QT ON CACHE BOOL "" FORCE)
  set(SKIP_QT_GUI ON CACHE BOOL "" FORCE)
  set(WITH_SYSTEM_PROVIDED_3PARTY OFF CACHE BOOL "" FORCE)
  set(SKIP_ANDROID_JNI ON CACHE BOOL "" FORCE)
  set(SKIP_PROTOBUF_CHECK ON CACHE BOOL "" FORCE)
  set(SKIP_TOOLS ON CACHE BOOL "" FORCE)

  # Platform detection is handled by OmimPlatform.cmake based on CMAKE_SYSTEM_NAME
  # - For Android: SKIP_ANDROID_JNI tells CoMaps to use our external platform impl
  # - For other platforms: SKIP_QT tells CoMaps to use dummy implementations

  # Build CoMaps
  add_subdirectory("${COMAPS_SOURCE_DIR}" build/comaps)
endif()

# ============================================================================
# Agus Maps Flutter Library
# ============================================================================
add_library(agus_maps_flutter SHARED
  "agus_maps_flutter.cpp"
  "agus_platform.cpp"
  "agus_ogl.cpp"
  "agus_gui_thread.cpp"
)

set_target_properties(agus_maps_flutter PROPERTIES
  OUTPUT_NAME "agus_maps_flutter"
)

# ============================================================================
# Include Directories
# ============================================================================
if(USE_PREBUILT_COMAPS AND COMAPS_HEADERS_DIR)
  # External consumer: use downloaded headers
  # Note: Include paths must match iOS podspec HEADER_SEARCH_PATHS
  target_include_directories(agus_maps_flutter PRIVATE
    "${COMAPS_HEADERS_DIR}/comaps"
    "${COMAPS_HEADERS_DIR}/comaps/libs"
    "${COMAPS_HEADERS_DIR}/comaps/3party"
    "${COMAPS_HEADERS_DIR}/comaps/3party/boost"
    "${COMAPS_HEADERS_DIR}/comaps/3party/utfcpp/source"
    "${COMAPS_HEADERS_DIR}/comaps/3party/glm"
    "${COMAPS_HEADERS_DIR}/comaps/3party/pugixml/pugixml/src"
    "${COMAPS_HEADERS_DIR}/comaps/3party/jansson/jansson/src"
    "${COMAPS_HEADERS_DIR}/comaps/3party/jansson"
    "${COMAPS_HEADERS_DIR}/comaps/3party/expat/expat/lib"
    "${COMAPS_HEADERS_DIR}/comaps/3party/icu/icu/source/common"
    "${COMAPS_HEADERS_DIR}/comaps/3party/icu/icu/source/i18n"
    "${COMAPS_HEADERS_DIR}/comaps/3party/freetype/include"
    "${COMAPS_HEADERS_DIR}/comaps/3party/harfbuzz/harfbuzz/src"
    "${COMAPS_HEADERS_DIR}/comaps/3party/minizip/minizip"
    "${COMAPS_HEADERS_DIR}/comaps/3party/protobuf/protobuf/src"
  )
  message(STATUS "Using headers from: ${COMAPS_HEADERS_DIR}/comaps")
else()
  # In-repo build: use thirdparty source headers
  # Note: Include paths must match iOS podspec HEADER_SEARCH_PATHS
  target_include_directories(agus_maps_flutter PRIVATE
    "../thirdparty/comaps"
    "../thirdparty/comaps/libs"
    "../thirdparty/comaps/3party"
    "../thirdparty/comaps/3party/boost"
    "../thirdparty/comaps/3party/utfcpp/source"
    "../thirdparty/comaps/3party/glm"
    "../thirdparty/comaps/3party/pugixml/pugixml/src"
    "../thirdparty/comaps/3party/jansson/jansson/src"
    "../thirdparty/comaps/3party/jansson"
    "../thirdparty/comaps/3party/expat/expat/lib"
    "../thirdparty/comaps/3party/icu/icu/source/common"
    "../thirdparty/comaps/3party/icu/icu/source/i18n"
    "../thirdparty/comaps/3party/freetype/include"
    "../thirdparty/comaps/3party/harfbuzz/harfbuzz/src"
    "../thirdparty/comaps/3party/minizip/minizip"
    "../thirdparty/comaps/3party/protobuf/protobuf/src"
    "../thirdparty/comaps/android/sdk/src/main/cpp" 
  )
endif()

# ============================================================================
# Link Libraries
# ============================================================================
if(USE_PREBUILT_COMAPS)
  # External consumer: link against pre-built static libraries
  # The pre-built libraries are organized by ABI in PREBUILT_DIR
  if(ANDROID)
    set(PREBUILT_ABI_DIR "${PREBUILT_DIR}/${ANDROID_ABI}")
    
    if(EXISTS "${PREBUILT_ABI_DIR}/libagus_maps_flutter.so")
      # If we have the full shared library, just use it directly
      # This is the expected case for pre-built distribution
      message(STATUS "Found pre-built shared library at ${PREBUILT_ABI_DIR}")
      
      # Import the pre-built shared library
      add_library(prebuilt_agus_maps SHARED IMPORTED)
      set_target_properties(prebuilt_agus_maps PROPERTIES
        IMPORTED_LOCATION "${PREBUILT_ABI_DIR}/libagus_maps_flutter.so"
      )
      
      # For pre-built mode, we just need to copy the library
      # The SHARED library declaration above will handle linking
      target_link_libraries(agus_maps_flutter PRIVATE prebuilt_agus_maps)
    else()
      message(FATAL_ERROR "Pre-built library not found at ${PREBUILT_ABI_DIR}")
    endif()
  endif()
else()
  # In-repo build: link against built CoMaps libraries
  target_link_libraries(agus_maps_flutter
    PRIVATE
    map
    platform
    coding
    geometry
    base
    drape
    drape_frontend
  )
endif()

target_compile_definitions(agus_maps_flutter PUBLIC DART_SHARED_LIB)

# Match CoMaps build mode definitions
if (CMAKE_BUILD_TYPE STREQUAL "Debug")
  target_compile_definitions(agus_maps_flutter PRIVATE DEBUG)
else()
  target_compile_definitions(agus_maps_flutter PRIVATE RELEASE)
endif()

if (ANDROID)
  find_library(log-lib log)
  find_library(android-lib android)
  find_library(EGL-lib EGL)
  find_library(GLESv3-lib GLESv3)
  
  message(STATUS "Found log-lib: ${log-lib}")
  message(STATUS "Found android-lib: ${android-lib}")
  message(STATUS "Found EGL-lib: ${EGL-lib}")
  message(STATUS "Found GLESv3-lib: ${GLESv3-lib}")

  target_link_libraries(agus_maps_flutter PRIVATE 
    -llog
    -landroid
    -lEGL
    -lGLESv3
  )
  # Support Android 15 16k page size
  target_link_options(agus_maps_flutter PRIVATE "-Wl,-z,max-page-size=16384")
  # Allow our stubs to override libplatform.a definitions
  target_link_options(agus_maps_flutter PRIVATE "-Wl,--allow-multiple-definition")
endif()
