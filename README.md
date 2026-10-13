<p align="center">
  <img src="assets/hero.png" alt="mirage" width="720">
</p>

# mirage

<img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue" alt="macOS 14+"> <img src="https://img.shields.io/badge/Swift-6.0-orange" alt="Swift 6.0"> <img src="https://img.shields.io/badge/virtual%20camera-CMIO%20Camera%20Extension-blue" alt="CMIO Camera Extension"> <img src="https://img.shields.io/badge/effects-Metal%20(.lens)-purple" alt="Metal .lens"> <img src="https://img.shields.io/badge/status-pre--alpha-red" alt="pre-alpha"> <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT">

Real-time Metal shader effects for your webcam, served to Zoom, Meet, OBS — any app — as a
virtual camera. The lens experience Snap Camera left behind when it shut down, rebuilt for
macOS, with effects you can write, drop in, and share without rebuilding the app.

> **Pre-alpha.** The architecture is settled (see `docs/ARCHITECTURE.md`); the code is not here
> yet. The first milestone is a pass-through frame reaching Zoom through the Camera Extension.

## How it works

```text
webcam ──▶ mirage (host app) ──▶ Metal effect (.lens, compiled at runtime) ──▶ Camera Extension ──▶ Zoom / Meet / OBS
```

- **Effects are `.lens` packages**: a `manifest.json` (name, parameters, inputs) plus an
  `effect.metal` written in the Metal Shading Language, compiled on the fly with
  `MTLDevice.makeLibrary(source:)`. Drop a package into the effects folder and it appears in the
  menu bar; edit the shader and it hot-reloads.
- **The virtual camera is a CoreMediaIO Camera Extension** (the only mechanism macOS 14+ still
  allows), so it works in every app that lists cameras.
- **Untrusted shaders can't take the app down**: each effect runs in its own command buffer;
  a hang or fault falls back to pass-through, and an effect that keeps failing is disabled
  automatically.

### Writing an effect

Runtime `.lens` loading arrives in MVP-B (see the roadmap); this is the contract `effect.metal`
is compiled against.

- **The engine's prelude comes first.** Your source is compiled after a prelude that already
  includes `<metal_stdlib>` with `using namespace metal;` and declares:
  - `struct Uniforms { float time; uint frameIndex; float2 resolution; uint seed; }`, bound at
    `[[buffer(0)]]`:
    - `time` is in **seconds**: the frame's presentation time minus the presentation time of the
      session's first frame, so it is 0 on that frame and counts up with the camera's timestamps
      (not a wall clock). A session restarts whenever the pipeline starts again.
    - `frameIndex` is the frame's index, counted from 0 each time the pipeline starts.
    - `resolution` is the output frame's size in **pixels** (width, height). The kernel is
      dispatched in whole 16 × 16 threadgroups, rounded up, so the grid can overshoot the
      output: `gid` may be past `resolution`. **Bounds-check `gid`** against the output
      texture's size (`output.get_width()` / `output.get_height()`) before you read or write.
    - `seed` is the engine's random seed for `hash` / `noise` (always 0 for now).
  - `float hash(uint2 cell, uint timeStep, uint seed)`: white noise in [0, 1) with 24 bits of
    precision, a pure function of a lattice cell, a discrete time step (`frameIndex`, for
    example) and the seed.
  - `float noise(float2 p, float time, uint seed)`: value noise in [0, 1], smooth in `p` and in
    `time`, over the integer grid of both.
- **Bindings**: the input frame is `texture2d<float, access::read>` at `[[texture(0)]]`, the
  output `texture2d<float, access::write>` at `[[texture(1)]]`, and `Uniforms` at
  `[[buffer(0)]]`.
- **One entry point, named `effect`**: a `kernel void effect(...)`. Don't define `Uniforms`,
  `hash` or `noise`, or anything in `namespace prelude`; those names are the engine's.
- **Errors point at your own lines.** Diagnostics read `effect:<line>:<column>: error: …`,
  counted from the first line of `effect.metal`; a note about a prelude declaration reads
  `prelude:<line>:`.

## Requirements

- macOS 14 or later, Apple silicon
- The app must live in `/Applications` and the Camera Extension must be approved once in
  System Settings → Privacy & Security

## Development

```sh
make test              # deterministic suite, no GPU or camera required
make test-gpu          # Metal smoke tests in their own process (needs a Metal device; CI has one)
make lint && make check
swift run dev-harness  # camera prompt, then your camera with the effect applied in a preview window; no virtual camera
```

Architecture, module map and the physical-abstraction table: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).
Conventions for contributors and AI agents: [`AGENTS.md`](AGENTS.md), [`.claude/`](.claude/).

## Roadmap

| Stage | Goal |
|---|---|
| M0 | Pass-through frame visible in Zoom via the real Camera Extension |
| MVP-A | One bundled effect end to end |
| MVP-B | Runtime `.lens` loading, hot reload, menu switching |
| MVP-C | Parameter UI generated from the manifest |
| MVP-D | Pass-through on failure, auto-disable |
| Later | Face landmarks / person segmentation inputs, GLSL (Shadertoy) import, URL/Git import, gallery |

## License

[MIT](LICENSE)
