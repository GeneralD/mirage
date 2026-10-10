---
paths:
  - "**/*.swift"
  - "**/Package.swift"
  - "project.yml"
  - "Apps/**"
---

# Dev Verification — What `swift run` Cannot Show

Three lanes, by what is being verified.

## Lane 1 — effects and preview (no extension): `swift run dev-harness`

`DevHarness` links `Tools/DevHarness/Info.plist` into its binary
(`-sectcreate __TEXT __info_plist`) so the camera prompt has a usage string
and a stable bundle identifier (`com.generald.dev-harness`). With #24 it runs
camera → effects → preview window with the virtual camera sink replaced by
`InMemoryVirtualCameraSink`, for shader work, hot reload and parameter UI. It
cannot show anything about the Camera Extension. Build it with
`make build-dev-harness`, never `swift build` alone, after editing the plist:
SwiftPM does not see the plist as a link input, and the make target relinks.

Today (#21, the lite harness) it has no camera frames and no effect: it asks
for the camera once and keeps one solid frame in a preview window, and the
usage string says only that (rewrite it when #24 wires capture). Drive it
yourself only when the user is at the machine — the camera prompt is a modal
dialog on their screen:

```sh
make build-dev-harness
swift run dev-harness
log stream --level debug --style compact --predicate 'subsystem == "<log subsystem>"'   # second terminal
```

| Check | Expected |
|---|---|
| Window | a 640 × 480 window titled "Dev Harness": a mid-grey 16:9 frame with black bars above and below (the preview kernel's aspect fit), still filled after a resize. Empty or all black means the frame never reached a drawable; look for `preview window not attached` / `frame not shown` lines |
| Camera prompt | on the first run, a camera dialog naming the harness (bundle `com.generald.dev-harness`) or the terminal app. Then `camera authorization: authorized` (category `camera`); anything else is followed by a `camera access not granted (…)` error line |
| Summary | every 30 ticks (about once a second) `solid frame: ticks=… presented=… skipped=…` (category `preview`) |
| Occluded window | cover the window or move it to another Space for a while: summary lines further apart than a second mean `nextDrawable` blocked the frame executor (`docs/ARCHITECTURE.md` → *Preview*); record what you see |
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
   was required, in the #21 PR so this section can state it as fact.

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
