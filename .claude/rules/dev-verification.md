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
(`RealEffectRuntimeIntegrationTests`, and `EffectCatalogIntegrationTests` for the
effects menu): the same effect runtime, DataSources and catalog over the fake GPU
layer and an in-memory effects folder. What only the device adds is the Metal compile, the
command buffer, the camera and the screen.

Not yet run on a device: the camera prompt is a modal dialog on the user's
screen, so drive it yourself only when the user is at the machine. The numbers
below are budgets (issue #24), not measurements; record what you see next to
them once a run exists. The effects menu has its own timed table below (*Effects menu: the timed run*).

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
| Effects menu | the main menu bar has an Effects menu (macOS 14.4+; an older system has none): `Chromatic Grain` first, with a check mark, then a divider, `Browse Effects…`, `Open Effects Folder…`, a divider and `Quit <display name>`. With no `.lens` package installed it is the only effect row. Choosing `Chromatic Grain` again changes nothing you can see: it stays checked and the window does not change (the catalog prepares the same source once more, a compile-cache hit, and logs `effect: effect 'Chromatic Grain' selected`). `Open Effects Folder…` opens the effects folder in Finder (`~/Library/Application Support/<host bundle id>/Effects`: the host's folder, which the harness shares). With a package in that folder its row appears, below the bundled effect, with its author as the second line where the system draws one (macOS 15 and later; on 14.x it may be missing, a known limit: see the note on step 8 below); choosing it moves the check mark and the window shows its effect; a package that failed to load is a disabled row whose second line says why (the same limit; the reason is then in the log); when the chosen effect fails to run, a disabled line `<name>: <why>` (for example `compile failed`) sits between the first divider and `Browse Effects…` |
| Effect picker | `Browse Effects…` opens a window titled "Effects" in front: a search field over a grid of square cells, one per row of the menu and in its order, each showing the package's thumbnail, or a coloured tile with the effect's initials when it has none (`Chromatic Grain`, a package whose manifest names no thumbnail or one that cannot be used) or the picture does not decode, then its name and the row's second line. With `Examples/Ripple.lens` in the effects folder, its cell shows the swaying stripes of its `thumbnail.png`; replace that file with a text file that begins with the PNG signature and it shows its tile, not an empty square. The chosen cell has an accent border and is the menu's checked row; choosing another cell moves the border and the menu's check mark together and the preview window shows its effect, as choosing the row does. A package that failed to load is a dimmed cell that cannot be clicked. Hovering a cell shows its name and author and, on a line after them, the manifest's `description` when it has one (the Ripple example does), or why it cannot be chosen. Typing in the search narrows the cells to the names and authors that contain it, ignoring case and accents; a search nothing matches says `No effects match “<search>”`. Widening the window adds columns. `Browse Effects…` again while it is open brings the same window forward, not a second one. Closing it (red button) leaves the harness running; reopening starts with an empty search |
| Effect | once, `effect: effect 'Chromatic Grain' compiled`; no `did not compile` line. Then every second `effect: applied=<n> failed=0 capDropped=<n>`, with `applied` rising by about the frame rate |
| Rate | every second `pipeline: frames=<sent> received=<n> dropped=<n> maxGapMs=<ms> slate=0`. The counters are cumulative: `received` rises by at least 25 per second, and `dropped` stays at or below 5% of `received` over the run. `frames` follows `received` (the discarding sink reports every send as sent). `slate` stays 0 here. `frames` stuck at 0 while `dropped` tracks `received` means the pipeline kept the real sink (it answers `.dropped(.notConnected)`): the harness's sink substitution did not reach it (`HarnessLiveWiringTests` is meant to catch that before a device does). A few frames dropped as `capDropped` while the first pass waits on the compile are normal |
| Broken source | local build only, never committed: break the bundled shader source (for example misspell a type name in `Sources/BundledEffectDataSource/ChromaticGrainEffect.swift`), `make build-dev-harness`, run. Expect exactly one error line `effect: effect 'Chromatic Grain' did not compile: …` (not one per frame), the **plain camera video** in the window with no fringing or grain, the per-second effect line showing `applied=0` with `compileFailed=<n>` rising, and `frames` in the pipeline line still rising with `received`. Then revert the edit |
| Occluded window | cover the window or move it to another Space for a while: `pipeline:` summary lines further apart than a second mean `nextDrawable` blocked the frame executor (`docs/ARCHITECTURE.md` → *Preview*); record what you see |
| Quit | ⌘Q or closing the preview window ends the process, with the effect picker open or not |

### Effects menu: the timed run (issue #52, epic #42)

Not yet run on a device: a budget below is a target of epic #42 (a step whose budget says
*none* has no target, only something to record), not a measurement, and
the last column says **not yet run** until someone does the run. Do not fill it from the
automated twin (`EffectCatalogIntegrationTests` proves the order of events and the 200 ms quiet
period under a fake clock; it cannot say how long a Metal compile or a window takes). Run it with
the user at the machine, on top of the table above (camera granted, harness running, Effects menu
open at least once). The effects folder is the one *Open Effects Folder…* shows
(`~/Library/Application Support/<host bundle id>/Effects`); `<folder>` below is that path. Time each
step from the action to the window changing, with a screen recording or the `effect:` log lines
(`--level debug`), and write the number, the OS version and the Mac in the last column.

| Step | Action | Expected | Budget | Measured |
|---|---|---|---|---|
| 1. List | open the Effects menu with `<folder>` empty or absent; then `cp -R Examples/Ripple.lens "<folder>/"` and open the menu again | first: `Chromatic Grain` alone, checked. After the copy: `Ripple` below it, unchecked, `Chromatic Grain` still checked and the window unchanged | the row is there within 1 s of the copy (step 5's budget) | not yet run |
| 2. Choose | choose `Ripple` | the check mark moves; the window shows Ripple's sideways sway (a smooth wave down the frame) instead of the fringing and grain; `effect: effect 'Ripple' compiled` appears once | the window changes within 1 s of the click, with one compile | not yet run |
| 3. Save | change a constant in `<folder>/Ripple.lens/effect.metal` (the sway amplitude, say) and save | the window shows the change without touching the menu; `effect: effect 'Ripple' compiled` again, once | within 1 s of the save (200 ms quiet period plus the compile) | not yet run |
| 4. Break and fix | misspell a type name in that `effect.metal` and save; then undo the misspelling and save | broken: the window shows the plain camera video, a disabled line `Ripple: compile failed` sits between the first divider and *Browse Effects…*, exactly one `effect: effect 'Ripple' did not compile: …` error line. Fixed: the effect is back and the line is gone | each save within 1 s | not yet run |
| 5. Add and remove | `cp -R Examples/Ripple.lens /tmp/Second.lens`, change `name` in `/tmp/Second.lens/manifest.json` to `Second` (a row is titled by the manifest's name, not its folder), `mv /tmp/Second.lens "<folder>/"`, then `rm -r "<folder>/Second.lens"`. Then move the *chosen* package out, `mv "<folder>/Ripple.lens" /tmp/`, and back, `mv /tmp/Ripple.lens "<folder>/"` | a `Second` row appears below `Ripple`, then disappears. With `Ripple.lens` out, the check mark moves to `Chromatic Grain`, the window to its effect, and `effect: effect 'Ripple' is gone; back to 'Chromatic Grain'` is logged; the stored choice is not rewritten. With it back, the `Ripple` row returns unchecked (listing a package chooses nothing) | each within 1 s | not yet run |
| 6. Open folder | `rm -r "<folder>"` (`Ripple.lens` goes with it), then choose *Open Effects Folder…* | Finder opens the folder (it is made if it was missing) | none; record whether Finder comes to the front and how long it takes | not yet run |
| 7. Restart | `cp -R Examples/Ripple.lens "<folder>/"` (step 6 removed it), choose `Ripple`, quit with ⌘Q, run `swift run dev-harness` again | `Ripple` is checked from the first menu opening and the window shows its effect with no click. `defaults read com.generald.dev-harness selectedEffect` is `package:Ripple` (the harness's own defaults domain) | no click needed | not yet run |
| 8. Second line | with `Ripple` listed, and after `mkdir "<folder>/Broken.lens"` | `Ripple` shows `Example Author` under its title; `Broken` is a disabled row whose second line says `manifest.json is missing` | none; record what is drawn | not yet run |

Record, next to the numbers:

- **The editor and its save style for steps 3 and 4.** The watch has two halves: a directory
  watch hears an atomic save (a temporary file renamed over `effect.metal`), a file watch hears
  an in-place overwrite (the same file truncated and written), and only a device hears both with
  a real editor. Do step 3 once each way if you can (an editor that saves atomically, then
  `cat edited.metal > effect.metal` for in place) and say which one produced which number.
- **Whether the second line of step 8 is drawn.** The Presenter's `detail` becomes the
  `NSMenuItem.subtitle` of the row. The SDK header (`NSMenuItem.h`) declares it macOS 14.4+ and
  says that on macOS 14 an item with an attributed title does not show it (macOS 15 and later
  do), so on a 14.x machine it may be missing: a known limit (`docs/ARCHITECTURE.md` → *Menu
  bar*). If it is not drawn, write that down with the OS version; the row, its mark and its
  enabled state are still the check, and the reason for a broken package is then visible only
  in the logs.
- **Anything over a budget**, with the log lines around it: that is the finding, not a failure to
  hide. The fix is a new issue; the budget stays.

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
