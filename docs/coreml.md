# The Core ML plugin, and why it is off by default

It builds. It loads. It produces correct results. It delegates **zero nodes**
from any model anyone is likely to run, and is therefore no faster than the CPU.

This document exists because that conclusion took a day to reach, and the next
person to wonder "what about Core ML?" should not have to spend another one.

## What was measured

M4 Max, macOS 24.6.0, TFLite 2.21.0, through
`tflite_beam_delegate:external/1`.

| model | nodes delegated | vs XNNPACK |
|---|---|---|
| `add.bin` (2 ops, float32) | **2 / 2** | — |
| `multi_add.bin` (3 ops, float32) | **3 / 3** | — |
| `mobilenet_v2_1.0_224_inat_bird_quant` | **0 / 65** | 1.03x |
| `lite-model_efficientdet_lite4` (float32) | **0 / 483** | 0.45x |

The first two rows matter: they rule out "Core ML does not work on macOS", which
is what the upstream README implies and what we assumed for several hours. It
works perfectly. The delegate simply supports almost nothing.

Top-5 output was identical to the CPU run wherever it delegated anything, so
correctness is not in question.

## Why zero nodes

`delegates/coreml/coreml_delegate.mm:IsNodeSupportedByDelegate` rejects a node
before looking at what it is:

```objc
if (registration->version > 1) {
    switch (registration->builtin_code) {
      case kTfLiteBuiltinDepthwiseConv2d: if (version > 2) return false; break;
      case kTfLiteBuiltinFullyConnected:  if (version > 6) return false; break;
      default: return false;
    }
}
if (GetInput(context, node, input_tensor_index)->type != kTfLiteFloat32) {
    return false;
}
```

**Only operator version 1**, with two exceptions, and **float32 only**. TFLite
operators have been shipping at version 2 and above since around 2019, so a
current model has essentially no version-1 nodes left. `add.bin` delegates fully
because its operators are still version 1.

Three independent details date this delegate to the same period:

- the operator-version ceiling above;
- `IsNeuralEngineAvailable()`, which recognises devices up to `iPhone11,x` and
  `iPad8,x` — hardware from 2018-2019;
- the float32-only restriction, which excludes every quantised model.

It is not experimental in the sense of being early. It has been left alone.

## The one thing worth patching, and the one thing not

`cmake/`'s build patches `IsNeuralEngineAvailable()` so that Apple silicon Macs
are recognised. Upstream identifies the Neural Engine by matching
`uname().machine` against `"iPad"` and `"iPhone"` prefixes and returns false for
everything else — including every Mac, all of which report `arm64` and, since
M1, all of which have a Neural Engine. Without the patch the delegate's own
default option, `DevicesWithNeuralEngine`, can never produce a delegate on
macOS at all.

That patch is safe: `IsNeuralEngineAvailable()` has exactly one caller and
decides only whether `Create` refuses. It takes no part in any computation, and
the build fails loudly if the code it matches ever changes upstream.

**The operator-version check is deliberately not patched.** Relaxing it would
make more nodes eligible, and each one would then be executed by a builder
written for version 1 semantics against an operator that has since changed its
parameters. That trades a delegate that does nothing for one that silently
computes the wrong answer. Individual operators could be re-validated and
allowed through one at a time; a blanket relaxation could not.

## Why it is still here

The build is worth more than the result. `plugins/coreml/CMakeLists.txt`
generates 33 coremltools protobuf definitions with TFLite's own protoc, compiles
22 Objective-C++ sources that have no CMake target upstream at all, and patches
one of them in the build tree without touching the fetched sources. If Core ML
ever moves, or if an iOS target is added, none of that has to be worked out
again.

Turn it on with `-D TFLITE_PLUGINS_COREML=ON` if you want to measure it
yourself. On macOS today, use the Metal plugin: same hardware, 9x.
