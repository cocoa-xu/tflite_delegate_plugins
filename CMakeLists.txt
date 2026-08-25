cmake_minimum_required(VERSION 3.16)

project(tflite_delegate_plugins
  VERSION 0.1.0
  DESCRIPTION "TensorFlow Lite delegate plugins for the external-delegate ABI"
  HOMEPAGE_URL "https://github.com/cocoa-xu/tflite_delegate_plugins"
  LANGUAGES CXX
)

# The runtime these plugins are loaded into is built from LiteRT's tflite
# subtree, so LITERT_VER is the version a plugin has to match. It is what
# tflite_beam:tflite_version/0 answers, and a mismatch there is undefined
# behaviour rather than an error: there is no binary stable delegate interface.
set(LITERT_VER "2.2.0" CACHE STRING "LiteRT version to build against")
set(LITERT_SOURCE_DIR "" CACHE PATH "Existing LiteRT source tree; downloaded when empty")
# TensorFlow is a build dependency of LiteRT rather than the source of the
# runtime: its CMake reaches into compiler/mlir/lite, TSL and XLA. The version
# is the one LiteRT pins, and mismatching it links two different definitions of
# the same flatbuffer tables.
set(TFLITE_VER "2.21.0-rc0" CACHE STRING "TensorFlow release LiteRT builds against")
set(TENSORFLOW_SOURCE_DIR "" CACHE PATH "Existing TensorFlow source tree; downloaded when empty")

option(TFLITE_PLUGINS_OPENCL "Build the OpenCL GPU delegate plugin" ON)
option(TFLITE_PLUGINS_METAL "Build the Metal delegate plugin (Apple only)" ON)
# Off by default: it builds and runs correctly but delegates no nodes from any
# current model. See docs/coreml.md before turning it on.
option(TFLITE_PLUGINS_COREML "Build the Core ML delegate plugin (Apple only, see docs/coreml.md)" OFF)
option(TFLITE_PLUGINS_INSTALL "Generate install rules" ON)

# A floor, not the number that ends up being used: TFLiteSource raises both to
# whatever LiteRT builds at, which is 20 today. CMAKE_CXX_STANDARD does not
# govern Objective-C++, which is why the second one has to be said at all: a .mm
# left behind at 17 while the archives around it are at 20 does not fail to
# compile, it fails to link, on a symbol that is visibly in the archive.
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
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

# enable_language has to be called at directory scope, not from inside the
# function that needs it: from there CMake configures but then fails to generate
# with "required internal CMake variable not set".
if(APPLE)
  enable_language(OBJCXX)
endif()
tflite_fixup_metal_delegate()

add_subdirectory(plugins)

message(STATUS "${PROJECT_NAME} ${PROJECT_VERSION}: LiteRT ${LITERT_VER} from ${LITERT_SOURCE_DIR}, TensorFlow ${TFLITE_VER} from ${TENSORFLOW_SOURCE_DIR}")
