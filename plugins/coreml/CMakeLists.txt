# TFLite's Core ML delegate depends on coremltools' model definitions, which are
# not in the TensorFlow tree; they are vendored under third_party/ and generated
# here. The sources include them as "mlmodel/format/X.pb.h", so --proto_path
# points at the vendor root and the directory structure carries through.
find_package(Protobuf REQUIRED)

set(COREML_PROTO_ROOT "${PROJECT_SOURCE_DIR}/third_party/coremltools")
set(COREML_PROTO_OUT "${CMAKE_BINARY_DIR}/coreml_proto")

file(GLOB COREML_PROTO_FILES "${COREML_PROTO_ROOT}/mlmodel/format/*.proto")
list(LENGTH COREML_PROTO_FILES _n)
if(_n EQUAL 0)
  message(FATAL_ERROR "No .proto files under ${COREML_PROTO_ROOT}/mlmodel/format")
endif()

set(COREML_PROTO_GENERATED "")
foreach(proto IN LISTS COREML_PROTO_FILES)
  get_filename_component(stem "${proto}" NAME_WE)
  list(APPEND COREML_PROTO_GENERATED
    "${COREML_PROTO_OUT}/mlmodel/format/${stem}.pb.cc"
    "${COREML_PROTO_OUT}/mlmodel/format/${stem}.pb.h")
endforeach()

# One invocation for all of them: they import each other, and protoc resolves
# that in a single pass without us restating the graph.
add_custom_command(
  OUTPUT ${COREML_PROTO_GENERATED}
  COMMAND ${CMAKE_COMMAND} -E make_directory ${COREML_PROTO_OUT}/mlmodel/format
  COMMAND ${Protobuf_PROTOC_EXECUTABLE}
  # proto_path is the directory holding the files, because they import each
  # other by bare name ("DataStructures.proto"); cpp_out then puts the results
  # under mlmodel/format so that the delegate's own
  # #include "mlmodel/format/X.pb.h" resolves against COREML_PROTO_OUT.
  # No quotes: VERBATIM escapes arguments itself, and quoting here would make
  # the quote characters part of the path protoc receives.
  ARGS --cpp_out=${COREML_PROTO_OUT}/mlmodel/format
       --proto_path=${COREML_PROTO_ROOT}/mlmodel/format
       ${COREML_PROTO_FILES}
  DEPENDS ${Protobuf_PROTOC_EXECUTABLE} ${COREML_PROTO_FILES}
  COMMENT "Generating coremltools model definitions (${_n} files)"
  VERBATIM
)
set_source_files_properties(${COREML_PROTO_GENERATED} PROPERTIES GENERATED TRUE)

add_library(coreml_mlmodel_proto STATIC ${COREML_PROTO_GENERATED})
target_link_libraries(coreml_mlmodel_proto PUBLIC protobuf::libprotobuf)
target_include_directories(coreml_mlmodel_proto PUBLIC "${COREML_PROTO_OUT}")
set_target_properties(coreml_mlmodel_proto PROPERTIES POSITION_INDEPENDENT_CODE ON)

# TFLite's Core ML delegate has no CMake target upstream at all. Metal at least
# ships a static one, so the Core ML sources are listed here instead. The two
# test files are excluded.
set(COREML_SRC_DIR "${TENSORFLOW_SOURCE_DIR}/tensorflow/lite/delegates/coreml")
# coreml_delegate.mm is patched rather than used as-is: see the comment on
# COREML_ANE_PATCH_FROM below. The patched copy lives in the build tree so the
# TFLite sources, which are fetched and cached, are never modified.
set(COREML_PATCHED_DIR "${CMAKE_CURRENT_BINARY_DIR}/patched")
file(MAKE_DIRECTORY "${COREML_PATCHED_DIR}")

# IsNeuralEngineAvailable() decides only whether Create refuses; it takes no
# part in any computation. It identifies the Neural Engine by matching
# uname().machine against "iPad"/"iPhone" prefixes, so it returns false on every
# Mac, including Apple silicon, where a Neural Engine is always present and
# uname reports "arm64". The result is that the delegate's own default option,
# DevicesWithNeuralEngine, can never produce a delegate on macOS.
# Bracket arguments so the newlines are real newlines rather than backslash-n.
set(COREML_ANE_PATCH_FROM [==[    return major_version >= 11;
  }
  return false;
}]==])
set(COREML_ANE_PATCH_TO [==[    return major_version >= 11;
  }
#if TARGET_OS_OSX
  // Patched by tflite-delegate-plugins: every Apple silicon Mac has a Neural
  // Engine, and uname reports "arm64" there, matching neither prefix above.
  if (strncmp("arm64", system_info.machine, 5) == 0) return true;
#endif
  return false;
}]==])

file(READ "${COREML_SRC_DIR}/coreml_delegate.mm" _coreml_delegate_src)
string(FIND "${_coreml_delegate_src}" "${COREML_ANE_PATCH_FROM}" _found)
if(_found EQUAL -1)
  message(FATAL_ERROR
    "Could not apply the Neural Engine patch to coreml_delegate.mm: the code it "
    "matches has changed upstream. Re-check IsNeuralEngineAvailable() in "
    "TFLite ${TFLITE_VER} before updating COREML_ANE_PATCH_FROM.")
endif()
string(REPLACE "${COREML_ANE_PATCH_FROM}" "${COREML_ANE_PATCH_TO}"
       _coreml_delegate_src "${_coreml_delegate_src}")
file(WRITE "${COREML_PATCHED_DIR}/coreml_delegate.mm" "${_coreml_delegate_src}")

set(COREML_DELEGATE_SOURCES
  "${COREML_PATCHED_DIR}/coreml_delegate.mm"
  "${COREML_SRC_DIR}/coreml_delegate_kernel.mm"
  "${COREML_SRC_DIR}/coreml_executor.mm"
)
file(GLOB COREML_BUILDER_SOURCES "${COREML_SRC_DIR}/builders/*.cc")
list(FILTER COREML_BUILDER_SOURCES EXCLUDE REGEX "_test\\.cc$")
list(APPEND COREML_DELEGATE_SOURCES ${COREML_BUILDER_SOURCES})

add_library(coreml_delegate STATIC ${COREML_DELEGATE_SOURCES})
target_include_directories(coreml_delegate PUBLIC
  ${TFLITE_GENERATED_INCLUDE_DIRS}
  "${COREML_PROTO_OUT}"
)
target_link_libraries(coreml_delegate PUBLIC
  coreml_mlmodel_proto
  tensorflow-lite
  "-framework CoreML"
  "-framework Foundation"
)
set_target_properties(coreml_delegate PROPERTIES POSITION_INDEPENDENT_CODE ON)

tflite_plugin_add_library(tensorflowlite_coreml_delegate
  SOURCES plugin_adaptor.mm
  LIBS coreml_delegate
  FRAMEWORKS CoreML Foundation CoreFoundation
)
target_include_directories(tensorflowlite_coreml_delegate PRIVATE "${COREML_PROTO_OUT}")
