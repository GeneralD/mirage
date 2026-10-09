import Entity
import Testing

@Suite struct EffectUniformsLayoutTests {
    /// The MSL side is `struct Uniforms { float time; uint frameIndex; float2 resolution; uint seed; }`;
    /// `float2` is 8-aligned, so the layout is 0 / 4 / 8 / 16 with a stride of 24 on both sides.
    @Test func layoutMatchesTheMetalUniformsStruct() {
        #expect(MemoryLayout<EffectUniforms>.offset(of: \.time) == 0)
        #expect(MemoryLayout<EffectUniforms>.offset(of: \.frameIndex) == 4)
        #expect(MemoryLayout<EffectUniforms>.offset(of: \.resolution) == 8)
        #expect(MemoryLayout<EffectUniforms>.offset(of: \.seed) == 16)
        #expect(MemoryLayout<EffectUniforms>.stride == 24)
    }
}

@Suite struct DispatchGridTests {
    @Test func coveringRoundsUpToWholeThreadgroups() {
        let hd = DispatchGrid.covering(width: 1280, height: 720)
        #expect(hd.threadgroups == GridSize(width: 80, height: 45))
        #expect(hd.threadsPerThreadgroup == GridSize(width: 16, height: 16))

        let ragged = DispatchGrid.covering(width: 100, height: 33)
        #expect(ragged.threadgroups == GridSize(width: 7, height: 3))
        #expect(ragged.threads == GridSize(width: 112, height: 48))
    }

    @Test(arguments: [1, 15, 16, 17, 255, 256, 1920])
    func coveringNeverFallsShort(side: Int) {
        let grid = DispatchGrid.covering(width: side, height: side)
        #expect(grid.threads.width >= side)
        #expect(grid.threads.height >= side)
        #expect(grid.threads.width - side < 16, "no more than one spare threadgroup")
    }
}

@Suite struct ShaderCompileOptionsTests {
    @Test func defaultsArePreciseAndNameTheEffectKernel() {
        let options = ShaderCompileOptions()
        #expect(options.entryPoint == "effect")
        #expect(options.precise)
    }

    @Test func fastMathIsPartOfTheCacheKey() {
        #expect(ShaderCompileOptions(precise: true) != ShaderCompileOptions(precise: false))
        #expect(ShaderCompileOptions(entryPoint: "a") != ShaderCompileOptions(entryPoint: "b"))
    }
}
