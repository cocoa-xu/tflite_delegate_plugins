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
%% Metal
tflite_beam_delegate:external(MetalPath, #{allow_precision_loss => true,
                                           wait_type => passive}).
%% OpenCL
tflite_beam_delegate:external(OpenCLPath, #{is_precision_loss_allowed => true}).
```

| plugin | options |
|---|---|
| Metal | `allow_precision_loss`, `enable_quantization`, `wait_type` (`passive` / `active` / `do_not_wait` / `aggressive`) |
| OpenCL | **do not pass any** — see below |

**The OpenCL plugin's option parsing is broken upstream.** Every branch of
`ParseOptions` (`delegates/gpu/delegate.cc`) is written

```c
if (strcmp(options_keys[i], "is_precision_loss_allowed")) {
```

and `strcmp` returns **0** on a match, so each test fires on *mismatch*. Every
value lands in the wrong field, silently. Measured against the built plugin:

| passed | result |
|---|---|
| `is_precision_loss_allowed` = `1` | accepted — and stored as `inference_preference` |
| `is_precision_loss_allowed` = `not_a_number` | refused |
| `definitely_not_an_option` = `1` | **accepted** — stored as `is_precision_loss_allowed` |
| `definitely_not_an_option` = `not_a_number` | refused |

An invented option name is accepted; a real one is applied to the next field
along. Until upstream fixes it, create the OpenCL delegate with no options at
all — the defaults are what you want anyway. The Metal adaptor is ours, parses
its three keys correctly, and refuses an unknown key instead of guessing.

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

## Layout

```
plugins/<name>/     one directory per plugin: its adaptor and its CMakeLists
cmake/              TFLiteSource, UpstreamFixups, PluginTarget, toolchains/
linker/             export lists -- .lds for Apple, version script elsewhere
third_party/        vendored sources, with their licences
test/               load_plugin.c, run against every built plugin in CI
scripts/            verify_plugin.sh, the CI gate on the export surface
docs/               upstream-defects.md
```

Adding a plugin is adding a directory under `plugins/` and one line in
`plugins/CMakeLists.txt`.

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
    -D CMAKE_TOOLCHAIN_FILE=cmake/toolchains/aarch64-linux-gnu.cmake \
    -D TFLITE_HOST_TOOLS_DIR=<dir containing a host flatc>
```

That `flatc` must match the flatbuffers version TensorFlow bundles (v25.9.23 for
TFLite 2.21.0), which is why building natively is the shorter path.

## Upstream defects

Building a shared object out of TFLite's delegate sources with CMake is a
combination nothing upstream exercises, and it turns up defects. Four so far,
including one that produces no error at all and silently misapplies every option
you pass the OpenCL plugin.

They are catalogued with symptoms, causes and workarounds in
[`docs/upstream-defects.md`](docs/upstream-defects.md). Read the third one before
passing options to anything.

## License

Apache-2.0, matching TensorFlow. `plugins/metal/plugin_adaptor.mm` is shaped after
`tensorflow/lite/delegates/utils/dummy_delegate/external_delegate_adaptor.cc`.
