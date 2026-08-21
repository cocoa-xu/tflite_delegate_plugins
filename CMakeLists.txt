cmake_minimum_required(VERSION 3.16)

project(tflite_delegate_plugins
  VERSION 0.1.0
  DESCRIPTION "TensorFlow Lite delegate plugins for the external-delegate ABI"
  HOMEPAGE_URL "https://github.com/cocoa-xu/tflite_delegate_plugins"
  LANGUAGES CXX
)

set(TFLITE_VER "2.21.0" CACHE STRING "TensorFlow Lite version to build against")
set(TENSORFLOW_SOURCE_DIR "" CACHE PATH "Existing TensorFlow source tree; downloaded when empty")

option(TFLITE_PLUGINS_OPENCL "Build the OpenCL GPU delegate plugin" ON)
option(TFLITE_PLUGINS_METAL "Build the Metal delegate plugin (Apple only)" ON)
# Off by default: it builds and runs correctly but delegates no nodes from any
# current model. See docs/coreml.md before turning it on.
option(TFLITE_PLUGINS_COREML "Build the Core ML delegate plugin (Apple only, see docs/coreml.md)" OFF)
option(TFLITE_PLUGINS_INSTALL "Generate install rules" ON)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
# CMAKE_CXX_STANDARD does not govern Objective-C++, so without this the .mm
# sources compile at whatever the compiler defaults to and can end up at a
# different standard from the .cc sources in the same static library.
set(CMAKE_OBJCXX_STANDARD 17)
set(CMAKE_OBJCXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  # RelWithDebInfo rather than Release: the release workflow separates the debug
  # info into its own artifact and strips the plugin, which is only worth doing
  # if there is debug info to separate.
  set(CMAKE_BUILD_TYPE RelWithDebInfo CACHE STRING "Build type" FORCE)
endif()

# Every plugin lands in one directory regardless of which subdirectory declares
# it, so packaging and the CI checks have a single place to look.
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib")
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")

list(APPEND CMAKE_MODULE_PATH "${PROJECT_SOURCE_DIR}/cmake")

include(TFLiteSource)     # locate or download TFLite, then add it
include(UpstreamFixups)   # defects in TFLite's own build, worked around here
include(UpstreamPatches)  # corrections to TFLite's own sources
include(PluginTarget)     # tflite_plugin_add_library()

add_subdirectory(plugins)

message(STATUS "${PROJECT_NAME} ${PROJECT_VERSION}: TFLite ${TFLITE_VER} from ${TENSORFLOW_SOURCE_DIR}")
