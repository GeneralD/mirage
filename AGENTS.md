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
- Coverage-ignored modules must hold no implementation:
  `.claude/rules/coverage-ignored-modules.md`
- Verifying the virtual camera on a real machine (install, approve, Zoom):
  `.claude/rules/dev-verification.md`

## Build And Verify

```sh
make build
make test
make test-gpu
make lint
make format
make check
make generate
swift run dev-harness   # MVP-A; not in M0
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
- OS boundaries are `*Gateway` modules consumed at the DataSource layer.
  Cross-cutting seams (`RandomSource`, `UnifiedLog`, `HostTime`,
  `AppDirectoriesProvider`) are Support modules.
- Frames travel as `FrameRef` (dimensions, format, PTS) + `SurfaceToken`
  (a generation-tagged index into the surface pool; a stale token resolves
  to nothing) — never as `Data` copies and never as raw `IOSurface` across
  layers.
- Product name appears only in `README.md`, `project.yml` and
  `Sources/Entity/ProductIdentity.swift`. Everything else is role-named.

## Non-Negotiable Rules

- No OS framework import (AVFoundation, Metal, MetalKit, IOSurface,
  CoreMediaIO, CoreMedia, CoreVideo, SystemExtensions, AppKit, os) outside
  Gateway modules and the View/Router/App lane. `make check` fails otherwise.
- No physical symbol outside Gateway/Support live modules: `Date()`,
  `Date.now`, `ContinuousClock()`, `.now`, `Task.sleep`, `DispatchQueue`,
  `DispatchSource`, `Thread`, `UUID()`, `.random(in:)`,
  `SystemRandomNumberGenerator`, `FileManager`, `UserDefaults`,
  `ProcessInfo`, `Bundle.main`, `NotificationCenter.default`, `print(`,
  `os.Logger`, `MTLCreateSystemDefaultDevice`. Allow-listed per line with
  `// allow-physical: <PortName>` only inside the port's live module.
- No layer skipping. An Interactor never holds a Gateway; a UseCase never
  holds a DataSource. Thread pass-through contracts through adjacent layers.
- No UseCase depends on another UseCase. Shared pure policy (health
  judgement, parameter clamping, uniform packing) lives as pure types inside
  the owning UseCase module, never as a second UseCase.
- Exactly two output paths, both write-only Domain protocols resolved via DI:
  `ErrorLog` and `DeveloperLog`. Live is `os.Logger` (`UnifiedLog`); neither
  the host app nor the extension has a usable stderr. Never `print`.
- Frame-path callbacks run on the `FrameExecutor` port. UseCase state on the
  frame path is a single-threaded state machine; no locks in UseCases. Async
  work the frame path must start (the host reconnect) goes through the
  `WorkRunner` port and its `WorkHandle`, never an unstructured `Task {` in a
  UseCase.
- Surface lifetime is owned by `SurfaceRepository`: `allocate` hands out a
  `SurfaceToken`, `release(token)` gives the slot back and reports whether the
  token was still live, `liveCount` is the invariant. A UseCase releases the
  token it was given exactly once; it never sees an `IOSurface` or a
  retain/release pair.
- Shells (`Apps/**`) hold only `main.swift` and assets; `make check` bounds
  their size. `Info.plist` and entitlements are generated from `project.yml`
  by `make generate` (gitignored), never hand-written.
- Host absence: the extension detects it by frame gap (watchdog every
  `frameGap / 4`) and by dead-name of the host's presence port; either yields
  `hostLost`, and the relay then runs a black slate (`SlateSchedule`) with
  strictly increasing PTS until a real frame arrives (real PTS is re-timed above
  the last slate PTS with `SlateSchedule.shift`; a frame that still does not
  advance drops as `.nonMonotonic`). The host reconnects on `destinationLost` from
  `FramePipelineUseCase` with `RetryPolicy.serviceLookup` backoff. The
  kill -9 / -STOP / -CONT timings are not yet measured on a device (issue #3).
- Install outcomes are typed: `InstallFailure` (`denied`, `canceled`,
  `invalidBuild`, `other`) is mapped from raw `OSSystemExtensionError` codes in
  `ExtensionInstallDataSource`, never in the gateway.
- The Mach service name is declared once in `ProductIdentity`; host
  `mach-lookup`, extension `mach-register` and the constant are compared by
  `make check` (a mismatch makes `bootstrap_look_up` fail silently).

## Testing Rules

- Never wait with a fixed `Task.sleep`. Use `settle` (published state),
  `Collector` (spy recorded off-main), `tickUntil` (test-driven subject),
  `pollUntil` (readable-only external state), `suspendUntilCancelled`
  (a double that must never answer) from `Tests/TestSupport`.
- Frame flow is driven by the test: `FakeCaptureSessionGateway.emit(frame)`,
  `ManualFrameExecutor.drain()`, `FakeGPUGateway.complete(...)`. Interleavings
  are enumerated with seed-driven `forAll` / `@Test(arguments: Seeds...)`.
- Time is `\.continuousClock` + `TestClock` (`GatedClock` for the reconnect
  proof); slate PTS is `base + n × (1/fps)` from one base — never read from a
  wall clock.
- Host IPC and host loss are tested on `InMemoryFrameTransport` (bootstrap
  table, queue cap, presence ports, dead-name, `killHost()`); client counts on
  `FakeStreamOutput.connectClient/disconnectClient`; wider seed sets via
  `Seeds.range(0..<N)`.
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
