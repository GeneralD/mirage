# Effect parameters

A parameter is a control the app shows for your effect: a slider, a number, a switch, a colour or a choice. You declare each one in `manifest.json`, and the app gives your kernel the current values in a `Parameters` struct. This page is the reference for what you can declare and what the kernel receives.

## Declaring parameters

The `parameters` key of `manifest.json` lists the parameters in the order the panel shows them. Leave the key out, or give it an empty list, and the effect declares no parameters. Adding parameters does not change `formatVersion`, which stays `1`.

Each parameter is an object with these keys:

- `id` is the name the kernel reads the value by. It must match `^[A-Za-z_][A-Za-z0-9_]{0,63}$`, be unique within the package, and not be a reserved word of the shader language, such as `kernel` or `float2`.
- `label` is the text the panel shows. It must not be empty.
- `type` is one of the six kinds described under The six kinds below. The other keys a parameter reads depend on its kind.

A package can declare at most 32 parameters.

The Tint example declares two parameters, a colour and a float:

```json file=Examples/Tint.lens/manifest.json
{
  "formatVersion": 1,
  "name": "Tint",
  "author": "Example Author",
  "description": "Blends the picture towards a colour of your choice.",
  "parameters": [
    { "id": "tint", "label": "Tint", "type": "color", "default": [1, 0.8, 0.6, 1] },
    { "id": "amount", "label": "Amount", "type": "float", "min": 0, "max": 1, "default": 0.5, "step": 0.05 }
  ]
}
```

## The six kinds

Each kind reads its own keys. The shader receives each value in the type shown in the Shader type column.

| Type | Keys read | Shader type | Value |
|---|---|---|---|
| `float` | `min`, `max`, `default`, and `step` (optional) | `float` | A number. `step` is the grid the value snaps to. |
| `int` | `min`, `max`, `default` | `int` | A whole number within 32 bits. |
| `bool` | `default` | `uint` | `true` or `false`, which the kernel reads as 1 or 0. |
| `color` | `default` | `float4` | Four numbers from 0 to 1: red, green, blue and alpha, in sRGB. |
| `vec2` | `min`, `max`, `default` | `float2` | Each key holds two numbers: x, then y. |
| `choice` | `options`, `default` | `uint` | One to 32 distinct, non-empty texts, and a `default` that is one of them. The kernel reads the index of the chosen option. |

Parameter Tour declares one parameter of every kind:

```json file=Examples/ParameterTour.lens/manifest.json
{
  "formatVersion": 1,
  "name": "Parameter Tour",
  "author": "Example Author",
  "description": "One parameter of every kind: tints the picture by its distance from a center you place.",
  "parameters": [
    { "id": "strength", "label": "Strength", "type": "float", "min": 0, "max": 1, "default": 0.5, "step": 0.05 },
    { "id": "reach", "label": "Reach", "type": "int", "min": 1, "max": 8, "default": 4 },
    { "id": "inverted", "label": "Inverted", "type": "bool", "default": false },
    { "id": "tint", "label": "Tint", "type": "color", "default": [1, 0.8, 0.6, 1] },
    { "id": "center", "label": "Center", "type": "vec2", "min": [0, 0], "max": [1, 1], "default": [0.5, 0.5] },
    { "id": "mode", "label": "Falloff", "type": "choice", "options": ["Linear", "Squared"], "default": "Linear" }
  ]
}
```

The app puts the values of all the parameters in one `Parameters` struct, with one field per parameter in manifest order, named by its `id`. Each field sits at its natural alignment: `float`, `int` and `uint` take 4 bytes, `float2` takes 8 and `float4` takes 16. The struct is as long as its last field ends, rounded up to the largest alignment.

The layout of Parameter Tour is:

```text layout=Examples/ParameterTour.lens
strength float offset 0
reach int offset 4
inverted uint offset 8
tint float4 offset 16
center float2 offset 32
mode uint offset 40
size 48
```

and the line the app writes ahead of your source for its struct is:

```metal struct=Examples/ParameterTour.lens
struct Parameters { float strength; int reach; uint inverted; float4 tint; float2 center; uint mode; }; static_assert(sizeof(Parameters) == 48, "Parameters must mirror the manifest");
```

## What the reader rejects

The reader refuses the whole package when one parameter breaks a rule. The message names the key at fault by its position in the list, such as `parameters[2].default`. The rules are:

- There are at most 32 parameters.
- Each `id` matches the pattern above, is not a reserved word, and does not repeat an earlier `id`. Ids are case-sensitive, so `Amount` and `amount` are different.
- Each `label` is not empty once surrounding spaces are trimmed.
- Each `type` is one of the six kinds above.
- For `float`, `int` and `vec2`, `min` is below `max` (for each component, in a `vec2`), and `default` lies between them, both included.
- For `float`, `step`, when given, is above 0 and at most `max` minus `min`.
- For `color`, each component of `default` lies from 0 to 1.
- For `choice`, there are 1 to 32 options, none empty and none repeated, and `default` is one of them.

A number too large for its field, such as `1e39` for a `float`, is refused in the same way.

Each of the three manifests below is refused for one rule, and is otherwise complete.

```json invalid=parameters[0].default
{
  "formatVersion": 1,
  "name": "Too Bright",
  "parameters": [
    { "id": "gain", "label": "Gain", "type": "float", "min": 0, "max": 1, "default": 2 }
  ]
}
```

```json invalid=parameters[1].id
{
  "formatVersion": 1,
  "name": "Twins",
  "parameters": [
    { "id": "gain", "label": "Gain", "type": "float", "min": 0, "max": 1, "default": 0.5 },
    { "id": "gain", "label": "Gain again", "type": "float", "min": 0, "max": 1, "default": 0.5 }
  ]
}
```

```json invalid=parameters[0].type
{
  "formatVersion": 1,
  "name": "Unknown Kind",
  "parameters": [
    { "id": "image", "label": "Image", "type": "texture", "default": 0 }
  ]
}
```

## What the kernel sees

You declare nothing for the `Parameters` struct, since the app writes it for you. To read the values, add `constant Parameters &params [[buffer(1)]]` to the kernel's arguments, then read a field as `params.strength`. The values are sent as a block that is as long as the struct and never shorter than 16 bytes.

The Tint kernel reads `params.tint` and `params.amount`:

```metal file=Examples/Tint.lens/effect.metal
// Tint: blends the frame towards a colour of your choice. `amount` 0 does nothing, and 1 multiplies
// every pixel by `tint`, so the whole frame takes on that colour; in between, the two are mixed.
//
// The engine's prelude is compiled in front of this file, so `Uniforms` is already declared, and so is
// `Parameters`, generated from this package's manifest `parameters`: the author declares neither. The
// input is texture 0, the output is texture 1, `Uniforms` is buffer 0 and `Parameters` is buffer 1.
// This file is only the kernel, which must be named `effect`.

kernel void effect(texture2d<float, access::read> input [[texture(0)]],
                   texture2d<float, access::write> output [[texture(1)]],
                   constant Uniforms &uniforms [[buffer(0)]],
                   constant Parameters &params [[buffer(1)]],
                   uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) { return; }
    uint2 inside = min(gid, uint2(input.get_width() - 1, input.get_height() - 1));
    float3 source = input.read(inside).rgb;
    output.write(float4(mix(source, source * params.tint.rgb, params.amount), 1.0f), gid);
}
```

## Try it

`lens-tool validate <package>` checks a `.lens` package and compiles its shader. When the manifest breaks a rule, it reports the key at fault, such as `parameters[0].default`.

Two example packages show the kinds in use:

- [Tint](../../Examples/Tint.lens) blends the picture towards a colour, with a colour and a float.
- [Parameter Tour](../../Examples/ParameterTour.lens) declares one parameter of every kind.
