// Plugin adaptor for TFLite's Core ML delegate, which exports only
// TfLiteCoreMlDelegateCreate and no plugin ABI of its own. Objective-C++
// because the delegate's headers reach into the Core ML framework. Shaped after
// delegates/utils/dummy_delegate/external_delegate_adaptor.cc.
#include <cstddef>
#include <cstdlib>
#include <cstring>
#include <string>

#include "tflite/core/c/common.h"
#include "tflite/delegates/external/external_delegate_interface.h"
#include <cerrno>
#include <climits>

#include "tflite/delegates/coreml/coreml_delegate.h"

namespace {

bool ParseInt(const char* value, int* out) {
    if (value == nullptr) return false;
    char* end = nullptr;
    errno = 0;
    const long parsed = std::strtol(value, &end, 10);
    if (end == value || *end != '\0') return false;
    // Without this a value past LONG_MAX comes back as LONG_MAX and one past
    // INT_MAX wraps, so 4294967298 arrives as 2 and looks deliberate.
    if (errno == ERANGE) return false;
    if (parsed < INT_MIN || parsed > INT_MAX) return false;
    *out = static_cast<int>(parsed);
    return true;
}

bool ParseEnabledDevices(const char* value,
                         TfLiteCoreMlDelegateEnabledDevices* out) {
    if (std::strcmp(value, "neural_engine") == 0) {
        *out = TfLiteCoreMlDelegateDevicesWithNeuralEngine;
    } else if (std::strcmp(value, "all") == 0) {
        *out = TfLiteCoreMlDelegateAllDevices;
    } else {
        return false;
    }
    return true;
}

void Report(void (*report_error)(const char*), const std::string& message) {
    if (report_error != nullptr) report_error(message.c_str());
}

}  // namespace

extern "C" {

TFL_EXTERNAL_DELEGATE_EXPORT TfLiteDelegate* tflite_plugin_create_delegate(
    const char* const* options_keys, const char* const* options_values,
    size_t num_options, void (*report_error)(const char*)) {
    TfLiteCoreMlDelegateOptions options = {};
    // Upstream's own default. It is usable here only because the build patches
    // IsNeuralEngineAvailable(), which otherwise reports no Neural Engine on
    // every Mac; see plugins/coreml/CMakeLists.txt.
    options.enabled_devices = TfLiteCoreMlDelegateDevicesWithNeuralEngine;
    // Left at 3 because upstream does not treat 0 as a request for a default:
    // it logs "coreml_version must be 2 or 3. Setting to 3." and overwrites it.
    options.coreml_version = 3;

    for (size_t i = 0; i < num_options; ++i) {
        const char* key = options_keys[i];
        const char* value = options_values[i];
        // The ABI only promises the arrays themselves may be null when
        // num_options is zero. A null element is a caller bug, and saying so
        // beats dereferencing it.
        if (key == nullptr || value == nullptr) {
            Report(report_error, "delegate options contain a null entry");
            return nullptr;
        }
        bool ok;
        if (std::strcmp(key, "enabled_devices") == 0) {
            ok = ParseEnabledDevices(value, &options.enabled_devices);
        } else if (std::strcmp(key, "coreml_version") == 0) {
            ok = ParseInt(value, &options.coreml_version);
        } else if (std::strcmp(key, "max_delegated_partitions") == 0) {
            ok = ParseInt(value, &options.max_delegated_partitions);
        } else if (std::strcmp(key, "min_nodes_per_partition") == 0) {
            ok = ParseInt(value, &options.min_nodes_per_partition);
        } else {
            Report(report_error, std::string("unknown option: ") + key);
            return nullptr;
        }
        if (!ok) {
            Report(report_error,
                   std::string("bad value for ") + key + ": " + value);
            return nullptr;
        }
    }

    TfLiteDelegate* delegate = TfLiteCoreMlDelegateCreate(&options);
    if (delegate == nullptr) {
        Report(report_error, "TfLiteCoreMlDelegateCreate returned no delegate");
    }
    return delegate;
}

TFL_EXTERNAL_DELEGATE_EXPORT void tflite_plugin_destroy_delegate(
    TfLiteDelegate* delegate) {
    TfLiteCoreMlDelegateDelete(delegate);
}

}  // extern "C"
