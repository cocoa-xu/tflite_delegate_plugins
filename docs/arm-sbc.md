# The OpenCL plugin on ARM single-board computers

Measured 2026-08-21 on two boards. The short version: **the plugin works and is
worth using on an RK3588 with a recent kernel, and cannot be used on a Raspberry
Pi 5 today**, for reasons that have nothing to do with the plugin itself.

## Raspberry Pi 5: no OpenCL to talk to

Stock Raspberry Pi OS (bookworm, kernel 6.6): no `libOpenCL`, no
`/etc/OpenCL/vendors`, no `clinfo`. Installing the distro's `mesa-opencl-icd`
(24.2.8) produces a platform and no devices:

```
Number of platforms   1
  Platform Name       Clover
Number of devices     0
```

`/usr/lib/aarch64-linux-gnu/gallium-pipe/` ships no `pipe_v3d.so`, so Clover has
no pipe driver for this GPU. The modern answer is rusticl, and **this Mesa build
does not contain it**. `libRusticlOpenCL.so` is absent from both the Raspberry
Pi and the Debian backports packages.

That is not an oversight. Building rusticl needs meson ≥ 1.1, LLVM ≥ 15, Rust ≥
1.78, bindgen, libclc, SPIRV-LLVM-Translator and SPIRV-Tools; bookworm ships
meson 1.0.1, LLVM 14 and Rust 1.63, and has no SPIRV-Tools development package
at all. Debian could not enable rusticl there even if it wanted to.

Everything else about the plugin works: `ocl-icd-opencl-dev` supplies the
unversioned `libOpenCL.so` that `opencl_wrapper.cc` dlopens, the plugin loads,
and applying the delegate fails cleanly rather than crashing:

```
INFO: Loaded OpenCL library with dlopen.
ERROR: No GPU detected.
ERROR: Restored original execution plan after delegate application failure.
```

The interpreter keeps its graph and the caller gets an error. Revisit when
Raspberry Pi OS moves to trixie, where the packaging problem disappears.

## FriendlyELEC CM3588 (RK3588, Mali-G610): 2.25x and correct

This one works, and nothing in the plugin is specific to the board. The
measurement below predates the option-parser patch and was taken against a
plugin built straight from upstream's source. **Three prerequisites, all of them
necessary:**

1. **A kernel with panthor**, not panfrost. Armbian's `vendor` 6.1.115 binds the
   GPU to panfrost and rusticl finds **zero** devices on it. `current`
   (6.18.45) binds panthor and rusticl finds the GPU. This is a kernel change,
   not a Mesa one.
2. **`RUSTICL_ENABLE=panthor` in the environment.** Rusticl enables no driver by
   default outside a short opt-in list (asahi, freedreno, radeonsi); without
   this variable there are no devices no matter what else is installed.
3. **`mesa-opencl-icd` and `ocl-icd-opencl-dev`.** The second supplies
   `libOpenCL.so`. Distros ship only `libOpenCL.so.1`, and TFLite dlopens the
   unversioned name.

With those in place:

```
RUSTICL_ENABLE=panthor clinfo
  Device Name        Mali-G610 (Panfrost)
  Device Type        GPU
  Max compute units  4
```

`mobilenet_v2_1.0_224_inat_bird_quant`, real `parrot.bin` input, 30 runs:

| | plan | nodes | ms | vs XNNPACK |
|---|---|---|---|---|
| XNNPACK (8x Cortex-A76) | 4 | 67 | 41.78 | 1.00x |
| **OpenCL plugin (Mali-G610)** | 1 | 66 | **18.55** | **2.25x** |

Correctness against the recorded expectation: **962 of 965 output bytes
identical**, three differ by at most 4/255, and the top-5 classes and their
order match the CPU run exactly. That is ordinary quantisation noise, the same
signature as on macOS.

## For contrast: the RK3588 NPU is not usable through TFLite today

The board also has a 6 TOPS NPU, reachable in principle through Mesa's Teflon
delegate, which exports our exact plugin ABI, so `external/1` loads it with no
code on our side. With kernel 6.18.45 the `rocket` driver comes up properly
(`/dev/accel/accel0`, all three NPU cores). But:

- a float32 model (`scale == 0`) is accepted and **segfaults the process**;
- a quantised model returns wrong results: 2.76x faster, top-5 entirely
  different, output distribution flattened (peak 176 → 32).

The rocket driver is reverse-engineered and this is a normal place for that to
be. A delegate that can segfault the host is not a recommendation regardless of
its speed. The GPU path above is the one to use on this board.
