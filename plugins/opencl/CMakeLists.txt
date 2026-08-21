# TFLite's OpenCL delegate defines both plugin entry points itself, so this
# needs no adaptor. It does need its option parsing corrected; see
# tflite_patch_opencl_parse_options in cmake/UpstreamPatches.cmake.
#
# The corrected copy is compiled into the plugin rather than pulled out of
# libtensorflow-lite.a, so the linker resolves the entry points from our object
# and never reaches the archive's.
tflite_patch_opencl_parse_options(OPENCL_DELEGATE_SRC)

tflite_plugin_add_library(tflite_opencl_delegate
  SOURCES "${OPENCL_DELEGATE_SRC}"
)

# TFLite compiles its GPU sources with these. Without the first, delegate.cc
# reaches for a GL fallback that is not built here; without the second it wants
# X11 headers.
target_compile_definitions(tflite_opencl_delegate PRIVATE CL_DELEGATE_NO_GL EGL_NO_X11)

