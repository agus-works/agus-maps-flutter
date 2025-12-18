cmake_minimum_required(VERSION 3.22.1)

# Force CMake Re-run 2
project(agus_maps_flutter_library LANGUAGES C CXX)

# Match CoMaps C++ standard
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# CoMaps Options
set(SKIP_TESTS ON CACHE BOOL "" FORCE)
set(SKIP_QT_GUI ON CACHE BOOL "" FORCE)
set(WITH_SYSTEM_PROVIDED_3PARTY OFF CACHE BOOL "" FORCE)
set(SKIP_ANDROID_JNI ON CACHE BOOL "" FORCE)
set(SKIP_PROTOBUF_CHECK ON CACHE BOOL "" FORCE)
set(SKIP_TOOLS ON CACHE BOOL "" FORCE)

# Force non-Android platform to use filesystem-based GetReader instead of ZipFileReader
# We provide our own platform implementation in agus_platform.cpp
set(PLATFORM_ANDROID FALSE CACHE BOOL "" FORCE)
set(PLATFORM_LINUX TRUE CACHE BOOL "" FORCE)
set(PLATFORM_DESKTOP TRUE CACHE BOOL "" FORCE)

# Build CoMaps
add_subdirectory(../thirdparty/comaps build/comaps)

add_library(agus_maps_flutter SHARED
  "agus_maps_flutter.cpp"
  "agus_platform.cpp"
  "agus_ogl.cpp"
  "agus_gui_thread.cpp"
)

set_target_properties(agus_maps_flutter PROPERTIES
  OUTPUT_NAME "agus_maps_flutter"
)

target_include_directories(agus_maps_flutter PRIVATE
  "../thirdparty/comaps"
  "../thirdparty/comaps/libs"
  "../thirdparty/comaps/3party/boost"
  "../thirdparty/comaps/android/sdk/src/main/cpp" 
)

# Link CoMaps libraries
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
