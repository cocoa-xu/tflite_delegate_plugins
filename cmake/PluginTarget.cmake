# tflite_plugin_add_library(<target>
#   SOURCES    <files...>
#   [LIBS      <targets...>]     linked before tensorflow-lite
#   [FRAMEWORKS <names...>]      Apple frameworks
# )
#
# Produces a shared library named <target>-v<TFLITE_VER> exporting exactly the
# two external-delegate entry points and nothing else. The version is in the
# filename because upstream provides no binary-stable delegate interface: a
# plugin is valid only against the runtime release it was built from.
function(tflite_plugin_add_library target)
  cmake_parse_arguments(ARG "" "" "SOURCES;FRAMEWORKS;LIBS" ${ARGN})
  if(NOT ARG_SOURCES)
    message(FATAL_ERROR "tflite_plugin_add_library(${target}): SOURCES is required")
  endif()

  add_library(${target} SHARED ${ARG_SOURCES})

  set_target_properties(${target} PROPERTIES
    OUTPUT_NAME "${target}-v${TFLITE_VER}"
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
