// Plugin adaptor for TFLite's Metal delegate. The GPU (OpenCL) delegate ships
// tflite_plugin_create_delegate itself; the Metal one only exposes
// TFLGpuDelegateCreate, so the plugin ABI has to be provided here. Shaped after
// delegates/utils/dummy_delegate/external_delegate_adaptor.cc.
#include <cstddef>
#include <cstring>
#include <string>

#include "tensorflow/lite/core/c/common.h"
#include "tensorflow/lite/delegates/external/external_delegate_interface.h"
#include "tensorflow/lite/delegates/gpu/metal_delegate.h"

namespace {

bool ParseBool(const char* value, bool* out) {
    if (std::strcmp(value, "true") == 0 || std::strcmp(value, "1") == 0) {
        *out = true;
        return true;
    }
    if (std::strcmp(value, "false") == 0 || std::strcmp(value, "0") == 0) {
        *out = false;
        return true;
    }
    return false;
}

bool ParseWaitType(const char* value, TFLGpuDelegateWaitType* out) {
    if (std::strcmp(value, "passive") == 0) {
        *out = TFLGpuDelegateWaitTypePassive;
    } else if (std::strcmp(value, "active") == 0) {
        *out = TFLGpuDelegateWaitTypeActive;
    } else if (std::strcmp(value, "do_not_wait") == 0) {
        *out = TFLGpuDelegateWaitTypeDoNotWait;
    } else if (std::strcmp(value, "aggressive") == 0) {
        *out = TFLGpuDelegateWaitTypeAggressive;
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
    TFLGpuDelegateOptions options = TFLGpuDelegateOptionsDefault();

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
        if (std::strcmp(key, "allow_precision_loss") == 0) {
            ok = ParseBool(value, &options.allow_precision_loss);
        } else if (std::strcmp(key, "enable_quantization") == 0) {
            ok = ParseBool(value, &options.enable_quantization);
        } else if (std::strcmp(key, "wait_type") == 0) {
            ok = ParseWaitType(value, &options.wait_type);
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

    TfLiteDelegate* delegate = TFLGpuDelegateCreate(&options);
    if (delegate == nullptr) {
        Report(report_error, "TFLGpuDelegateCreate returned no delegate");
    }
    return delegate;
}

TFL_EXTERNAL_DELEGATE_EXPORT void tflite_plugin_destroy_delegate(
    TfLiteDelegate* delegate) {
    // The ABI says destroying a null delegate does nothing. TFLGpuDelegateDelete
    // reads delegate->data_ without checking, and create above returns null for
    // any option it will not take, so the pair is reachable.
    if (delegate == nullptr) return;
    TFLGpuDelegateDelete(delegate);
}

}  // extern "C"
