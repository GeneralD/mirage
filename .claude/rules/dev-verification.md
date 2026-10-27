---
paths:
  - "**/*.swift"
  - "**/Package.swift"
  - "project.yml"
  - "Apps/**"
---

# Dev Verification — What `swift run` Cannot Show

Three lanes, by what is being verified.

## Lane 1 — camera → effect → preview (no extension): `swift run dev-harness`

`DevHarness` links `Tools/DevHarness/Info.plist` into its binary
(`-sectcreate __TEXT __info_plist`) so the camera prompt has a usage string
and a stable bundle identifier (`com.generald.dev-harness`). It runs the host's
real pipeline — camera → `FramePipelineUseCase` → the real effect runtime with
the bundled effect (`Chromatic Grain`) → the preview window — with one
substitution: the virtual camera sink is `DiscardingVirtualCameraSink`
(`HarnessSession.live()`), which accepts every frame and sends it nowhere.
That type is for the harness only (no extension exists to send to); the host
app keeps the real sink. The harness shows nothing about the Camera Extension
(Mach, the stream, the slate): that is Lane 2. Build it with
`make build-dev-harness`, never `swift build` alone, after editing the plist:
SwiftPM does not see the plist as a link input, and the make target relinks.

The automated twin of this lane is `Tests/FramePathIntegrationTests`
(`RealEffectRuntimeIntegrationTests`): the same effect runtime and DataSources
over the fake GPU layer. What only the device adds is the Metal compile, the
command buffer, the camera and the screen.

Not yet run on a device: the camera prompt is a modal dialog on the user's
screen, so drive it yourself only when the user is at the machine. The numbers
below are budgets (issue #24), not measurements; record what you see next to
them once a run exists.

```sh
make build-dev-harness
swift run dev-harness
log stream --level debug --style compact --predicate 'subsystem == "<log subsystem>"'   # second terminal; <log subsystem> is ProductIdentity.logSubsystem
# --level debug is required: the authorization, started, attached, compiled and
# per-second summary lines are debug-level; only the failures are error-level.
```

| Check | Expected (log lines are `category: message`) |
|---|---|
| Camera prompt | on the first run, a camera dialog naming the harness (bundle `com.generald.dev-harness`) or the terminal app. Then these three lines appear, `preview window attached` in no fixed place (it may come first, because the window's view attaches independently of the camera prompt): `camera: camera authorization: authorized`, then `pipeline: pipeline started`, and `preview: preview window attached`. Anything but `authorized` is followed by a `camera access not granted (…)` error line and no pipeline. A granted camera that cannot start gives `pipeline: pipeline failed to start: …` instead of `pipeline started` |
| Window | a 1280 × 720 window titled "Dev Harness" showing the live camera with the effect applied: colour fringing at the edges and moving grain, visible for 30 s. Plain camera video means the effect did not run (see the broken-source row); black or empty means the frame never reached a drawable: look for `preview window not attached`, `frame not shown`, `preview detached, its kernel did not compile (…)` and `preview draw failed: …` lines |
| Effects menu | the main menu bar has an Effects menu (macOS 14.4+; an older system has none): `Chromatic Grain` first, with a check mark, then a divider, `Open Effects Folder…`, a divider and `Quit <display name>`. With no `.lens` package installed it is the only effect row. Choosing `Chromatic Grain` again is a no-op: it stays checked and the window does not change. `Open Effects Folder…` opens the effects folder in Finder (`~/Library/Application Support/<host bundle id>/Effects`: the host's folder, which the harness shares). With a package in that folder its row appears, below the bundled effect, with its author as the second line; choosing it moves the check mark and the window shows its effect; a package that failed to load is a disabled row whose second line says why; when the chosen effect fails to run, a disabled line `<name>: <why>` (for example `compile failed`) sits between the first divider and `Open Effects Folder…` |
| Effect | once, `effect: effect 'Chromatic Grain' compiled`; no `did not compile` line. Then every second `effect: applied=<n> failed=0 capDropped=<n>`, with `applied` rising by about the frame rate |
| Rate | every second `pipeline: frames=<sent> received=<n> dropped=<n> maxGapMs=<ms> slate=0`. The counters are cumulative: `received` rises by at least 25 per second, and `dropped` stays at or below 5% of `received` over the run. `frames` follows `received` (the discarding sink reports every send as sent). `slate` stays 0 here. `frames` stuck at 0 while `dropped` tracks `received` means the pipeline kept the real sink (it answers `.dropped(.notConnected)`): the harness's sink substitution did not reach it (`HarnessLiveWiringTests` is meant to catch that before a device does). A few frames dropped as `capDropped` while the first pass waits on the compile are normal |
| Broken source | local build only, never committed: break the bundled shader source (for example misspell a type name in `Sources/BundledEffectDataSource/ChromaticGrainEffect.swift`), `make build-dev-harness`, run. Expect exactly one error line `effect: effect 'Chromatic Grain' did not compile: …` (not one per frame), the **plain camera video** in the window with no fringing or grain, the per-second effect line showing `applied=0` with `compileFailed=<n>` rising, and `frames` in the pipeline line still rising with `received`. Then revert the edit |
| Occluded window | cover the window or move it to another Space for a while: `pipeline:` summary lines further apart than a second mean `nextDrawable` blocked the frame executor (`docs/ARCHITECTURE.md` → *Preview*); record what you see |
| Quit | ⌘Q or closing the window ends the process |

**When TCC ignores the linked plist.** A process started from a terminal is
attributed to the terminal app (its "responsible process"), so the prompt may
name the terminal instead of the harness, or no prompt may appear and the
status comes back `denied`. Then:

1. System Settings → Privacy & Security → Camera: turn the terminal app on
   (Terminal, iTerm2, Ghostty, …), quit and reopen it, and run the harness again.
2. To see the prompt again, reset the decision for whichever identity was
   recorded: `tccutil reset Camera com.generald.dev-harness` and/or
   `tccutil reset Camera <terminal bundle id>` (e.g. `com.apple.Terminal`).
3. Record which identity the dialog named, and whether granting the terminal
   was required, in the PR that ran the check so this section can state it as fact.

## Lane 2 — the virtual camera (extension): signed `.app` under `/Applications`

A Camera Extension activates only from an app located under `/Applications`,
signed consistently with its embedded extension, after the user approves it
in System Settings → Privacy & Security. Drive this cycle yourself when the
user wants to see the camera in Zoom/Meet/QuickTime:

```sh
make generate                                        # xcodegen → project
xcodebuild -scheme Host -configuration Debug build DEVELOPMENT_TEAM=<team id>   # the team is not in project.yml; the two Apple Development profiles (#3) must exist
# copy the built .app to /Applications (replace the previous copy)
open -a "<the app>"                                  # triggers OSSystemExtensionRequest
systemextensionsctl list                             # expect: [activated enabled] for the extension bundle id
# then pick the virtual camera in QuickTime Player → New Movie Recording (fastest smoke), or Zoom/Meet
```

Guardrails:

- Replace, never stack: an older copy of the `.app` elsewhere makes
  `systemextensionsctl` report the stale one. Remove it first.
- Approval is the user's click; never script System Settings.
- `systemextensionsctl developer on` may require SIP off; confirm on the
  machine before relying on it (open question in `docs/ARCHITECTURE.md`).
- After verification, leave the machine as found: `systemextensionsctl
  uninstall <team> <bundle id>` if the user does not want the extension to
  stay.

### M0-c acceptance — host loss, slate and reconnect (pending the profiles of issue #3)

Not yet run on a device: the signed build needs the profiles of issue #3, and
the timings below are the budgets of issue #6, not measurements. With the
camera selected in QuickTime Player (or Zoom) and frames flowing, stream the
logs of both processes (subsystem from `ProductIdentity`):

```sh
log stream --level debug --style compact --predicate 'subsystem == "<log subsystem>"'
# extension: process = the Camera Extension; host: process = the app
# --level debug is required: only `host lost` and `destination lost` are error-level,
# the slate, hello, connect and summary lines are debug-level and hidden otherwise.
```

| Step | Action | Expected lines (grep) | Budget |
|---|---|---|---|
| 1. Baseline | nothing | extension `frames=… received=… dropped=… maxGapMs=… slate=0`; host `connected to port` | — |
| 2. Host killed | `kill -9 <host pid>` | extension `host lost: .*deadName` (kernel destroys the presence right) or, as backstop, `host lost: .*frameGap`; then `slate entered base=` (debug); the client shows black. The summary line is printed per second of *real* frames only, so no `slate=` line appears while the host is away | black frames within 1.25 × frameGap (2.5 s at the default 2 s gap); target well under 3 s |
| 3. Host stalled | `kill -STOP <host pid>` | only `host lost: .*frameGap` (the presence right stays alive); `slate entered base=` | same budget |
| 4. Host resumed | `kill -CONT <host pid>` | `slate left`; the first summary line after the resume shows the accumulated `slate=<n>`, which stays constant afterwards; picture back in the client without a restart (real PTS is re-timed above the slate, so frames are not dropped for a late capture time) | next frame after resume |
| 5. Host relaunched | relaunch the app after step 2 | host `connected to port` (the extension stayed alive, so the first look-up normally succeeds; `look-up attempt <n> failed` appears only if it is not checked in); extension `hello received, watching presence right`; `slate left` | reconnect within a few seconds (backoff is 250 ms doubling to 5 s) |
| 6. Extension gone | kill the extension process (`pkill -f <extension process name>`); expectation, not yet verified on a device | host `destination lost, port <n> released` (error), then `look-up attempt <n> failed` lines (debug) until the extension is back, then `connected to port`; no host restart needed | — |
| 7. Client first | quit the host app, then open the virtual camera in the client (QuickTime/Zoom) before launching the host | extension `host lost: .*frameGap` (no frame ever arrived); `slate entered base=`; then after launching the app `hello received, watching presence right` and `slate left` | black frames within 1.25 × frameGap of the extension starting (2.5 s at the default gap), then the picture on host launch |

Record the measured times next to the budgets once they exist; until then do
not claim which detector fired for step 2 — the log line tells (`deadName` vs
`frameGap`). `host lost: …` is the error-log copy of the same event.

## Lane 3 — destructive GPU scenarios: VM only

Infinite-loop / out-of-bounds shaders, `accessRevoked` recovery, and anything
that can wedge the GPU run only in a UTM macOS guest (see the `utm-macos-vm`
skill). Never on the developer's machine, never in CI.
