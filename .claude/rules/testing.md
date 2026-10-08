---
paths:
  - "Tests/**/*.swift"
---

# Testing — Deterministic by Construction

Tests are the specification. Swift Testing only (`@Suite` / `@Test("display name")`).
Every suite that waits carries `.timeLimit(.minutes(1))`; CI adds
`timeout-minutes: 30` as the outer bound for anything a time limit cannot reach.

## Pick the wait by what you are waiting on (lyra's TestSupport, verbatim)

| You are waiting on… | Use | Never |
|---|---|---|
| State the subject publishes (`@Published`, a publishing spy) | `settle(_:until:)` | a deadline poll; `withMainSerialExecutor` |
| State a spy you own records off the main actor (gateway callback, Combine sink on a worker) | `Collector<Element>` + `waitForCount` / `waitFor` / `settle(until:)` | `NSLock` + timeout |
| State the test itself drives (`tick()`, `drain()`) | `tickUntil(_:tick:until:)`; assert the `Bool` | awaiting a publisher without ticking |
| Readable-only external state (a file a subprocess writes) | `pollUntil(timeout:interval:_:)` + `try #require` | — |
| Proving nothing happens | a `receiveCancel` spy, or a **sentinel** through the same pipeline | a fixed sleep |
| A double that must never answer / must hold a value back | `suspendUntilCancelled()`; a `Collector<Void>` gate | `Task.sleep` |

Fixed `Task.sleep` anywhere in a test is a review rejection.

## Frame-flow primitives (added here)

- `FakeCaptureSessionGateway.emit(frame)` — the test is the camera; it owns
  PTS and order.
- `ManualFrameExecutor.drain()` — runs queued frame-path work synchronously.
  Interleavings between capture, GPU completion, timer and UI are enumerated
  by the test, with seed-driven orderings for property tests.
- `ManualFrameScheduler.tick()` — one pipeline step.
- `FakeGPUGateway.complete(pass:, with: GPUCompletion)` — completion timing
  and outcome are the test's; raw error codes are synthesized, never provoked.
- `InMemoryFrameTransport` — host↔extension loopback with **separate surface
  pools on each side**, `FakeMachPortToken` hand-off, a queue cap and the real
  drop policy. A test that passes a `SurfaceToken` straight across is wrong.

## Property tests

`forAll(seed:)` expands to `@Test(arguments: Seeds.range(0..<N))`; the seed
is in the test name and failures reproduce by seed. Nightly widens `N`.
Generators live in `Tests/TestSupport/Generators/`. Targets are listed in
`docs/ARCHITECTURE.md` (Key Design Decisions → *Seeded property tests*).

## Rules

- Never `setenv`. Inject paths through `AppDirectoriesProvider` or constructors.
- Never `withMainSerialExecutor` / `uncheckedUseMainSerialExecutor`.
- Build the subject **inside** `withDependencies { } operation: { Impl() }`;
  building it in the `update` closure captures default values.
- `DispatchSemaphore.wait` and `Process.waitUntilExit()` after an `await` hang
  the cooperative pool; record the completion into a `Collector` instead.
- `receive(on: .main)` + deadline poll is non-deterministic; `settle` instead.
- A live Gateway smoke (real IOSurface, real file system under a UUID temp
  dir, `UserDefaults(suiteName: UUID)`, real `DispatchSource`) asserts `≥ 1`
  event, never "exactly one" — the OS coalesces.
- Test doubles shared across layers live in `Tests/TestDoubles`; nothing
  test-only lives under `Sources/`.
- GPU-touching suites follow `.claude/rules/gpu-testing.md`.
