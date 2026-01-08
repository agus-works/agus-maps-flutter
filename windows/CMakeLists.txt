# The Flutter tooling requires that developers have a version of Visual Studio
# installed that includes CMake 3.14 or later. You should not increase this
# version, as doing so will cause the plugin to fail to compile for some
# customers of the plugin.
cmake_minimum_required(VERSION 3.14)

# ============================================================================
# vcpkg Integration - MUST be before project()
# ============================================================================
# Look for vcpkg in environment or common locations
if(NOT DEFINED CMAKE_TOOLCHAIN_FILE)
  if(DEFINED ENV{VCPKG_ROOT})
    set(CMAKE_TOOLCHAIN_FILE "$ENV{VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake"
        CACHE STRING "vcpkg toolchain file")
    message(STATUS "Using vcpkg from VCPKG_ROOT: $ENV{VCPKG_ROOT}")
  elseif(EXISTS "C:/vcpkg/scripts/buildsystems/vcpkg.cmake")
    set(CMAKE_TOOLCHAIN_FILE "C:/vcpkg/scripts/buildsystems/vcpkg.cmake"
        CACHE STRING "vcpkg toolchain file")
    message(STATUS "Using vcpkg from C:/vcpkg")
  endif()
endif()

# Set vcpkg target triplet for x64
if(NOT DEFINED VCPKG_TARGET_TRIPLET)
  set(VCPKG_TARGET_TRIPLET "x64-windows" CACHE STRING "vcpkg target triplet")
endif()

# Project-level configuration.
set(PROJECT_NAME "agus_maps_flutter")
project(${PROJECT_NAME} LANGUAGES CXX)

# This value is used when generating builds using this plugin, so it must
# not be changed
set(PLUGIN_NAME "agus_maps_flutter_plugin")

# C++17 for std::filesystem
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ============================================================================
# Prebuilt Binary Detection
# ============================================================================
# Searches for pre-built Windows binaries in multiple locations.
# 
# For plugin consumers:
#   1. Download agus-maps-binaries-vX.Y.Z.zip from GitHub Releases
#   2. Extract to your Flutter app root (e.g., my_app/)
#   3. Run flutter build windows
#
# After extraction, binaries should be at: my_app/windows/prebuilt/x64/

set(PREBUILT_DIR "")
set(PREBUILT_DLL "")
set(PREBUILT_ZLIB "")

# Detect if we're in the plugin repository (in-repo build)
set(IS_IN_REPO OFF)
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/../.git" AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/../thirdparty/comaps")
  set(IS_IN_REPO ON)
  message(STATUS "Detected in-repo development environment")
endif()

# Detect CI environment (GitHub Actions, etc.)
set(IS_CI OFF)
if(DEFINED ENV{CI})
  set(IS_CI ON)
  message(STATUS "Detected CI environment")
endif()

# Location 1a: AGUS_MAPS_HOME (Environment Variable)
if(DEFINED ENV{AGUS_MAPS_HOME} AND NOT PREBUILT_DIR)
  set(AGUS_SDK_HOME "$ENV{AGUS_MAPS_HOME}")
  # Normalize path (remove quotes etc if present)
  file(TO_CMAKE_PATH "${AGUS_SDK_HOME}" AGUS_SDK_HOME)
  
  set(SDK_WINDOWS_PREBUILT_DIR "${AGUS_SDK_HOME}/windows/prebuilt/x64")
  if(EXISTS "${SDK_WINDOWS_PREBUILT_DIR}/agus_maps_flutter.dll")
    set(PREBUILT_DIR "${SDK_WINDOWS_PREBUILT_DIR}")
    set(PREBUILT_DLL "${PREBUILT_DIR}/agus_maps_flutter.dll")
    set(PREBUILT_ZLIB "${PREBUILT_DIR}/zlib1.dll")
    message(STATUS "Found pre-built Windows binaries in AGUS_MAPS_HOME: ${PREBUILT_DIR}")
  else()
    message(STATUS "WARNING: AGUS_MAPS_HOME set but binaries not found in ${SDK_WINDOWS_PREBUILT_DIR}")
  endif()
endif()

# Location 1b: Plugin-local prebuilt (CI builds, or plugin vendored with binaries)
if(NOT PREBUILT_DIR AND (IS_CI OR EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/prebuilt/x64/agus_maps_flutter.dll"))
  set(PLUGIN_PREBUILT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/prebuilt/x64")
  if(EXISTS "${PLUGIN_PREBUILT_DIR}/agus_maps_flutter.dll")
    set(PREBUILT_DIR "${PLUGIN_PREBUILT_DIR}")
    set(PREBUILT_DLL "${PREBUILT_DIR}/agus_maps_flutter.dll")
    set(PREBUILT_ZLIB "${PREBUILT_DIR}/zlib1.dll")
    if(IS_CI)
      message(STATUS "CI environment: Found pre-built binaries in plugin dir: ${PREBUILT_DIR}")
    else()
      message(STATUS "Found pre-built binaries in plugin dir: ${PREBUILT_DIR}")
    endif()
  endif()
endif()

# Location 2: Project root windows/prebuilt (consumer extracts unified package to app root)
# REMOVED: Legacy support for binary extraction to root is deprecated.

# Determine build mode
if(PREBUILT_DIR)
  set(USE_PREBUILT_WINDOWS ON)
  message(STATUS "=== Using pre-built Windows binaries ===")
  message(STATUS "Pre-built DLL: ${PREBUILT_DLL}")
elseif(IS_IN_REPO)
  set(USE_PREBUILT_WINDOWS OFF)
  message(STATUS "=== Building Windows binaries from source ===")
else()
  # External consumer without binaries - provide helpful error
  message(STATUS "")
  message(STATUS "========================================================================")
  message(STATUS "ERROR: Pre-built binaries not found for agus_maps_flutter.")
  message(STATUS "========================================================================")
  message(STATUS "")
  message(STATUS "For app consumers:")
  message(STATUS "  1. Download agus-maps-sdk-vX.Y.Z.zip from GitHub Releases")
  message(STATUS "     https://github.com/agus-works/agus-maps-flutter/releases")
  message(STATUS "  2. Extract the archive")
  message(STATUS "  3. Set environment variable: set AGUS_MAPS_HOME=C:\\path\\to\\agus-maps-sdk-vX.Y.Z")
  message(STATUS "  4. Copy SDK assets/ contents to your Flutter app's assets/ folder")
  message(STATUS "  5. Rebuild your app")
  message(STATUS "")
  message(STATUS "For plugin contributors:")
  message(STATUS "  Use scripts/build_all.ps1 (Windows) or scripts/build_all.sh (macOS/Linux)")
  message(STATUS "")
  message(STATUS "========================================================================")
  message(FATAL_ERROR "Pre-built binaries required for external consumers")
endif()

# ============================================================================
# Flutter Plugin (MethodChannel handler)
# ============================================================================
# The plugin DLL handles MethodChannel communication with Dart
add_library(${PLUGIN_NAME} SHARED
  "agus_maps_flutter_plugin.cpp"
)

# Apply standard Flutter plugin compile definitions
apply_standard_settings(${PLUGIN_NAME})

# FLUTTER_PLUGIN_IMPL tells the header to use dllexport
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden
)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

# Link Flutter wrapper for MethodChannel support
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

# Link Windows system libraries
target_link_libraries(${PLUGIN_NAME} PRIVATE
  shell32  # For SHGetKnownFolderPath
  ole32    # For CoTaskMemFree
)

# Include directories for Flutter plugin headers
target_include_directories(${PLUGIN_NAME} PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)

# ============================================================================
# Native CoMaps Library (FFI bindings)
# ============================================================================
if(USE_PREBUILT_WINDOWS)
  # Use pre-built DLL - no need to build from source
  message(STATUS "Skipping CoMaps source build - using pre-built DLL")
else()
  # Invoke the build for native code shared with the other target platforms.
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../src" "${CMAKE_CURRENT_BINARY_DIR}/shared")
endif()

# ============================================================================
# Find Runtime Dependencies
# ============================================================================
if(USE_PREBUILT_WINDOWS)
  # Use pre-built zlib DLL
  if(EXISTS "${PREBUILT_ZLIB}")
    set(ZLIB_DLL "${PREBUILT_ZLIB}")
    message(STATUS "Using pre-built zlib: ${ZLIB_DLL}")
  else()
    message(WARNING "Pre-built zlib1.dll not found at ${PREBUILT_ZLIB}")
  endif()
else()
  # CoMaps uses zlib via find_package(ZLIB), which on Windows with vcpkg
  # results in a dynamic library dependency on zlib1.dll
  find_package(ZLIB REQUIRED)

# Get the zlib DLL path for bundling
# vcpkg installs zlib1.dll in the bin directory
if(ZLIB_FOUND)
  get_filename_component(ZLIB_LIB_DIR "${ZLIB_LIBRARY_RELEASE}" DIRECTORY)
  get_filename_component(ZLIB_ROOT_DIR "${ZLIB_LIB_DIR}" DIRECTORY)
  set(ZLIB_DLL "${ZLIB_ROOT_DIR}/bin/zlib1.dll")
  if(EXISTS "${ZLIB_DLL}")
    message(STATUS "Found zlib DLL: ${ZLIB_DLL}")
  else()
    # Fallback: check vcpkg installed directory
    if(DEFINED ENV{VCPKG_ROOT})
      set(ZLIB_DLL "$ENV{VCPKG_ROOT}/installed/${VCPKG_TARGET_TRIPLET}/bin/zlib1.dll")
    elseif(EXISTS "C:/vcpkg/installed/${VCPKG_TARGET_TRIPLET}/bin/zlib1.dll")
      set(ZLIB_DLL "C:/vcpkg/installed/${VCPKG_TARGET_TRIPLET}/bin/zlib1.dll")
    endif()
    if(EXISTS "${ZLIB_DLL}")
      message(STATUS "Found zlib DLL (fallback): ${ZLIB_DLL}")
    else()
      message(WARNING "zlib1.dll not found - app may fail to load")
    endif()
  endif()
endif()
endif()

# ============================================================================
# Bundled Libraries
# ============================================================================
# List of absolute paths to libraries that should be bundled with the plugin.
if(USE_PREBUILT_WINDOWS)
  # Use pre-built DLLs
  set(agus_maps_flutter_bundled_libraries
    # The plugin DLL (MethodChannel handler)
    $<TARGET_FILE:${PLUGIN_NAME}>
    # Pre-built native CoMaps FFI library
    "${PREBUILT_DLL}"
    # Runtime dependencies
    "${ZLIB_DLL}"
    PARENT_SCOPE
  )
else()
  # Use freshly built DLLs
  set(agus_maps_flutter_bundled_libraries
    # The plugin DLL (MethodChannel handler)
    $<TARGET_FILE:${PLUGIN_NAME}>
    # The native CoMaps FFI library
    $<TARGET_FILE:agus_maps_flutter>
    # Runtime dependencies
    "${ZLIB_DLL}"
    PARENT_SCOPE
  )
endif()
