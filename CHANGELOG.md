# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[semantic versioning](https://semver.org/).

Note that a plugin's *filename* carries the TensorFlow Lite version it was built
against, which is independent of this project's version. Upstream provides no
binary-stable delegate interface, so a plugin is only valid for a host built
from the same TFLite release.

## [Unreleased]

### Added

- OpenCL GPU delegate plugin for macOS and Linux, on x86_64 and aarch64.
- Metal delegate plugin for macOS. TFLite's Metal delegate exports no plugin
  ABI, so `plugins/metal/plugin_adaptor.mm` supplies one; it must be
  Objective-C++ because `metal_delegate.h` imports `Metal/Metal.h`.
- `scripts/verify_plugin.sh`, run in CI on every target: fails the build unless
  exactly the two plugin entry points are exported and nothing but system
  libraries is linked.
- `test/load_plugin.c`, which opens a plugin the way TFLite's loader does and
  exercises both entry points, including the case where no device is present.
  With `--reject-unknown-options` it also asserts that an adaptor we wrote
  refuses an option it does not know.

### Fixed

Four defects in TensorFlow Lite's own build and runtime, worked around here and
documented in [`docs/upstream-defects.md`](docs/upstream-defects.md).
