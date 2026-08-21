# Defects in TFLite's own CMake build. Each exists because no upstream target
# links a shared object out of these sources, so nothing there exercises them.

# The custom command generating inference_context_generated.h declares no
# DEPENDS on the flatc target (tensorflow/lite/CMakeLists.txt:453 in 2.21.0),
# unlike the XNNPACK schema command at line 545 of the same file which does.
# Under -j it races and fails with "flatc: No such file or directory".
if(TARGET inference_context_cc_fbs AND TARGET flatbuffers-flatc)
  add_dependencies(inference_context_cc_fbs flatbuffers-flatc)
elseif(NOT TARGET inference_context_cc_fbs)
  # Silence here would let the race back in on a TFLite bump that renames the
  # target, and the symptom is an intermittent cold-build failure rather than
  # anything pointing at this file.
  message(WARNING
    "inference_context_cc_fbs is gone from this TFLite. Either the flatc race "
    "was fixed upstream, in which case delete this, or the target was renamed "
    "and this fixup no longer applies.")
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
