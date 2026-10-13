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
  in any order (a slow compile overtaken, a late GPU completion). Like the live
  runtime it ignores the caller's cancellation: a cancelled call is still
  recorded and waits for its completion, so a test that stops the pipeline
  mid-pass completes the pending request itself (`pendingCount`). Requests,
  submissions, presentations and draws carry the instance that issued them: ids
  restart at 1 per fake, so one from another instance returns `false` (a
  reported issue for the two gateways, `FakeGPUGateway` and
  `FakePreviewGateway`) and never resumes anything. Start
  concurrent callers one at a time (`waitForCount(n)` between them) when the
  test depends on request order.
  `FakeGPURenderer` — one layer down, for the Repository suites: `render`
  suspends until `complete(_:with:)` (any order, exactly once) unless
  `respond(with:)` scripted an immediate answer; `requests` is a `Collector` in
  call (`id`) order. Its requests carry their issuing instance the same way, so
  `complete` returns `false` for another `FakeGPURenderer`'s request and leaves
  every pending render untouched. Like `FakeEffectRuntimeRepository` it ignores
  cancellation, as its live counterpart does: `GPURenderDataSource` cannot
  withdraw a committed pass, so a cancelled caller — even one cancelled before
  the call — is recorded and keeps waiting; complete every request a test
  cancels.
  The `GPURenderDataSource` suite itself drives the executor hop in two
  phases: it awaits `RecordingFrameExecutor.enqueued` (the render has queued its
  hop), asserts that no context, binding or command buffer exists and no answer
  arrived, then `drain()`s; passes complete through `FakeGPUGateway`. Removing
  the hop turns that suite red. `RecordingFrameExecutor` lives in
  `Tests/TestDoubles`. The `EffectRuntimeStateDataSource` suite drives the
  runtime's state through its port with it (`StateFixture.answer` drains until
  the call answers) and proves tickets, the cache, newest wins, waiting and the
  GPU-context retry by settling compiles in either order; the
  `EffectRuntimeRepository` suite runs the real state on the same executor with
  `FakeShaderCompiler` and `FakeGPURenderer`, and gives the Repository no
  executor of its own, so one that reached for it would meet the unimplemented
  default. A negative check ("the apply is still waiting") is a bounded
  `tickUntil(...) == false` (`stillWaiting`), never a count read right after one
  `drain()`: an answer on its way to the call's task is invisible to that. A
  compile an `apply` starts itself runs on a `RecordingWorkRunner`, and the
  `apply` answers when the selection settles, which is before that compile's own
  task has logged: the Repository suite waits for it with `compilesFinished(n)`
  (draining the executor) before it reads the log, and leaves a compile held
  to prove that an `apply` does not wait for it. `InMemoryPreviewSink` —
  `present` holds the completion until `complete(_:)`, in any order, and
  records `attached` targets. Requests are `Collector`s, so a test awaits
  `applyRequests.waitForCount(n)` instead of polling.
- The pipeline's in-flight cap is driven by **manual completion**: the fake
  runtime never answers on its own — nor, like the live one, on cancellation —
  so a tick only starts a pass and the test decides when (and how) it ends. In
  `Tests/FramePipelineUseCaseTests/Rig.swift`, `applyRequest(n)` awaits the n-th
  `apply` (failing the test, not crashing it, when that never comes),
  `answer(_:with:)` completes it and drains until the pipeline has taken the
  answer, `answerAbandoned(_:with:)` does the same for a pass `stop()` abandoned
  (it drains until both leases are back), and `completeEffect(with:)` answers
  the next pass in order (pass-through by default). A test that wants a tick to
  meet a running pass simply ticks before answering; one that wants an answer
  queued on the executor ahead of `stop()`'s cleanup answers, stops, then
  drains, with a sink whose teardown has not landed yet (`QueuedTeardownSink`).
  A `stop()` that lands inside a tick, after the pass's work has started but
  before the tick has recorded the pass, is staged with `Rig(runner:)` and a
  runner whose `run` calls it before returning (`InterruptingWorkRunner`).
  `FakeEffectRuntimeRepository.pendingCount` shows that no `apply` was left
  waiting. `LoopbackRig.capture` answers the pass it
  started (pass-through by default, `effect:` to choose) and drains its result,
  so integration tests stay one frame per call.
- `FakePreviewGateway` — what `PreviewDataSource` is proven against: `prepare`
  answers a `FakePreviewLayerHandle`, `draw` records a pending `Draw` until
  `complete(_:with:)`, exactly once, in any order. Its draws carry their issuing
  instance the same way, so `complete` returns `false` for another
  `FakePreviewGateway`'s draw and leaves every pending draw untouched.
  `failPrepare(with:)` / `failDraw(with:)` make **every** later `prepare` /
  `draw` throw (`draw` before commit) until `fail…(with: nil)` clears it, like
  the other fakes' `fail…` hooks. Foreign handles are refused in the live order
  (`prepare`: target, then context; `draw`: context, kernel, texture, layer).
- `FakeShaderCompiler` — the `ShaderCompiler` (`ShaderCompilationDataSource`)
  double: every `compile` suspends until `complete(_:with:)` (any handle or
  diagnostics) or `succeed(_:)` (a fresh `FakeLibraryHandle` of the request's
  source), exactly once and in any order, so a slow compile overtaken by a newer
  one is a sequence the test writes. Like `FakeEffectRuntimeRepository` it
  ignores cancellation, as the live DataSource does: a cancelled caller waits
  for the test's completion and gets that result (the stale success after a
  newer compile can be written down), so a test completes every request it
  starts — one left pending surfaces through the time limit. Its requests carry
  their issuing instance the same way, so `complete` returns `false` and
  `succeed` `nil` for another `FakeShaderCompiler`'s request, leaving every
  pending compile untouched. `HashNoiseReference`
  (Tests/TestSupport) is the Swift twin of the prelude's `hash` / `noise`, for
  the parity GPU suite and the Swift-only property tests.
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
