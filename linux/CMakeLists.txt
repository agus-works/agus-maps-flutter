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

# Invoke the build for native code shared with the other target platforms.
# This produces the main shared library with CoMaps functionality.
add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../src" "${CMAKE_CURRENT_BINARY_DIR}/shared")

# Link the plugin against the native library for FFI function access
target_link_libraries(${PLUGIN_NAME} PRIVATE agus_maps_flutter)

# List of absolute paths to libraries that should be bundled with the plugin.
# This list could contain prebuilt libraries, or libraries created by an
# external build triggered from this build file.
set(agus_maps_flutter_bundled_libraries
  # The plugin library itself
  $<TARGET_FILE:${PLUGIN_NAME}>
  # The native CoMaps library
  $<TARGET_FILE:agus_maps_flutter>
  PARENT_SCOPE
)
