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
# Invoke the build for native code shared with the other target platforms.
add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../src" "${CMAKE_CURRENT_BINARY_DIR}/shared")

# ============================================================================
# Bundled Libraries
# ============================================================================
# List of absolute paths to libraries that should be bundled with the plugin.
set(agus_maps_flutter_bundled_libraries
  # The plugin DLL (MethodChannel handler)
  $<TARGET_FILE:${PLUGIN_NAME}>
  # The native CoMaps FFI library
  $<TARGET_FILE:agus_maps_flutter>
  PARENT_SCOPE
)
