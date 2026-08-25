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
# Each function records the versions it was verified against. LITERT_VER outside
# that list is a warning: the patch still applies if it matches, but nobody has
# checked the result.

function(_tflite_patch_verified_for patch_name)
  # LITERT_VER names the release this build downloads. A caller who supplied
  # their own LITERT_SOURCE_DIR can leave it at the default while pointing at
  # any version at all, so it says nothing about the tree being patched and the
  # check has to say so rather than pass quietly.
  if(TFLITE_SOURCE_WAS_SUPPLIED)
    message(WARNING
      "${patch_name} is being applied to a LiteRT tree this build did not "
      "fetch, so its version is unknown. It was verified against ${ARGN}.")
    return()
  endif()
  list(FIND ARGN "${LITERT_VER}" _found)
  if(_found EQUAL -1)
    message(WARNING
      "${patch_name} was verified against ${ARGN}, not LiteRT ${LITERT_VER}. "
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
  _tflite_patch_verified_for("opencl_parse_options" "2.2.0")

  set(_src "${LITERT_SOURCE_DIR}/tflite/delegates/gpu/delegate.cc")
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
      "ParseOptions and found ${_count}. Either LiteRT ${LITERT_VER} fixed some or "
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
# tflite_patch_coreml_neural_engine used to live here. It taught the Core ML
# delegate that every Apple silicon Mac has a Neural Engine, which TFLite 2.21.0
# did not know: uname reports "arm64" there and the detection only matched the
# iPad and iPhone prefixes. LiteRT 2.2.0 handles it upstream, under TARGET_OS_OSX
# and __aarch64__ rather than by comparing the machine string, so there is
# nothing left to correct.
