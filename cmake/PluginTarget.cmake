# tflite_plugin_add_library(<target>
#   SOURCES    <files...>
#   [LIBS      <targets...>]     linked before tensorflow-lite
#   [FRAMEWORKS <names...>]      Apple frameworks
# )
#
# Produces a shared library named lib<target> exporting exactly the two
# external-delegate entry points and nothing else.
#
# The TFLite version is not in the filename. The release it ships in names it,
# and the check that matters happens at runtime against
# tflite_beam:tflite_version/0.
# Putting it here only made every path referencing a plugin break on upgrade.
function(tflite_plugin_add_library target)
  cmake_parse_arguments(ARG "" "" "SOURCES;FRAMEWORKS;LIBS" ${ARGN})
  if(NOT ARG_SOURCES)
    message(FATAL_ERROR "tflite_plugin_add_library(${target}): SOURCES is required")
  endif()

  add_library(${target} SHARED ${ARG_SOURCES})

  set_target_properties(${target} PROPERTIES
    CXX_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN ON
  )

  target_include_directories(${target} PRIVATE ${TFLITE_GENERATED_INCLUDE_DIRS})
  target_link_libraries(${target} PRIVATE
    ${ARG_LIBS} tensorflow-lite ${TFLITE_PLUGIN_ABSL_DEPS})

  if(APPLE)
    target_link_options(${target} PRIVATE
      "-Wl,-exported_symbols_list,${PROJECT_SOURCE_DIR}/linker/exported_symbols.lds")
    foreach(framework IN LISTS ARG_FRAMEWORKS)
      target_link_libraries(${target} PRIVATE "-framework ${framework}")
    endforeach()
  else()
    target_link_options(${target} PRIVATE
      "-Wl,--version-script,${PROJECT_SOURCE_DIR}/linker/version_script.lds")
  endif()

  if(TFLITE_PLUGINS_INSTALL)
    install(TARGETS ${target} LIBRARY DESTINATION lib)
  endif()
endfunction()
