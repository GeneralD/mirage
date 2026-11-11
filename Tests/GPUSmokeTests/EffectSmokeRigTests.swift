import Domain
import Testing

/// The rig's input and its helpers: no device needed, so they run everywhere.
@Suite("Effect smoke rig image", .timeLimit(.minutes(1)))
struct EffectSmokeRigImageTests {
    @Test("the three fixed points of testImage match their constants")
    func fixedPointsMatch() {
        #expect(EffectSmokeRig.testImage(0, 0) == [0, 0, 0, 255])
        #expect(EffectSmokeRig.testImage(80, 48) == [192, 160, 112, 255])
        #expect(EffectSmokeRig.testImage(159, 95) == [118, 48, 209, 255])
    }

    @Test("testImage is opaque at all 100 points with x and y in 0..<10")
    func alphaIsOpaqueAtHundredPoints() {
        let alphas = (0..<10).flatMap { y in (0..<10).map { x in EffectSmokeRig.testImage(x, y)[3] } }
        #expect(alphas.count == 100)
        #expect(alphas.allSatisfy { $0 == 255 })
    }
}

/// Runs one compute pass of a small effect over the fixed input on a real device: the pixels the
/// pass writes are compared with the Swift expectation, and the parameter block is checked where
/// the kernel reads it.
@Suite("Effect smoke rig", .serialized, .enabled(if: MetalDeviceProbe.isAvailable), .timeLimit(.minutes(1)))
struct EffectSmokeRigTests {
    /// Copies the input texel to the output texel: the pass-through the pixel checks compare with.
    private static let identity = EffectSource(
        name: "Identity",
        source: """
            kernel void effect(texture2d<float, access::read> input [[texture(0)]],
                               texture2d<float, access::write> output [[texture(1)]],
                               uint2 gid [[thread_position_in_grid]]) {
                if (gid.x >= output.get_width() || gid.y >= output.get_height()) { return; }
                output.write(input.read(gid), gid);
            }
            """)

    /// `level` at offset 0, `pair` at 8 and `count` at 16: a stride of 24.
    private static let probe = EffectSource(
        name: "Probe",
        source: """
            kernel void effect(texture2d<float, access::read> input [[texture(0)]],
                               texture2d<float, access::write> output [[texture(1)]],
                               constant Parameters &params [[buffer(1)]], uint2 gid [[thread_position_in_grid]]) {
                if (gid.x >= output.get_width() || gid.y >= output.get_height()) { return; }
                output.write(float4(params.pair.y, params.level, float(params.count) / 255.0f, 1.0f), gid);
            }
            """,
        parameters: [
            EffectParameterSpec(id: "level", label: "Level", kind: .float(min: 0, max: 1, step: nil, defaultValue: 0)),
            EffectParameterSpec(id: "pair", label: "Pair", kind: .vector2(min: SIMD2(0, 0), max: SIMD2(1, 1), defaultValue: SIMD2(0, 0))),
            EffectParameterSpec(id: "count", label: "Count", kind: .int(min: 0, max: 255, defaultValue: 0)),
        ])

    /// `flag` at offset 0, `mode` at 4 and `tint` at 16: a stride of 32.
    private static let flags = EffectSource(
        name: "Flags",
        source: """
            kernel void effect(texture2d<float, access::read> input [[texture(0)]],
                               texture2d<float, access::write> output [[texture(1)]],
                               constant Parameters &params [[buffer(1)]], uint2 gid [[thread_position_in_grid]]) {
                if (gid.x >= output.get_width() || gid.y >= output.get_height()) { return; }
                output.write(float4(float(params.flag), float(params.mode) / 2.0f, params.tint.g, 1.0f), gid);
            }
            """,
        parameters: [
            EffectParameterSpec(id: "flag", label: "Flag", kind: .bool(defaultValue: false)),
            EffectParameterSpec(id: "mode", label: "Mode", kind: .choice(options: ["a", "b", "c"], defaultIndex: 0)),
            EffectParameterSpec(id: "tint", label: "Tint", kind: .color(defaultValue: SIMD4(0, 0, 0, 1))),
        ])

    /// Two parameters, for the errors that are thrown before anything is compiled.
    private static let pair = EffectSource(
        name: "Pair",
        source: """
            kernel void effect(texture2d<float, access::read> input [[texture(0)]],
                               texture2d<float, access::write> output [[texture(1)]],
                               constant Parameters &params [[buffer(1)]], uint2 gid [[thread_position_in_grid]]) {
                if (gid.x >= output.get_width() || gid.y >= output.get_height()) { return; }
                output.write(float4(params.level, float(params.count) / 255.0f, 0.0f, 1.0f), gid);
            }
            """,
        parameters: [
            EffectParameterSpec(id: "level", label: "Level", kind: .float(min: 0, max: 1, step: nil, defaultValue: 0)),
            EffectParameterSpec(id: "count", label: "Count", kind: .int(min: 0, max: 255, defaultValue: 0)),
        ])

    /// How many pixels of `image` differ from `expected` by more than the tolerance in some channel.
    private static func outsideTolerance(
        _ image: SurfacePixels, _ expected: (Int, Int) -> [UInt8], width: Int = EffectSmokeRig.width, height: Int = EffectSmokeRig.height
    ) -> Int {
        (0..<height).flatMap { y in
            (0..<width).filter { x in GPUSmokeSupport.distance(image.pixel(x: x, y: y), expected(x, y)) > GPUSmokeSupport.tolerance }
        }.count
    }

    @Test("identity over the default 160 x 96 reproduces testImage within the tolerance at every pixel")
    func identityWithinToleranceAtDefaultSize() async throws {
        let image = try await EffectSmokeRig.render(Self.identity)
        let outside = Self.outsideTolerance(image) { EffectSmokeRig.testImage($0, $1) }
        #expect(outside == 0, "\(outside) pixels outside the tolerance")
    }

    @Test("identity over a 163 x 101 surface, whose rows are not a multiple of 16 bytes, reproduces testImage at every pixel")
    func identityAtAnUnalignedSize() async throws {
        let (width, height) = (163, 101)
        let image = try await EffectSmokeRig.render(Self.identity, width: width, height: height)
        let mismatches = (0..<height).flatMap { y in
            (0..<width).filter { x in image.pixel(x: x, y: y) != EffectSmokeRig.testImage(x, y) }
        }
        #expect(mismatches.isEmpty, "\(mismatches.count) pixels differ from testImage")
    }

    @Test("each parameter reaches the kernel at the offset its layout gives it: level at 0, pair at 8, count at 16")
    func parametersReachTheirLayoutOffsets() async throws {
        let expected: [UInt8] = [51, 64, 191, 255]
        let image = try await EffectSmokeRig.render(Self.probe, values: [.float(0.25), .vector2(SIMD2(0.5, 0.75)), .int(51)])
        let outside = Self.outsideTolerance(image) { _, _ in expected }
        #expect(outside == 0, "\(outside) pixels outside the tolerance of \(expected)")
    }

    @Test("a bool sets red, a choice sets green and a colour's green sets blue, each read at its layout offset")
    func boolChoiceAndColorReachTheKernel() async throws {
        let tint = EffectParameterValue.color(SIMD4(0, 0.25, 0, 1))

        let on = try await EffectSmokeRig.render(Self.flags, values: [.bool(true), .choice(2), tint])
        let onExpected: [UInt8] = [64, 255, 255, 255]
        let onOutside = Self.outsideTolerance(on) { _, _ in onExpected }
        #expect(onOutside == 0, "\(onOutside) pixels outside the tolerance of \(onExpected) with the bool on")

        let off = try await EffectSmokeRig.render(Self.flags, values: [.bool(false), .choice(2), tint])
        let offExpected: [UInt8] = [64, 255, 0, 255]
        let offOutside = Self.outsideTolerance(off) { _, _ in offExpected }
        #expect(offOutside == 0, "\(offOutside) pixels outside the tolerance of \(offExpected) with the bool off")
    }

    @Test("a syntax error on the author's third line is thrown as a compile error whose message starts with effect:3:")
    func syntaxErrorIsCompileErrorOnLineThree() async throws {
        let broken = EffectSource(
            name: "Broken",
            source: """
                kernel void effect(texture2d<float, access::read> input [[texture(0)]], texture2d<float, access::write> output [[texture(1)]],
                                   uint2 gid [[thread_position_in_grid]]) {
                    float broken = 1.0 +;
                    output.write(float4(broken), gid);
                }
                """)
        do {
            _ = try await EffectSmokeRig.render(broken)
            Issue.record("a source with a syntax error rendered instead of throwing")
        } catch EffectSmokeRig.RigError.compile(let message) {
            #expect(message.hasPrefix("effect:3:"), "\(message)")
        }
    }

    @Test("fewer values than declared parameters is a parameter error")
    func fewerValuesThanParametersIsAParameterError() async throws {
        do {
            _ = try await EffectSmokeRig.render(Self.pair, values: [.float(0.5)])
            Issue.record("one value for two parameters rendered instead of throwing")
        } catch EffectSmokeRig.RigError.parameters(let message) {
            #expect(message.contains("2 parameters"), "\(message)")
        }
    }

    @Test("a value of the wrong kind for its parameter is a parameter error that names the parameter")
    func wrongKindIsAParameterErrorNamingTheParameter() async throws {
        do {
            _ = try await EffectSmokeRig.render(Self.pair, values: [.int(3), .int(3)])
            Issue.record("an int for a float parameter rendered instead of throwing")
        } catch EffectSmokeRig.RigError.parameters(let message) {
            #expect(message.contains("level"), "\(message)")
        }
    }
}
