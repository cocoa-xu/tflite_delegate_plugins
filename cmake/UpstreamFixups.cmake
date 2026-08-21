# Defects in TFLite's own CMake build. Each exists because no upstream target
# links a shared object out of these sources, so nothing there exercises them.

# The custom command generating inference_context_generated.h declares no
# DEPENDS on the flatc target (tensorflow/lite/CMakeLists.txt:453 in 2.21.0),
# unlike the XNNPACK schema command thirty lines below it which does. Under -j
# it races and fails with "flatc: No such file or directory".
if(TARGET inference_context_cc_fbs AND TARGET flatbuffers-flatc)
  add_dependencies(inference_context_cc_fbs flatbuffers-flatc)
endif()

# The GPU sources reference absl logging but the tensorflow-lite target links
# none of it. A static archive never resolves symbols, so the gap is invisible
# until something builds a .so, which is exactly what this project does.
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
