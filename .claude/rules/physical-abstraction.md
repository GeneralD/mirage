---
paths:
  - "Sources/**/*.swift"
---

# Physical Abstraction — Nothing Real Above the Gateway

A *physical element* is anything that makes a test depend on the machine it
runs on: hardware (camera, GPU), the OS (System Extension, Mach ports, CMIO,
files, file events, UserDefaults, bundles, workspaces, global hotkeys, the
login item, the OS log store, image codecs), time (clocks, timers, host time,
display links), randomness, threads and queues, process-global state (the app
and macOS versions among it), and output streams. Every one of them is a
Domain port with a fake in `Tests/TestDoubles`. The full table is
`docs/ARCHITECTURE.md` → *Physical Abstraction Table*; add a row there when you
add a port.

## Forbidden symbols (outside Gateway / Support live modules)

`scripts/check-physical-symbols.sh` (AST-based via `sg`, run by `make check`)
fails on any of these in every module under `Sources/` except its
`LIVE_MODULES` (the Gateway and Support live modules). The modules it checks
are the UseCase, Repository, DataSource, DataStore, Interactor, Presenters,
Domain, Entity, Views and AppRouter modules, the entry points and the DI
targets:

| Category | Symbols |
|---|---|
| Time | `Date()`, `Date.now`, `ContinuousClock()`, `SuspendingClock()`, `Task.sleep`, `mach_absolute_time`, `CFAbsoluteTimeGetCurrent` |
| Randomness / identity | `.random(in:)`, `.randomElement()`, `.shuffled()`, `SystemRandomNumberGenerator()`, `UUID()` |
| Threads / queues | `DispatchQueue(…)`, `DispatchQueue.main`, `DispatchQueue.global(…)`, `DispatchSource.*`, `DispatchSemaphore(…)`, `Thread.*`, `Task.detached`, `OSAllocatedUnfairLock(…)`, `NSLock()` |
| Global state | `NotificationCenter.default`, `Bundle.main`, `FileManager.default`, `ProcessInfo.processInfo`, `setenv`, `getenv`, and the name `UserDefaults` in any spelling (a type annotation or `.standard` included) |
| Output | `print(`, `debugPrint(`, `NSLog(`, `Logger(` |
| OS frameworks | `MTLCreateSystemDefaultDevice()`; framework `import`s are `scripts/check-imports.sh`'s |

The lint does not match `DispatchTime`, `ProcessInfo.systemUptime`, `Timer`,
`fputs(`, an unstructured `Task {` on the frame path (start it through
`WorkRunner`), `AVCaptureSession`, `IOSurfaceCreate`, `bootstrap_look_up`,
`OSSystemExtensionRequest` or `CMIOExtensionStream`; the framework `import`
allow-list keeps most of the OS symbols out, and review rejects the rest.

The only escape hatch is a per-line `// allow-physical: <PortName>` comment,
valid **only inside the live module that implements `<PortName>`**. The lint
rejects it anywhere else.

## How each category is abstracted

- **Time** → `\.continuousClock` for sleeping/timers/debounce; `HostTimeProvider`
  for PTS. Slate PTS is `base + n × (1/fps)` with
  `base = max(hostTime.now(), lastEmitted + frameDuration)`; uniform `time` is
  `PTS − start`.
- **Randomness** → `RandomSource` (seeded). GPU hash-noise is a pure function
  of (coordinate, time, seed) with a Swift reference implementation.
- **Execution context** → `FrameExecutor` (serial) and `FrameScheduler`
  (ticks). UseCase frame state is a single-threaded state machine.
- **GPU** → `GPUGateway`, `ShaderLibraryGateway`, `TextureCacheGateway`; the
  Gateway returns raw completion data, the DataSource maps it.
- **Surfaces** → `SurfaceToken` from `SurfaceRepository`; raw `IOSurface` is
  seen only by the Gateways that wrap it: `IOSurfaceGateway`, `MetalGateway`,
  and `CMIOExtensionGateway` (it wraps the surface into the stream's sample
  buffers).
- **Files** → `FileSystemGateway` + `AppDirectoriesProvider` (paths are
  injected; never read from the environment).
- **IPC** → `MachBootstrapGateway` / `MachMessageGateway`; the receive loop is
  in `FrameReceiverDataSource`, one `IncomingMessage` (frame / hello /
  dead-name) per `receive(on:)`. The host's presence port, the watchdog and the
  dead-name matching are DataSource logic, never Gateway logic.
- **Logging** → `ErrorLog` / `DeveloperLog` (live: `UnifiedLog`).
- **Settings store** → `KeyValueStoreGateway` (strings by key; live:
  `UserDefaultsGateway`), the only place `UserDefaults` is named.
- **File events, Finder** → `FileWatchGateway` (`FileWatchHandle.stop()`; live:
  `FileWatchGateway`) and `WorkspaceGateway` (live: `WorkspaceGateway`, over
  `NSWorkspace`).
- **Hotkeys, login item, OS log** → `HotkeyGateway` (a `HotkeyHandle` given
  back by `release()`; Carbon), `LoginItemGateway` (ServiceManagement) and
  `LogStoreGateway` (`entries(subsystem:)`; OSLog). What a status or a line
  means is decided above them, in `HotkeyDataSource`, `LoginItemDataSource` and
  `SupportLogDataSource`.
- **Images** → `ImageIOGateway` (`dimensions(of:)`, `decode(_:)`,
  `encodePNG(_:)`); `StillImageDataSource` decides what a failure means.
- **Console** → `ConsoleWriter` (live: `StandardStreams`), the command-line
  tool's one exit to standard output and standard error. `print(` stays
  forbidden, and logs never go through it.
- **App and OS version** → `HostEnvironmentProvider` (live: `HostEnvironment`),
  the one reader of `ProcessInfo` and `Bundle`.

## Thin-live rule for coverage-ignored Gateways

A Gateway that cannot run in CI is coverage-ignored and therefore must be
too simple to hide a bug: ≤ 50 lines per file, no
`if`/`guard`/`switch`/`for`/`while`, no `var` at any access level, and a short
header comment naming the port and the OS API. `scripts/check-live-thin.sh`
enforces the line cap, the branch ban and the `var` ban (not the comment) on
the `*Gateway` modules listed in `codecov.yml`. Anything that needs a branch
moves up into the DataSource, where it is tested against the fake.
