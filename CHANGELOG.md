# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[semantic versioning](https://semver.org/).

Note that the TensorFlow Lite version a release was built against is
independent of this project's version, and is named in the release notes rather
than in any filename. Upstream provides no binary-stable delegate interface, so
a plugin is only valid for a host built from the same TFLite release.

## [Unreleased]

### Added

- OpenCL GPU delegate plugin for macOS and Linux, on x86_64 and aarch64.
- Metal delegate plugin for macOS. TFLite's Metal delegate exports no plugin
  ABI, so `plugins/metal/plugin_adaptor.mm` supplies one; it must be
  Objective-C++ because `metal_delegate.h` imports `Metal/Metal.h`.
- Core ML delegate plugin for macOS, **off by default**. It builds, loads and
  computes correctly, but upstream's delegate accepts only operator version 1
  and only float32, so it delegates no nodes from any current model. The build
  generates 33 coremltools protobuf definitions and compiles the 19 delegate
  sources that upstream provides no CMake target for, and patches
  `IsNeuralEngineAvailable()` so Apple silicon is recognised. See
  [`docs/coreml.md`](docs/coreml.md).
- `scripts/verify_plugin.sh`, run in CI on every target: fails the build unless
  exactly the two plugin entry points are exported and nothing but system
  libraries is linked.
- `test/load_plugin.c`, which opens a plugin the way TFLite's loader does and
  exercises both entry points, including the case where no device is present.
  With `--reject-unknown-options` it also asserts that an adaptor we wrote
  refuses an option it does not know.

- [`docs/arm-sbc.md`](docs/arm-sbc.md): measurements on two ARM boards. The
  OpenCL plugin needs nothing board-specific to reach **2.25x** on an RK3588's
  Mali-G610, with
  output matching the CPU, given a panthor kernel and `RUSTICL_ENABLE=panthor`.
  A Raspberry Pi 5 has no OpenCL device available today, for packaging reasons
  documented there. Also records why the RK3588's NPU is not usable through
  TFLite yet.

### Fixed

TFLite's OpenCL delegate tested every option key with a bare `strcmp` and so
acted on the mismatches instead of the matches, which meant an invented key was
accepted and a real one landed in the next field along. Options passed to the
plugin now do what they say. The correction is applied to a copy of upstream's
source at configure time, alongside a second one that lets Core ML's Neural
Engine check see Apple silicon; both live in `cmake/UpstreamPatches.cmake`.

`cmake/UpstreamFixups.cmake` holds the rest of what this build has to smooth
over, each explained at the point it is applied. One of them is not a defect but
a version window: 2.21.0 was tagged five months before the change that gives
`tensorflow-lite` its absl logging dependency, so a shared library linked
against it needs that spelled out. It goes away when TFLITE_VER does.
