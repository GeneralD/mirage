# AGENTS.md

This file is the Codex entrypoint for this repository.

The long-form architecture and workflow docs live under `.claude/` and
`docs/`. Keep this file concise, and open the referenced files before making
the corresponding kinds of changes.

## Read Before Changing

- Architecture, dependency graph, module responsibilities, physical
  abstraction table, Key Design Decisions: `docs/ARCHITECTURE.md` (canonical;
  `.claude/CLAUDE.md` keeps a short summary + pointer)
- Guardrails for layering and import boundaries:
  `.claude/rules/architecture-boundaries.md`
- Which physical elements must be ports and the forbidden symbols:
  `.claude/rules/physical-abstraction.md`
- Deterministic test rules and the TestSupport primitives:
  `.claude/rules/testing.md`
- GPU-touching tests (separate process; the CI runner has a paravirtual Metal device):
  `.claude/rules/gpu-testing.md`
- Module addition and documentation sync checklist:
  `.claude/rules/module-checklist.md`
- Swift implementation style and immutability rules:
  `.claude/rules/swift-idioms.md`
- Coverage-ignored modules must hold no implementation (only protocols,
  `liveValue` one-liners, one-assignment dev substitutions, declarative views and
  thin-live Gateways): `.claude/rules/coverage-ignored-modules.md`
- Verifying the virtual camera on a real machine (install, approve, Zoom):
  `.claude/rules/dev-verification.md`

## Build And Verify

```sh
make build
make build-dev-harness  # dev-harness in debug, as `swift run` builds it, always relinked so a plist edit lands; not shipped (`make build` compiles it too, see docs/ARCHITECTURE.md)
make test
make test-gpu
make lint
make format
make check
make generate
swift run dev-harness   # camera prompt, then camera → effect → preview window, no virtual camera; .claude/rules/dev-verification.md Lane 1
```

## Project Summary

A macOS menu-bar app: webcam → real-time Metal shader effects (`.lens`
packages loaded at runtime, community-authored) → virtual camera for any app
(CoreMediaIO Camera Extension). Two processes: the host app and the Camera
Extension.

Core dependency direction:

```text
App/Router/Views -> Presenters -> Interactors -> UseCases
                 -> Repositories -> DataSources/DataStores -> Gateways (OS boundary)
```

Shared conventions:

- `Entity` owns pure data types. `Domain` owns protocols and `DependencyKey`
  definitions (`@_exported import Entity`).
- Implementation targets depend on `Domain` only. The DI targets
  (`CommonDependencyInjection`, `HostDependencyInjection`,
  `ExtensionDependencyInjection`) are the only places that import
  implementation targets; one wiring point per process.
- OS boundaries are `*Gateway` modules consumed at the DataSource layer (the
  execution-context ports — `frameExecutor`, `frameScheduler`, `workRunner` —
  are the exception: UseCases run the frame path on them).
  Cross-cutting seams (`RandomSource`, `UnifiedLog`, `HostTime`,
  `AppDirectories`, the live `AppDirectoriesProvider`) are Support modules.
- Frames travel as `FrameRef` (dimensions, format, PTS) + `SurfaceToken`
  (a generation-tagged index into the surface pool; a stale token resolves
  to nothing) — never as `Data` copies and never as raw `IOSurface` across
  layers.
- Product name appears only in `README.md`, `project.yml` and
  `Sources/Entity/ProductIdentity.swift`. Everything else is role-named.
- A `.lens` package is a directory `<id>.lens/` in the effects folder
  (`~/Library/Application Support/<host bundle id>/Effects`, the path comes from
  `AppDirectoriesProvider`) holding `manifest.json` (`formatVersion` 1 and
  `name`; optional `author` / `description`; unknown keys, `parameters`
  included, ignored) and `effect.metal` (entry point `effect`, compiled behind
  the prelude). The id is the directory name without the suffix.
  `EffectPackageDataSource` reads it through `FileSystemGateway` and lists a
  package it cannot use as `.broken` with the reason instead of leaving it out
  (epic #42, D1 / D3); `Examples/Ripple.lens` is a complete one.

## Non-Negotiable Rules

- No OS framework import (AVFoundation, Metal, MetalKit, IOSurface,
  CoreMediaIO, CoreMedia, CoreVideo, SystemExtensions, AppKit, os) outside
  Gateway modules and the View/Router/App lane. `make check` fails otherwise.
- No layer skipping through `@Dependency`: a module resolves only the ports of
  the layer right below it, plus Support (`scripts/check-dependency-keypaths.sh`,
  run by `make check`; a port's kind is its `Sources/Domain/<Kind>/` directory).
  The exceptions are listed in `.claude/rules/architecture-boundaries.md`: the
  frame path's execution context for UseCases, `workRunner` for Repositories,
  `surfacePool` for `GPURenderDataSource` and `PreviewDataSource`, and
  `extensionRelayUseCase` for `ExtensionApp`, whose process has no GUI and so
  no Interactor lane.
- The extension process never links Metal: `MetalGateway` and
  `MetalKitPreviewGateway` are registered in `HostDependencyInjection` only,
  and `scripts/check-extension-no-metal.sh` (in `make check`) walks the
  package graph from `ExtensionApp` / `ExtensionDependencyInjection` and fails
  when a Metal module, `PreviewDataSource` or `Views` is reachable.
- No physical symbol outside Gateway/Support live modules: `Date()`,
  `Date.now`, `ContinuousClock()`, `.now`, `Task.sleep`, `DispatchQueue`,
  `DispatchSource`, `Thread`, `UUID()`, `.random(in:)`,
  `SystemRandomNumberGenerator`, `FileManager`, `UserDefaults`,
  `ProcessInfo`, `Bundle.main`, `NotificationCenter.default`, `print(`,
  `os.Logger`, `MTLCreateSystemDefaultDevice`. Allow-listed per line with
  `// allow-physical: <PortName>` only inside the port's live module.
- No layer skipping. An Interactor never holds a Gateway; a UseCase never
  holds a DataSource. Thread pass-through contracts through adjacent layers.
- Every host port above the OS boundary has a live value from the day its
  contract exists, so a PR merged out of order never leaves the pipeline
  without a runtime or a sink.
  Both are real now: `PreviewSink` is `PreviewRepositoryImpl` over
  `PreviewDataSource` (which completes frames at once until a view is
  attached), and `EffectRuntimeRepository` is `EffectRuntimeRepositoryImpl`.
  The effects catalog (epic #42) followed the same rule: its seven modules
  started as pass-throughs (`NoPackages`, `NeverChangingWatch`, `EmptyPreferences`,
  `EmptySettings`, `BundledOnlyEffectCatalog`, `StaticEffectInteractor` and
  `BundledOnlyCatalog`) that listed the bundled effect alone, and each was replaced
  in place (`EffectInteractorImpl` replaced `StaticEffectInteractor`, #49,
  `EffectCatalogUseCaseImpl` replaced `BundledOnlyEffectCatalog`, #48,
  `EffectPackageRepositoryImpl` replaced `BundledOnlyCatalog`, #47, and
  `EffectWatchDataSourceImpl` replaced `NeverChangingWatch`, #46).
  Their streams, and `EffectWatchDataSourceImpl`'s, stay open until the consumer
  lets go.
  `EmptyPreferences` and `EmptySettings` are already replaced (#51):
  `PreferencesDataStoreImpl` keeps the chosen effect as one `<origin>:<key>` string
  (`StoredEffectID`) in the user's defaults through `KeyValueStoreGateway`, ignoring
  and logging a stored string that does not decode, and `SettingsRepositoryImpl`
  passes it through; there is no `SettingsUseCase` until a settings UI exists.
  `NoPackages` is replaced as well (#45): `EffectPackageDataSourceImpl` lists the effects
  folder's `.lens` packages through the file ports.
  The OS-boundary ports of the catalog get their live with the issue that wraps
  the OS API: `FileSystemGateway`, `FileWatchGateway`, `WorkspaceGateway` and
  `AppDirectoriesProvider` (module `AppDirectories`) are registered in
  `HostDependencyInjection` (#44), and `KeyValueStoreGateway` as
  `UserDefaultsGateway` (#51), which `PreferencesDataStoreImpl` resolves. No
  pass-through of the catalog remains: `EffectPackageDataSourceImpl` (#45) resolves
  `FileSystemGateway`, `AppDirectoriesProvider` and `WorkspaceGateway`,
  `EffectWatchDataSourceImpl` (#46) resolves `FileWatchGateway`, and each of them has
  a live value, so nothing reaches a Gateway that has none. Every test of
  `HostEffectRegistrationsTests` resolves through `live(_:)` over an in-memory file
  system, a fixed effects folder, a `FakeFileWatchGateway`, an in-memory key-value store,
  a `FakeWorkspaceGateway` and fresh logs: a test never touches the user's own folder,
  defaults or Finder, or opens a real descriptor. That suite resolves only the stateless
  values (the Repositories, DataSources and DataStore);
  `HostFileGatewayRegistrationsTests` pins the OS-boundary lives (file system, file
  events, Finder, app directories, key-value store). `effectInteractor` and
  `effectCatalogUseCase` are resolved live by `HarnessLiveWiringTests` alone, because
  they hold a task and a session and freeze the scope that built them (see the
  harness bullet below).
- The effects menu lane (epic #42, D9): `EffectInteractorImpl` owns the one task
  that runs `EffectCatalogUseCase` (`run()` and the forwarding of `observe()` are
  its two structured children) and publishes the state through a
  `CurrentValueSubject`. `start()` / `stop()` only queue a command; one task
  started with the Interactor carries them out in call order, waiting for the run
  it ends, so there is no lock and no actor hop that could reorder them, and a
  second `start()` restarts the catalog. `select` is not queued with them nor behind another
  `select` (a newer choice must be able to overtake a slow compile), so two near-simultaneous
  choices are unordered, as the port says. `MenuBarPresenter` (`Presenters`,
  `@MainActor`, no AppKit / SwiftUI) maps `state` to `@Published items`
  (`EffectMenuItem`) and `status` with a `@MainActor` task over an `AsyncStream`
  that a `sink` feeds (newest state wins), never `receive(on: DispatchQueue.main)`
  and never `publisher.values` (an `AsyncPublisher` drops states sent while it
  is applying the last one), and owns the Interactor's `start()` / `stop()` (whoever wires the Presenter calls
  only its `start()` / `stop()`, never `effectInteractor.start()`: a second
  `start()` is a restart; a started Presenter that is let go stops itself); its suite waits with `settle` only. `AppRouter` (View lane, `@MainActor`) builds the one
  Presenter in `init` and calls only its `start()` / `stop()`: the host (`HostAppDelegate`) and the dev harness
  (`HarnessAppDelegate`) start and stop the Router and nothing below it. `EffectMenu` (`Views`) draws the Presenter for
  the host's `MenuBarExtra(.menu)` and the harness's `NSHostingMenu` and decides nothing (a `Toggle` per row, the
  Presenter's flags and words); the host stays out of the Dock through `LSUIElement` in `project.yml`. Details: the
  *Key Design Decisions* entries in `docs/ARCHITECTURE.md` (*The effects menu's Interactor and Presenter*, *Menu bar*).

- The effect runtime splits in two. `EffectRuntimeRepositoryImpl` only
  orchestrates (compile through `ShaderCompiler`, render through
  `GPURenderer`) and holds no state and no executor; its memory is
  `EffectRuntimeStateDataSource` (port `EffectRuntimeState`), confined to
  `FrameExecutor` (no lock, no actor), whose calls hop onto the executor
  themselves. The compile cache is in-process, keyed by
  `(source, compile options)` and never by the effect's name; a cache on disk
  (which would need a device id, an OS version and a `RuntimeEnvironment` port) is
  deferred to Later, epic #42 D12. The newest `prepare` decides what
  `apply` runs (newest wins, success or failure); a stale compile still answers
  its own caller and fills the cache but never releases a waiting `apply`. An
  `apply` that compiles an effect itself starts the compile on the `WorkRunner`
  and waits for the selection, not for that compile, so a newer `prepare` that
  settles first answers it at once.
  While nothing is prepared, the first `apply` prepares
  `BundledEffects.defaultEffect`, served by `BundledEffectDataSource` as an
  MSL string constant (no `Bundle.main`). A source that does not compile is
  `.compileFailed` and final; a compile that failed for the environment's reasons
  (`ShaderDiagnostics.cause == .environment`) is `.internalError` and retried by the
  next `apply`, and that streak is logged once, plus its recovery.
  Two things make a compile `.environment`: no GPU context, and
  `MTLLibraryError.internal` (the compiler service failing) — the pure
  `LibraryErrorMapping` in `ShaderCompilationDataSource` classifies the raw code
  the Gateway reports, every other code is `.source`, and `LibraryErrorCodeTests`
  pins the number to the SDK (epic #42, D7).
  `EffectUniforms.pass` is pure: `time` is seconds
  since the session's first frame (`EffectSession`, PTS minus the session
  start), `resolution` the output size in pixels (the grid is rounded up to
  whole threadgroups, so a kernel bounds-checks `gid`), `seed` 0 until MVP-C.
- `EffectCatalogUseCaseImpl` (epic #42, D5 / D6 / D11) is the only caller of
  `EffectRuntimeRepository.prepare`; the pipeline never calls it. Choosing an effect
  prepares its source, and a listing in which the chosen effect's source changed
  prepares it again (hot reload: the Repository lists again after every change, so an
  edit arrives as a listing). A broken edit is `.compileFailed` and passes frames
  through until it is fixed; there is no last-good library to keep. The persisted
  choice is restored when a run starts; a chosen package that is gone, or broken,
  falls back to the bundled effect, and that fallback is not remembered (only `select`
  writes the settings). The decisions live in an internal actor, `EffectCatalogSession`
  (off the frame path); `observe()` is a `CurrentValueSubject` broadcast subscribed
  before the call returns, so any number of observers see the same states. Newest wins
  is mirrored there: the generation is taken in the same actor turn that calls
  `prepare`, so an answer overtaken by a newer request reaches its caller but publishes
  nothing, whatever order the runtime answers in; a run number and a read number stop
  a flow that waited across a run boundary, or behind a newer read of a source, from
  acting on its answer. The compile failure itself is logged
  once by the runtime; the catalog logs the selection, the reload and the fallback.
- The effect catalog is assembled in `EffectPackageRepositoryImpl` (epic #42,
  D3), which resolves `effectPackages`, `effectWatch` and `bundledEffects`.
  `catalog()` is an eager `AsyncStream`: making it lists the folder, arms the
  watch for that listing, shows the catalog (armed first, so the first change
  after a catalog is heard), and on every watch element lists again and arms the
  *new* inventory's `EffectWatchSet`, the old watch having been let go first: an
  edit that lands inside a re-listing is heard only with the next change. Every
  listing is shown, even one equal to the last: the watch folds bursts, and a
  same-looking listing can be an edited `effect.metal`. The bundled effect is
  first, packages follow by display name (case-insensitive, numeric runs, folder
  name as the tie-break, no locale), a broken one is `.broken` under its folder
  name. `source(of:)` reads afresh and caches nothing: the bundled id is
  `defaultEffect` (another bundled id `.sourceMissing`), a package is its source
  when `.ready`, its problem when `.broken`, `.manifestMissing` when gone. The
  loop is a `Task` off the frame path, cancelled when the stream ends; a watch
  that ends by itself ends the catalog and logs an error, and the task logs its
  end (whichever side it came from) to the developer log.
- The watch is `EffectWatchDataSourceImpl` (epic #42, D4), which resolves
  `fileWatchGateway`, `continuousClock` and `developerLog`. `changes(of:)` arms
  every directory (`watch(directory:)`, an editor's atomic save) and then every file
  (`watch(file:)`, an in-place overwrite) before it returns, logs and skips a path
  that cannot be watched, and folds a burst into one element after a 200 ms quiet
  period (`quietPeriod`): each event numbers a `clock.sleep` of its own and only the
  newest event's sleep yields. The stream never ends on its own, even for an empty
  set; ending it stops every armed watch exactly once and drops the period in
  progress. The debounce is a DataSource, not a Gateway, because `FileWatchGateway`
  is thin (no timing, no branch).

- No UseCase depends on another UseCase. Shared pure policy (health
  judgement, parameter clamping, uniform packing) lives as pure types inside
  the owning UseCase module, never as a second UseCase.
- Exactly two output paths, both write-only Domain protocols resolved via DI:
  `ErrorLog` and `DeveloperLog`. Live is `os.Logger` (`UnifiedLog`); neither
  the host app nor the extension has a usable stderr. Never `print`.
- Frame-path callbacks run on the `FrameExecutor` port. UseCase state on the
  frame path is a single-threaded state machine; no locks in UseCases. Async
  work the frame path must start (the host reconnect, the effect `apply`) goes
  through the `WorkRunner` port and its `WorkHandle`, never an unstructured
  `Task {` in a UseCase. The shader compile is the same: `ShaderCompilationDataSource` runs it
  inside a `WorkRunner` item, never on main and never in a bare `Task {`.
- Effects compile behind the engine prelude (`Uniforms`, `hash`, `noise`) and a
  `#line 1 "effect"` directive, so diagnostics carry the author's line numbers;
  locations against the assembled source are rewritten to `effect:` /
  `prelude:`. `hash` / `noise` have a Swift twin, `HashNoiseReference`, checked
  on the GPU by the `hash-noise parity` suite.
- Surface lifetime is owned by `SurfaceRepository`: `allocate` hands out a
  `SurfaceToken`, `release(token)` gives the slot back and reports whether the
  token was still live, `liveCount` is the invariant. A UseCase releases the
  token it was given exactly once; it never sees an `IOSurface` or a
  retain/release pair.
- Host frame path: camera → latest-frame slot (newest wins) → one effect pass
  per tick → sink and preview. At most one pass is in flight; a tick that finds
  one running drops its frame as `.inFlightCapReached`. A pass holds two leases
  and only its answer ends them: on success the input is released at the
  answer; on any failure the output is released at the answer and the input
  goes on unchanged. The frame that goes on is sent, then presented on the
  `PreviewSink` (sent or not), and released once both are done with it — the
  send returns synchronously, so the preview's completion, hopped back onto
  the executor, ends the lease. The preview holds that lease, never the
  in-flight cap. No failure state is kept between frames. `stop()` abandons
  the pass rather than cancelling it (the GPU may still use both surfaces): it
  bumps a stop count first, so no answer sends or presents after it; the pass
  keeps its leases and the cap until its answer, which releases both unsent;
  and `releaseAll()` waits for that answer and for every frame still on the
  preview (and is left out once a restart owns the pool). A pass carries the
  count its run's `start()` read, never one a tick reads, so a tick still
  running when `stop()` bumps the count cannot adopt the new one.
- Shells (`Apps/**`) hold only `main.swift` and assets; `make check` bounds
  their size. `Info.plist` and entitlements are generated from `project.yml`
  by `make generate` (gitignored), never hand-written. The one exception is
  `Tools/DevHarness/Info.plist`, linked into the `dev-harness` SwiftPM
  executable with `-sectcreate` (xcodegen never builds it); it carries no
  product name, and `make check` scans `Tools/` for one.
- `DevHarness` keeps `main.swift` to AppKit's launch and `HarnessSession` to
  the lifecycle and the view wiring; the session resolves only `HarnessInteractor`,
  which drives `CameraControlUseCase` and `FramePipelineUseCase`. Each layer is
  tested against fakes. `HarnessAppDelegate` also owns an `AppRouter`, started beside the
  session, and shows the host's `EffectMenu` as the main menu's Effects item (`NSHostingMenu`,
  macOS 14.4+); `HarnessLiveWiringTests` builds that Router beside the session and drives
  its Presenter through the real catalog. It logs through `DeveloperLog` / `ErrorLog` like
  every other module, never `print`. `HarnessSession.live()` builds the
  session inside `withDependencies { $0.useDiscardingVirtualCameraSink() }`:
  the host's real graph with one substitution, `DiscardingVirtualCameraSink`
  (dev-only, in `VirtualCameraRepository`: it accepts and drops every frame
  because the harness has no extension). The host app keeps the real sink, and
  the substitution must wrap the construction, because `@Dependency` captures
  the scope where it is built. `HarnessLiveWiringTests` is the one `.live` test
  of that route and the only suite that resolves `effectInteractor` and
  `effectCatalogUseCase` live (the live registrations are process-wide singletons that
  keep the first builder's scope: add no second one, and wrap every call that can
  reach a catalog value in that test's `wired { }`), over fakes at the OS boundary
  only (camera, IOSurface, Mach, GPU, file system, file events, key-value store,
  Finder). `scripts/check-dev-substitutions.sh` (in `make check`) keeps
  the sink's name out of everything but the harness, its DI helper and
  `VirtualCameraRepository`.
- Host absence: the extension detects it by frame gap (watchdog every
  `frameGap / 4`, counted from the last frame, or from `start` while no host
  has been seen yet, so a host that never launched is lost too) and by dead-name
  of the host's presence port; either yields `hostLost`, and the relay then runs a black slate (`SlateSchedule`) with
  strictly increasing PTS until a real frame arrives (real PTS is re-timed above
  the last slate PTS with `SlateSchedule.shift`; a frame that still does not
  advance drops as `.nonMonotonic`). The host reconnects on `destinationLost` from
  `FramePipelineUseCase` with `RetryPolicy.serviceLookup` backoff. The
  kill -9 / -STOP / -CONT timings are not yet measured on a device (issue #3).
- Install outcomes are typed: `InstallFailure` (`denied`, `canceled`,
  `invalidBuild`, `other`) is mapped from raw `OSSystemExtensionError` codes in
  `ExtensionInstallDataSource`, never in the gateway.
- GPU outcomes are typed the same way: `GPURenderDataSource` (port
  `GPURenderer`) maps raw command-buffer codes onto `EffectFailure` in the pure
  `GPUCompletionMapping` (only in `MTLCommandBufferErrorDomain`; anything else
  is `unknown(code:)`), never in `MetalGateway`. One render is one command
  buffer; a stale lease is `.invalidResource` and reaches no gateway; every
  bound texture is unbound exactly once on every path. It keeps no failure
  history (health policy is MVP-D) and packs no uniform bytes: the gateway
  sends `EffectUniforms` itself, pinned to the MSL layout by a property test.
- The Mach service name is declared once in `ProductIdentity`; host
  `mach-lookup`, extension `mach-register` and the constant are compared by
  `make check` (a mismatch makes `bootstrap_look_up` fail silently).

## Testing Rules

- Never wait with a fixed `Task.sleep`. Use `settle` (published state),
  `Collector` (spy recorded off-main), `tickUntil` (test-driven subject),
  `pollUntil` (readable-only external state), `suspendUntilCancelled`
  (a double that must never answer) from `Tests/TestSupport`.
- Frame flow is driven by the test: `FakeCaptureSessionGateway.emit(frame)`,
  `ManualFrameExecutor.drain()`, `FakeGPUGateway.complete(submission, with:)`.
  Interleavings are enumerated with seed-driven `forAll` / `@Test(arguments: Seeds...)`.
- The GPU and effect fakes complete manually, in any order: `FakeGPUGateway`
  (pending `Submission`s), `FakeEffectRuntimeRepository` (`completePrepare` /
  `completeApply`), `FakeGPURenderer` (`complete(request, with:)`, or a
  scripted `respond(with:)`), `FakeShaderCompiler` (`complete(request, with:)` /
  `succeed(request)`), `InMemoryPreviewSink` (`complete(presentation)`; with
  `holding: .onceAttached` it completes every frame inside `present` until a
  target is attached — stricter than the live sink, whose `PreviewDataSource`
  gives them back in a later executor job, after `present` has returned),
  `FakePreviewGateway` (`complete(draw, with:)`).
  Each completion is exactly once; a second one, or one another instance
  issued, returns `false` (`FakeShaderCompiler.succeed` returns `nil`). Like
  their live counterparts, the runtime, renderer and compiler fakes ignore
  cancellation.
  `FakeShaderLibraryGateway` reports an issue when called on the main thread;
  `FakeTextureCacheGateway.isBalanced` is the bind/unbind invariant.
- The pipeline's in-flight cap is driven by answering its `apply` by hand: a
  pipeline test answers each pass (`Rig.completeEffect` / `answer`, and
  `answerAbandoned` for a pass `stop()` gave up on), and `LoopbackRig.capture`
  answers with pass-through unless told otherwise. The fake runtime ignores
  cancellation like the live one, so an abandoned pass stays pending
  (`pendingCount`) until the test answers it. Both rigs present on an
  `InMemoryPreviewSink(holding: .onceAttached)`, so a test that never attaches
  a preview sees a frame's lease end with the drain that sent it; one that
  attaches (`Rig.attachPreview`) completes each presentation by hand.
  `LoopbackRig(preview: .rendered)` puts the real `PreviewRepository` /
  `PreviewDataSource` on the host side, over the fake GPU layer — the one rig
  with the live timing for an unattached preview. `LoopbackRig(effects: .real)`
  does the same for the effect stage: the real `EffectRuntimeRepository` over
  its live DataSources and the fake GPU layer, driven by
  `captureThroughRuntime` (the compile runs on the work runner and the GPU
  completes by hand); `RealEffectRuntimeIntegrationTests` asserts the
  extension streams the effect's output, and that a source that does not
  compile still streams the camera's own frames. `LoopbackRig(effects: .real,
  catalog: .real)` adds the real effects catalog on that runtime (`HostSide.catalog`,
  a `CatalogSide`: an `InMemoryFileSystemGateway` effects folder, a
  `FakeFileWatchGateway`, an `InMemoryKeyValueStore`, a `FakeWorkspaceGateway`, and a
  `GatedClock` of its own for the watch's quiet period, which a test can see parked);
  `EffectCatalogIntegrationTests` writes a package, fires the watch, steps that clock
  past 200 ms and judges by the fake GPU's pass graph what the extension is sent: the
  package appears, choosing it compiles it once, a rewritten source compiles again, a
  source that does not compile streams the camera's own frame, and a removed package
  falls back to the bundled effect.
- Time is `\.continuousClock` + `TestClock` (`GatedClock` for the reconnect
  proof and for the watch's quiet period); slate PTS is `base + n × (1/fps)` from
  one base — never read from a wall clock.
- Host IPC and host loss are tested on `InMemoryFrameTransport` (bootstrap
  table, queue cap, presence ports, dead-name, `killHost()`); client counts on
  `FakeStreamOutput.connectClient/disconnectClient`; wider seed sets via
  `Seeds.range(0..<N)`.
- The `EffectCatalogUseCase` suites answer each `prepare` by hand
  (`EffectCatalogRig.answer`), in the order they write down; a state that equals the
  last one is not published, so a hot reload that works is proven by the next listing
  (a sentinel through the same pipeline), not by a state of its own.
- The catalog fakes are driven by the test: `InMemoryFileSystemGateway`
  (`write` / `remove` between reads, `failRead(of:with:)`), `FakeFileWatchGateway.fire(path)`
  (`isBalanced` is the watch/stop invariant), `FakeEffectWatch.fire()` / `fire(request:)`,
  `FakeEffectPackages.script(_:)`, `FakeEffectPackageRepository.publish(_:)` /
  `script(_:for:)`, `FakeEffectCatalogUseCase.publish(_:)` and
  `FakeEffectInteractor.publish(_:)`. A stream a fake hands out is registered
  before the call returns and its `terminations` collector counts the consumer
  letting go; keep the stream alive for the test (`withExtendedLifetime`), since
  dropping its iterator cancels it.
- Never `setenv`; inject paths through `AppDirectoriesProvider`.
- Never `withMainSerialExecutor` / `uncheckedUseMainSerialExecutor`.
- Build `@Dependency`-holding objects inside `withDependencies { } operation: { }`,
  never in the `update` closure (captures default values).
- GPU suites run only via `make test-gpu`, in their own process, `.serialized`,
  gated by `.enabled(if: MetalDeviceProbe.isAvailable)`, excluded from coverage,
  and written against the `mac2` family only (the CI runner's "Apple
  Paravirtual device" reports `supportsFamily(.apple7) == false`; see #4).
- Test doubles shared across layers live in `Tests/TestDoubles`; a double
  used by one suite stays private to that suite.

## Change Checklist

- When adding or removing modules, update `Package.swift`, the relevant
  `*DependencyInjection`, `docs/ARCHITECTURE.md`, this `AGENTS.md` and
  `README.md` (see `.claude/rules/module-checklist.md`).
- Every PR bumps `version.txt`.
- Do not commit directly to `main`. Branch → PR → merge.
