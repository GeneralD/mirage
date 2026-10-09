import Domain
import GPURenderDataSource
import TestDoubles
import TestSupport
import Testing

@Suite("GPURenderDataSource properties", .timeLimit(.minutes(1)))
struct GPURenderPropertyTests {
    /// No byte packer sits between the DataSource and the GPU: the live gateway
    /// hands `EffectUniforms` itself to `setBytes(_:length: stride, index: 0)`.
    /// So the packing *is* the struct's memory, and this pins it, for any values
    /// (NaN and infinity bit patterns included), against the MSL `Uniforms`
    /// declaration: `time` at 0, `frameIndex` at 4, `resolution` at 8 and 12,
    /// `seed` at 16, 24 bytes in all.
    @Test("the uniforms a pass hands to the GPU are, byte for byte, the MSL Uniforms layout", arguments: Seeds.range(0..<50))
    func uniformLayout(seed: UInt64) async throws {
        var generator = SeededGenerator(seed: seed)
        let words = (0..<5).map { _ in UInt32(truncatingIfNeeded: generator.next()) }
        let uniforms = EffectUniforms(
            time: Float(bitPattern: words[0]), frameIndex: words[1],
            resolution: SIMD2(Float(bitPattern: words[2]), Float(bitPattern: words[3])), seed: words[4])
        let fixture = RenderFixture()

        let call = try await fixture.start(input: fixture.lease(), output: fixture.lease(), uniforms: uniforms)

        let pass = try #require(fixture.gpu.submissions.values.only).pass
        let bytes = withUnsafeBytes(of: pass.uniforms) { Array($0) }
        #expect([0, 4, 8, 12, 16].map { word(in: bytes, at: $0) } == words)
        #expect(MemoryLayout<EffectUniforms>.stride == 24, "the length setBytes sends; MSL sizeof(Uniforms)")
        try fixture.completePending(with: .finished)
        _ = await call.value
    }

    /// Whatever the mix — stale leases among live ones, any outcome, any
    /// completion order — every render gets the answer of its own pass, one
    /// command buffer per committed render, and every binding goes back once.
    @Test("any mix of leases, outcomes and completion orders keeps bindings balanced and answers attributed", arguments: Seeds.range(0..<50))
    func interleavings(seed: UInt64) async throws {
        var generator = SeededGenerator(seed: seed)
        let plans = (0..<Int.random(in: 1...5, using: &generator)).map { _ in Plan.random(using: &generator) }
        let fixture = RenderFixture()

        let calls = try await plans.asyncMap { plan in
            let input = try plan.staleInput ? fixture.staleLease() : fixture.lease()
            return try await fixture.start(input: input, output: fixture.lease())
        }
        let committed = plans.filter { !$0.staleInput }
        #expect(fixture.gpu.pending.count == committed.count, "one command buffer per render that reached the GPU")
        #expect(fixture.textures.liveCount == committed.count * 2)
        for (submission, plan) in zip(fixture.gpu.pending, committed).shuffled(using: &generator) {
            #expect(fixture.gpu.complete(submission, with: plan.completion))
        }
        let answers = await calls.asyncMap { await $0.value }

        #expect(answers == plans.map(\.expected))
        #expect(fixture.textures.isBalanced)
        #expect(fixture.textures.bindCount == committed.count * 2)
        #expect(fixture.gpu.submissions.count == committed.count)
        #expect(fixture.gpu.contextCount == (committed.isEmpty ? 0 : 1))
    }

    private func word(in bytes: [UInt8], at offset: Int) -> UInt32 {
        bytes[offset..<offset + 4].enumerated().reduce(0) { $0 | UInt32($1.element) << (8 * $1.offset) }
    }
}

/// One render of an interleaving: whether its input lease is already gone, and
/// how its command buffer finishes if it reaches the GPU.
private struct Plan {
    let staleInput: Bool
    let completion: GPUCompletion

    var expected: RenderResult {
        staleInput ? .failure(.invalidResource) : GPUCompletionMapping.result(of: completion)
    }

    static func random(using generator: inout SeededGenerator) -> Plan {
        let code = Int.random(in: -1...12, using: &generator)
        let error = code < 0 ? nil : RawGPUError(domain: GPUCompletionMapping.commandBufferErrorDomain, code: code)
        let start = Double(Int.random(in: 0...1_000, using: &generator))
        return Plan(
            staleInput: Int.random(in: 0..<4, using: &generator) == 0,
            completion: GPUCompletion(gpuStart: start, gpuEnd: start + 0.25, error: error))
    }
}

extension Sequence {
    /// `map` for an async transform, applied one element at a time in order.
    fileprivate func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        // The accumulator is the helper's only state; it exists because `map` cannot `await`.
        var mapped: [T] = []
        for element in self { mapped.append(try await transform(element)) }
        return mapped
    }
}
