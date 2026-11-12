# Spec: effect parameters (MVP-C)

## Problem

A `.lens` package has no way to expose a knob. `manifest.json` reads past `parameters`, the only
per-frame data is `Uniforms` at buffer 0, and nothing carries a value from a UI to a kernel.

## Shape

### Manifest

```json
{
  "formatVersion": 1,
  "name": "Ripple",
  "parameters": [
    { "id": "strength", "label": "Strength", "type": "float", "min": 0, "max": 1, "default": 0.5, "step": 0.01 },
    { "id": "rings", "label": "Rings", "type": "int", "min": 1, "max": 16, "default": 4 },
    { "id": "inverted", "label": "Inverted", "type": "bool", "default": false },
    { "id": "tint", "label": "Tint", "type": "color", "default": [1, 0.8, 0.6, 1] },
    { "id": "center", "label": "Center", "type": "vec2", "min": [0, 0], "max": [1, 1], "default": [0.5, 0.5] },
    { "id": "mode", "label": "Mode", "type": "choice", "options": ["Soft", "Hard"], "default": "Soft" }
  ]
}
```

`formatVersion` stays 1: the README and `EffectManifestDecoding` already say `parameters` is read past
"until MVP-C". Absent key is an empty list. A package without parameters behaves exactly as it does today.

Validation (`EffectManifestDecoding`; any failure is `manifestInvalid` naming `parameters[i].<key>`):

| Rule | |
|---|---|
| Count | at most 32 |
| `id` | `^[A-Za-z_][A-Za-z0-9_]{0,63}$`, unique, not an MSL keyword from a closed list |
| `label` | non-empty after trim |
| `type` | one of the six; an unknown type rejects the package (its field would not exist for the shader) |
| `float`, `int`, `vec2` | `min < max` per component; `default` within `[min, max]` |
| `step` | optional, `0 < step <= max - min` |
| `color` | four components in `[0, 1]`, sRGB |
| `choice` | 1 to 32 distinct non-empty options; `default` is one of them |

### Entity (exact)

```swift
// Sources/Entity/EffectParameter.swift
public enum EffectParameterKind: Sendable, Hashable {
    case float(min: Float, max: Float, step: Float?, defaultValue: Float)
    case int(min: Int32, max: Int32, defaultValue: Int32)
    case bool(defaultValue: Bool)
    case color(defaultValue: SIMD4<Float>)
    case vector2(min: SIMD2<Float>, max: SIMD2<Float>, defaultValue: SIMD2<Float>)
    case choice(options: [String], defaultIndex: Int)
}

public struct EffectParameterSpec: Sendable, Hashable, Codable {
    public let id: String
    public let label: String
    public let kind: EffectParameterKind
}

public enum EffectParameterValue: Sendable, Hashable, Codable {
    case float(Float), int(Int32), bool(Bool), color(SIMD4<Float>), vector2(SIMD2<Float>), choice(Int)
}

// Sources/Entity/EffectParameterLayout.swift — pure, as DispatchGrid is
public enum EffectParameterFieldType: Sendable, Hashable, CaseIterable { case float, int, uint, float2, float4 }
public struct EffectParameterLayout: Sendable, Hashable {
    public struct Field: Sendable, Hashable { public let id: String; public let type: EffectParameterFieldType; public let offset: Int }
    public let fields: [Field]
    public let stride: Int
    public init(_ specs: [EffectParameterSpec])
}

// Sources/Entity/EffectParameterBlock.swift
public struct EffectParameterBlock: Sendable, Hashable {
    public let bytes: [UInt8]          // never empty: at least 16 bytes
    public static let none: EffectParameterBlock
}

// Sources/Entity/EffectParameterState.swift — what the panel shows for the chosen effect
public struct EffectParameterState: Sendable, Hashable { public let spec: EffectParameterSpec; public let value: EffectParameterValue }
```

`EffectManifest.parameters: [EffectParameterSpec]`; `EffectSource.parameters: [EffectParameterSpec]`,
both defaulting to `[]`, so every existing call site still compiles.

### Layout

Fields in manifest order, natural alignment: `float`, `int`, `uint` 4/4; `float2` 8/8; `float4` 16/16.
`stride` is the end rounded up to the largest alignment. Mapping: float→`float`, int→`int`,
bool→`uint`, choice→`uint`, vec2→`float2`, color→`float4`. Block length is `max(stride, 16)`.

### MSL generation

`ShaderSourceAssembly.assemble(_:layout:)` writes prelude, **one** generated line, the `#line`
directive, the author's source:

```metal
struct Parameters { float strength; int rings; uint inverted; float4 tint; float2 center; uint mode; }; static_assert(sizeof(Parameters) == 48, "Parameters must mirror the manifest");
```

For no parameters the line is the comment `// no parameters`, so no name is taken from an existing
package and `authorLineOffset` stays one constant (`+ 2`). The author writes
`constant Parameters& params [[buffer(1)]]`.

### Binding

`ComputePass.parameters: EffectParameterBlock`, bound at buffer index 1 by one `setBytes` with no
branch. `GPURenderer.render` and `EffectAdmission` carry it. The compile cache key becomes
`(source, options, EffectParameterLayout)`; labels and defaults do not recompile.

### Flow of a value

```text
ParameterPanelView → ParameterPanelPresenter.set → EffectInteractor.setParameter
  → EffectCatalogUseCase.setParameter (session actor: clamp, pack with ParameterPacker,
    publish state, schedule persist) → EffectRuntimeRepository.setParameters(block, of: source)
  → EffectRuntimeState (executor-confined) → read by admit → that pass's ComputePass
```

- **A parameter write never calls `prepare`** and returns without waiting for the frame executor.
- `prepare(_:parameters:)` delivers the initial block with the selection, in one step.
- `setParameters` for an effect other than the newest begun one is dropped.
- Sampled at admission by value, so a pass never sees a half-written update.

### Pure policy (sibling files in `EffectCatalogUseCase`)

- `ParameterPacker.pack(values:, specs:, layout:) -> EffectParameterBlock`: clamps, snaps to `step`, defaults what is missing.
- `ParameterReconciliation.reconcile(stored:, specs:) -> [String: EffectParameterValue]`: drops removed ids, defaults new ones and ones whose type changed, clamps the rest.

### Persistence

`Preferences.parameterValues(of:) -> [String: EffectParameterValue]` and
`setParameterValues(_:of:)`, passed through `SettingsRepository`. One key per effect,
`effect.parameters.v1.<origin>:<key>`, JSON. A value that does not decode is `[:]` with one developer
log line, like `StoredEffectID`. Writes are debounced 500 ms on `\.continuousClock`, latest wins.

### Randomness

`RandomSource` port (`next(below:)`), live module, `ZeroRandomSource` and `SequenceRandomSource`
(ARCHITECTURE physical table). `seed` is drawn once per session.

### UI

Closed switch on `EffectParameterKind`:

| Kind | Control |
|---|---|
| float | `Slider` with step, numeric value beside it |
| int | `Stepper` with the value |
| bool | `Toggle` |
| color | `ColorPicker` |
| vec2 | two `Slider`s |
| choice | `Picker` |

Presenter `ParameterPanelPresenter` (`Presenters`, `@MainActor`, observes `EffectInteractor.state` as
`EffectPickerPresenter` does). `ParameterPanelView` holds the struct only; layout numbers in
`ParameterPanelGeometry`. Window `ParameterPanelWindow` with protocol `ParameterWindow` in `AppRouter`,
injected like `PickerWindow`. `MenuBarRouting.openParameterPanel()`; menu item *Adjust Effect…*
enabled when the chosen effect has parameters. Reset restores defaults.

## Out

Presets, keyframing, MIDI, per-parameter automation, a texture parameter type.
