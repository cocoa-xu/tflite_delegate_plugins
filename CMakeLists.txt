cmake_minimum_required(VERSION 3.16)
project(tflite_delegate_plugins LANGUAGES CXX)

set(TFLITE_VER "2.21.0" CACHE STRING "TensorFlow Lite version to build against")
set(TENSORFLOW_SOURCE_DIR "" CACHE PATH "Existing TensorFlow source tree; downloaded when empty")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

# neon2sse, pulled in on x86, declares a cmake_minimum_required that CMake 4
# refuses outright.
set(CMAKE_POLICY_VERSION_MINIMUM 3.5 CACHE STRING "" FORCE)

if(TENSORFLOW_SOURCE_DIR STREQUAL "")
  include(FetchContent)
  # DOWNLOAD_EXTRACT_TIMESTAMP arrived in 3.24; older CMake reads it as another
  # URL entry and fails with "At least one entry of URL is a path".
  set(TFLITE_FETCH_EXTRA "")
  if(CMAKE_VERSION VERSION_GREATER_EQUAL 3.24)
    set(TFLITE_FETCH_EXTRA DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
  endif()
  FetchContent_Declare(tensorflow
    URL "https://github.com/tensorflow/tensorflow/archive/refs/tags/v${TFLITE_VER}.zip"
    ${TFLITE_FETCH_EXTRA}
  )
  FetchContent_MakeAvailable(tensorflow)
  set(TENSORFLOW_SOURCE_DIR "${tensorflow_SOURCE_DIR}" CACHE PATH "" FORCE)
endif()

if(NOT EXISTS "${TENSORFLOW_SOURCE_DIR}/tensorflow/lite/CMakeLists.txt")
  message(FATAL_ERROR "No TFLite sources under TENSORFLOW_SOURCE_DIR=${TENSORFLOW_SOURCE_DIR}")
endif()

set(TFLITE_ENABLE_GPU ON CACHE BOOL "" FORCE)
set(TFLITE_ENABLE_XNNPACK OFF CACHE BOOL "" FORCE)
if(APPLE)
  set(TFLITE_ENABLE_METAL ON CACHE BOOL "" FORCE)
endif()

add_subdirectory("${TENSORFLOW_SOURCE_DIR}/tensorflow/lite" "${CMAKE_BINARY_DIR}/tflite" EXCLUDE_FROM_ALL)

# Upstream generates inference_context_generated.h with a custom command that
# declares no dependency on the flatc target (CMakeLists.txt:453 in 2.21.0),
# unlike the XNNPACK schema command thirty lines below it. Under -j it races and
# fails with "flatc: No such file or directory".
if(TARGET inference_context_cc_fbs AND TARGET flatbuffers-flatc)
  add_dependencies(inference_context_cc_fbs flatbuffers-flatc)
endif()

# The GPU sources reference absl logging, but nothing in the tensorflow-lite
# target links it. A static archive never resolves symbols, so the gap only
# surfaces when something builds a shared object out of it -- which no upstream
# target does.
set(TFLITE_PLUGIN_ABSL_DEPS
  absl::log_internal_message
  absl::log_internal_check_op
  absl::log_internal_nullguard
  absl::log_internal_conditions
  absl::log_internal_globals
  absl::log_globals
  absl::log_severity
  absl::log_sink
  absl::log_entry
  absl::strerror
)

function(tflite_plugin_target target)
  cmake_parse_arguments(ARG "" "" "SOURCES;FRAMEWORKS;LIBS" ${ARGN})
  add_library(${target} SHARED ${ARG_SOURCES})
  set_target_properties(${target} PROPERTIES
    OUTPUT_NAME "${target}-v${TFLITE_VER}"
    CXX_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN ON
  )
  target_include_directories(${target} PRIVATE
    "${TENSORFLOW_SOURCE_DIR}"
    "${CMAKE_BINARY_DIR}/tflite/flatbuffers/include"
    "${CMAKE_BINARY_DIR}/tflite/abseil-cpp"
  )
  target_link_libraries(${target} PRIVATE ${ARG_LIBS} tensorflow-lite ${TFLITE_PLUGIN_ABSL_DEPS})
  if(APPLE)
    target_link_options(${target} PRIVATE
      "-Wl,-exported_symbols_list,${CMAKE_CURRENT_SOURCE_DIR}/cmake/exported_symbols.lds")
    foreach(fw IN LISTS ARG_FRAMEWORKS)
      target_link_libraries(${target} PRIVATE "-framework ${fw}")
    endforeach()
  else()
    target_link_options(${target} PRIVATE
      "-Wl,--version-script,${CMAKE_CURRENT_SOURCE_DIR}/cmake/version_script.lds")
  endif()
  install(TARGETS ${target} LIBRARY DESTINATION lib)
endfunction()

tflite_plugin_target(tensorflowlite_gpu_delegate SOURCES src/opencl_plugin_shim.cc)

if(APPLE)
  enable_language(OBJCXX)
  # metal_delegate is a separate static target upstream; TFLGpuDelegateCreate
  # lives there, not in tensorflow-lite.
  tflite_plugin_target(tensorflowlite_metal_delegate
    SOURCES src/metal_plugin_adaptor.mm
    LIBS metal_delegate
    FRAMEWORKS Metal Foundation CoreFoundation QuartzCore)
endif()

message(STATUS "tflite_delegate_plugins: TFLite ${TFLITE_VER}, sources at ${TENSORFLOW_SOURCE_DIR}")
