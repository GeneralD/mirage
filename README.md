<p align="center">
  <img src="assets/hero.png" alt="mirage" width="720">
</p>

# mirage

<img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue" alt="macOS 14+"> <img src="https://img.shields.io/badge/Swift-6.0-orange" alt="Swift 6.0"> <img src="https://img.shields.io/badge/virtual%20camera-CMIO%20Camera%20Extension-blue" alt="CMIO Camera Extension"> <img src="https://img.shields.io/badge/effects-Metal%20(.lens)-purple" alt="Metal .lens"> <img src="https://img.shields.io/badge/status-pre--alpha-red" alt="pre-alpha"> <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT">

Real-time Metal shader effects for your webcam, served to Zoom, Meet, OBS — any app — as a
virtual camera. The lens experience Snap Camera left behind when it shut down, rebuilt for
macOS, with effects you can write, drop in, and share without rebuilding the app.

> **Pre-alpha.** The architecture is settled (see `docs/ARCHITECTURE.md`). The frame path, the
> bundled effect and the preview run today in the dev harness (`swift run dev-harness`, below).
> Runtime `.lens` loading and hot reload are built into it and covered end to end by the loopback
> tests, and the Effects menu's Presenter by a live-wiring test; how the menu and the effect
> picker look and how fast any of it reacts on a device have not been checked yet. The virtual
> camera itself still awaits its first run on a device through the Camera Extension.

## How it works

```text
webcam ──▶ mirage (host app) ──▶ Metal effect (.lens, compiled at runtime) ──▶ Camera Extension ──▶ Zoom / Meet / OBS
```

- **Effects are `.lens` packages**: a `manifest.json` (name, author, description, an optional
  thumbnail; parameters arrive with MVP-C) plus an `effect.metal` written in the Metal Shading
  Language, compiled on the fly with `MTLDevice.makeLibrary(source:)` (see [Packaging](#packaging)). Drop a package
  into the effects folder and it appears in the menu bar and in the effect picker (*Browse Effects…*,
  a grid of thumbnails); edit the shader and it hot-reloads.
- **The virtual camera is a CoreMediaIO Camera Extension** (the only mechanism macOS 14+ still
  allows), so it works in every app that lists cameras.
- **Untrusted shaders can't take the app down**: each effect runs in its own command buffer;
  a hang or fault falls back to pass-through, and an effect that keeps failing is disabled
  automatically.

### Writing an effect

This is the contract `effect.metal` is compiled against.

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

### Packaging

An effect is a **folder named `<id>.lens`** holding two files, and a thumbnail if you want one. The
folder name without `.lens` is the effect's id, so it stays the same however you edit the files:

```text
Ripple.lens/
├── manifest.json
├── effect.metal
└── thumbnail.png
```

```json
{
  "formatVersion": 1,
  "name": "Ripple",
  "author": "Example Author",
  "description": "The frame sways sideways like heat haze, in a smooth wave that drifts with time.",
  "thumbnail": "thumbnail.png"
}
```

- `formatVersion` (required): the integer `1`. Any other integer that fits a 64-bit integer is
  reported as unsupported; a number that is not an integer (`1.5`), or a whole number beyond that
  range, is reported as invalid.
- `name` (required): what the menu shows. Surrounding whitespace is trimmed; it cannot be empty.
- `author`, `description` (optional): the effect picker's hover shows them, the description on a line
  after the author (without the whitespace around it, and cut at 280 characters).
- `thumbnail` (optional): a picture for the effect picker's cell (the menu does not show it), a
  PNG or JPEG file inside the package, given by its path relative to the package
  (`thumbnail.png`, `images/thumb.jpg`) and at most 1 MiB. A path that is absolute or has a `..`
  segment (`../thumb.png`, even `images/../thumb.png`), a file that is missing, a directory, larger
  than 1 MiB, not named `.png` / `.jpg` / `.jpeg` or not really a PNG or JPEG costs the effect only
  its picture: it still loads, and the reason goes to the app's log (at debug level; a file that is
  there and cannot be read is an error). A picture that does not decode, or has more than
  2048 × 2048 pixels in all (about 4 megapixels), is drawn like a missing one: the effect's coloured
  tile with its initials. The cell is a few hundred points wide, so 512 × 512 is plenty.
- Keys this version doesn't know are ignored, so a package can carry more than an older build
  reads. A `parameters` list is read past for now; the parameter UI is MVP-C.
- `effect.metal` is the kernel described above, entry point `effect`, and nothing else: no
  `Uniforms`, `hash` or `noise` of your own. It is compiled with the default options.

The effects folder is `~/Library/Application Support/com.generald.mirage/Effects` (the host's
bundle identifier). The app makes it the first time it looks, and **Open Effects Folder…** in the
menu shows it in Finder. Only a directory whose name ends in `.lens` counts; any other file or
folder in there is ignored.

A package that can't be used is not left out. The menu lists it as a disabled item with the
reason, so a mistake shows up where you made it: no `manifest.json`, a manifest that isn't valid
JSON or lacks a required key, an unsupported `formatVersion`, no `effect.metal`, or a file the
app can't read (permissions, or text that isn't UTF-8). Fix the file and the item comes back to
life. The reason is the item's second line, which macOS 14 may not draw: the disabled item is
still listed, and the reason is then only in the app's log. A shader that doesn't compile is a
different failure, reported when the effect is chosen.

[`Examples/Ripple.lens`](Examples/Ripple.lens) is a complete package to start from.

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
| MVP-A | One bundled effect end to end: camera → GPU → preview in the dev harness and the loopback (the extension path is M0's) |
| MVP-B (landed, epic #42) | Runtime `.lens` loading, hot reload, menu switching; timings on a device still to be measured |
| Effect picker (landed, #12) | Thumbnail grid opened from the menu (*Browse Effects…*): search, the chosen effect marked, the manifest's picture or a coloured tile; the live camera preview above it is #68, and how it looks on a device is still to be checked |
| MVP-C | Parameter UI generated from the manifest |
| MVP-D | Pass-through on failure, auto-disable |
| Later | Face landmarks / person segmentation inputs, GLSL (Shadertoy) import, URL/Git import, gallery |

## License

[MIT](LICENSE)
