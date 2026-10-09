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

`DevHarness` embeds `Info.plist` via `-sectcreate` so the camera permission is
keyed to a stable bundle identifier. It runs camera → effects → preview
window with the virtual camera sink replaced by `InMemoryVirtualCameraSink`.
Use it for shader work, hot reload and parameter UI. It cannot show anything
about the Camera Extension.

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
log stream --style compact --predicate 'subsystem == "<log subsystem>"'
# extension: process = the Camera Extension; host: process = the app
```

| Step | Action | Expected lines (grep) | Budget |
|---|---|---|---|
| 1. Baseline | nothing | extension `frames=… received=… dropped=… maxGapMs=… slate=0`; host `connected to port` | — |
| 2. Host killed | `kill -9 <host pid>` | extension `host lost: hostLost(deadName)` (kernel destroys the presence right) or, as backstop, `hostLost(frameGap(`; then `slate entered base=`; summary `slate=<n>` grows | black frames within 1.25 × frameGap (2.5 s at the default 2 s gap); target well under 3 s |
| 3. Host stalled | `kill -STOP <host pid>` | only `hostLost(frameGap(` (the presence right stays alive); `slate entered base=` | same budget |
| 4. Host resumed | `kill -CONT <host pid>` | `slate left`; summary `slate=` stops growing; picture back in the client without a restart (0–2 real frames may drop as non-monotonic) | next frame after resume |
| 5. Host relaunched | relaunch the app after step 2 | host `look-up attempt <n> failed` while the extension is not yet checked in, then `connected to port`; extension `hello received, watching presence right`; `slate left` | reconnect within a few seconds (backoff is 250 ms doubling to 5 s) |
| 6. Extension gone | quit the last client of the camera so the extension exits | host `destination lost, port <n> released`, then `look-up attempt` lines until the extension is back, then `connected to port`; no host restart needed | — |

Record the measured times next to the budgets once they exist; until then do
not claim which detector fired for step 2 — the log line tells (`deadName` vs
`frameGap`). `host lost: …` is the error-log copy of the same event.

## Lane 3 — destructive GPU scenarios: VM only

Infinite-loop / out-of-bounds shaders, `accessRevoked` recovery, and anything
that can wedge the GPU run only in a UTM macOS guest (see the `utm-macos-vm`
skill). Never on the developer's machine, never in CI.
