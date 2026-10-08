---
paths:
  - "Tests/GPUSmokeTests/**"
  - "Sources/MetalGateway/**"
  - "Sources/MetalKitPreviewGateway/**"
---

# GPU Tests — Separate Process, Local by Default

Everything that *decides* (pass-through, auto-disable, budget, in-flight cap,
newest-wins compile) is tested against `FakeGPUGateway` and never needs a GPU.
Only two things touch a real `MTLDevice`:

1. `MetalGateway` smoke — `makeLibrary(source:)` of the prelude + one effect,
   one compute pass, output compared with the Swift reference implementation
   under a single fixed tolerance (`fastMathEnabled = false` is part of the
   compile options the port takes).
2. Hash-noise parity — GPU vs Swift reference, same tolerance.

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
- Whether GitHub-hosted macOS runners expose a Metal device is unknown; the
  M0 spike adds a probe job that only prints the device name. Until that is
  green, `make test-gpu` is a local-only target.
