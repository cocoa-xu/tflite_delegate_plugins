# TFLite's OpenCL GPU delegate defines both plugin entry points itself, so this
# needs no adaptor -- only a reference that pulls the object out of the archive.
tflite_plugin_add_library(tensorflowlite_gpu_delegate
  SOURCES plugin_shim.cc
)
