# Corrections to TFLite's own sources, kept together so the full set is visible
# in one place, after the shape evision uses for OpenCV.
#
# Two rules these follow, both learned the hard way:
#
#   * A patched copy goes in the build tree. The sources are fetched and cached,
#     and editing them in place makes the next build depend on whether the last
#     one ran.
#   * A patch that no longer matches is a hard error, never a silent skip. When
#     upstream moves the code, the build must say so rather than quietly
#     producing a plugin without the fix.
#
# Each function records the versions it was verified against. TFLITE_VER outside
# that list is a warning: the patch still applies if it matches, but nobody has
# checked the result.

function(_tflite_patch_verified_for patch_name)
  list(FIND ARGN "${TFLITE_VER}" _found)
  if(_found EQUAL -1)
    message(WARNING
      "${patch_name} was verified against ${ARGN}, not TFLite ${TFLITE_VER}. "
      "It will be applied if it still matches; check the result.")
  endif()
endfunction()

# ParseOptions in delegates/gpu/delegate.cc tests every option key with a bare
# strcmp, which returns 0 on a match and so makes each test fire on *mismatch*.
# An invented option name is accepted and stored in the first field; a real one
# is applied to the next field along. Nothing errors, nothing logs. All nine
# branches are written this way.
#
# out_var receives the path to the corrected copy.
function(tflite_patch_opencl_parse_options out_var)
  _tflite_patch_verified_for("opencl_parse_options" "2.21.0")

  set(_src "${TENSORFLOW_SOURCE_DIR}/tensorflow/lite/delegates/gpu/delegate.cc")
  set(_out "${CMAKE_CURRENT_BINARY_DIR}/patched")
  file(MAKE_DIRECTORY "${_out}")

  file(READ "${_src}" _text)
  string(REGEX MATCHALL "strcmp\\(options_keys\\[i\\], \"[a-z0-9_]+\"\\)\\)" _hits "${_text}")
  list(LENGTH _hits _count)
  if(_count EQUAL 0)
    message(FATAL_ERROR
      "opencl_parse_options found no inverted strcmp tests in ParseOptions. "
      "Either TFLite ${TFLITE_VER} fixed them, in which case delete this patch, "
      "or the code moved and it needs rewriting.")
  endif()
  string(REGEX REPLACE "strcmp\\((options_keys\\[i\\], \"[a-z0-9_]+\")\\)\\)"
         "strcmp(\\1) == 0)" _text "${_text}")

  # The entry points are marked TFL_CAPI_EXPORT, which expands to nothing when
  # TFL_STATIC_LIBRARY_BUILD is defined -- correct for objects destined for an
  # archive, wrong here, where -fvisibility=hidden then strips the only two
  # symbols this plugin exists to export. Marking them directly does not depend
  # on the order CMake happens to put -D and -U in.
  string(REPLACE "TfLiteDelegate* tflite_plugin_create_delegate("
         "__attribute__((visibility(\"default\"))) TfLiteDelegate* tflite_plugin_create_delegate("
         _text "${_text}")
  string(REPLACE "void tflite_plugin_destroy_delegate(TfLiteDelegate* delegate)"
         "__attribute__((visibility(\"default\"))) void tflite_plugin_destroy_delegate(TfLiteDelegate* delegate)"
         _text "${_text}")

  file(WRITE "${_out}/delegate.cc" "${_text}")
  message(STATUS "patched opencl_parse_options: corrected ${_count} inverted tests")
  set(${out_var} "${_out}/delegate.cc" PARENT_SCOPE)
endfunction()

# IsNeuralEngineAvailable in delegates/coreml/coreml_delegate.mm identifies the
# Neural Engine by matching uname().machine against "iPad" and "iPhone"
# prefixes, so it reports none on every Mac, including Apple silicon where one
# is always present. Without this the delegate's own default option can never
# produce a delegate on macOS.
#
# It has one caller and decides only whether Create refuses; it takes no part in
# any computation.
function(tflite_patch_coreml_neural_engine out_var)
  _tflite_patch_verified_for("coreml_neural_engine" "2.21.0")

  set(_src "${TENSORFLOW_SOURCE_DIR}/tensorflow/lite/delegates/coreml/coreml_delegate.mm")
  set(_out "${CMAKE_CURRENT_BINARY_DIR}/patched")
  file(MAKE_DIRECTORY "${_out}")

  set(_from [==[    return major_version >= 11;
  }
  return false;
}]==])
  set(_to [==[    return major_version >= 11;
  }
#if TARGET_OS_OSX
  // Patched by tflite_delegate_plugins: every Apple silicon Mac has a Neural
  // Engine, and uname reports "arm64" there, matching neither prefix above.
  if (strncmp("arm64", system_info.machine, 5) == 0) return true;
#endif
  return false;
}]==])

  file(READ "${_src}" _text)
  string(FIND "${_text}" "${_from}" _at)
  if(_at EQUAL -1)
    message(FATAL_ERROR
      "coreml_neural_engine could not match IsNeuralEngineAvailable in TFLite "
      "${TFLITE_VER}. Re-read the function before updating this patch.")
  endif()
  string(REPLACE "${_from}" "${_to}" _text "${_text}")
  file(WRITE "${_out}/coreml_delegate.mm" "${_text}")
  message(STATUS "patched coreml_neural_engine: Apple silicon now recognised")
  set(${out_var} "${_out}/coreml_delegate.mm" PARENT_SCOPE)
endfunction()
