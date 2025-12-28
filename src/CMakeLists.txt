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
  # CoMaps source directory
  set(COMAPS_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../thirdparty/comaps")
  get_filename_component(COMAPS_SOURCE_DIR "${COMAPS_SOURCE_DIR}" ABSOLUTE)
  
  # On Windows with Flutter, the project may be accessed via symlinks
  # (e.g., .plugin_symlinks/agus_maps_flutter/...). This causes:
  # 1. MAX_PATH limit (260 chars) exceeded with deep boost headers
  # 2. #pragma once fails when same file accessed via different paths
  # Solution: Resolve to REALPATH before add_subdirectory so all source files
  # use consistent resolved paths, making #pragma once work correctly.
  if(WIN32)
    get_filename_component(COMAPS_SOURCE_DIR "${COMAPS_SOURCE_DIR}" REALPATH)
    message(STATUS "COMAPS_SOURCE_DIR resolved for Windows: ${COMAPS_SOURCE_DIR}")
  endif()
  
  # CoMaps Options - only needed when building from source
  set(SKIP_TESTS ON CACHE BOOL "" FORCE)
  set(SKIP_QT ON CACHE BOOL "" FORCE)
  set(SKIP_QT_GUI ON CACHE BOOL "" FORCE)
  set(WITH_SYSTEM_PROVIDED_3PARTY OFF CACHE BOOL "" FORCE)
  set(SKIP_ANDROID_JNI ON CACHE BOOL "" FORCE)
  set(SKIP_PROTOBUF_CHECK ON CACHE BOOL "" FORCE)
  set(SKIP_TOOLS ON CACHE BOOL "" FORCE)
  
  # Skip install rules for CoMaps and its dependencies (glaze, etc.)
  # This prevents the install() commands from trying to use generator expressions
  # like $<TARGET_FILE_DIR:...> which don't resolve during cmake_install.cmake execution
  set(CMAKE_SKIP_INSTALL_RULES ON CACHE BOOL "" FORCE)

  # Platform detection is handled by OmimPlatform.cmake based on CMAKE_SYSTEM_NAME
  # - For Android: SKIP_ANDROID_JNI tells CoMaps to use our external platform impl
  # - For other platforms: SKIP_QT tells CoMaps to use dummy implementations
  # Note: OMIM_ROOT is now correctly set inside CoMaps CMakeLists.txt using
  # CMAKE_CURRENT_SOURCE_DIR, so it works when added as subdirectory

  # ============================================================================
  # Thread Checker Disable for Embedded Builds
  # ============================================================================
  # Flutter embedded builds have different threading models where objects may be
  # created on the platform thread but accessed from the render thread. CoMaps
  # uses thread checkers to verify single-thread access which causes assertions
  # to fail in embedded contexts. Disable thread checking globally for all
  # CoMaps libraries by defining OMIM_DISABLE_THREAD_CHECKER.
  # This is supported by patches 0030 and 0031 (thread_checker.cpp/.hpp).
  add_compile_definitions(OMIM_DISABLE_THREAD_CHECKER)
  message(STATUS "Thread checker disabled for embedded Flutter builds")

  # Build CoMaps
  add_subdirectory("${COMAPS_SOURCE_DIR}" build/comaps)
  
  # Restore install rules after CoMaps subdirectory
  set(CMAKE_SKIP_INSTALL_RULES OFF CACHE BOOL "" FORCE)
endif()

# ============================================================================
# Agus Maps Flutter Library
# ============================================================================

# Platform-specific source files
if(WIN32)
  # Windows uses OpenGL (WGL) with D3D11 texture sharing for Flutter
  set(PLATFORM_SOURCES
    "agus_maps_flutter_win.cpp"
    "agus_platform_win.cpp"
    "AgusWglContextFactory.cpp"
  )
elseif(ANDROID)
  # Android uses EGL/GLES3 implementation
  set(PLATFORM_SOURCES
    "agus_maps_flutter.cpp"
    "agus_platform.cpp"
    "agus_ogl.cpp"
    "agus_gui_thread.cpp"
  )
else()
  # Default (iOS/macOS uses Metal, handled separately in podspec)
  set(PLATFORM_SOURCES
    "agus_maps_flutter.cpp"
    "agus_platform.cpp"
    "agus_ogl.cpp"
    "agus_gui_thread.cpp"
  )
endif()

add_library(agus_maps_flutter SHARED
  ${PLATFORM_SOURCES}
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
  # IMPORTANT: Use absolute paths to avoid symlink issues with Flutter builds
  # (Flutter creates symlinks in example/windows/flutter/ephemeral/.plugin_symlinks)
  # Using COMAPS_SOURCE_DIR which is already resolved to absolute path
  # Note: Include paths must match iOS podspec HEADER_SEARCH_PATHS
  target_include_directories(agus_maps_flutter PRIVATE
    "${COMAPS_SOURCE_DIR}"
    "${COMAPS_SOURCE_DIR}/libs"
    "${COMAPS_SOURCE_DIR}/3party"
    "${COMAPS_SOURCE_DIR}/3party/utfcpp/source"
    "${COMAPS_SOURCE_DIR}/3party/glm"
    "${COMAPS_SOURCE_DIR}/3party/pugixml/pugixml/src"
    "${COMAPS_SOURCE_DIR}/3party/jansson/jansson/src"
    "${COMAPS_SOURCE_DIR}/3party/jansson"
    "${COMAPS_SOURCE_DIR}/3party/expat/expat/lib"
    "${COMAPS_SOURCE_DIR}/3party/icu/icu/source/common"
    "${COMAPS_SOURCE_DIR}/3party/icu/icu/source/i18n"
    "${COMAPS_SOURCE_DIR}/3party/freetype/include"
    "${COMAPS_SOURCE_DIR}/3party/harfbuzz/harfbuzz/src"
    "${COMAPS_SOURCE_DIR}/3party/minizip/minizip"
    "${COMAPS_SOURCE_DIR}/3party/protobuf/protobuf/src"
    "${COMAPS_SOURCE_DIR}/android/sdk/src/main/cpp" 
  )
  # Add boost modular include directories (set by CoMaps CMakeLists.txt)
  if(BOOST_INCLUDE_DIRS)
    target_include_directories(agus_maps_flutter PRIVATE ${BOOST_INCLUDE_DIRS})
  endif()
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
# Use generator expressions for multi-config generators (Visual Studio, Xcode)
if (CMAKE_CONFIGURATION_TYPES)
  # Multi-config generator - use generator expressions
  target_compile_definitions(agus_maps_flutter PRIVATE
    $<$<CONFIG:Debug>:DEBUG>
    $<$<NOT:$<CONFIG:Debug>>:RELEASE>
  )
elseif (CMAKE_BUILD_TYPE STREQUAL "Debug")
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

# ============================================================================
# Windows Platform Configuration
# ============================================================================
if(WIN32)
  message(STATUS "=== Configuring Windows OpenGL Build ===")
  
  # Windows platform definitions
  target_compile_definitions(agus_maps_flutter PRIVATE
    OMIM_OS_WINDOWS
    WIN32_LEAN_AND_MEAN
    NOMINMAX
  )
  
  # Link Windows system libraries (OpenGL, D3D11 for texture sharing)
  target_link_libraries(agus_maps_flutter PRIVATE
    opengl32
    d3d11
    dxgi
    dxguid
    dbghelp   # For MiniDumpWriteDump crash handler
    shell32   # For SHGetFolderPath
  )
  
  # MSVC-specific flags
  if(MSVC)
    target_compile_options(agus_maps_flutter PRIVATE
      /W3
      /wd4251  # Disable DLL-interface warnings for STL
      /wd4275  # Disable non-DLL-interface base class warnings
    )
  endif()
endif()
