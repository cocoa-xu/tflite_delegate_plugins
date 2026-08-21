# tflite-delegate-plugins

Prebuilt TensorFlow Lite delegate plugins — shared libraries exporting the
`tflite_plugin_create_delegate` / `tflite_plugin_destroy_delegate` ABI, loadable
by anything that speaks TFLite's external-delegate protocol.

Built for [tflite_beam](https://github.com/cocoa-xu/tflite_beam) and
[tflite_elixir](https://github.com/cocoa-xu/tflite_elixir), but nothing here is
BEAM-specific: the same `.so` works with `benchmark_model
--external_delegate_path=`, the Python `load_delegate`, or a C++ host.

## What is built

| plugin | backend | platforms |
|---|---|---|
| `libtensorflowlite_gpu_delegate-v<VER>` | OpenCL | macOS, Linux |
| `libtensorflowlite_metal_delegate-v<VER>` | Metal | macOS only |

## Version locking is not optional

Open-source TFLite provides **no binary-stable delegate interface**. Upstream's
own words: a dynamically loaded delegate *"must have been built against the same
version (and commit) that the TF Lite runtime itself has been built at"*.

That is why the TFLite version is in every filename. A plugin marked `v2.21.0`
is for a host built against TFLite 2.21.0 and nothing else — check before you
load it.

There is a gap here worth knowing about: **tflite_beam does not currently expose
the TFLite version it was built against**, so the match has to be made against
its release notes rather than queried at runtime. Loading a mismatched plugin is
undefined behaviour, not a clean error.

## Using one

```erlang
{ok, Delegate} = tflite_beam_delegate:external(
    "/path/to/libtensorflowlite_metal_delegate-v2.21.0.dylib"),
ok = tflite_beam_interpreter_builder:add_delegate(Builder, Delegate),
ok = tflite_beam_interpreter_builder:build(Builder, Interpreter).
```

Options are passed as a map and forwarded to the plugin:

```erlang
tflite_beam_delegate:external(Path, #{allow_precision_loss => true,
                                      wait_type => passive}).
```

| plugin | options |
|---|---|
| OpenCL | whatever `TfLiteGpuDelegateOptionsV2` parses |
| Metal | `allow_precision_loss`, `enable_quantization`, `wait_type` (`passive`/`active`/`do_not_wait`/`aggressive`) |

## What to expect from it

Measured on an M4 Max, `mobilenet_v2_1.0_224_inat_bird_quant`, 30 inferences
after 5 warmups, against a real image fixture:

| | ms | vs XNNPACK | top-5 |
|---|---|---|---|
| XNNPACK (CPU) | 7.39 | 1.00x | `[923,837,245,409,293]` |
| OpenCL | 1.30 | 5.70x | `[923,837,245,409,293]` |
| Metal | 0.84 | **8.79x** | `[923,837,245,409,293]` |

All three agree on the top-5 classes and their order. Against the CPU run,
OpenCL differs in 5 of 965 output bytes (at most 7/255) and Metal in 3 (at most
2/255) — the ordinary signature of a quantised model executed in float on a GPU.

Speedups are not a promise. They depend on the model, the GPU, and how much of
the graph the delegate can claim; a model the delegate cannot partition will be
*slower* than the CPU path. Measure yours.

## Requirements at runtime

Neither plugin links its GPU API — OpenCL is `dlopen`ed and Metal comes from the
system framework — so both load on machines that have neither, and fail when the
delegate is applied rather than when the library is opened.

**Linux/OpenCL** needs an ICD *and* the unversioned `libOpenCL.so`. Distros
often ship only `libOpenCL.so.1`; install `ocl-icd-opencl-dev` (Debian/Ubuntu)
for the symlink.

**A Raspberry Pi 5 cannot use the OpenCL plugin today.** Debian's
`mesa-opencl-icd` enumerates zero devices there — `gallium-pipe/` ships no
`pipe_v3d.so` — and reaching VideoCore VII's OpenCL means building Mesa with
rusticl, which upstream does not yet call production-ready. The plugin loads and
fails cleanly:

```
INFO: Loaded OpenCL library with dlopen.
ERROR: No GPU detected.
ERROR: Restored original execution plan after delegate application failure.
```

The interpreter keeps its original graph and the caller gets an error. There is
no GL fallback: CMake builds define `-DCL_DELEGATE_NO_GL`.

## Building

```console
$ cmake -S . -B build -D CMAKE_BUILD_TYPE=Release
$ cmake --build build -j
$ ./scripts/verify_plugin.sh build/libtensorflowlite_metal_delegate-v2.21.0.dylib
```

The TensorFlow sources are downloaded to match `TFLITE_VER` (default 2.21.0).
Point `-D TENSORFLOW_SOURCE_DIR=<path>` at an existing tree to skip that.

Building for another architecture is best done natively — CI uses GitHub's
arm64 runners, and an arm64 Linux container on an Apple Silicon host does the
same job in about two minutes, against hours on the board itself.

A cross build works too, but TFLite needs a **host** `flatc` for it and aborts
without one:

```console
$ cmake -S . -B build \
    -D CMAKE_TOOLCHAIN_FILE=cmake/aarch64-linux-gnu.cmake \
    -D TFLITE_HOST_TOOLS_DIR=<dir containing a host flatc>
```

That `flatc` must match the flatbuffers version TensorFlow bundles (v25.9.23 for
TFLite 2.21.0), which is why building natively is the shorter path.

## Two upstream defects this build works around

Neither is ours, and both exist because no upstream CMake target builds a shared
object out of the GPU sources:

- **`GPU=ON` is missing its abseil-log link dependency.** The GPU sources use
  `absl::log_internal::LogMessage`, but the `tensorflow-lite` target links none
  of it. A static archive never resolves symbols, so it only breaks when
  something links a `.so`. `TFLITE_PLUGIN_ABSL_DEPS` in `CMakeLists.txt` supplies
  the missing targets.
- **The Metal flatc command declares no dependency on flatc.** The
  `add_custom_command` generating `inference_context_generated.h`
  (`tensorflow/lite/CMakeLists.txt:453` in 2.21.0) has no `DEPENDS`, unlike the
  XNNPACK schema command thirty lines below it, so parallel builds race and fail
  with `flatc: No such file or directory`. We add the edge back.

## License

Apache-2.0, matching TensorFlow. `src/metal_plugin_adaptor.mm` is shaped after
`tensorflow/lite/delegates/utils/dummy_delegate/external_delegate_adaptor.cc`.
