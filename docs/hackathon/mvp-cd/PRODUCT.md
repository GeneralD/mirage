# PRODUCT (pointer file for workers)

Nothing the repository already states is copied here. Read this, then your issue.

## Stack and rules

Swift 6.3 locally, an older toolchain on the `release-build` CI job (macos-15): no language feature
newer than Swift 6.1, no `isolated deinit`. SwiftPM, swift-dependencies, Swift Testing, Combine.

- Layers and what each may import or resolve: `.claude/rules/architecture-boundaries.md`
- Adding a module: `.claude/rules/module-checklist.md`
- Idioms (no force unwraps, immutability, no actors on the frame path): `.claude/rules/swift-idioms.md`
- Tests are deterministic (no sleeps, no wall clock): `.claude/rules/testing.md`, `.claude/rules/gpu-testing.md`
- Coverage-ignored modules hold no logic: `.claude/rules/coverage-ignored-modules.md`
- Physical boundaries are ports: `.claude/rules/physical-abstraction.md`
- Architecture and Key Design Decisions: `docs/ARCHITECTURE.md`
- Parameter contract: `docs/hackathon/mvp-cd/specs/parameters.md`
- Health contract: `docs/hackathon/mvp-cd/specs/health.md`

## Gate (one command, the same for every issue)

```sh
scripts/gate -- swift test --filter <YourSuite>
```

Lint, `make check`, release build, dev-harness build, tests, GPU tests. The known-issue count in
`make test` is 12 on `main`; a new known issue from your code is red. Run `make format` first and
commit what it rewrites.

## Hot files (workers never edit them)

| File | How it changes |
|---|---|
| `version.txt` | Once, in the final PR to `main` |
| `Package.swift` | Only by an issue whose Scope names it; new targets are created together up front |
| `docs/ARCHITECTURE.md`, `AGENTS.md`, `.claude/CLAUDE.md`, `README.md` | Only by the one docs-sync issue before the final PR; a single-line paragraph conflicts whole |
| `codecov.yml`, `scripts/check-*.sh` allow-lists | Only by an issue whose Scope names them |
| `Sources/*DependencyInjection/*.swift` | `merge=union` (`.gitattributes`): add your `liveValue` block; never reorder existing ones |

A code comment that says "until MVP-C" or names a type that did not exist is corrected by the issue
that lands the piece.

## Exemplars (in-repo; your issue's `exemplar:` line wins)

| Kind | Copy the shape of |
|---|---|
| Entity | `Sources/Entity/EffectMenuItem.swift`; decoded from a file: `Sources/Entity/EffectManifest.swift` |
| Port (protocol, key, `Unimplemented*`, `DependencyValues`) | `Sources/Domain/DataStore/Preferences.swift` |
| UseCase | `Sources/EffectCatalogUseCase/` (`EffectCatalogSession.swift`, `EffectCatalogBroadcast.swift`) |
| Pure policy beside a UseCase | `Sources/FramePipelineUseCase/EffectPass.swift` |
| Interactor | `Sources/EffectInteractor/EffectInteractorImpl.swift` |
| Repository | pass-through `Sources/SettingsRepository/SettingsRepositoryImpl.swift`; orchestration `Sources/EffectPackageRepository/EffectPackageRepositoryImpl.swift` |
| DataSource | pure decode `Sources/EffectPackageDataSource/EffectManifestDecoding.swift`; executor-confined state `Sources/EffectRuntimeStateDataSource/EffectRuntimeStateDataSourceImpl.swift` |
| DataStore | `Sources/PreferencesDataStore/PreferencesDataStoreImpl.swift` (an undecodable stored value is logged and ignored) |
| Thin Gateway and its fake | `Sources/UserDefaultsGateway/KeyValueStoreGatewayImpl.swift`, `Tests/TestDoubles/InMemoryKeyValueStore.swift` |
| Presenter, text, geometry | `Sources/Presenters/EffectPickerPresenter.swift`, `EffectPickerText.swift`, `EffectPickerGeometry.swift` |
| Window | `Sources/AppRouter/PickerWindow.swift`, `EffectPickerWindow.swift` |
| GPU smoke | `Tests/GPUSmokeTests/MetalGatewaySmokeTests.swift` |
| Frame path without a device | `Tests/FramePathIntegrationTests/LoopbackRig.swift` |

## Machine budget

10 cores, 64 GB. Workers run at most five at a time, and their gates share 3 slots (`HK_GATE_SLOTS=3`,
set by the detached gate helper; the script's own default is 5); a screenshot is one at a time. A
worker's worktree outlives it when it holds changes, so the orchestrator deletes its `.build` (about
1.2 GiB) once the worker is gone. Never run the dev harness from a worker unless the issue says
so: its camera prompt is modal on the human's screen.

## Verification lanes

| Scenario | Lane |
|---|---|
| Logic | `swift test --filter <Suite>` on fakes |
| GPU behaviour, MSL | `make test-gpu` |
| Whole frame path without a device | `Tests/FramePathIntegrationTests` (`LoopbackRig`) |
| Pixels of a window | the view gallery + `scripts/shot` (see UI check) |
| Real camera, Zoom, device timings, real hangs | Human or VM lane only |

## Depth checklist (what "done" means per feature)

Error handling, empty and loading states, boundary values, accessibility labels, developer-log lines,
a named reason for every failure the user can see. All user-visible wording lives in pure text types
(`MenuBarText`, `EffectPickerText`) and is tested.

## UI check

```sh
scripts/shot <out.png> --title <window title>     # exit 1 when no such window is on screen
scripts/shot <out.png> --list
```

Read the image yourself: overlaps, clipping, overflow, controls off-screen. A UI PR commits
`docs/shots/<issue>/after.png` and embeds it. Windows are opened with fixture data by the view
gallery (arrives with the first UI issue), never through the camera path.

While the screen is locked (`ioreg -n Root -d1 | grep -q '"CGSSessionScreenIsLocked"=Yes'` exits 0), no window can be captured
(`could not create image from window`). A UI PR then lands on a green gate with the line
`Shot: pending (screen locked)`, and its issue carries the label `hk:shot-pending`. Once the screen is
unlocked the orchestrator captures and reads every pending screen; a visual defect becomes a regen issue.

## External services

None. Sparkle, Homebrew and notarization wait for Apple Developer signing (#3).

## Off-limits

- `main`. Every PR targets `hackathon/mvp-cd`.
- The extension process's no-Metal rule (`scripts/check-extension-no-metal.sh`).
- Anything that adds an actor, a lock or an allocation per frame to the frame path.
- The product name outside its three files (`scripts/check-product-name.sh`).

## House style

Rules born during the run land here with their issue number.
