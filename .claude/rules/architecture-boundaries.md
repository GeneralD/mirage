# Architecture Boundaries

## Layer Responsibilities

| Layer | Owns | Never |
|---|---|---|
| **Entity** | Pure data types, enums, Codable structs, `ProductIdentity` constants | Logic; imports beyond Foundation |
| **Domain** | Protocols, `TestDependencyKey`s, `Unimplemented*` | Data type definitions; imports beyond Foundation, Combine (Interactor streams) and Dependencies |
| **UseCase** | Business logic, pure policy types (`EffectHealthPolicy`, `ParameterPacker`) | Another UseCase; a DataSource; a Gateway other than the execution-context ports (`frameExecutor`, `frameScheduler`, `workRunner`: Key-Path table); locks; OS frameworks |
| **Repository** | Orchestration of DataSources/DataStores, cache strategy, surface lifetime (`SurfaceRepository`) | Gateways other than `workRunner`; the `FrameExecutor`; OS frameworks |
| **DataSource / DataStore** | Real work against Gateways plus persistence-shaped knowledge (paths, manifests, source assembly, IPC state machines, receive loops, pool bookkeeping, the effect runtime's executor-confined state) | Business policy; OS frameworks (those stay in the Gateway) |
| **Gateway** | 1:1 thin pass-through to one OS API | Branching, timing, ordering, retries, loops — anything that needs a test |
| **Ambient** | The cross-cutting ports every lane may resolve (logs, the clock, host time, host environment, the console), each admitted by the *Ambient admission* below | Business logic; a resource with a lifetime |
| **Interactor** | Combine state pipelines over UseCases for the GUI (the `state` streams a Presenter observes and the start / stop lifecycle), and stateless Interactors with no `state` (`CameraInteractor`, `HarnessInteractor` and `EffectAuthoringInteractor`, called by an entry lane, and `PreviewInteractor`, called by `PreviewPresenter`): a launch sequence or one call per command | Another Interactor; a Repository, DataSource or Gateway; display wording; AppKit / SwiftUI imports |
| **Presenter** | `@Published` display state | AppKit / SwiftUI / MetalKit imports; business logic |
| **Views / Router / App** | Declarative rendering, wiring, lifecycle; in `AppRouter` also the picker's thumbnail decode (`EffectThumbnailDecoding`: one AppKit call and the pixel limit that guards it, which stay covered and tested because `Views` is not) | Other business logic; direct UseCase/Gateway access (`ExtensionApp` → `extensionRelayUseCase` excepted: Key-Path table) |
| **DI targets** | `liveValue` registrations, and dev-only `DependencyValues` extensions whose members each only assign one value (no branch, no `var`; `scripts/check-live-thin.sh` checks `DevelopmentSubstitutions.swift`) | Implementation |
| **Shells (`Apps/**`)** | `main.swift`, assets (plus generated `Info.plist` / entitlements from `project.yml`) | Any logic; hand-written plists |

## Dependency Chain — Adjacent Layers Only, No Skipping

```text
View → Presenter → Interactor → UseCase → Repository → DataSource/DataStore → Gateway (OS boundary)
```

- **No layer skipping.** An Interactor holding a Gateway, or a UseCase holding
  a DataSource, is a violation even when `@Dependency` makes it a one-liner.
  Thread pass-through contracts through the adjacent layers instead.
- **OS-boundary gateways are consumed at the DataSource layer only.** The
  execution-context ports (`frameExecutor`, `frameScheduler`, `workRunner`,
  live in `DispatchExecutorGateway`) are the exception: the Key-Path table.
- **No UseCase → UseCase.** Shared pure policy lives as sibling pure types
  inside the owning UseCase module.
- **Knowledge placement follows the chain.** Path resolution, manifest
  decoding, source assembly, IPC framing live in DataSources; the layers above
  see only the contract.
- **`make check` enforces two mechanical halves**: the import allow-list per
  layer (`scripts/check-imports.sh`) and the key-path allow-list per layer
  (`scripts/check-dependency-keypaths.sh`: which port kinds a layer may
  resolve through `@Dependency(\.xxx)`). Both tables are below. The judgement
  calls stay in review.

## Import Allow-List (enforced by `scripts/check-imports.sh`)

| Layer | May import |
|---|---|
| Entity | Foundation |
| Domain | Foundation, Combine, Dependencies, Entity |
| UseCase / Repository / DataSource / DataStore / Interactor / Presenters | Foundation, Combine, Dependencies, Domain, Entity |
| Gateway live, Ambient live | the one OS framework the module wraps (+ Foundation, Combine, Dependencies, Domain, Entity) |
| Views / AppRouter | AppKit, SwiftUI, MetalKit (only the preview view files use it; the lint allows it module-wide), Foundation, Combine, Dependencies, Domain, Entity, Presenters; `AppRouter` also takes `Views`, for the views of the windows it opens |
| App / ExtensionApp / DevHarness (composition roots) | the above plus the process's DI target (`HostDependencyInjection` / `ExtensionDependencyInjection`), so the `liveValue` registrations are linked into the shell; `App` also takes the `AppRouter` and `Views` modules of the menu bar; `DevHarness` takes only AppKit and SwiftUI from the row above, plus `Views` (`PreviewView`, `EffectMenu`) and `AppRouter` (its Effects menu) |
| ViewGallery (executable: the app's windows over fixture data) | Foundation, Combine, Dependencies, Domain, Entity, AppKit, SwiftUI, Presenters, `Views` and `AppRouter`; no DI target, so no live value is linked |
| LensTool (executable: the command-line authoring tool) | Foundation, Combine, Dependencies, Domain, Entity, Presenters and `HostDependencyInjection`; no AppKit, SwiftUI or MetalKit |
| DI targets | everything in their process |
| Shells | only their SPM products |

## Key-Path Allow-List (enforced by `scripts/check-dependency-keypaths.sh`)

A key's port kind is the `Sources/Domain/<Kind>/` directory that declares its
`DependencyValues` member, so a new port needs no lint entry (an Ambient one excepted: *Ambient admission*); a module's lane
is derived from its name (the layer suffix, or the entry and view names). Each
lane may resolve the kind of the layer right below it plus Ambient (the ports
under `Sources/Domain/Ambient/` and swift-dependencies' `continuousClock`),
and nothing else. A key outside those kinds is a per-key exception in the
script, each citing the decision it rests on; an exception nothing resolves any
more fails, so the list cannot outlive its reason. The
resolutions are found through the AST — the `@Dependency(...)` attribute in any
layout, and the wrapper's initializer spelled `Dependency(...)`,
`Dependency<T>(...)`, `Dependencies.Dependency(...)` or `Dependency.init(...)` —
so comments and strings never count, and only the plain `\.key` form passes: a
key-path chain, `Key.self`, `\DependencyValues.key` or a second argument fails
instead of slipping through. Not seen: an initializer reached through inference
(`.init(\.key)`) or spelled `Dependency<T>.init(...)`, and `withDependencies`
overrides, which assign rather than resolve.

| Lane (modules) | May resolve | Per-key exceptions |
|---|---|---|
| Entry (`App`, `DevHarness`, `ExtensionApp`, `LensTool`) | Interactor, Ambient; but `App` and `DevHarness` never `effectInteractor` (*Per-key denials* below) | `LensTool` alone: `consoleWriter` — the command-line tool's one exit to standard output and standard error; the host and the extension report through the logs (`AMBIENT`; Physical Abstraction Table: *Standard output / standard error*). `ExtensionApp`: `extensionRelayUseCase` — the extension process has no GUI and so no Interactor lane; its entry point resolves the relay UseCase (Key Design Decisions) |
| View (`Views`, `AppRouter`) | Presenter, Ambient | |
| Presenter (`Presenters`, `*Presenter`) | Interactor, Ambient | |
| `*Interactor` | UseCase, Ambient | |
| `*UseCase` | Repository, Ambient | `frameExecutor`, `frameScheduler`, `workRunner` — the execution context the frame path runs on (Physical Abstraction Table: *Frame execution context*, *Frame pacing*; → *Effect runtime*) |
| `*Repository` | DataSource, DataStore, Ambient | `workRunner` only; never `frameExecutor` or `frameScheduler` (→ *Effect runtime*, epic #14 D14; the decision of #36) |
| `*DataSource` / `*DataStore` | Gateway, Ambient | `GPURenderDataSource`, `PreviewDataSource`: `surfacePool` — leases resolve through the executor-confined pool (→ *One effect, one command buffer*, epic #14 D4; Physical Abstraction Table: *Texture binding*) |
| Everything else (Entity, Domain, Gateway and Ambient lives, DI targets, `ViewGallery`) | nothing | |

**Per-key denials.** The kind rule cannot say "this Interactor and not that one": the Entry lane
resolves Interactors (`cameraInteractor`, `harnessInteractor`, `effectAuthoringInteractor`), yet `App` and `DevHarness` may not
resolve `\.effectInteractor`. That Interactor is started and stopped by `MenuBarPresenter`, and the
Presenter by `AppRouter` alone (`docs/ARCHITECTURE.md` → *Menu bar*): an entry point that started it
too would restart the catalog (`run()` twice, the first state sent twice). A denial is a `DENIALS`
entry in the script, `<module glob> <key> <reason>`, checked before the lane's kinds and before any
exception. A denial that works is never matched by a resolution, so the staleness check is static:
an entry fails when its key is no longer a declared port, when no module matches its glob, or when
the lane of every module matching it already keeps it from the key, so the list cannot outlive its
reason.

## Ambient admission

Ambient is an open layer: every lane may resolve it, because closing it would
add layers that only pass a call down (the architecture sinkhole). That makes
it the one kind the lane rule cannot bound, so the key-path lint holds it to a
closed list instead: a port enters `Sources/Domain/Ambient/` only by a line of
`AMBIENT` in `scripts/check-dependency-keypaths.sh`, and a line may pin its key
to the modules that own it (`consoleWriter LensTool`). A port is Ambient when
it meets all three:

1. **Its contract decides no product behaviour.** It knows nothing of how
   cameras, effects, frames or packages are handled; taking a classification
   label such as `LogSubsystem` is fine. No lint can judge this; review does.
2. **It hands out no resource with a lifetime.** A port that issues a handle is
   a Gateway.
3. **It is time, logging or a fact about the host** that belongs to no one step
   of the chain.

Being used by several lanes is not a criterion: `hostTime` is used by one
UseCase and is still ambient. A port that fails one moves to the kind of the
layer that uses it, as `AppDirectoriesProvider` and `RandomSource` moved to the
Gateway kind (DataSources resolve them). The lint fails when an unlisted port
appears under `Sources/Domain/Ambient/`, when a listed key is no Ambient port,
when a module outside a key's owners resolves it, and when no owner resolves a
listed key any more, so the list cannot outlive its reason.

## Protocol API Design

- Protocols define what consumers need, not the mechanics of one backend.
- Event enums are self-contained; `AsyncStream` ending is the cleanup signal
  (no redundant `.finished`).
- Ports that hand out resources return opaque handles (`SurfaceToken`,
  `MachPortToken`, `LibraryHandle`, `CaptureSessionHandle`, `StreamOutputHandle`,
  `FileWatchHandle`, `HotkeyHandle`) — never OS types.
  A handle is given back through the port that issued it (or, for a handle
  that carries its own `stop()` or `release()`, by its owner), exactly once. Where a
  stale handle can reach the port, it is detected rather than trusted:
  `SurfaceToken` carries a generation for that.

## Testing Constraints

- Never `setenv`; inject through `AppDirectoriesProvider` or constructor
  parameters.
- A window is checked over fixture data by the view gallery (`ViewGallery`,
  run through `scripts/gallery`), which builds the Router (the camera and
  controls menus, which have no window of their own, build their Presenter)
  inside `withDependencies` over the `Gallery*Interactor` fixtures in its own
  process; there is no UI test target, and an in-memory `withDependencies`
  override never crosses a process boundary.
- The extension and the host are never tested through the real Mach boundary
  in `swift test`; the in-process loopback (`InMemoryFrameTransport`) is the
  integration seam and it keeps separate surface pools on each side.
