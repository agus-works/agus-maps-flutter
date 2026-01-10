# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

# Project-level configuration.
set(PROJECT_NAME "agus_maps_flutter")
project(${PROJECT_NAME} LANGUAGES CXX)

# This value is used when generating builds using this plugin, so it must
# not be changed
set(PLUGIN_NAME "agus_maps_flutter_plugin")

# Should be configured by the host app, but for standalone builds or cleanliness:
find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK REQUIRED gtk+-3.0)
pkg_check_modules(EPOXY REQUIRED epoxy)

# Define the plugin library target
add_library(${PLUGIN_NAME} SHARED
  "agus_maps_flutter_plugin.cc"
)

# Apply a standard set of build settings that are configured in the
# application-level CMakeLists.txt.
apply_standard_settings(${PLUGIN_NAME})

# Symbols are hidden by default to reduce the chance of accidental conflicts
# between plugins.
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_STANDARD 17
  CXX_STANDARD_REQUIRED YES
)

# Source include directories
# PUBLIC so that the Flutter app can include the plugin header
target_include_directories(${PLUGIN_NAME} PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)
target_include_directories(${PLUGIN_NAME} PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}"
  ${EPOXY_INCLUDE_DIRS}
)

# Link against Flutter, GTK, and Epoxy (for OpenGL)
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GTK)
target_link_libraries(${PLUGIN_NAME} PRIVATE ${EPOXY_LIBRARIES})

# ============================================================================
# Prebuilt Binary Detection (no auto-download)
# ============================================================================
# For consumers: Download the unified package from GitHub Releases and extract
# it to your Flutter app root directory before building.
# 
# Download: https://github.com/agus-works/agus-maps-flutter/releases
# Extract to: my_app/ (results in my_app/linux/prebuilt/x64/, my_app/assets/, etc.)
# ============================================================================
set(PREBUILT_FOUND OFF)

# Detect if we're in the plugin repository (in-repo build from source)
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
if(DEFINED ENV{AGUS_MAPS_HOME} AND NOT PREBUILT_FOUND)
  set(AGUS_SDK_HOME "$ENV{AGUS_MAPS_HOME}")
  set(SDK_LINUX_PREBUILT_DIR "${AGUS_SDK_HOME}/linux/prebuilt/x64")
  if(EXISTS "${SDK_LINUX_PREBUILT_DIR}/libagus_maps_flutter.so")
    set(PREBUILT_DIR "${SDK_LINUX_PREBUILT_DIR}")
    set(PREBUILT_FOUND ON)
    message(STATUS "Found pre-built Linux binaries in AGUS_MAPS_HOME: ${PREBUILT_DIR}")
  else()
    message(STATUS "WARNING: AGUS_MAPS_HOME set to ${AGUS_SDK_HOME} but binaries not found in ${SDK_LINUX_PREBUILT_DIR}")
  endif()
endif()

# Location 1b: Plugin-local prebuilt directory (CI builds copy binaries here)
if(NOT PREBUILT_FOUND AND (IS_CI OR EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/prebuilt/x64/libagus_maps_flutter.so"))
  set(PLUGIN_PREBUILT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/prebuilt/x64")
  if(EXISTS "${PLUGIN_PREBUILT_DIR}/libagus_maps_flutter.so")
    set(PREBUILT_DIR "${PLUGIN_PREBUILT_DIR}")
    set(PREBUILT_FOUND ON)
    if(IS_CI)
      message(STATUS "CI environment: Found pre-built Linux binaries in plugin dir: ${PREBUILT_DIR}")
    else()
      message(STATUS "Found pre-built Linux binaries in plugin dir: ${PREBUILT_DIR}")
    endif()
  endif()
endif()

# Location 2: Project linux directory (consumer extracts unified package to app root)
# REMOVED: Legacy support for binary extraction to root is deprecated.

# If binaries not found and we're an external consumer, provide clear instructions
if(NOT PREBUILT_FOUND AND NOT IS_IN_REPO)
  message(FATAL_ERROR "\n"
    "========================================================================\n"
    "ERROR: Pre-built binaries not found for agus_maps_flutter.\n"
    "========================================================================\n"
    "\n"
    "For app consumers:\n"
    "  1. Download agus-maps-sdk-vX.Y.Z.zip from GitHub Releases\n"
    "     https://github.com/agus-works/agus-maps-flutter/releases\n"
    "  2. Extract the archive\n"
    "  3. Set environment variable: export AGUS_MAPS_HOME=/path/to/agus-maps-sdk-vX.Y.Z\n"
    "  4. Copy SDK assets/ contents to your Flutter app's assets/ folder\n"
    "  5. Rebuild your app\n"
    "\n"
    "For plugin contributors:\n"
    "  Use scripts/build_all.sh (macOS/Linux) or scripts/build_all.ps1 (Windows)\n"
    "\n"
    "========================================================================\n"
  )
endif()

if(PREBUILT_FOUND)
  message(STATUS "=== Using pre-built Linux binaries ===")
  
  # Define IMPORTED target for agus_maps_flutter (the native CoMaps wrapper)
  # Note: All CoMaps functionality is statically linked into this single shared library
  add_library(agus_maps_flutter SHARED IMPORTED)
  set_target_properties(agus_maps_flutter PROPERTIES
    IMPORTED_LOCATION "${PREBUILT_DIR}/libagus_maps_flutter.so"
    INTERFACE_INCLUDE_DIRECTORIES "${CMAKE_CURRENT_SOURCE_DIR}/../src"
  )

else()
  message(STATUS "=== Building Linux binaries from source ===")
  # Invoke the build for native code shared with the other target platforms.
  # This produces the main shared library with CoMaps functionality.
  add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../src" "${CMAKE_CURRENT_BINARY_DIR}/shared")
endif()

# Link the plugin against the native library for FFI function access
target_link_libraries(${PLUGIN_NAME} PRIVATE agus_maps_flutter)

# List of absolute paths to libraries that should be bundled with the plugin.
# This list could contain prebuilt libraries, or libraries created by an
# external build triggered from this build file.
if(PREBUILT_FOUND)
  set(agus_maps_flutter_bundled_libraries
    # The plugin library itself
    $<TARGET_FILE:${PLUGIN_NAME}>
    # The prebuilt native library
    "${PREBUILT_DIR}/libagus_maps_flutter.so"
    PARENT_SCOPE
  )
else()
  set(agus_maps_flutter_bundled_libraries
    # The plugin library itself
    $<TARGET_FILE:${PLUGIN_NAME}>
    # The native CoMaps library name might be different when built from source, check src/CMakeLists.txt
    $<TARGET_FILE:agus_maps_flutter>
    PARENT_SCOPE
  )
endif()
