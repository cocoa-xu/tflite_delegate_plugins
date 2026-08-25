# Puts TFLite's own build into this one, downloading the sources when the caller
# has not supplied a tree. Sets TENSORFLOW_SOURCE_DIR in the cache either way.

# neon2sse, which only x86 targets pull in, declares a cmake_minimum_required
# that CMake 4 refuses outright. This has to be set before TFLite is added.
set(CMAKE_POLICY_VERSION_MINIMUM 3.5 CACHE STRING "" FORCE)

# Recorded because LITERT_VER only describes the download. A caller pointing at
# their own tree can leave it at the default while building any version at all,
# and the patch guards have to know they cannot trust it.
if(LITERT_SOURCE_DIR STREQUAL "")
  set(TFLITE_SOURCE_WAS_SUPPLIED FALSE CACHE INTERNAL "")
else()
  set(TFLITE_SOURCE_WAS_SUPPLIED TRUE CACHE INTERNAL "")
endif()

if(TENSORFLOW_SOURCE_DIR STREQUAL "")
  include(FetchContent)
  # DOWNLOAD_EXTRACT_TIMESTAMP arrived in CMake 3.24; older versions read it as
  # another URL entry and fail with "At least one entry of URL is a path".
  set(_tflite_fetch_extra "")
  if(CMAKE_VERSION VERSION_GREATER_EQUAL 3.24)
    set(_tflite_fetch_extra DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
  endif()
  FetchContent_Declare(tensorflow
    URL "https://github.com/tensorflow/tensorflow/archive/refs/tags/v${TFLITE_VER}.zip"
    ${_tflite_fetch_extra}
  )
  FetchContent_MakeAvailable(tensorflow)
  set(TENSORFLOW_SOURCE_DIR "${tensorflow_SOURCE_DIR}" CACHE PATH "" FORCE)
endif()

if(LITERT_SOURCE_DIR STREQUAL "")
  include(FetchContent)
  FetchContent_Declare(litert
    URL "https://github.com/google-ai-edge/LiteRT/archive/refs/tags/v${LITERT_VER}.zip"
    ${_tflite_fetch_extra}
  )
  FetchContent_MakeAvailable(litert)
  set(LITERT_SOURCE_DIR "${litert_SOURCE_DIR}" CACHE PATH "" FORCE)
endif()

if(NOT EXISTS "${LITERT_SOURCE_DIR}/tflite/CMakeLists.txt")
  message(FATAL_ERROR
    "No TFLite sources under LITERT_SOURCE_DIR=${LITERT_SOURCE_DIR}")
endif()
if(NOT EXISTS "${TENSORFLOW_SOURCE_DIR}/tensorflow/compiler/mlir/lite")
  message(FATAL_ERROR
    "LiteRT's build reaches into TensorFlow for compiler/mlir/lite and it is "
    "not under TENSORFLOW_SOURCE_DIR=${TENSORFLOW_SOURCE_DIR}")
endif()

# LiteRT sets CMAKE_CXX_STANDARD itself, and it moved from 17 to 20 between the
# TensorFlow tree this used to build against and LiteRT 2.2.0. That governs C++
# but not Objective-C++, so the .mm sources kept compiling at whatever this
# project asked for. The consequence is not a diagnostic: abseil picks
# std::source_location above C++17 and its own absl::SourceLocation below, so a
# .mm at 17 and an .a at 20 reference two different overloads of the same
# function and the link fails on a symbol that is plainly in the archive.
#
# Read rather than copied, so the next bump moves this with it.
file(STRINGS "${LITERT_SOURCE_DIR}/tflite/CMakeLists.txt" _litert_std_line
     REGEX "^set\\(CMAKE_CXX_STANDARD [0-9]+\\)")
if(NOT _litert_std_line)
    message(FATAL_ERROR
      "LiteRT's CMakeLists no longer sets CMAKE_CXX_STANDARD, so the standard "
      "the Objective-C++ sources have to match cannot be read off it.")
endif()
string(REGEX MATCH "[0-9]+" LITERT_CXX_STANDARD "${_litert_std_line}")
# No PARENT_SCOPE: include() does not open a scope of its own, so that would
# set these one level above the only place that reads them.
set(CMAKE_CXX_STANDARD ${LITERT_CXX_STANDARD})
set(CMAKE_OBJCXX_STANDARD ${LITERT_CXX_STANDARD})
message(STATUS "LiteRT builds at C++${LITERT_CXX_STANDARD}; Objective-C++ follows")

set(TFLITE_ENABLE_GPU ON CACHE BOOL "" FORCE)
set(TFLITE_ENABLE_XNNPACK OFF CACHE BOOL "" FORCE)
if(APPLE)
  # Off, and rebuilt below. LiteRT renamed six of the Metal sources from .cc to
  # .mm and its CMakeLists still lists the old names, so add_library fails
  # before anything can be corrected afterwards. See tflite_fixup_metal_delegate.
  set(TFLITE_ENABLE_METAL OFF CACHE BOOL "" FORCE)
endif()

add_subdirectory(
  "${LITERT_SOURCE_DIR}/tflite"
  "${CMAKE_BINARY_DIR}/tflite"
  EXCLUDE_FROM_ALL
)

# TFLite ships find-modules for its own dependencies (protobuf among them);
# consumers need them on the module path to reuse the same versions.
list(APPEND CMAKE_MODULE_PATH "${LITERT_SOURCE_DIR}/tflite/tools/cmake/modules")
set(CMAKE_MODULE_PATH "${CMAKE_MODULE_PATH}" PARENT_SCOPE)

# Where TFLite's own build leaves the headers its sources include by bare name.
# fp16 is fetched by the GPU path and included as "fp16.h" from the Core ML
# sources, which have no CMake target upstream to carry the path for them.
set(TFLITE_GENERATED_INCLUDE_DIRS
  # LiteRT's own headers are reached as tflite/..., which resolves from the
  # directory above the subtree. TensorFlow stays on the list because LiteRT's
  # build compiles sources out of it that include tensorflow/... by their own
  # path.
  "${LITERT_SOURCE_DIR}"
  "${TENSORFLOW_SOURCE_DIR}"
  "${CMAKE_BINARY_DIR}/flatbuffers/include"
  "${CMAKE_BINARY_DIR}/abseil-cpp"
  "${CMAKE_BINARY_DIR}/fp16_headers/include"
  # The GPU sources include these by bare name (<CL/cl.h>, <EGL/egl.h> and so
  # on). TFLite fetches them but carries the paths only on its own targets, and
  # opengl/egl put theirs under api/ rather than include/.
  "${CMAKE_BINARY_DIR}/opencl_headers"
  "${CMAKE_BINARY_DIR}/vulkan_headers/include"
  "${CMAKE_BINARY_DIR}/opengl_headers/api"
  "${CMAKE_BINARY_DIR}/egl_headers/api"
)
