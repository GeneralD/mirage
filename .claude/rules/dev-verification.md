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

## Lane 3 — destructive GPU scenarios: VM only

Infinite-loop / out-of-bounds shaders, `accessRevoked` recovery, and anything
that can wedge the GPU run only in a UTM macOS guest (see the `utm-macos-vm`
skill). Never on the developer's machine, never in CI.
