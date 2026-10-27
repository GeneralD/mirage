# Module Addition Checklist

When adding a new module (UseCase, Repository, DataSource, Gateway, …):

1. **Package.swift** — add `.target` and `.testTarget` (Gateway modules that
   cannot run in CI get a smoke `.testTarget` gated by `.enabled(if:)`).
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
   no key-path entry (its `Sources/Domain/<Kind>/` directory is its kind); a
   module whose name carries no layer suffix (an entry point, a view or
   presenter module) needs a lane in `scripts/check-dependency-keypaths.sh`,
   and a key outside the lane's kinds is a per-key exception there that cites
   the decision it rests on. The reverse, a key of an allowed kind that one
   module must not resolve, is a per-key denial (`DENIALS`) with its reason.
7. **codecov.yml** — if the module is a CI-unreachable Gateway, add it to
   `ignore` and make it obey the thin-live rule.
8. **Documentation**:
   - `docs/ARCHITECTURE.md` — dependency graph node + edges, Layer Summary
     row, Physical Abstraction Table row (for a port), Key Design Decisions
     entry if the module embodies a decision.
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
