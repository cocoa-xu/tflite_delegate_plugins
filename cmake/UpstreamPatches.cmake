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
  # ParseOptions has nine option branches and every one of them is inverted.
  # Counting rather than checking for at least one, because a partial match is
  # the dangerous outcome: the branches that still read inverted swallow the
  # key belonging to the branch after them, so a valid option makes the plugin
  # refuse to create.
  set(_expected_tests 9)
  string(REGEX MATCHALL "strcmp\\(options_keys\\[i\\], \"[a-z0-9_]+\"\\)\\)" _hits "${_text}")
  list(LENGTH _hits _count)
  if(NOT _count EQUAL _expected_tests)
    message(FATAL_ERROR
      "opencl_parse_options expected ${_expected_tests} inverted strcmp tests in "
      "ParseOptions and found ${_count}. Either TFLite ${TFLITE_VER} fixed some or "
      "all of them, in which case rewrite or delete this patch, or the code moved. "
      "Patching a subset is worse than patching none.")
  endif()
  string(REGEX REPLACE "strcmp\\((options_keys\\[i\\], \"[a-z0-9_]+\")\\)\\)"
         "strcmp(\\1) == 0)" _text "${_text}")
  string(REGEX MATCHALL "strcmp\\(options_keys\\[i\\], \"[a-z0-9_]+\"\\)\\)" _left "${_text}")
  list(LENGTH _left _remaining)
  if(NOT _remaining EQUAL 0)
    message(FATAL_ERROR
      "opencl_parse_options left ${_remaining} inverted tests behind. The match "
      "pattern and the replace pattern have drifted apart.")
  endif()

  # The entry points are marked TFL_CAPI_EXPORT, which expands to nothing when
  # TFL_STATIC_LIBRARY_BUILD is defined. That is right for objects headed into
  # an archive and wrong here, where -fvisibility=hidden then strips the only
  # two symbols this plugin exists to export. Marking them directly does not
  # depend on the order CMake happens to put -D and -U in.
  # Silence here is the worst outcome in the file: the plugin still builds, the
  # message below still says it was patched, and the .so exports nothing at all,
  # so dlsym hands the host a null and it dies calling it.
  foreach(_decl
      "TfLiteDelegate* tflite_plugin_create_delegate("
      "void tflite_plugin_destroy_delegate(TfLiteDelegate* delegate)")
    string(FIND "${_text}" "${_decl}" _at)
    if(_at EQUAL -1)
      message(FATAL_ERROR
        "opencl_parse_options could not find \"${_decl}\" to mark visible. "
        "Without it -fvisibility=hidden strips the entry points and the plugin "
        "exports nothing.")
    endif()
    string(REPLACE "${_decl}" "__attribute__((visibility(\"default\"))) ${_decl}"
           _text "${_text}")
  endforeach()

  # Upstream dereferences delegate->data_ without checking, but the external
  # delegate ABI says destroying a null delegate is allowed and does nothing.
  # A host that pairs create and destroy unconditionally, which is what a
  # resource destructor does, takes the process down on a declined create.
  set(_destroy "__attribute__((visibility(\"default\"))) void tflite_plugin_destroy_delegate(TfLiteDelegate* delegate) {")
  string(FIND "${_text}" "${_destroy}" _at)
  if(_at EQUAL -1)
    message(FATAL_ERROR "opencl_parse_options could not find the destroy body to guard.")
  endif()
  string(REPLACE "${_destroy}" "${_destroy}\n  if (delegate == nullptr) return;"
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
