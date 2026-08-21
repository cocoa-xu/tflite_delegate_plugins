if(TFLITE_PLUGINS_OPENCL)
  add_subdirectory(opencl)
endif()

if(TFLITE_PLUGINS_METAL AND APPLE)
  enable_language(OBJCXX)
  add_subdirectory(metal)
endif()
