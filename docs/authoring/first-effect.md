# Your first effect

This tutorial takes you from an empty folder to a photo changed by an effect of your own. You make a package called `Swap`, check it, render it over a picture, and then use it in the app. Every output shown here is what the tool prints.

## Before you start

You need a Mac with a GPU and a Swift toolchain. Run the commands below from the root of a checkout of this repository, where `swift run` finds `lens-tool`.

## 1. Create the package

`lens-tool new` writes a new `.lens` package from a template into the folder given by `--in`, or into the current folder when `--in` is left out, and makes that folder when it is not there. The name is 1 to 64 ASCII letters, digits, spaces, `-` or `_`. It starts with a letter or a digit and does not end in a space.

```sh
swift run lens-tool new Swap --in /tmp/lenses
```

```text
Created /tmp/lenses/Swap.lens
```

## 2. Look inside

A package is a folder with two files. `manifest.json` names the effect and lists its parameters, and `effect.metal` holds the kernel. The template's manifest declares one parameter, `strength`, a float from 0 to 1 with a default of 1.

```json scaffold=manifest
{
  "formatVersion": 1,
  "name": "Swap",
  "parameters": [
    { "id": "strength", "label": "Strength", "type": "float", "min": 0, "max": 1, "default": 1, "step": 0.05 }
  ]
}
```

The template's kernel inverts the colours, and `strength` sets how far: 0 leaves the picture as it is, and 1 inverts it fully.

```metal scaffold=effect
// Uniforms and Parameters are declared for you: Parameters has one member per entry
// of "parameters" in manifest.json, under the same id.
kernel void effect(texture2d<float, access::read> input [[texture(0)]],
                   texture2d<float, access::write> output [[texture(1)]],
                   constant Uniforms &uniforms [[buffer(0)]],
                   constant Parameters &params [[buffer(1)]],
                   uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) { return; }
    uint2 inside = min(gid, uint2(input.get_width() - 1, input.get_height() - 1));
    float3 color = input.read(inside).rgb;
    output.write(float4(mix(color, 1.0f - color, params.strength), 1.0f), gid);
}
```

The app declares `Uniforms` and `Parameters` for you. `Parameters` has one member per parameter of the manifest, under the same id.

## 3. Make it yours

Replace the whole of `effect.metal` with this kernel. It swaps the red and blue channels. `strength` blends from the original picture (0) to the fully swapped one (1), and the kernel reads it as `params.strength`.

```metal result=effect
// Swap: trade the red and blue channels. Strength blends from the original (0) to fully swapped (1).
kernel void effect(texture2d<float, access::read> input [[texture(0)]],
                   texture2d<float, access::write> output [[texture(1)]],
                   constant Uniforms &uniforms [[buffer(0)]],
                   constant Parameters &params [[buffer(1)]],
                   uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) { return; }
    uint2 inside = min(gid, uint2(input.get_width() - 1, input.get_height() - 1));
    float3 color = input.read(inside).rgb;
    output.write(float4(mix(color, color.bgr, params.strength), 1.0f), gid);
}
```

## 4. Check it

`lens-tool validate` reads the package and compiles its shader with the Metal compiler. When the shader has a mistake, the message names the line of your file in the form `effect:<line>:`.

```sh
swift run lens-tool validate /tmp/lenses/Swap.lens
```

```text
Swap: OK, 1 parameter
```

## 5. See it on a picture

`lens-tool render` runs the effect once over an image and writes the result to a PNG. The image is a PNG or a JPEG, with each side at most 4096 pixels. The parameters take their default values, and time is 0.

```sh
swift run lens-tool render /tmp/lenses/Swap.lens --input photo.png --output swapped.png
```

```text
Wrote swapped.png (1280x720) with /tmp/lenses/Swap.lens
```

The effect can also be the name of a bundled effect, such as `Chromatic Grain`, in place of a package path.

## 6. Use it in the app

Put the `Swap.lens` package in the app's effects folder. The app picks it up without a restart, and the menu shows it as `Swap`. The [packaging section of the README](../../README.md#packaging) says where that folder is.

## Where to go next

- [Effect parameters](parameters.md) describes the six kinds of parameter and the rules the reader enforces.
- [Tint](../../Examples/Tint.lens) is a finished package with a colour and a float parameter.
