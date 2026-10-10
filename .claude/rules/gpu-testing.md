---
paths:
  - "Tests/GPUSmokeTests/**"
  - "Sources/MetalGateway/**"
  - "Sources/MetalKitPreviewGateway/**"
---

# GPU Tests — Separate Process, CI-Capable

Everything that *decides* (pass-through, auto-disable, budget, in-flight cap,
newest-wins compile, the preview's latest-wins and exactly-once completion) is
tested against `FakeGPUGateway` / `FakePreviewGateway` and never needs a GPU.
Only four things touch a real `MTLDevice`:

1. `MetalDeviceSmokeTests` — the issue #4 runner probe kept as a test: a
   device exists, it is in the `mac2` family, and a kernel compiled from
   source fills a buffer correctly. It predates `MetalGateway` (MVP-A) so the
   CI job exists before the gateway does; `MetalDeviceProbe` next to it is
   the one place the suites ask whether a device exists.
2. `MetalGatewaySmokeTests` — the three ports against the real device:
   `compile` of kernels assembled with the engine prelude exactly as an effect
   is (`ShaderSourceAssembly`: prelude, `#line 1 "effect"`, author source),
   `bind` of a real IOSurface (`.shared`, `bgra8Unorm`), one
   `encodeAndCommit`, the pixels read back
   through the IOSurface and compared with a Swift reference under a single
   fixed tolerance of one 8-bit step, plus exact checks at the corners so a
   dropped `- 1`, a swapped axis or an unread uniform cannot hide inside the
   tolerance. Also: a syntax error and a missing entry point come back as
   `ShaderDiagnostics`, two commits on one context each write their own
   surface, a surface rebinds after `unbind`, a 6-pixel-wide surface (rows
   padded by `IOSurfaceGateway.create`'s alignment; unaligned rows abort the
   process inside Metal) binds, fills and unbinds, and foreign handles are
   refused. `#line` is proven here: a syntax error on the author's third line
   comes back as `effect:3:`; and `ShaderCompilationDataSource` over the live
   gateway keeps author lines, rewrites a prelude note to `prelude:<line>:` and
   returns a handle that dispatches on another context of the device.
   `ShaderCompileOptions.precise` (→ `fastMathEnabled = false`) is the default.
3. `HashNoiseParityTests` (suite `hash-noise parity`) — the prelude's `hash` /
   `noise` on a 256 × 256 image against `HashNoiseReference` (Tests/TestSupport),
   for seed 0 and another seed: every pixel within the same single tolerance
   (`GPUSmokeSupport.tolerance`, one 8-bit step, shared by every GPU suite), plus
   the hash's 24 bits compared bit for bit (one byte per channel, stored as
   `k / 255`, which the unorm store returns exactly).
4. `PreviewSmokeTests` — the preview kernel's pixels, run as an ordinary
   compute pass between two IOSurfaces so they can be read back: letterbox and
   pillarbox, each scaled ×2 and ×½, against a Swift reference of the
   aspect-fit bilinear blit (within `GPUSmokeSupport.tolerance`; the inputs
   vary per texel, so a missing scale or a nearest filter is caught), and an exact same-size copy
   that catches a flip, a swapped axis or a half-texel shift; `MetalKitPreviewGateway.prepare` readying an
   off-screen `MTKView` and `draw` completing once into its layer's drawable.
   The view is created at a non-zero size and every draw asserts the layer's
   drawable size afterwards: a zero-sized view gets no drawable, and its empty
   command buffer completes just as cleanly, so the size is the proof that the
   pass was encoded. The drawable's pixels belong to the compositor and are not
   read back; the frame surface is, to prove the draw only read it;
   a paused view resized between two draws getting a drawable of its new size;
   `PreviewDataSource` over the live gateways end to end; foreign handles
   refused.

`CommandBufferErrorCodeTests` sits in the same target without touching a
device: it pins `GPUCompletionMapping`'s domain string and code numbers to the
SDK's `MTLCommandBufferErrorDomain` / `MTLCommandBufferError.Code`, wrapped as
`MetalGateway` wraps them, because this is the only target that links Metal.

## Rules

- These suites live in `Tests/GPUSmokeTests`, are `.serialized`, and are gated
  with `.enabled(if: MetalDeviceProbe.isAvailable)` so a machine without a
  device skips instead of failing.
- They run only through `make test-gpu`, which executes
  `swift test --filter GPUSmokeTests` in its **own process** after the main
  run (`--skip GPUSmokeTests`), the way lyra isolates its CoreAudio HAL suite.
- `MetalGateway` and `MetalKitPreviewGateway` are coverage-ignored
  **unconditionally**; GPU suites never feed codecov.
- Never write a test that provokes a real `timeout` / `pageFault` /
  `accessRevoked`: a repeated hang can revoke the test process's Metal access.
  Those scenarios are a manual VM lane (`.claude/rules/dev-verification.md`).
- The compile cache key is `(source hash, compile options, device id, OS
  version)`; a GPU test that depends on cache state resets it first.
- **GitHub-hosted macOS runners do expose a Metal device** (measured
  2026-10-09, issue #4, on both `macos-latest` = macOS 26.6.2 / Xcode 26.6 and
  `macos-15` = macOS 15.7.9 / Xcode 16.4; hardware `VirtualMac2,1`, "Apple M2
  Pro (Virtual)"): `MTLCreateSystemDefaultDevice()` returns one **"Apple
  Paravirtual device"**, `makeLibrary(source:)` compiles, and a compute pass
  returns correct results. It is a VM's paravirtual GPU, not Apple silicon
  as seen by an app: `supportsFamily(.apple7) == false`, `.mac2 == true`
  (those two families are all the probe asked; the kernel it ran was a plain
  buffer fill). So `make test-gpu` **runs in CI** as the `test-gpu` job of
  `.github/workflows/test.yml` (#9): `macos-latest`, its own process, 15-minute
  outer bound, and it **fails if the suites skip** — a skip means the runner
  lost its device, which must surface rather than pass as an empty run. GPU
  smoke tests are written against the `mac2` family only: anything gated on
  an Apple family (SIMD-group functions, Apple-family texture formats, …) is
  treated as unavailable until a probe shows otherwise.
