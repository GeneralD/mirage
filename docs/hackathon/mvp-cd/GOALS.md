# Hackathon `mvp-cd`

## Brief (verbatim)

> 続きをたたみかけるように進める

(Given as `/hackathon` after the standing request 「さて、残っているissueをどんどん昇華して」 /
「残りのissueを並列して」. Read as: the roadmap's next stages, MVP-C and MVP-D, and everything a
product in this category is expected to have, without stopping to ask.)

## Vision (one line)

The lens experience Snap Camera left behind, rebuilt for macOS: effects you write, drop in, tune with
sliders generated from their manifest, and that can never take your video call down.

## Boring tier

What any virtual-camera effects app must have. Status from the requirements scout on `main` 0.24.1.

### Effect parameters (MVP-C)

- [ ] Typed parameters in `manifest.json` (float, int, bool, color, vec2, choice) with range, default, label
- [ ] A package with a malformed `parameters` is broken, with a reason that names the key
- [ ] A `Parameters` struct generated from the manifest, bound at `[[buffer(1)]]`, read as `params.strength`
- [ ] Clamping, defaults and byte packing that cannot drift from the generated struct
- [ ] A parameter panel generated from the manifest, with reset
- [ ] A slider moves the very next frame, without recompiling
- [ ] Values kept per effect across relaunch, reconciled when the manifest changes
- [ ] Seeded randomness for `hash` / `noise` (`seed` is 0 today)
- [ ] Parameters in the bundled effect and the example packages; authoring docs

### Failure handling (MVP-D)

- [x] A failed pass passes the frame through; a broken shader passes through
- [ ] Each pass's outcome reaches a policy, stamped with the effect it ran
- [ ] Consecutive-failure breaker, GPU-time budget, cool-down with one trial
- [ ] Disabled set persisted, so a crash loop cannot repeat at launch
- [ ] Menu says which effect was disabled and why; re-enable action; an edit re-enables
- [ ] GPU timing proven real on a device; hang behaviour measured in the VM lane

### Camera and formats

- [ ] Choose among several cameras; hot-plug; remembered across launches
- [ ] Resolution and frame-rate choice; mirror toggle

### Menu bar, settings, onboarding

- [ ] Pause / bypass toggle; state-driven menu-bar icon; FPS readout
- [ ] Settings window; launch at login; reset all; stored values carry a schema version
- [ ] Global hotkeys (bypass, next / previous effect)
- [ ] Onboarding window; extension status and approval action with a Settings deep link
- [ ] Failure reason (compiler text) visible; support log export

### Preview (#68)

- [ ] Live preview window in the host app; before / after split

### Effect authoring and distribution

- [ ] Several bundled effects and example packages
- [ ] Offline `.lens` validator and a scaffold command, both without a camera
- [ ] Render a still image through an effect, without a camera
- [ ] First-effect tutorial; parameter reference
- [ ] README install and usage; CONTRIBUTING; issue and PR templates; release notes from tags
- [ ] `[blocked: signing]` notarized DMG, Sparkle, Homebrew cask (#3, #7): drafts only

## Differentiator

- Effects are community-authored `.lens` packages, loaded at runtime, hot-reloaded, with diagnostics
  in the author's own line numbers.
- Untrusted GPU code is contained: one command buffer per effect, pass-through, auto-disable.
- A real Camera Extension, so every app that lists cameras works.
- Tests are the specification: fake GPU, manual executor, seeded properties; the real GPU in its own job.

## Bold additions

Existing-repo mode: provisional default is **don't**. Candidates, killed or adopted with one word.

- Effect chaining (more than one pass per frame) → provisional: don't
- `.lens` parameter presets (named value sets, shareable) → provisional: don't

## Next horizon

From the README's "Later" and the category; supply once the tiers above are met.

- Vision face landmarks and person segmentation as effect inputs
- GLSL (Shadertoy) import
- Import from URL or Git; a public effect gallery
- LUT inputs; background replacement on top of segmentation
- Shortcuts / App Intents; Stream Deck; per-app effect profiles

## Done criteria

Lanes: `make test`, `make test-gpu`, the in-process loopback, `scripts/shot` over the dev harness or
the view gallery. The real Camera Extension, Zoom and device timings stay for the human.

### MVP-C works when

- A manifest with `parameters` decodes; every malformed shape is a broken package naming the key (table test).
- Layout offsets match a golden table, the rendered MSL matches a checked-in string, and a GPU probe
  kernel reads back every field (`make test-gpu`).
- In the loopback, a parameter change alters the block from the next admitted frame; earlier passes keep theirs.
- A fresh DataStore over `InMemoryKeyValueStore` restores the values; a changed manifest reconciles them.
- `scripts/shot` of the panel shows one control per kind.

### MVP-D works when

- `EffectHealthPolicy` (pure, seeded `forAll`): k consecutive counted failures open it; one success resets;
  the cool-down advanced with `TestClock` allows one trial; a failed trial reopens with a longer cool-down.
- In the loopback, a fake GPU answering `timeout` k times still delivers every frame; no further pass runs
  for the disabled effect; sent + dropped = taken.
- The disabled set survives a fresh DataStore, an edit clears it, and re-enable clears it.
- `MenuBarPresenter` shows the reason and the action; `scripts/shot` of that menu state.
