# Defects in TFLite's own CMake build. Each exists because no upstream target
# links a shared object out of these sources, so nothing there exercises them.

# The custom command generating inference_context_generated.h declares no
# DEPENDS on the flatc target (tensorflow/lite/CMakeLists.txt:453 in 2.21.0),
# unlike the XNNPACK schema command at line 545 of the same file which does.
# Under -j it races and fails with "flatc: No such file or directory".
# The Metal block that declared inference_context_cc_fbs is turned off by this
# build, and tflite_fixup_metal_delegate below compiles the schema itself with
# the DEPENDS upstream forgot. Nothing to reach for here any more, but the race
# is worth naming: if that block is ever turned back on, it needs this.
if(TARGET inference_context_cc_fbs AND TARGET flatbuffers-flatc)
  add_dependencies(inference_context_cc_fbs flatbuffers-flatc)
endif()

# libtensorflow-lite.a leaves seven absl::log_internal::LogMessage symbols
# undefined, from LOG() calls in flatbuffer_conversions.cc and elsewhere. A
# static archive never resolves symbols, so nothing notices until something
# links a .so, which is exactly what this project does.
#
# This is a version window, not a defect. TensorFlow PR #110784 added
# absl::log to the tensorflow-lite target on 2026-08-14; v2.21.0 was tagged on
# 2026-03-04, five months before that, so it does not have the line. Verified
# on 2026-08-21: a shared library linked against a master build needs none of
# what follows.
#
# Still open against LiteRT 2.2.0, checked on 2026-08-26: its tflite/CMakeLists.txt
# has no absl::log line either, so the window did not close when the runtime
# moved off TensorFlow.
#
# DELETE THIS once LITERT_VER moves to a release that carries the equivalent of
# #110784. The check is one grep in the sources this build is using:
#
#   grep 'absl::log$' "${LITERT_SOURCE_DIR}/tflite/CMakeLists.txt"
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


# LiteRT 2.2.0 renamed six Metal sources from .cc to .mm and did not update the
# list in its own CMakeLists, so TFLITE_ENABLE_METAL fails at add_library with
# "Cannot find source file". Nothing downstream can correct a target that was
# never created, so the option is off and the target is declared here instead.
#
# The list is copied, which means it can drift. The check below is what makes
# that loud: it reads the names back out of upstream's CMakeLists and compares
# them, ignoring the extension, so a source added or removed upstream stops the
# build rather than quietly producing a delegate missing a piece.
function(tflite_fixup_metal_delegate)
  if(NOT APPLE)
    return()
  endif()

  set(_metal_dir "${LITERT_SOURCE_DIR}/tflite/delegates/gpu/metal")
  set(_ours
    "${LITERT_SOURCE_DIR}/tflite/delegates/gpu/metal_delegate.mm"
    "${_metal_dir}/buffer.mm"
    "${_metal_dir}/buffer_convert.mm"
    "${_metal_dir}/common.mm"
    "${_metal_dir}/compute_task.mm"
    "${_metal_dir}/inference_context.mm"
    "${_metal_dir}/metal_arguments.mm"
    "${_metal_dir}/metal_device.mm"
    "${_metal_dir}/metal_spatial_tensor.mm"
  )

  file(READ "${LITERT_SOURCE_DIR}/tflite/CMakeLists.txt" _cmakelists)
  string(REGEX MATCH "list\\(APPEND TFLITE_DELEGATES_METAL_SRCS[^)]*\\)" _block "${_cmakelists}")
  if(NOT _block)
    message(FATAL_ERROR
      "TFLITE_DELEGATES_METAL_SRCS is no longer in LiteRT's CMakeLists, so the "
      "Metal source list here has nothing to be checked against.")
  endif()
  string(REGEX MATCHALL "[a-z0-9_]+\\.(cc|mm)" _theirs "${_block}")
  list(LENGTH _theirs _theirs_count)
  list(LENGTH _ours _ours_count)
  if(NOT _theirs_count EQUAL _ours_count)
    message(FATAL_ERROR
      "LiteRT ${LITERT_VER} lists ${_theirs_count} Metal sources and this build "
      "replicates ${_ours_count}. Bring tflite_fixup_metal_delegate back in line.")
  endif()

  foreach(_theirs_one IN LISTS _theirs)
    string(REGEX REPLACE "\\.(cc|mm)$" "" _stem "${_theirs_one}")
    set(_found FALSE)
    foreach(_ours_one IN LISTS _ours)
      get_filename_component(_ours_stem "${_ours_one}" NAME_WE)
      if(_ours_stem STREQUAL _stem)
        set(_found TRUE)
      endif()
    endforeach()
    if(NOT _found)
      message(FATAL_ERROR
        "LiteRT ${LITERT_VER} builds ${_theirs_one} into the Metal delegate and "
        "this build does not. Bring tflite_fixup_metal_delegate back in line.")
    endif()
  endforeach()

  foreach(_one IN LISTS _ours)
    if(NOT EXISTS "${_one}")
      message(FATAL_ERROR "no Metal source at ${_one}")
    endif()
  endforeach()

  # inference_context.fbs is compiled by the block that was turned off, so it is
  # compiled here. Upstream writes the header back into its own source tree;
  # this writes it into the build tree, so a second build does not depend on
  # whether the first one ran.
  set(_gen "${CMAKE_BINARY_DIR}/litert_generated/tflite/delegates/gpu/metal")
  file(MAKE_DIRECTORY "${_gen}")
  # flatbuffers-flatc is an ExternalProject rather than an executable target, so
  # TARGET_FILE cannot name it and the binary has to be named by its path.
  if(FLATBUFFERS_FLATC_EXECUTABLE)
    set(_flatc "${FLATBUFFERS_FLATC_EXECUTABLE}")
  elseif(TARGET flatbuffers-flatc)
    set(_flatc "${CMAKE_BINARY_DIR}/flatbuffers-flatc/bin/flatc")
  else()
    set(_flatc flatc)
  endif()
  # inference_context.fbs still includes its siblings as tensorflow/lite/..., a
  # path LiteRT does not have. Upstream resolves that from the TensorFlow tree,
  # which means the schema compiled into the Metal delegate comes from a
  # different release than the sources around it. The two are identical in
  # LiteRT 2.2.0 against TensorFlow 2.21.0-rc0, so nothing is wrong today; a
  # link that points the old path at LiteRT's own tree is what keeps it that way
  # without depending on the two staying in step.
  set(_fbs_include "${CMAKE_BINARY_DIR}/litert_fbs_include")
  file(MAKE_DIRECTORY "${_fbs_include}/tensorflow")
  if(NOT EXISTS "${_fbs_include}/tensorflow/lite")
    file(CREATE_LINK "${LITERT_SOURCE_DIR}/tflite" "${_fbs_include}/tensorflow/lite" SYMBOLIC)
  endif()

  add_custom_command(
    OUTPUT "${_gen}/inference_context_generated.h"
    COMMAND "${_flatc}" --scoped-enums
            -I "${_fbs_include}"
            -I "${LITERT_SOURCE_DIR}"
            -o "${_gen}"
            -c "${_metal_dir}/inference_context.fbs"
    DEPENDS "${_metal_dir}/inference_context.fbs"
    COMMENT "flatc: inference_context.fbs"
    VERBATIM
  )
  add_custom_target(litert_inference_context_fbs
                    DEPENDS "${_gen}/inference_context_generated.h")
  if(TARGET flatbuffers-flatc)
    add_dependencies(litert_inference_context_fbs flatbuffers-flatc)
  endif()

  add_library(metal_delegate STATIC ${_ours})
  add_dependencies(metal_delegate litert_inference_context_fbs)
  # Upstream hangs abseil off TFLITE_TARGET_DEPENDENCIES, which reaches this
  # only because it is linked into the same binary as the runtime. A plugin is
  # a shared object of its own, and linking the whole runtime into it would put
  # a second copy in the process, so the pieces it actually calls are named.
  target_link_libraries(metal_delegate PUBLIC
    absl::status
    absl::statusor
    absl::strings
    absl::span
    absl::flat_hash_map
  )
  target_include_directories(metal_delegate
    PUBLIC
      "${CMAKE_BINARY_DIR}/abseil-cpp"
      "${CMAKE_BINARY_DIR}/flatbuffers/include"
    PRIVATE
      "${LITERT_SOURCE_DIR}"
      "${TENSORFLOW_SOURCE_DIR}"
      "${CMAKE_BINARY_DIR}/fp16_headers/include"
      "${LITERT_SOURCE_DIR}/tflite/delegates/gpu/common"
      "${LITERT_SOURCE_DIR}/tflite/delegates/gpu/common/task"
      "${CMAKE_BINARY_DIR}/litert_generated"
  )
  message(STATUS "metal_delegate rebuilt here: LiteRT ${LITERT_VER} lists six of its sources under the wrong extension")
endfunction()
