# Module Addition Checklist

When adding a new module (UseCase, Repository, DataSource, Gateway, …):

1. **Package.swift** — add `.target` and `.testTarget` (a Gateway whose smoke
   suite can run on a runner gets a `.testTarget`, even when the module is
   coverage-ignored: `HotkeyGatewayTests` and `LoginItemGatewayTests` only call
   the OS and read a status, `MachGatewayTests` loops back; a Gateway with
   nothing a runner can exercise (`AVFoundationGateway`,
   `SystemExtensionGateway`, `CMIOExtensionGateway`, `WorkspaceGateway`,
   `LogStoreGateway`) gets none; a suite that needs a Metal device lives in
   `GPUSmokeTests`, gated by `.enabled(if: MetalDeviceProbe.isAvailable)`).
2. **Domain** — add the protocol under the matching subdirectory, its
   `TestDependencyKey` (`testValue` = `Unimplemented*`), and the
   `DependencyValues` extension.
3. **Entity** — put any new data type here first; never in Domain.
4. **DI** — register `liveValue` in the right target: `CommonDependencyInjection`
   (both processes), `HostDependencyInjection` or `ExtensionDependencyInjection`.
5. **TestDoubles** — add the fake if more than one suite will use it.
6. **Lint allow-lists** — if the module is a Gateway or Support live, add it
   to `scripts/check-imports.sh` (framework allow) and
   `scripts/check-physical-symbols.sh` (live-module allow). A new port needs
   no key-path entry (its `Sources/Domain/<Kind>/` directory is its kind). A
   module whose name carries no layer suffix (an entry point, a view or
   presenter module) needs its own `allowed_for` case in
   `scripts/check-imports.sh` (without one it may import only Foundation,
   Combine, Dependencies, Domain and Entity) and a lane in `lane_of` of
   `scripts/check-dependency-keypaths.sh` (`LensTool` is `Entry`; a module
   with no lane, such as `ViewGallery`, resolves nothing). A key outside the
   lane's kinds is a per-key exception there that cites the decision it rests
   on. The reverse, a key of an allowed kind that one module must not resolve,
   is a per-key denial (`DENIALS`) with its reason.
   A module reachable from `ExtensionApp` or `ExtensionDependencyInjection`
   must not reach `MetalGateway`, `MetalKitPreviewGateway`,
   `PreviewDataSource` or `Views` (`scripts/check-extension-no-metal.sh`
   walks the package graph).
7. **codecov.yml** — if the module is a CI-unreachable Gateway, add it to
   `ignore` and make it obey the thin-live rule.
8. **Documentation**:
   - `docs/ARCHITECTURE.md` — the node and its edges in its area's diagram
     under *Implementation Modules* (the *Layer Overview* changes only with
     a new lane or a new key-path exception), Layer Summary row, Physical
     Abstraction Table row (for a port), Key Design Decisions entry if the
     module embodies a decision.
   - `AGENTS.md` — update the summary or guardrails when they change.
   - `.claude/CLAUDE.md` — only when Build & Test commands or the layer chain
     itself change.
   - `README.md` — only for user-facing behaviour.
9. **Name check** — the module, its types and files are role-named; the
   product name does not appear (`make check` → `check-product-name.sh`).

## Data Type Placement

- Pure data (structs/enums with no logic) → `Entity`. Domain re-exports it via
  `@_exported import Entity`.
- Never define data types in Domain.
- Pure policy that belongs to one UseCase (health, packing) → a sibling file
  in that UseCase module, not a new module.
