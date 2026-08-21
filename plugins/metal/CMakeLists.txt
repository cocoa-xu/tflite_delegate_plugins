# metal_delegate is a separate static target upstream: TFLGpuDelegateCreate
# lives there rather than in tensorflow-lite, and it exports no plugin ABI, so
# plugin_adaptor.mm supplies one.
tflite_plugin_add_library(tflite_metal_delegate
  SOURCES plugin_adaptor.mm
  LIBS metal_delegate
  FRAMEWORKS Metal Foundation CoreFoundation QuartzCore
)
