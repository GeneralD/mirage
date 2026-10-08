---
paths:
  - "Sources/**/*.swift"
---

# Physical Abstraction — Nothing Real Above the Gateway

A *physical element* is anything that makes a test depend on the machine it
runs on: hardware (camera, GPU), the OS (System Extension, Mach ports, CMIO,
files, file events, UserDefaults, bundles, workspaces), time (clocks, timers,
host time, display links), randomness, threads and queues, process-global
state, and output streams. Every one of them is a Domain port with a fake in
`Tests/TestDoubles`. The full table is `docs/ARCHITECTURE.md` → *Physical
Abstraction Table*; add a row there when you add a port.

## Forbidden symbols (outside Gateway / Support live modules)

`scripts/check-physical-symbols.sh` (AST-based via `sg`, run by `make check`)
fails on any of these in UseCase, Repository, DataSource, DataStore,
Interactor, Presenter, Domain and Entity sources:

| Category | Symbols |
|---|---|
| Time | `Date()`, `Date.now`, `ContinuousClock()`, `SuspendingClock()`, `.now` on a clock type, `Task.sleep`, `DispatchTime`, `mach_absolute_time`, `ProcessInfo.systemUptime`, `CFAbsoluteTimeGetCurrent`, `Timer` |
| Randomness / identity | `.random(in:)`, `.randomElement()`, `.shuffled()`, `SystemRandomNumberGenerator`, `UUID()` |
| Threads / queues | `DispatchQueue`, `DispatchSource`, `DispatchSemaphore`, `Thread`, `Task.detached`, unstructured `Task {` on the frame path, `OSAllocatedUnfairLock`, `NSLock` |
| Global state | `NotificationCenter.default`, `Bundle.main`, `FileManager`, `UserDefaults`, `ProcessInfo.processInfo`, `setenv`, `getenv` |
| Output | `print(`, `debugPrint(`, `fputs(`, `os.Logger`, `NSLog` |
| OS frameworks | `MTLCreateSystemDefaultDevice`, `AVCaptureSession`, `IOSurfaceCreate`, `bootstrap_look_up`, `OSSystemExtensionRequest`, `CMIOExtensionStream` and any `import` of AVFoundation, Metal, MetalKit, IOSurface, CoreMediaIO, CoreMedia, CoreVideo, SystemExtensions, AppKit, `os` |

The only escape hatch is a per-line `// allow-physical: <PortName>` comment,
valid **only inside the live module that implements `<PortName>`**. The lint
rejects it anywhere else.

## How each category is abstracted

- **Time** → `\.continuousClock` for sleeping/timers/debounce; `HostTimeProvider`
  for PTS. Slate PTS is `base + n × (1/fps)`; uniform `time` is `PTS − start`.
- **Randomness** → `RandomSource` (seeded). GPU hash-noise is a pure function
  of (coordinate, time, seed) with a Swift reference implementation.
- **Execution context** → `FrameExecutor` (serial) and `FrameScheduler`
  (ticks). UseCase frame state is a single-threaded state machine.
- **GPU** → `GPUGateway`, `ShaderLibraryGateway`, `TextureCacheGateway`; the
  Gateway returns raw completion data, the DataSource maps it.
- **Surfaces** → `SurfaceLease` from `SurfaceRepository`; raw `IOSurface` is
  seen only by `IOSurfaceGateway` and `MetalGateway`.
- **Files** → `FileSystemGateway` + `AppDirectoriesProvider` (paths are
  injected; never read from the environment).
- **IPC** → `MachBootstrapGateway` / `MachMessageGateway`; the receive loop is
  in `FrameReceiverDataSource`, one message per `receive()`.
- **Logging** → `ErrorLog` / `DeveloperLog` (live: `UnifiedLog`).

## Thin-live rule for coverage-ignored Gateways

A Gateway that cannot run in CI is coverage-ignored and therefore must be
too simple to hide a bug: ≤ 50 lines per file, no `if`/`guard`/`switch`/`for`,
no `var`, a three-line header comment naming the port and the OS API.
`scripts/check-live-thin.sh` enforces it. Anything that needs a branch moves
up into the DataSource, where it is tested against the fake.
