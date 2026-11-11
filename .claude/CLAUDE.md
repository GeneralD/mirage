# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Keep the repository root `AGENTS.md` in sync when build/test commands,
architecture boundaries, or workflow rules change. Codex uses `AGENTS.md` as
its project entrypoint, while this file holds the long-form conventions and
workflow reference. The architecture design — module dependency graph, layer
tables, physical-abstraction table, and Key Design Decisions — lives in
`docs/ARCHITECTURE.md`; keep it in sync when modules or architecture change.

Contributor-facing guides: `CONTRIBUTING.md` (setup, checks, commits, PRs) and
`docs/authoring/` (`first-effect.md`, `parameters.md`: writing a `.lens`
package, its manifest and its `parameters`).

## Build & Test

```sh
make build                 # release build of App + ExtensionApp (never a bare `swift build`; SwiftPM still compiles every non-test target, dev-harness, view-gallery and lens-tool included)
make build-dev-harness     # debug build of the dev-harness product (what `swift run dev-harness` runs; not shipped); always relinks, so a plist edit lands
make test                  # swift test (parallel, no GPU)
make test-gpu              # GPU smoke suites in their own process (needs a Metal device; CI runs it as the `test-gpu` job)
make lint                  # swift-format lint --strict
make format                # swift-format --in-place
make check                 # import-boundary lint, dependency key-path lint, physical-symbol lint, thin-live check, shell-thin check, service-name check, product-name check, extension-no-Metal check, dev-substitution check, live-owner check
make generate              # xcodegen → *.xcodeproj (gitignored thin shell for the .app + Camera Extension)
swift run dev-harness      # camera prompt, then camera → effect → preview window, no virtual camera (the virtual camera sink is discarding)
swift run view-gallery <screen>   # one of the app's own windows over fixture data; no camera, no capture path; `--list` names the screens (not shipped)
scripts/gallery <screen> <out.png>   # build view-gallery, capture that screen's window to a PNG, quit it; `scripts/gallery --list` prints the screen names
scripts/shot <out.png>     # screenshot one window (the dev harness by default; `--owner`, `--title`, `--pid`, `--list`); the terminal needs Screen Recording
swift run lens-tool new <name> [--in <folder>]                          # scaffold a `.lens` package (not shipped)
swift run lens-tool validate <package>                                  # validate a `.lens` package
swift run lens-tool render <effect> --input <in.png> --output <out.png>   # run an effect over a still image; <effect> is a `.lens` path or a bundled effect name
scripts/gate               # lint, check, build, build-dev-harness, test and test-gpu behind a slot shared by every worktree of the checkout (what a worker runs before a push)
```

The System Extension (virtual camera) cannot be exercised from `swift run`;
install the signed `.app` under `/Applications` and follow
`.claude/rules/dev-verification.md`.

## Architecture

macOS menu-bar app that applies real-time Metal shader effects to a webcam
and serves the result to any app (Zoom, Meet, OBS…) as a virtual camera
(CoreMediaIO Camera Extension). Effects are `.lens` packages loaded at
runtime, so the community can author and share them; the four bundled effects
are the exception, compiled into the app as string constants
(`BundledEffectDataSource`). Clean Architecture in the lyra style: one SwiftPM target per layer
slice, implementation targets depend on `Domain` only, DI resolved with
swift-dependencies.

```text
View → Presenter → Interactor → UseCase → Repository → DataSource/DataStore → Gateway (OS boundary)
                 → Router (wireframe; plus the picker's thumbnail decode, see `architecture-boundaries.md`)
```

The host app and the Camera Extension are two processes; each has exactly
one DI wiring point (`HostDependencyInjection`, `ExtensionDependencyInjection`)
on top of `CommonDependencyInjection`.

Three executables are not shipped: `DevHarness` (`swift run dev-harness`) runs
the host's live graph with a discarding sink, `ViewGallery` (`swift run
view-gallery`) opens the app's own windows over fixture Interactors and never
touches the capture path, and `LensTool` (`swift run lens-tool`) is the `.lens`
authoring command line over the host's live registrations. `make check` bounds
their imports and key paths like any other entry point (`ViewGallery` imports
the view lane's modules and resolves nothing, `LensTool` is in the Entry lane).

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
  image decode and encode, global hotkeys, login item, log store, clock, host
  time, randomness, UserDefaults, logging, standard streams, display link, the
  host's app and macOS versions (the full list is the *Physical Abstraction
  Table* in `docs/ARCHITECTURE.md`). Outside the Gateway modules and the
  View/Router/App lane, nothing imports an OS framework (AVFoundation, Metal,
  MetalKit, IOSurface, CoreMediaIO, CoreMedia, CoreVideo, SystemExtensions,
  AppKit, ImageIO, CoreGraphics, Carbon, ServiceManagement, OSLog, os);
  `scripts/check-imports.sh` holds the allow-list per module.
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

Documents are held to the code by suites that read the repository from
`#filePath` and write nothing. Those under
`Tests/TestSupportTests/RepositoryDocs/` use `repositoryText` / `repositoryHas` /
`repositoryRoot` (`Tests/TestSupport/RepositoryFile.swift`): a `Makefile`
target or repository path that `CONTRIBUTING.md` or the PR template names in
backticks must exist (`DocumentReferences`), the PR template, the issue forms
and the release workflow keep their shape, and `StaleStatementTests` fails when
a comment or rule document repeats a sentence the code has made untrue.
`ParametersDocTests` and `FirstEffectDocTests` read the fenced blocks of
`docs/authoring/` through `MarkdownFences` (`Tests/TestSupport/MarkdownFences.swift`:
a document's fenced blocks and their attributes, such as `file=`) and hold each
fact a guide states to the code. Run `make test` after editing a guide.

**Domain imports.** `Entity` and `Domain` may import Foundation (lyra's
"no Foundation" rule is not carried over — see Key Design Decisions). OS
frameworks are forbidden everywhere except Gateway modules and the
View/Router/App lane; `make check` enforces it.

**View testing strategy**: SwiftUI view bodies are not unit-tested. Display
logic lives in Presenters.

### Git Workflow

**Never commit directly to main.** Branch → PR → merge, Conventional
Commits with a scope (`feat(effect-package): read manifest parameters`), one
logical change per commit. Issues are the living spec: a feature is specified
in its issue before work starts and the issue closes via the PR. Open the PR
from `.github/pull_request_template.md`: a `Closes #N` line, the checks list
and, for anything that shows in a window or the menu, a screenshot
(`scripts/gallery` makes one without a camera). `CONTRIBUTING.md` has the
full flow.

### Version Management

`version.txt` at the repository root is the single source of truth. CI reads
it to auto-create a tag on push to main, and a GitHub release for the tag with
notes generated from the pull requests merged since the previous tag
(`.github/workflows/auto-tag.yml`). Every PR includes a version bump
(`feat:` → minor, `fix:`/`refactor:`/`chore:` → patch, breaking → major).

## Language

- Conversation with the user: Japanese.
- Repository documentation, code identifiers and comments: English (as in lyra).
- GitHub issues and PRs: Japanese is fine.
