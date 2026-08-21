// TFLite's OpenCL GPU delegate defines both plugin entry points itself
// (delegates/gpu/delegate.cc), so this library needs no adaptor -- only a
// reference that makes the linker pull that object out of the static archive.
#include "tensorflow/lite/delegates/gpu/delegate.h"

namespace {
__attribute__((used)) void* const kKeepPluginEntryPoints[] = {
    reinterpret_cast<void*>(&tflite_plugin_create_delegate),
    reinterpret_cast<void*>(&tflite_plugin_destroy_delegate),
};
}  // namespace
