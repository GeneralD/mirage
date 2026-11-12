import Domain
import IOSurfaceGateway
import MetalGateway
import ShaderCompilationDataSource

/// Compiles one effect the way the runtime does (the prelude, the `Parameters` line, the author's
/// source), packs its parameter values into a block and runs one compute pass over a fixed input,
/// so a test compares the output pixels with a Swift value. The block is packed here, from
/// `EffectParameterLayout` alone, and not by `ParameterPacker`: the rig checks what the kernel reads
/// against the layout, not the packer against itself. Test-only; the suites that use it are gated on a
/// Metal device.
enum EffectSmokeRig {
    static let width = 160
    static let height = 96

    /// The fixed input at `(x, y)` as `[B, G, R, A]`.
    static func testImage(_ x: Int, _ y: Int) -> [UInt8] {
        [
            UInt8((x * 7 + y * 3) % 256),
            UInt8((x * 5 + y * 11) % 256),
            UInt8((x * 13 + y * 2) % 256),
            255,
        ]
    }

    enum RigError: Error, CustomStringConvertible {
        case compile(String)
        case parameters(String)
        case gpu(String)

        var description: String {
            switch self {
            case .compile(let message), .parameters(let message), .gpu(let message):
                return message
            }
        }
    }

    /// The output of one pass of `effect` over `testImage`, with `values` packed as its parameters.
    /// The input is texture 0 and the output texture 1, the order the prelude's kernels expect.
    static func render(
        _ effect: EffectSource, values: [EffectParameterValue] = [], width: Int = EffectSmokeRig.width, height: Int = EffectSmokeRig.height
    ) async throws -> SurfacePixels {
        let block = try parameterBlock(for: effect.parameters, values: values)
        let gateway = MetalGatewayImpl()
        let context = try gateway.makeContext()
        let kernel = try gateway.compile(
            source: ShaderSourceAssembly.assemble(effect.source, layout: EffectParameterLayout(effect.parameters)),
            options: effect.options, on: context
        )
        .mapError { RigError.compile(ShaderSourceAssembly.authorRelative($0).message) }
        .get()

        let surfaces = IOSurfaceGatewayImpl()
        let descriptor = SurfaceDescriptor.bgra(width: width, height: height)
        let input = try surfaces.create(descriptor)
        try GPUSmokeSupport.write(input) { EffectSmokeRig.testImage($0, $1) }
        let output = try surfaces.create(descriptor)
        let inputTexture = try gateway.bind(input, on: context)
        defer { try? gateway.unbind(inputTexture) }
        let outputTexture = try gateway.bind(output, on: context)
        defer { try? gateway.unbind(outputTexture) }

        let pass = ComputePass(
            kernel: kernel, textures: [inputTexture, outputTexture],
            uniforms: EffectUniforms(time: 0, frameIndex: 0, resolution: SIMD2(Float(width), Float(height)), seed: 0),
            parameters: block, grid: DispatchGrid.covering(width: width, height: height))
        let completion = try await GPUSmokeSupport.run(pass, on: context, through: gateway)
        if let error = completion.error {
            throw RigError.gpu("command buffer failed: \(error.domain) \(error.code)")
        }
        return try GPUSmokeSupport.pixels(of: output)
    }

    /// The block `values` make under `specs`: each value's words, little-endian, at the offset
    /// `EffectParameterLayout` gives its field, every other byte zero.
    static func parameterBlock(for specs: [EffectParameterSpec], values: [EffectParameterValue]) throws -> EffectParameterBlock {
        guard values.count == specs.count else {
            throw RigError.parameters("\(specs.count) parameters are declared but \(values.count) values are given")
        }
        let layout = EffectParameterLayout(specs)
        let zeros = [UInt8](repeating: 0, count: max(layout.stride, EffectParameterBlock.minimumLength))
        let bytes = try zip(zip(specs, layout.fields), values).reduce(into: zeros) { bytes, placed in
            let ((spec, field), value) = placed
            let encoded = try words(of: value, for: spec)
            for (index, word) in encoded.enumerated() {
                for byte in 0..<4 {
                    bytes[field.offset + index * 4 + byte] = UInt8(truncatingIfNeeded: word >> UInt32(8 * byte))
                }
            }
        }
        return EffectParameterBlock(bytes: bytes)
    }

    /// The words a value occupies, in the order its field reads them: a float's bit pattern, an int's
    /// two's complement, a bool or a choice as a `uint`, a colour or a `float2` one float at a time.
    /// A value whose case is not the kind's is a parameter error that names the parameter.
    private static func words(of value: EffectParameterValue, for spec: EffectParameterSpec) throws -> [UInt32] {
        switch (spec.kind, value) {
        case (.float, .float(let number)):
            return [number.bitPattern]
        case (.int, .int(let number)):
            return [UInt32(bitPattern: number)]
        case (.bool, .bool(let flag)):
            return [flag ? 1 : 0]
        case (.choice, .choice(let index)):
            return [UInt32(truncatingIfNeeded: index)]
        case (.color, .color(let color)):
            return [color.x, color.y, color.z, color.w].map(\.bitPattern)
        case (.vector2, .vector2(let vector)):
            return [vector.x, vector.y].map(\.bitPattern)
        default:
            throw RigError.parameters("parameter '\(spec.id)' is declared as \(spec.kind) but given \(value)")
        }
    }
}
