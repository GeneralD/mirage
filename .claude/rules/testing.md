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
- `FakeGPUGateway.complete(_ submission, with: GPUCompletion)` — every
  `encodeAndCommit` is a pending `Submission`; completion timing, order and
  outcome are the test's, raw error codes are synthesized, never provoked. A
  double completion is a reported issue. `FakeShaderLibraryGateway` compiles
  every source to a fresh `FakeLibraryHandle` unless `failCompile(of:with:)`
  scripted diagnostics, and **reports an issue when called on the main
  thread**. `FakeTextureCacheGateway` counts: `isBalanced` is
  `bindCount == unbindCount` with no double unbind. Foreign handles are refused
  with the live errors in the live order; a double unbind is **fake-only** — the
  live gateway is stateless and cannot see it — so the fake throws
  `GPUError.foreignHandle` and counts it in `doubleUnbindCount`, and the
  DataSource's exactly-once unbind is proven against the fake.
- `FakeEffectRuntimeRepository` — `prepare` / `apply` suspend until
  `completePrepare(_:with:)` / `completeApply(_:with:)`, each exactly once,
  in any order (a slow compile overtaken, a late GPU completion); a cancelled
  caller resumes with `.failure(.internalError)`, and one cancelled before it
  suspended is never recorded. Start concurrent callers one at a time
  (`waitForCount(n)` between them) when the test depends on request order.
  `FakeGPURenderer` — one layer down, for the Repository suites: `render`
  suspends until `complete(_:with:)` (any order, exactly once) unless
  `respond(with:)` scripted an immediate answer; `requests` is a `Collector` in
  call (`id`) order. Unlike `FakeEffectRuntimeRepository` it follows its live
  counterpart on cancellation: `GPURenderDataSource` cannot withdraw a committed
  pass, so a cancelled caller — even one cancelled before the call — is
  recorded and keeps waiting; complete every request a test cancels.
  The `GPURenderDataSource` suite itself drives the executor hop with
  `tickUntil(tick: { executor.drain() }, …)` and completes passes through
  `FakeGPUGateway`. `InMemoryPreviewSink` —
  `present` holds the completion until `complete(_:)`, in any order, and
  records `attached` targets. Requests are `Collector`s, so a test awaits
  `applyRequests.waitForCount(n)` instead of polling.
- `InMemoryFrameTransport` — the in-process Mach kernel behind the host↔extension
  loopback (`Tests/FramePathIntegrationTests/LoopbackRig.swift` keeps
  **separate surface pools on each side**). Hooks: a bootstrap table (look-up
  fails until check-in and after the service port is destroyed;
  `failNextLookUps(_:code:)`), a per-port queue cap (default 5, then
  `.queueFull`), destroyed receive rights (`.destinationLost` on send,
  `.portDied` on a pending receive), presence ports (destroying one delivers
  `.deadName` to the registered notify port) and `killHost()` (the kill -9
  model). A test that passes a `SurfaceToken` straight across is wrong.
- `FakeStreamOutput.connectClient()` / `disconnectClient()` — client count and
  `.streamStarted` / `.streamStopped`; `GatedClock` — a hand-stepped clock whose
  `sleepers` collector fires once a sleep is registered, so a test advances time
  only when the subject is parked (reconnect backoff proof); its sleeps honour
  task cancellation like `ContinuousClock`. `RecordingWorkRunner` — the
  `WorkRunner` double: starts each work item as a real `Task` at once and
  records `started` / `finished` / `cancelled`, so a test awaits
  `work.finished.waitForCount(n)` instead of polling.

## Property tests

`forAll(seeds:)` runs over `standardSeeds` (0..<32); `Seeds.range(0..<N)` names
a wider set for `@Test(arguments:)`, where the seed is in the test name and
failures reproduce by seed. Nightly widens `N`.
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
