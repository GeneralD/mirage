import Domain
import TestDoubles
import TestSupport
import Testing

@Suite("FakeGPUGateway", .timeLimit(.minutes(1)))
struct FakeGPUGatewayTests {
    private let gateway = FakeGPUGateway()
    private let textures = FakeTextureCacheGateway()

    private func pass(seed: UInt32, on context: any GPUContextHandle) throws -> ComputePass {
        let texture = try textures.bind(FakeSurfaceHandle(id: seed), on: context)
        let uniforms = EffectUniforms(time: 0, frameIndex: 0, resolution: SIMD2(1280, 720), seed: seed)
        return ComputePass(
            kernel: FakeLibraryHandle(source: "effect"), textures: [texture], uniforms: uniforms, grid: .covering(width: 1280, height: 720))
    }

    @Test("passes complete in the order the test chooses, each exactly once")
    func completionOrderIsTheTests() throws {
        let context = try gateway.makeContext()
        let completed = Collector<UInt32>()
        try gateway.encodeAndCommit(pass(seed: 1, on: context), on: context) { _ in completed.append(1) }
        try gateway.encodeAndCommit(pass(seed: 2, on: context), on: context) { _ in completed.append(2) }
        #expect(gateway.pending.map(\.id) == [1, 2])

        let second = try #require(gateway.pending.last)
        let first = try #require(gateway.pending.first)
        #expect(gateway.complete(second, with: GPUCompletion(gpuStart: 1, gpuEnd: 2, error: nil)))
        #expect(gateway.pending.map(\.id) == [1])
        #expect(gateway.complete(first, with: GPUCompletion(gpuStart: 2, gpuEnd: 3, error: nil)))

        #expect(completed.values == [2, 1])
        #expect(gateway.pending.isEmpty)
        #expect(gateway.submissions.count == 2)
    }

    @Test("a completion is delivered verbatim, raw error included")
    func completionIsVerbatim() throws {
        let context = try gateway.makeContext()
        let received = Collector<GPUCompletion>()
        try gateway.encodeAndCommit(pass(seed: 7, on: context), on: context) { received.append($0) }
        let fault = GPUCompletion(gpuStart: 10, gpuEnd: 12.5, error: RawGPUError(domain: "MTLCommandBufferErrorDomain", code: 5))

        gateway.complete(try #require(gateway.pending.first), with: fault)

        #expect(received.values == [fault])
    }

    @Test("completing a submission twice is a reported issue and returns false")
    func doubleCompletionIsRefused() throws {
        let context = try gateway.makeContext()
        let completed = Collector<Void>()
        try gateway.encodeAndCommit(pass(seed: 1, on: context), on: context) { _ in completed.append(()) }
        let submission = try #require(gateway.pending.first)
        gateway.complete(submission, with: GPUCompletion(gpuStart: 0, gpuEnd: 0, error: nil))

        // Only the report is the known issue; the return value is asserted outside,
        // so a `true` cannot be absorbed into it.
        let again = Collector<Bool>()
        withKnownIssue {
            again.append(gateway.complete(submission, with: GPUCompletion(gpuStart: 0, gpuEnd: 0, error: nil)))
        }
        #expect(again.values == [false])
        #expect(completed.count == 1)
    }

    @Test("foreign handles are refused before anything is recorded")
    func foreignHandlesAreRefused() throws {
        let context = try gateway.makeContext()
        let valid = try pass(seed: 1, on: context)
        let foreignKernel = ComputePass(kernel: ForeignLibraryHandle(), textures: valid.textures, uniforms: valid.uniforms, grid: valid.grid)
        let foreignTexture = ComputePass(kernel: valid.kernel, textures: [ForeignTextureHandle()], uniforms: valid.uniforms, grid: valid.grid)

        #expect(throws: GPUError.foreignHandle) { try gateway.encodeAndCommit(valid, on: ForeignContextHandle()) { _ in } }
        #expect(throws: GPUError.foreignHandle) { try gateway.encodeAndCommit(foreignKernel, on: context) { _ in } }
        #expect(throws: GPUError.foreignHandle) { try gateway.encodeAndCommit(foreignTexture, on: context) { _ in } }
        #expect(gateway.submissions.count == 0)
    }

    @Test("a submission records the pass exactly as it was handed in")
    func submissionRecordsThePass() throws {
        let context = try gateway.makeContext()
        let pass = try pass(seed: 42, on: context)

        try gateway.encodeAndCommit(pass, on: context) { _ in }

        let recorded = try #require(gateway.submissions.last).pass
        #expect(ObjectIdentifier(recorded.kernel) == ObjectIdentifier(pass.kernel))
        #expect(recorded.textures.map { ObjectIdentifier($0) } == pass.textures.map { ObjectIdentifier($0) })
        #expect(recorded.uniforms == pass.uniforms)
        #expect(recorded.grid == pass.grid)
    }

    @Test("scripted failures: no device, and an encode that fails")
    func scriptedFailures() throws {
        gateway.failMakeContext(with: .noDevice)
        #expect(throws: GPUError.noDevice) { try gateway.makeContext() }
        gateway.failMakeContext(with: nil)
        let context = try gateway.makeContext()
        #expect(gateway.contextCount == 1)

        gateway.failEncode(with: .encoderUnavailable)
        #expect(throws: GPUError.encoderUnavailable) { try gateway.encodeAndCommit(try pass(seed: 1, on: context), on: context) { _ in } }
        #expect(gateway.submissions.count == 0)
    }
}

final class ForeignContextHandle: GPUContextHandle, Sendable {
    var backing: AnyObject { self }
}

final class ForeignLibraryHandle: LibraryHandle, Sendable {
    var backing: AnyObject { self }
}

final class ForeignTextureHandle: TextureHandle, Sendable {
    var backing: AnyObject { self }
}
