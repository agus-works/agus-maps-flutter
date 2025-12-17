# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(agus_maps_flutter_library VERSION 0.0.1 LANGUAGES C)

add_library(agus_maps_flutter SHARED
  "agus_maps_flutter.c"
)

set_target_properties(agus_maps_flutter PROPERTIES
  PUBLIC_HEADER agus_maps_flutter.h
  OUTPUT_NAME "agus_maps_flutter"
)

target_compile_definitions(agus_maps_flutter PUBLIC DART_SHARED_LIB)

if (ANDROID)
  # Support Android 15 16k page size
  target_link_options(agus_maps_flutter PRIVATE "-Wl,-z,max-page-size=16384")
endif()
