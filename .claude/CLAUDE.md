# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Keep the repository root `AGENTS.md` in sync when build/test commands,
architecture boundaries, or workflow rules change. Codex uses `AGENTS.md` as
its project entrypoint, while this file holds the long-form conventions and
workflow reference. The architecture design — module dependency graph, layer
tables, physical-abstraction table, and Key Design Decisions — lives in
`docs/ARCHITECTURE.md`; keep it in sync when modules or architecture change.

## Build & Test

```sh
make build                 # release build of App + ExtensionApp (never a bare `swift build`; SwiftPM still compiles every non-test target, dev-harness included)
make build-dev-harness     # debug build of the dev-harness product (what `swift run dev-harness` runs; not shipped); always relinks, so a plist edit lands
make test                  # swift test (parallel, no GPU)
make test-gpu              # GPU smoke suites in their own process (needs a Metal device; CI runs it as the `test-gpu` job)
make lint                  # swift-format lint --strict
make format                # swift-format --in-place
make check                 # import-boundary lint, physical-symbol lint, thin-live check, service-name check, product-name check, extension-no-Metal check
make generate              # xcodegen → *.xcodeproj (gitignored thin shell for the .app + Camera Extension)
swift run dev-harness      # camera prompt, then camera → effect → preview window, no virtual camera (the virtual camera sink is discarding)
```

The System Extension (virtual camera) cannot be exercised from `swift run`;
install the signed `.app` under `/Applications` and follow
`.claude/rules/dev-verification.md`.

## Architecture

macOS menu-bar app that applies real-time Metal shader effects to a webcam
and serves the result to any app (Zoom, Meet, OBS…) as a virtual camera
(CoreMediaIO Camera Extension). Effects are `.lens` packages loaded at
runtime — never compiled into the app — so the community can author and share
them. Clean Architecture in the lyra style: one SwiftPM target per layer
slice, implementation targets depend on `Domain` only, DI resolved with
swift-dependencies.

```text
View → Presenter → Interactor → UseCase → Repository → DataSource/DataStore → Gateway (OS boundary)
                 → Router (wireframe only)
```

The host app and the Camera Extension are two processes; each has exactly
one DI wiring point (`HostDependencyInjection`, `ExtensionDependencyInjection`)
on top of `CommonDependencyInjection`.

> **Full architecture reference → [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md).**
> The module dependency graph, the layer/module table, the **physical
> abstraction table** (every OS/hardware/time/random/file boundary and its
> port, live module and test double), and the per-decision **Key Design
> Decisions** live there — read it before making architectural changes. The
> **enforceable** layer boundaries are in
> `.claude/rules/architecture-boundaries.md`; the physical-boundary rule is in
> `.claude/rules/physical-abstraction.md`.

### Non-negotiables (summary)

- **Every physical element is a port.** Camera, GPU, shader compiler,
  IOSurface, Mach ports, System Extension, CMIO stream, files, file watch,
  clock, host time, randomness, UserDefaults, logging, process execution,
  display link. Nothing above the Gateway layer imports AVFoundation, Metal,
  IOSurface, CoreMediaIO, SystemExtensions, AppKit or MetalKit.
- **Tests are deterministic.** No fixed `Task.sleep`, no `setenv`, no wall
  clock. Frame flow is driven by `ManualFrameExecutor.drain()` and
  `tick()`; time by `TestClock`; GPU completion by `FakeGPUGateway`.
  See `.claude/rules/testing.md`.
- **The product name lives in three places only** (`README.md`,
  `project.yml`, `Sources/Entity/ProductIdentity.swift`). Module, target,
  type and file names are role names (`App`, `CameraExtension`,
  `FramePipelineUseCase`), never prefixed with the product name — the name
  may change. See `docs/ARCHITECTURE.md` → *Rename-safe naming*.
- **Shells stay thin.** `Apps/**` holds only `main.swift` and assets; all
  logic is in SPM targets. `Info.plist` and entitlements are xcodegen output
  from `project.yml` (gitignored), never hand-written. The one exception is
  `Tools/DevHarness/Info.plist`: the dev harness is a SwiftPM executable
  xcodegen never builds, so its plist is hand-written, role-named and linked
  into the binary (`-sectcreate`).

### Testing Guidelines

The lyra TestSupport primitives are used verbatim — `settle`, `Collector`,
`tickUntil`, `pollUntil`, `suspendUntilCancelled` — plus the frame-flow
primitives added here (`ManualFrameExecutor`, `FakeGPUGateway` manual
completion, seed-driven `forAll`). The rules and the reasoning are in
`.claude/rules/testing.md`; GPU-touching suites are governed by
`.claude/rules/gpu-testing.md`.

**Domain imports.** `Entity` and `Domain` may import Foundation (lyra's
"no Foundation" rule is not carried over — see Key Design Decisions). OS
frameworks are forbidden everywhere except Gateway modules and the
View/Router/App lane; `make check` enforces it.

**View testing strategy**: SwiftUI view bodies are not unit-tested. Display
logic lives in Presenters.

### Git Workflow

**Never commit directly to main.** Branch → PR → merge, Conventional
Commits, one logical change per commit. Issues are the living spec: a
feature is specified in its issue before work starts and the issue closes
via the PR.

### Version Management

`version.txt` at the repository root is the single source of truth. CI reads
it to auto-create tags on push to main. Every PR includes a version bump
(`feat:` → minor, `fix:`/`refactor:`/`chore:` → patch, breaking → major).

## Language

- Conversation with the user: Japanese.
- Repository documentation, code identifiers and comments: English (as in lyra).
- GitHub issues and PRs: Japanese is fine.
