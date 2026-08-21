# tflite_delegate_plugins

Prebuilt TensorFlow Lite delegate plugins: shared libraries exporting the
`tflite_plugin_create_delegate` / `tflite_plugin_destroy_delegate` ABI, loadable
by anything that speaks TFLite's external-delegate protocol.

Built for [tflite_beam](https://github.com/cocoa-xu/tflite_beam) and
[tflite_elixir](https://github.com/cocoa-xu/tflite_elixir), but nothing here is
BEAM-specific: the same `.so` works with `benchmark_model
--external_delegate_path=`, the Python `load_delegate`, or a C++ host.

## What is built

| plugin | backend | platforms | built by default |
|---|---|---|---|
| `libtflite_opencl_delegate` | OpenCL | macOS, Linux | yes |
| `libtflite_metal_delegate` | Metal | macOS | yes |
| `libtflite_coreml_delegate` | Core ML | macOS | **no** ([why](docs/coreml.md)) |

The Core ML plugin is complete and correct and delegates zero nodes from any
current model, because upstream's delegate accepts only operator version 1 and
only float32. On macOS use Metal: same hardware, 9x. The full measurement is in
[`docs/coreml.md`](docs/coreml.md).

## Version locking is not optional

Open-source TFLite provides **no binary-stable delegate interface**. Upstream's
own words: a dynamically loaded delegate *"must have been built against the same
version (and commit) that the TF Lite runtime itself has been built at"*.

The version a plugin was built against is the release it came from, and the
host can be asked directly:

```erlang
1> tflite_beam:tflite_version().
<<"2.21.0">>
```

Take the plugins from the release whose notes name that same version. A
mismatch is undefined behaviour rather than a clean error, so nothing will tell
you at load time that you got it wrong.

## Verifying a download

Every tarball on a release ships its own checksum file alongside it:

```console
$ sha256sum -c tflite_delegate_plugins-aarch64-linux-gnu.tar.gz.sha256
tflite_delegate_plugins-aarch64-linux-gnu.tar.gz: OK
```

Check it before loading. A plugin is `dlopen`ed into your process, so an
unverified one is a security problem rather than a hygiene one.

## Using one

```erlang
{ok, Delegate} = tflite_beam_delegate:external(
    "/path/to/libtflite_metal_delegate.dylib"),
ok = tflite_beam_interpreter_builder:add_delegate(Builder, Delegate),
ok = tflite_beam_interpreter_builder:build(Builder, Interpreter).
```

Options are passed as a map and forwarded to the plugin:

```erlang
tflite_beam_delegate:external(MetalPath, #{allow_precision_loss => true,
                                           wait_type => passive}).
```

### Metal

- `allow_precision_loss`: `true` or `false`
- `enable_quantization`: `true` or `false`
- `wait_type`: `passive`, `active`, `do_not_wait`, or `aggressive`

An unknown key is refused rather than ignored.

### Core ML

- `enabled_devices`: `neural_engine` or `all`
- `coreml_version`: `2` or `3`
- `max_delegated_partitions`: integer
- `min_nodes_per_partition`: integer

### OpenCL

- `is_precision_loss_allowed`: `0` or `1`
- `inference_preference`: integer
- `inference_priority1`, `inference_priority2`, `inference_priority3`: integer
- `experimental_flags`: integer
- `max_delegated_partitions`: integer
- `serialization_dir`: path
- `model_token`: string

**These work here and do not work upstream.** Every branch of `ParseOptions` in
`delegates/gpu/delegate.cc` is written

```c
if (strcmp(options_keys[i], "is_precision_loss_allowed")) {
```

and `strcmp` returns 0 on a match, so each test fires on *mismatch*: an invented
option name is accepted and stored in the first field, while a real one is
applied to the next field along. Silently, with no error anywhere. All nine
branches are written that way.

This build corrects them, so an invented name is refused and a real one reaches
the field it names. Measured against the plugin before and after the fix:

| passed | upstream | here |
|---|---|---|
| `is_precision_loss_allowed` = `1` | accepted, stored as `inference_preference` | accepted, stored correctly |
| `definitely_not_an_option` = `1` | **accepted** | **refused** |

The correction lives in `cmake/UpstreamPatches.cmake` and fails the build loudly
if upstream ever moves the code it matches.

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
2/255), the ordinary signature of a quantised model executed in float on a GPU.

Speedups are not a promise. They depend on the model, the GPU, and how much of
the graph the delegate can claim; a model the delegate cannot partition will be
*slower* than the CPU path. Measure yours.

## Requirements at runtime

The OpenCL plugin `dlopen`s its driver rather than linking it, so it loads on a
machine with no OpenCL at all and fails when the delegate is applied rather than
when the library is opened. Metal links `Metal.framework`, which is present on
every Mac, and fails the same way when there is no usable device.

**Linux/OpenCL** needs an ICD *and* the unversioned `libOpenCL.so`. Distros
often ship only `libOpenCL.so.1`; install `ocl-icd-opencl-dev` (Debian/Ubuntu)
for the symlink.

**On ARM single-board computers the answer varies by board**, and the deciding
factor is the kernel rather than anything about the plugin. Measured:

| board | result |
|---|---|
| FriendlyELEC CM3588 (RK3588, Mali-G610) | **2.25x**, output matching the CPU run |
| Raspberry Pi 5 (VideoCore VII) | no OpenCL device available today |

The CM3588 needs three things, all of them necessary: a kernel binding the GPU
to **panthor** rather than panfrost (Armbian `current` 6.18.45, not `vendor`
6.1.115), **`RUSTICL_ENABLE=panthor`** in the environment, and
`ocl-icd-opencl-dev` for the `libOpenCL.so` symlink. The Pi 5's Mesa has no
rusticl at all and its distro cannot build one. Full measurements, including
what the RK3588's NPU does through Mesa's Teflon delegate, are in
[`docs/arm-sbc.md`](docs/arm-sbc.md).

Where no device is available the plugin fails cleanly: the interpreter keeps
its original graph and the caller gets an error, rather than a crash.

## Layout

```
plugins/<name>/     one directory per plugin: a CMakeLists, and an adaptor
                    where upstream does not export the entry points itself
cmake/              TFLiteSource, UpstreamPatches, UpstreamFixups, PluginTarget,
                    toolchains/
linker/             export lists: .lds for Apple, version script elsewhere
third_party/        vendored sources, with their licences
test/               load_plugin.c, run against every built plugin in CI
scripts/            verify_plugin.sh, the CI gate on the export surface
docs/               arm-sbc.md, coreml.md
```

Adding a plugin is adding a directory under `plugins/` and one line in
`plugins/CMakeLists.txt`.

## Building

```console
$ cmake -S . -B build -D CMAKE_BUILD_TYPE=Release
$ cmake --build build -j
$ ./scripts/verify_plugin.sh build/lib/libtflite_metal_delegate.dylib
```

The TensorFlow sources are downloaded to match `TFLITE_VER` (default 2.21.0).
Point `-D TENSORFLOW_SOURCE_DIR=<path>` at an existing tree to skip that.

Building for another architecture is best done natively. CI uses GitHub's
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

## License

Apache-2.0, matching TensorFlow. `plugins/metal/plugin_adaptor.mm` is shaped after
`tensorflow/lite/delegates/utils/dummy_delegate/external_delegate_adaptor.cc`.
