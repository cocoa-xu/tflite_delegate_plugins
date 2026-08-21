# Puts TFLite's own build into this one, downloading the sources when the caller
# has not supplied a tree. Sets TENSORFLOW_SOURCE_DIR in the cache either way.

# neon2sse, which only x86 targets pull in, declares a cmake_minimum_required
# that CMake 4 refuses outright. This has to be set before TFLite is added.
set(CMAKE_POLICY_VERSION_MINIMUM 3.5 CACHE STRING "" FORCE)

# Recorded because TFLITE_VER only describes the download. A caller pointing at
# their own tree can leave it at the default while building any version at all,
# and the patch guards have to know they cannot trust it.
if(TENSORFLOW_SOURCE_DIR STREQUAL "")
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

if(NOT EXISTS "${TENSORFLOW_SOURCE_DIR}/tensorflow/lite/CMakeLists.txt")
  message(FATAL_ERROR
    "No TFLite sources under TENSORFLOW_SOURCE_DIR=${TENSORFLOW_SOURCE_DIR}")
endif()

set(TFLITE_ENABLE_GPU ON CACHE BOOL "" FORCE)
set(TFLITE_ENABLE_XNNPACK OFF CACHE BOOL "" FORCE)
if(APPLE)
  set(TFLITE_ENABLE_METAL ON CACHE BOOL "" FORCE)
endif()

add_subdirectory(
  "${TENSORFLOW_SOURCE_DIR}/tensorflow/lite"
  "${CMAKE_BINARY_DIR}/tflite"
  EXCLUDE_FROM_ALL
)

# TFLite ships find-modules for its own dependencies (protobuf among them);
# consumers need them on the module path to reuse the same versions.
list(APPEND CMAKE_MODULE_PATH "${TENSORFLOW_SOURCE_DIR}/tensorflow/lite/tools/cmake/modules")
set(CMAKE_MODULE_PATH "${CMAKE_MODULE_PATH}" PARENT_SCOPE)

# Where TFLite's own build leaves the headers its sources include by bare name.
# fp16 is fetched by the GPU path and included as "fp16.h" from the Core ML
# sources, which have no CMake target upstream to carry the path for them.
set(TFLITE_GENERATED_INCLUDE_DIRS
  "${TENSORFLOW_SOURCE_DIR}"
  "${CMAKE_BINARY_DIR}/tflite/flatbuffers/include"
  "${CMAKE_BINARY_DIR}/tflite/abseil-cpp"
  "${CMAKE_BINARY_DIR}/fp16_headers/include"
  # The GPU sources include these by bare name (<CL/cl.h>, <EGL/egl.h> and so
  # on). TFLite fetches them but carries the paths only on its own targets, and
  # opengl/egl put theirs under api/ rather than include/.
  "${CMAKE_BINARY_DIR}/opencl_headers"
  "${CMAKE_BINARY_DIR}/vulkan_headers/include"
  "${CMAKE_BINARY_DIR}/opengl_headers/api"
  "${CMAKE_BINARY_DIR}/egl_headers/api"
)
