# Architecture Boundaries

## Layer Responsibilities

| Layer | Owns | Never |
|---|---|---|
| **Entity** | Pure data types, enums, Codable structs, `ProductIdentity` constants | Logic; imports beyond Foundation |
| **Domain** | Protocols, `TestDependencyKey`s, `Unimplemented*` | Data type definitions; imports beyond Foundation, Combine (Interactor streams) and Dependencies |
| **UseCase** | Business logic, pure policy types (`EffectHealthPolicy`, `ParameterPacker`) | Another UseCase; a DataSource or Gateway; locks; OS frameworks |
| **Repository** | Orchestration of DataSources/DataStores, cache strategy, surface lifetime (`SurfaceRepository`) | Gateways; the `FrameExecutor`; OS frameworks |
| **DataSource / DataStore** | Real work against Gateways plus persistence-shaped knowledge (paths, manifests, source assembly, IPC state machines, receive loops, pool bookkeeping, the effect runtime's executor-confined state) | Business policy; OS frameworks (those stay in the Gateway) |
| **Gateway** | 1:1 thin pass-through to one OS API | Branching, timing, ordering, retries, loops — anything that needs a test |
| **Support** | Cross-cutting seams (random, log, host time, app directories) | Business logic |
| **Presenter** | `@Published` display state | AppKit / SwiftUI / MetalKit imports; business logic |
| **Views / Router / App** | Declarative rendering, wiring, lifecycle | Business logic; direct UseCase/Gateway access |
| **DI targets** | `liveValue` registrations, and dev-only `DependencyValues` extensions whose members each only assign one value (no branch, no `var`; `scripts/check-live-thin.sh` checks `DevelopmentSubstitutions.swift`) | Implementation |
| **Shells (`Apps/**`)** | `main.swift`, assets (plus generated `Info.plist` / entitlements from `project.yml`) | Any logic; hand-written plists |

## Dependency Chain — Adjacent Layers Only, No Skipping

```text
View → Presenter → Interactor → UseCase → Repository → DataSource/DataStore → Gateway (OS boundary)
```

- **No layer skipping.** An Interactor holding a Gateway, or a UseCase holding
  a DataSource, is a violation even when `@Dependency` makes it a one-liner.
  Thread pass-through contracts through the adjacent layers instead.
- **OS-boundary gateways are consumed at the DataSource layer only.**
- **No UseCase → UseCase.** Shared pure policy lives as sibling pure types
  inside the owning UseCase module.
- **Knowledge placement follows the chain.** Path resolution, manifest
  decoding, source assembly, IPC framing live in DataSources; the layers above
  see only the contract.
- **`make check` enforces two mechanical halves**: the import allow-list per
  layer, and the `@Dependency(\.xxx)` key-path allow-list per layer (which port
  kinds a layer may resolve). The judgement calls stay in review.

## Import Allow-List (enforced by `scripts/check-imports.sh`)

| Layer | May import |
|---|---|
| Entity | Foundation |
| Domain | Foundation, Combine, Dependencies, Entity |
| UseCase / Repository / DataSource / DataStore / Interactor / Presenters / Support (non-live) | Foundation, Combine, Dependencies, Domain |
| Gateway live, Support live | the one OS framework the module wraps (+ Foundation, Dependencies, Domain) |
| Views / AppRouter | AppKit, SwiftUI, MetalKit (preview view only), Dependencies, Domain, Presenters |
| App / ExtensionApp / DevHarness (composition roots) | the above plus the process's DI target (`HostDependencyInjection` / `ExtensionDependencyInjection`), so the `liveValue` registrations are linked into the shell; `DevHarness` takes only AppKit and SwiftUI from the row above, plus `Views` for `PreviewView` |
| DI targets | everything in their process |
| Shells | only their SPM products |

## Protocol API Design

- Protocols define what consumers need, not the mechanics of one backend.
- Event enums are self-contained; `AsyncStream` ending is the cleanup signal
  (no redundant `.finished`).
- Ports that hand out resources return opaque handles (`SurfaceToken`,
  `MachPortToken`, `LibraryHandle`, `CaptureSessionHandle`, `StreamOutputHandle`)
  — never OS types.
  A handle is given back through the port that issued it (or, for a handle
  that carries its own `stop()`, stopped by its owner), exactly once. Where a
  stale handle can reach the port, it is detected rather than trusted:
  `SurfaceToken` carries a generation for that.

## Testing Constraints

- Never `setenv`; inject through `AppDirectoriesProvider` or constructor
  parameters.
- UI tests select a fixture graph at app bootstrap (`#if DEBUG`,
  `AppRouter`); in-memory `withDependencies` overrides do not cross the process
  boundary.
- The extension and the host are never tested through the real Mach boundary
  in `swift test`; the in-process loopback (`InMemoryFrameTransport`) is the
  integration seam and it keeps separate surface pools on each side.
