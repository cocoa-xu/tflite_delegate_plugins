# Puts TFLite's own build into this one, downloading the sources when the caller
# has not supplied a tree. Sets TENSORFLOW_SOURCE_DIR in the cache either way.

# neon2sse, which only x86 targets pull in, declares a cmake_minimum_required
# that CMake 4 refuses outright. This has to be set before TFLite is added.
set(CMAKE_POLICY_VERSION_MINIMUM 3.5 CACHE STRING "" FORCE)

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

set(TFLITE_GENERATED_INCLUDE_DIRS
  "${TENSORFLOW_SOURCE_DIR}"
  "${CMAKE_BINARY_DIR}/tflite/flatbuffers/include"
  "${CMAKE_BINARY_DIR}/tflite/abseil-cpp"
)
