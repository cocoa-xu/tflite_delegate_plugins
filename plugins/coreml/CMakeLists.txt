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
# coreml_delegate.mm needs its Neural Engine detection corrected; see
# tflite_patch_coreml_neural_engine in cmake/UpstreamPatches.cmake.
tflite_patch_coreml_neural_engine(COREML_DELEGATE_PATCHED)

set(COREML_DELEGATE_SOURCES
  "${COREML_DELEGATE_PATCHED}"
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

tflite_plugin_add_library(tflite_coreml_delegate
  SOURCES plugin_adaptor.mm
  LIBS coreml_delegate
  FRAMEWORKS CoreML Foundation CoreFoundation
)
target_include_directories(tflite_coreml_delegate PRIVATE "${COREML_PROTO_OUT}")
