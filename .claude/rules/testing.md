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
  records `attached` targets; with `holding: .onceAttached` it models a
  preview nobody has opened: until a target is attached every frame is
  recorded and completes inside `present`. That is stricter than live, where
  `PreviewDataSource` queues the frame on the executor and gives it back in
  that job, after `present` has returned (`PreviewDataSourceTests` pins it;
  the pipeline hops the completion onto its executor either way).
  Requests are `Collector`s, so a test awaits
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
  so integration tests stay one frame per call. Both rigs present on an
  `InMemoryPreviewSink(holding: .onceAttached)`, so a test that never attaches
  sees each frame's lease end with the drain that sent it. A pipeline test that
  wants the preview late calls `Rig.attachPreview()`, finds what was shown with
  `presentation(n)` and ends it with `completePresentation(_:)` (complete, then
  drain). `LoopbackRig(preview: .rendered)` puts the real `PreviewRepository` /
  `PreviewDataSource` on the host side instead, over the fake GPU layer
  (`gpu`, `shaders`, `textures`, `previewGateway` on `HostSide`); until it is
  attached it gives each frame back in a later executor job, as live, and its
  `attachPreview()` drains the attach's executor half off the main thread,
  where the kernel compile must run. `LoopbackRig(effects: .real)` puts the real
  effect runtime on the host side the same way (`EffectRuntimeRepositoryImpl`
  over `EffectRuntimeStateDataSourceImpl`, `ShaderCompilationDataSourceImpl`,
  `GPURenderDataSourceImpl` and `BundledEffectDataSourceImpl`, over the same fake
  GPU layer). A test then uses `captureThroughRuntime(_:at:completing:)` instead
  of `capture`: it ticks, drains until the pass has either answered without a
  GPU (a source that did not compile) or committed its command buffer, completes
  the pending `FakeGPUGateway` submission (`.finished` by default, `.failed(code:)`
  to script a failing command buffer), drains to the answer and then waits for
  every work-runner item to finish — the `apply` answers before the compile it
  started has logged, so the log is read only after that wait. Each of the two
  helpers refuses a rig of the other kind (`HostSide.effectsKind`), and
  `stopHostExpectingIdleGPU()` asserts that no pass or draw was left pending.
  A broken effect is scripted with `FakeShaderLibraryGateway.failCompile(of:with:)`,
  keyed by the exact assembled source (`ShaderSourceAssembly.assemble`).
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
  only when the subject is parked (the reconnect backoff proof, the watch's quiet
  period); its sleeps honour task cancellation like `ContinuousClock`, and its
  `cancelledSleepers` collector fires once a parked sleep was cancelled (and has left
  `parkedCount`), so a test waits for a cancellation instead of polling for it.
  `RecordingWorkRunner` — the
  `WorkRunner` double: starts each work item as a real `Task` at once and
  records `started` / `finished` / `cancelled`, so a test awaits
  `work.finished.waitForCount(n)` instead of polling.
- The effect-catalog fakes (epic #42) follow the same manual-completion rule and are
  under contract test in `Tests/TestDoublesTests`. `InMemoryFileSystemGateway` is a
  mutable tree: `write(_:_:)` / `remove(_:)` / `makeDirectory(_:)` change it between
  two reads, `failRead(of:with:)` / `failCreateDirectory(of:with:)` script an error per
  path, listings come back sorted, a missing path throws `CocoaError`, a hook that would
  make a path both a file and a directory (`write` over a directory, `write` or
  `makeDirectory` below a file) is reported and leaves the tree as it was, and
  `listings` / `reads` / `createdDirectories` are `Collector`s. `FakeFileWatchGateway.fire(path)`
  runs the `onChange` of every live watch on that path and returns how many ran;
  `isBalanced` is every watch stopped exactly once (`doubleStopCount` counts the
  second `stop()` of a handle). `EffectWatchDataSourceImpl` is written as
  `gateway.fire(path)`, then `await clock.sleepers.waitForCount(n)` on a `GatedClock`,
  then `clock.advance(by:)`: an `advance` straight after `fire` can run before the
  subject's sleep is registered and is lost. "No element yet" is read off the clock
  (`clock.parkedCount` still counts the sleep that could yield one), never off a
  window of ticks, and a property test writes the 200 ms out itself instead of
  reading `quietPeriod`. The fake never fires a stopped watch, so an event that
  arrives after a stream ended (a dispatch source cannot recall a handler that is
  already running) is delivered through a wrapper that keeps each `onChange`
  (`WatchRig.keeper.callbacks`), and "it started nothing" is read off the clock's
  `sleepers` after a second stream's burst, which is the sentinel.
  `FakeEffectWatch` and `FakeEffectPackageRepository` register a stream before `changes(of:)` / `catalog()`
  returns, so `fire(request:)` / `publish(_:)` right after the call cannot be lost, and
  their `terminations` collector fires when the consumer lets go. A test keeps such a
  stream alive with `withExtendedLifetime` (a dropped iterator cancels it).
  `FakeEffectPackageRepository.publish(_:)` yields an equal catalog again, as the live port
  does after an edit that changes no row. An unscripted `source(of:)` reports an issue and
  answers `.sourceMissing`; `holdSources()` parks every read until `completeSource(_:with:)`
  (any order, exactly once, the answer being what was scripted when the read began, requests
  tagged with their issuing instance like the other manual-completion fakes, `heldSources`
  and `pendingSourceCount` to see them), so "a select arrives while a listing waits for a
  source" is a sequence a test writes down;
  `FakeEffectCatalogUseCase.run()` parks on `suspendUntilCancelled` and counts
  `runCancellations`, and `runEvents` orders when each run began and returned. When
  cancelled it finishes the open `observe()` streams and leaves nothing current, once the
  run returns (the live use case does, so an Interactor that does not subscribe again at
  each start is caught); `holdCancelledRuns()` keeps a cancelled run in `run()` (ignoring
  the cancel, like the other manual-completion fakes; `heldRunCount` counts them) until
  `releaseCancelledRuns()`, which is how a subject that must wait for the run it ends
  is proven; `FakeEffectInteractor.publish(_:)` pushes into its `CurrentValueSubject`.

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
