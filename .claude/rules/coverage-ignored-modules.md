# Coverage-Ignored Modules: No Implementation Allowed

**Never place production implementation code in modules that are excluded
from code coverage.** Coverage-ignored modules are reserved for wiring,
contracts, stubs and thin OS pass-throughs — putting real logic there lets
bugs hide behind the ignore rule.

The ignore list is `codecov.yml` → `ignore:`. Before adding code to a module,
confirm it is not on that list. If it is, the module may contain only:

- Protocol / `TestDependencyKey` definitions (`Domain`)
- In the three DI targets: `liveValue = Foo()` one-liners, and `DependencyValues`
  extensions (dev-only substitutions) whose members each only assign one value —
  no branch, no `var`, at most 50 lines per file, which `scripts/check-live-thin.sh`
  checks on the listed files (today `DevelopmentSubstitutions.swift`)
- Declarative SwiftUI bodies (`Views`)
- `main.swift` and assets (`Apps/**`; plists and entitlements there are generated)
- A thin-live Gateway (≤ 50 lines per file, no branches, no `var` —
  `scripts/check-live-thin.sh`)

## Correct Pattern

When a Gateway cannot run in CI, keep it thin and move every decision one
layer up into a DataSource that is tested against the fake:

```text
Sources/Domain/Gateway/MachMessageGateway.swift   # ignored — protocol + Unimplemented
Sources/MachGateway/MachMessageGateway+Live.swift  # ignored — thin pass-through
Sources/FrameReceiverDataSource/                   # covered — the receive loop, framing, timeouts
Tests/FrameReceiverDataSourceTests/                # tests against FakeMachMessageGateway
```

## Red Flags

- A coverage-ignored file with an `if`, a loop, a retry or a timeout.
- A PR that moves code into `Domain`, a DI target or a Gateway "to make CI green".
- An `ignore:` entry that is conditional on the environment (GPU present or not).
