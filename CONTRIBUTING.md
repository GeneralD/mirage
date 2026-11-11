# Contributing

Thank you for helping. This is a macOS menu-bar app that applies real-time Metal shader effects to your webcam and serves the result to Zoom, Meet, OBS and any other app as a virtual camera. The [README](README.md) says what it does and how an effect is written; this page says how to change the project itself.

## Ways to help

- **Write an effect.** An effect is a `.lens` package and needs no change to the app. Read *Writing an effect* and *Packaging* in the [README](README.md), and start from `Examples/Ripple.lens`.
- **Report a bug or suggest a change.** Open an issue with one of the forms in `.github/ISSUE_TEMPLATE`. The app version, the macOS version and the steps to reproduce are what make a bug fixable.
- **Change the code or the documentation.** Start from an issue, so that the change is specified before it is written: issues are the living spec. If there is none, open one first.

## Set up

You need macOS 14 or later on Apple silicon and Xcode with a Swift 6 toolchain. `make check` uses `sg` (ast-grep) and `jq`, and `make generate` uses `xcodegen`:

```sh
brew install ast-grep jq xcodegen
```

## Build, test and check

```sh
make build             # release build of the app and the Camera Extension
make test              # deterministic suite, no GPU or camera needed
make test-gpu          # Metal smoke tests in their own process (needs a Metal device)
make lint              # swift-format lint, strict
make format            # swift-format in place; run it before you commit
make check             # architecture, naming and boundary guards
swift run dev-harness  # your camera with an effect in a preview window, no virtual camera
```

CI runs the same checks on every pull request. The virtual camera itself (the signed app under `/Applications`, approved once in System Settings) cannot be run from `swift run`; `.claude/rules/dev-verification.md` says how to check it by hand.

## How the code is organised

The app is Clean Architecture with one SwiftPM target per layer slice. A view talks to a presenter, a presenter to an interactor, then use case, repository, data source and gateway, and a layer reaches only the layer right below it. Every hardware, OS, clock, random and file boundary is a port with a fake in `Tests/TestDoubles`. `make check` enforces the import and dependency rules, so most violations fail before review.

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md): the module graph and the reasons behind it
- `.claude/rules/architecture-boundaries.md`: what each layer owns and may import
- `.claude/rules/physical-abstraction.md`: what must be a port
- `.claude/rules/module-checklist.md`: what to touch when you add a module
- `.claude/rules/swift-idioms.md`: Swift style (`let` first, no force unwraps, no actors on the frame path)

The product name appears only in `README.md`, `project.yml` and `Sources/Entity/ProductIdentity.swift`; everywhere else, code and documents use role names.

## Tests

Tests are the specification. They are written with Swift Testing and are deterministic: no fixed sleeps, no wall clock, no `setenv`. The test drives frame flow through the fakes (`ManualFrameExecutor`, `FakeGPUGateway`, `TestClock`). Read `.claude/rules/testing.md` before you write one, and send every change with the tests that would fail without it.

## Git workflow

- Never commit to `main`. Branch, open a pull request against `main`, merge.
- Write each commit as a Conventional Commit with a scope, such as `feat(effect-package): read manifest parameters` or `fix(preview): redraw after a resize`, and keep one logical change per commit.
- Link the issue the pull request completes with a closing keyword (`Closes #123`).
- Every pull request bumps `version.txt`: `feat` is a minor bump, `fix`, `refactor` and `chore` a patch bump, a breaking change a major bump. When a pull request merges to `main`, CI tags the version and publishes a release whose notes are generated from the merged pull requests.
- Run `make format`, `make lint`, `make check` and `make test` before you push. The pull request template (`.github/pull_request_template.md`) lists the rest.

## Documentation

When a command, an architecture boundary or a workflow rule changes, update every document that states it in the same pull request: `AGENTS.md`, `docs/ARCHITECTURE.md` and this page. Search for the words of the old rule, not only the file you edited.

## License

The project is released under the [MIT License](LICENSE).
