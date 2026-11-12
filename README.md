<p align="center">
  <img src="assets/hero.png" alt="mirage" width="720">
</p>

# mirage

<img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue" alt="macOS 14+"> <img src="https://img.shields.io/badge/Swift-6.0-orange" alt="Swift 6.0"> <img src="https://img.shields.io/badge/virtual%20camera-CMIO%20Camera%20Extension-blue" alt="CMIO Camera Extension"> <img src="https://img.shields.io/badge/effects-Metal%20(.lens)-purple" alt="Metal .lens"> <img src="https://img.shields.io/badge/status-pre--alpha-red" alt="pre-alpha"> <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT">

Real-time Metal shader effects for your webcam, served to Zoom, Meet, OBS — any app — as a
virtual camera. The lens experience Snap Camera left behind when it shut down, rebuilt for
macOS, with effects you can write, drop in, and share without rebuilding the app.

> **Pre-alpha.** The architecture is settled (see `docs/ARCHITECTURE.md`). The frame path, the
> four bundled effects and the preview run today in the dev harness (`swift run dev-harness`, below).
> Runtime `.lens` loading, hot reload, effect parameters and the automatic switch-off of a failing
> effect are built into it and covered end to end by the loopback tests, and every window's
> Presenter (the menu, the picker, the parameter panel, the settings and the onboarding window) by
> tests of its own; how those windows look and how fast any of it reacts on a device have not been
> checked yet. The virtual camera itself still awaits its first run on a device through the Camera
> Extension.

## How it works

```text
webcam ──▶ mirage (host app) ──▶ Metal effect (.lens, compiled at runtime) ──▶ Camera Extension ──▶ Zoom / Meet / OBS
```

- **Effects are `.lens` packages**: a `manifest.json` (name, author, description, an optional
  thumbnail and optional parameters) plus an `effect.metal` written in the Metal Shading
  Language, compiled on the fly with `MTLDevice.makeLibrary(source:)` (see [Packaging](#packaging)). Drop a package
  into the effects folder and it appears in the menu bar and in the effect picker (*Browse Effects…*,
  a grid of thumbnails); edit the shader and it hot-reloads.
- **Effects can declare parameters** (a slider, a number, a switch, a colour, a vector or a
  choice) in the manifest. The *Adjust Effect…* window draws a control for each, the shader reads
  the values as `params.<id>`, and a change applies to the frames that follow, without recompiling
  the shader. The values are kept for each effect across launches, and a manifest edit keeps the
  values that still fit (see [Effect parameters](docs/authoring/parameters.md)).
- **The virtual camera is a CoreMediaIO Camera Extension** (the only mechanism macOS 14+ still
  allows), so it works in every app that lists cameras.
- **Untrusted shaders can't take the app down**: each effect runs in its own command buffer;
  a hang or fault falls back to pass-through, and a `.lens` package that keeps failing is switched
  off automatically (five failed passes in a row, or thirty in a row that each take more than
  100 ms of GPU time; losing GPU access switches it off at once). The app then runs the first
  bundled effect in its place, and the menu keeps your choice: its row reads `Disabled: <reason>`
  and offers `Re-enable <name>`. A bundled effect is never switched off: if it fails too, the menu
  says `GPU unavailable: frames pass through unchanged`. The switch-off is remembered across
  launches, and editing the effect's source or parameter layout lifts it. After an out-of-memory
  error, an unknown error or going over the time budget, the app gives the effect one trial pass
  once a 5 minute cool-down has passed, as long as it is still the chosen effect (the cool-down
  doubles, up to an hour, each time a trial fails); a timeout, a page fault or a lost GPU access
  is never retried by itself.

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
    - `seed` is the engine's random seed for `hash` / `noise`: a value drawn once when the effect's
      session starts, so it is the same on every frame of a session and differs between sessions.
  - `float hash(uint2 cell, uint timeStep, uint seed)`: white noise in [0, 1) with 24 bits of
    precision, a pure function of a lattice cell, a discrete time step (`frameIndex`, for
    example) and the seed.
  - `float noise(float2 p, float time, uint seed)`: value noise in [0, 1], smooth in `p` and in
    `time`, over the integer grid of both.
- **Bindings**: the input frame is `texture2d<float, access::read>` at `[[texture(0)]]`, the
  output `texture2d<float, access::write>` at `[[texture(1)]]`, and `Uniforms` at
  `[[buffer(0)]]`. The values of the effect's parameters arrive as `constant Parameters &params`
  at `[[buffer(1)]]`: a struct the engine writes from the manifest's `parameters`, with one field
  per parameter named by its `id` (`params.strength`). An effect that declares no parameters has
  no `Parameters` struct, and its kernel leaves that argument out.
- **One entry point, named `effect`**: a `kernel void effect(...)`. Don't define `Uniforms`,
  `Parameters`, `hash` or `noise`, or anything in `namespace prelude`; those names are the
  engine's.
- **Errors point at your own lines.** Diagnostics read `effect:<line>:<column>: error: …`,
  counted from the first line of `effect.metal`; a note about a prelude declaration, or about the
  `Parameters` struct the engine generates, reads `prelude:<line>:`.

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
  after the author (without the whitespace around it, and cut at 280 characters, counted as Unicode
  scalars; the name and the author are shown in full).
- `thumbnail` (optional): a picture for the effect picker's cell (the menu does not show it), a
  PNG or JPEG file inside the package, given by its path relative to the package
  (`thumbnail.png`, `images/thumb.jpg`) and at most 1 MiB. A path that is absolute or has a `..`
  segment (`../thumb.png`, even `images/../thumb.png`), a file that is missing, a directory, larger
  than 1 MiB, not named `.png` / `.jpg` / `.jpeg` or not really a PNG or JPEG costs the effect only
  its picture: it still loads, and the reason goes to the app's log (at debug level; a file that is
  there and cannot be read is an error). A picture that does not decode, or has more than
  2048 × 2048 pixels in all (about 4 megapixels), is drawn like a missing one: the effect's coloured
  tile with its initials, and nothing is logged for it. A PNG or JPEG cut off in the middle of its
  pixels (a file that is still being written) is not told from a whole one: it draws as far as it goes,
  the rest black or grey, until the finished file is read. The cell is a few hundred points wide, so 512 × 512 is plenty.
- `parameters` (optional): the controls the *Adjust Effect…* window shows, at most 32. Each is an
  object with an `id` (the field name the kernel reads, such as `strength`), a `label` (the text the
  panel shows) and a `type`, which is one of `float`, `int`, `bool`, `color`, `vec2` and `choice`;
  the other keys depend on the type (`min`, `max`, `default`, `step`, `options`). A parameter that
  breaks a rule makes the whole package broken, and the reason names the key (such as
  `parameters[2].default`). [Effect parameters](docs/authoring/parameters.md) is the reference;
  `Examples/ParameterTour.lens` declares one of every type. Adding `parameters` does not change
  `formatVersion`, which stays `1`.
- Keys this version doesn't know are ignored, so a package can carry more than an older build
  reads.
- `effect.metal` is the kernel described above, entry point `effect`, and nothing else: no
  `Uniforms`, `Parameters`, `hash` or `noise` of your own. It is compiled with the default options.

The effects folder is `~/Library/Application Support/com.generald.mirage/Effects` (the host's
bundle identifier). The app makes it the first time it looks, and **Open Effects Folder…** in the
menu shows it in Finder. Only a directory whose name ends in `.lens` counts; any other file or
folder in there is ignored.

A package that can't be used is not left out. The menu lists it as a disabled item with the
reason, so a mistake shows up where you made it: no `manifest.json`, a manifest that isn't valid
JSON, lacks a required key or declares a parameter that breaks a rule, an unsupported
`formatVersion`, no `effect.metal`, or a file the app can't read (permissions, or text that isn't
UTF-8). Fix the file and the item comes back to life. The reason is the item's second line, which
macOS 14 may not draw: the disabled item is still listed, and the reason is then only in the app's
log. A shader that doesn't compile is a different failure, reported when the effect is chosen: the
menu's status line says `<name>: compile failed`, and the compiler's message is also in the *Set Up
Virtual Camera…* window.

Three complete packages in [`Examples/`](Examples) are there to start from:
[`Ripple.lens`](Examples/Ripple.lens) (a plain effect with a thumbnail),
[`Tint.lens`](Examples/Tint.lens) (a colour and a float parameter) and
[`ParameterTour.lens`](Examples/ParameterTour.lens) (one parameter of every type). New to writing
an effect? [Your first effect](docs/authoring/first-effect.md) takes you from an empty folder to a
picture changed by your own effect, and [Effect parameters](docs/authoring/parameters.md) is the
reference for what you can declare and what the kernel receives.

### Authoring tools

`lens-tool` checks, scaffolds and previews a `.lens` package without the camera or the app. Run it
from a checkout with `swift run lens-tool <command>`:

```text
validate <package>                              check a .lens package and compile its shader
new <name> [--in <folder>]                      create a .lens package from a template
render <effect> --input <png> --output <png>    run an effect over an image file
help                                            show this message
```

- `validate` prints `<name>: OK, <n> parameters` (`no parameters` for none, `1 parameter` for one)
  when the package reads and its shader compiles. A manifest problem prints the reason the menu would show, and a shader error is reported against
  your own lines (`effect:<line>:<column>`).
- `new` writes `<name>.lens` into `--in <folder>` (the current folder when left out): a manifest
  with one `strength` parameter and a kernel that uses it. The name is 1 to 64 ASCII letters,
  digits, spaces, `-` or `_`, starts with a letter or a digit and does not end in a space. It never
  overwrites an existing folder.
- `render` runs the effect once over a PNG or JPEG (at most 4096 pixels a side) and writes a PNG,
  with the parameters at their defaults and time 0. `<effect>` is a package path (it ends in
  `.lens`) or the name of a bundled effect, such as `"Chromatic Grain"`.

Errors start with `error:` on standard error. The exit code is 0 on success, 1 when the command
fails and 2 when the command line is wrong. [Your first effect](docs/authoring/first-effect.md) walks
through all three, and [Effect parameters](docs/authoring/parameters.md) is the reference for the
manifest's `parameters`.

## Using the app

The app lives in the menu bar. Its icon shows the state: a camera with filters while an effect runs,
a plain camera while the effect is bypassed, and a warning triangle while the chosen effect has a
problem.

### The menu

From the top, the menu holds:

- *Set Up Virtual Camera…*: the [onboarding window](#setting-up-the-virtual-camera).
- *Bypass Effects*: a check item that passes the camera through unchanged. The `⌃⌥⌘B` global
  hotkey toggles it too (see [Settings](#settings)).
- A line such as `30 fps`, while frames flow.
- One row per effect, the bundled ones first, then your `.lens` packages. The chosen one is checked.
  The second line is the author, or why the effect cannot be chosen. A switched-off effect is
  disabled and has a `Re-enable <name>` item under it.
- A status line, when the chosen effect failed to run: `<name>: <reason>`, `<name>: disabled,
  <reason>`, or `GPU unavailable: frames pass through unchanged`.
- *Browse Effects…*: the [effect picker](#the-effect-picker).
- *Adjust Effect…*: the [parameter panel](#adjusting-an-effect). Disabled unless the chosen effect
  declares parameters.
- *Open Effects Folder…*: shows the effects folder in Finder.
- *Camera*: the camera submenu below.
- *Settings…* (`⌘,`) and *Quit Mirage* (`⌘Q`).

The *Camera* submenu lists the cameras the system offers, the chosen one checked (a line says
`<name> is not connected`, `<name> is suspended` or `No camera found` when the chosen camera cannot
be used). When no camera is chosen, or the chosen one is not connected or is suspended (a laptop's
built-in camera with the lid closed), the app uses a camera that gives frames, a physical camera
before another app's virtual camera, and keeps your choice for when it comes back. Then comes a
*Resolution* submenu (`1280 × 720` and the other 16:9 sizes up to 1920 wide that the camera
supports), a *Frame Rate* submenu (`15 fps`, `24 fps` and `30 fps`, as the camera supports) and a
*Mirror* check item. The camera, resolution, frame rate and mirror choice are kept across launches,
and so is the chosen effect. The virtual camera's own output stays 1280 × 720 at 30 fps.

### Bundled effects

Four effects ship inside the app, listed first in the menu, and each one's parameters show in
*Adjust Effect…*:

- **Chromatic Grain** (the default): the red and blue channels drift sideways in opposite
  directions and a fresh grain covers every frame. No parameters.
- **Vignette**: the picture darkens toward its corners. *Strength* (0 to 1, default 0.5) and
  *Radius* (0.2 to 1.5, default 0.8).
- **Pixelate**: blocks of one colour. *Block Size* (1 to 64, default 8).
- **Duotone**: maps brightness onto two colours. *Shadows* and *Highlights* are the colours, and
  *Amount* (0 to 1, default 1) mixes the result with the original.

### The effect picker

*Browse Effects…* opens a window titled `Effects`: a `Search Effects` field over a grid with one
cell per effect, in the menu's order. A search matches the name or the author. A cell shows the
manifest's thumbnail or a coloured tile with the effect's initials, the name and the second line;
the chosen cell has a border, and clicking another one chooses it. A broken or switched-off effect
is dimmed and cannot be clicked, and hovering it says why (`<name> is disabled: <reason>` for a
switched-off effect, `<name> cannot be chosen: <reason>` for a broken package).
Re-enabling is done from the menu. A search that matches nothing says
`No effects match “<search>”`.

Between the search field and the grid the app shows a live preview of your camera with the chosen
effect, and a switch under it: *After* shows the effect applied, *Split* compares it with the
original, split down the middle. When the preview cannot start, the pane says `No GPU is available,
so the preview cannot be shown.`, `The preview could not use its view.` or `The preview could not
start.` (The dev harness's picker has no preview pane.)

### Adjusting an effect

*Adjust Effect…* opens a window titled `Adjust Effect` that names the chosen effect and draws one
row for each parameter its manifest declares: a slider for a float (snapped to its step when it
has one), a stepper for an integer, a switch for a boolean, a colour picker with opacity for a
colour, two sliders (X and Y) for a vector and a picker for a choice. *Reset* puts every parameter
back to its default. An effect without parameters shows `<name> has no parameters`.

### Settings

*Settings…* opens a window with:

- *Launch at Login*, with a note when macOS wants an approval (`Waiting for approval in System
  Settings → General → Login Items.`, and an *Open Login Items Settings…* button) or when the app is
  not in `/Applications` (`Available when the app is installed in /Applications.`).
- *Enable Global Hotkeys* (on by default) and the keys it registers: *Toggle Bypass* `⌃⌥⌘B`,
  *Next Effect* `⌃⌥⌘→` and *Previous Effect* `⌃⌥⌘←`. Next and previous skip an effect that is
  broken or switched off. When another app holds a key, the window says `Could not register <action>.
  Another app may be using the same keys.`
- *Reset All Settings…*, which asks `Reset all settings?` and then puts the chosen effect and every
  other stored setting back to its default and turns launch at login off.

### Setting up the virtual camera

*Set Up Virtual Camera…* opens a window titled `Set Up the Virtual Camera`. It says where the Camera
Extension stands (`Virtual camera not installed`, `Installing the virtual camera…`, `Approval
needed`, `Virtual camera ready`, `Restart your Mac`, or why the install failed), and while approval
is needed or was denied it has buttons for *Open Login Items & Extensions* and *Open Privacy &
Security*; the approval sits under one or the other depending on the macOS version.

While the menu has a status line for the chosen effect (a compile failure, a switch-off, `GPU
unavailable`), the window also shows `Why the effect failed` with that line, and under it the
compiler's message when the effect failed to compile. Under *Support Log*, *Save Support Log* writes `support-log.txt` (the app and
macOS versions, the extension's status, the effect's status, the compiler's output and the newest
log lines) to `~/Library/Application Support/com.generald.mirage/Diagnostics` and opens that folder
in Finder; attach the file when you report a problem. Saving again replaces the file.

## Requirements

- macOS 14 or later, Apple silicon
- The app must live in `/Applications` and the Camera Extension must be approved once in
  System Settings (under Login Items & Extensions on macOS 15 and later, under Privacy & Security
  before that; *Set Up Virtual Camera…* in the menu has a button for each)
- There is no signed, notarized download yet: build the app from source (see
  [`CONTRIBUTING.md`](CONTRIBUTING.md))

## Reporting a problem

Open an issue with the bug report or the feature request form. A bug report asks for the app
version, the macOS version and the steps to reproduce. In the menu, *Set Up Virtual Camera…* →
*Save Support Log* writes the file to attach, and if an effect is at fault, attach its
`effect.metal` and `manifest.json` too.

## Development

```sh
make test              # deterministic suite, no GPU or camera required
make test-gpu          # Metal smoke tests in their own process (needs a Metal device; CI has one)
make lint && make check
swift run dev-harness  # camera prompt, then your camera with the effect applied in a preview window; no virtual camera
swift run view-gallery --list   # the app's own windows over fixture data, no camera; `swift run view-gallery <screen>` opens one
swift run lens-tool help        # the effect authoring tool (see Authoring tools)
```

How to set up, what the checks guard and how a change is sent: [`CONTRIBUTING.md`](CONTRIBUTING.md).
Architecture, module map and the physical-abstraction table: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).
Conventions for contributors and AI agents: [`AGENTS.md`](AGENTS.md), [`.claude/`](.claude/).

## Roadmap

| Stage | Goal |
|---|---|
| M0 | Pass-through frame visible in Zoom via the real Camera Extension |
| MVP-A | One bundled effect end to end: camera → GPU → preview in the dev harness and the loopback (the extension path is M0's) |
| MVP-B (landed, epic #42) | Runtime `.lens` loading, hot reload, menu switching; timings on a device still to be measured |
| Effect picker (landed, #12, #68) | Thumbnail grid opened from the menu (*Browse Effects…*): search, the chosen effect marked, the manifest's picture or a coloured tile, and above it the live camera preview with *After* and *Split*; how it looks on a device is still to be checked |
| MVP-C (landed) | Parameters in the manifest (six types), the generated `Parameters` struct at `[[buffer(1)]]`, the *Adjust Effect…* panel, values kept for each effect, three parameterised bundled effects |
| MVP-D (landed) | Pass-through on failure, automatic switch-off with a cool-down and one trial pass, *Re-enable*, kept across launches; timings on a device still to be measured |
| Menu bar and settings (landed) | Bypass, frame rate readout, state icon, the Camera submenu (camera, resolution, frame rate, mirror), global hotkeys, launch at login, reset all settings |
| Onboarding (landed) | *Set Up Virtual Camera…*: extension status and approval buttons, the compiler's message, a saved support log |
| Authoring (landed) | `lens-tool` (validate, new, render), the first-effect tutorial and the parameter reference, the Tint and Parameter Tour examples |
| Distribution | Signed, notarized DMG, Sparkle updates, Homebrew cask: waiting for Apple Developer signing (#3, #7) |
| Later | Face landmarks / person segmentation inputs, GLSL (Shadertoy) import, URL/Git import, gallery |

## License

[MIT](LICENSE)
