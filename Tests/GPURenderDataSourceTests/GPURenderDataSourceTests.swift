import Domain
import GPURenderDataSource
import TestDoubles
import TestSupport
import Testing

@Suite("GPURenderDataSource", .timeLimit(.minutes(1)))
struct GPURenderDataSourceTests {
    // MARK: - One effect, one command buffer

    @Test("a pass commits one command buffer: the library, input then output, the uniforms verbatim, a grid covering the output")
    func passGraph() async throws {
        let fixture = RenderFixture()
        let input = try fixture.lease()
        let output = try fixture.lease(.bgra(width: 641, height: 359))
        let surfaces = [try fixture.surface(input).id, try fixture.surface(output).id]

        let call = await fixture.start(input: input, output: output)

        let submission = try #require(fixture.gpu.submissions.values.only)
        let kernel = try #require(submission.pass.kernel as? FakeLibraryHandle)
        let bound = submission.pass.textures.compactMap { ($0 as? FakeTextureHandle)?.surface.id }
        #expect(ObjectIdentifier(kernel) == ObjectIdentifier(fixture.library))
        #expect(bound == surfaces)
        #expect(submission.pass.uniforms == .sample)
        #expect(submission.pass.grid == .covering(width: 641, height: 359))
        #expect(fixture.gpu.contextCount == 1)

        try fixture.completePending(with: .finished)
        #expect(await call.value == .success(GPUTiming(gpuStart: 10, gpuEnd: 10.004)))
        #expect(fixture.gpu.submissions.count == 1, "one render, one command buffer")
    }

    @Test("the render answers only when its command buffer completes; the textures stay bound until then")
    func answersOnCompletion() async throws {
        let fixture = RenderFixture()
        let answered = Collector<RenderResult>()
        let call = try await fixture.start(input: fixture.lease(), output: fixture.lease())
        let waiter = Task { answered.append(await call.value) }

        // The executor has nothing left to run and the GPU has not answered: nothing may be given back yet.
        #expect(fixture.executor.drain() == 0)
        #expect(answered.count == 0)
        #expect(fixture.textures.liveCount == 2)
        #expect(fixture.textures.unbindCount == 0)

        try fixture.completePending(with: .finished)
        await waiter.value
        #expect(answered.values == [.success(GPUTiming(gpuStart: 10, gpuEnd: 10.004))])
        #expect(fixture.textures.isBalanced)
        #expect(fixture.textures.liveCount == 0)
    }

    @Test("passes in flight each hold their own bindings and answer in the order the GPU completes them")
    func delayedCompletionsOutOfOrder() async throws {
        let fixture = RenderFixture()
        let first = try await fixture.start(input: fixture.lease(), output: fixture.lease())
        let second = try await fixture.start(input: fixture.lease(), output: fixture.lease())
        let pending = fixture.gpu.pending
        #expect(pending.count == 2, "two renders, two command buffers")
        #expect(fixture.textures.bindCount == 4)
        #expect(fixture.textures.liveCount == 4)

        #expect(fixture.gpu.complete(pending[1], with: .failed(code: 3)))
        #expect(await second.value == .failure(.pageFault))
        #expect(fixture.textures.liveCount == 2, "only the completed pass gave its textures back")

        #expect(fixture.gpu.complete(pending[0], with: .finished))
        #expect(await first.value == .success(GPUTiming(gpuStart: 10, gpuEnd: 10.004)))
        #expect(fixture.textures.isBalanced)
        #expect(fixture.textures.unbindCount == 4)
        #expect(fixture.gpu.contextCount == 1, "the context is made once and reused")
    }

    @Test(
        "every raw command-buffer code reaches the caller as its EffectFailure, with both textures given back",
        arguments: GPUCompletionMappingTests.commandBufferCodes
    )
    func everyCodeThroughTheGPU(code: Int, expected: EffectFailure) async throws {
        let fixture = RenderFixture()
        let call = try await fixture.start(input: fixture.lease(), output: fixture.lease())

        try fixture.completePending(with: .failed(code: code))

        #expect(await call.value == .failure(expected))
        #expect(fixture.textures.isBalanced)
        #expect(fixture.textures.bindCount == 2)
    }

    @Test("a raw code from another error domain is unknown, whatever its number")
    func foreignDomainThroughTheGPU() async throws {
        let fixture = RenderFixture()
        let call = try await fixture.start(input: fixture.lease(), output: fixture.lease())

        try fixture.completePending(with: .failed(code: 2, domain: "NSPOSIXErrorDomain"))

        #expect(await call.value == .failure(.unknown(code: 2)))
        #expect(fixture.textures.isBalanced)
    }

    @Test("a caller cancelled while its pass runs still gets the GPU's answer, and the textures still go back once")
    func cancelledCallerStillSettles() async throws {
        let fixture = RenderFixture()
        let call = try await fixture.start(input: fixture.lease(), output: fixture.lease())

        call.cancel()
        try fixture.completePending(with: .failed(code: 2))

        #expect(await call.value == .failure(.timeout))
        #expect(fixture.textures.isBalanced)
    }

    // MARK: - Leases that do not resolve

    @Test("a stale input or output lease is invalidResource and reaches no gateway", arguments: [StaleSide.input, .output, .both])
    func staleLease(_ side: StaleSide) async throws {
        let fixture = RenderFixture()
        let input = try side.inputIsStale ? fixture.staleLease() : fixture.lease()
        let output = try side.outputIsStale ? fixture.staleLease() : fixture.lease()

        let result = await fixture.start(input: input, output: output).value

        #expect(result == .failure(.invalidResource))
        #expect(fixture.gpu.contextCount == 0)
        #expect(fixture.textures.bindCount == 0)
        #expect(fixture.gpu.submissions.count == 0)
    }

    @Test("a token the pool never issued is invalidResource too")
    func neverIssued() async throws {
        let fixture = RenderFixture()

        let result = try await fixture.start(input: SurfaceToken(index: 99, generation: 1), output: fixture.lease()).value

        #expect(result == .failure(.invalidResource))
        #expect(fixture.textures.bindCount == 0)
        #expect(fixture.gpu.submissions.count == 0)
    }

    // MARK: - Failures before the commit

    @Test("no GPU context is internalError with nothing bound, and the next pass asks for one again")
    func contextUnavailable() async throws {
        let fixture = RenderFixture()
        fixture.gpu.failMakeContext(with: .noDevice)

        let refused = try await fixture.start(input: fixture.lease(), output: fixture.lease()).value

        #expect(refused == .failure(.internalError))
        #expect(fixture.textures.bindCount == 0)
        #expect(fixture.log.contains("no GPU context"))

        fixture.gpu.failMakeContext(with: nil)
        let call = try await fixture.start(input: fixture.lease(), output: fixture.lease())
        try fixture.completePending(with: .finished)
        #expect(await call.value == .success(GPUTiming(gpuStart: 10, gpuEnd: 10.004)))
        #expect(fixture.gpu.contextCount == 1)
    }

    @Test("a surface the device will not wrap is invalidResource and nothing stays bound")
    func bindRefused() async throws {
        let fixture = RenderFixture()
        fixture.textures.failBind(with: .textureBindingFailed)

        let result = try await fixture.start(input: fixture.lease(), output: fixture.lease()).value

        #expect(result == .failure(.invalidResource))
        #expect(fixture.textures.isBalanced)
        #expect(fixture.gpu.submissions.count == 0)
        #expect(fixture.log.contains("textureBindingFailed"))
    }

    @Test("when the output cannot be bound, the input bound before it is given back")
    func secondBindRefused() async throws {
        let fixture = RenderFixture()
        let output = try #require(fixture.pool.adopt(ForeignSurfaceHandle(), descriptor: .hd720))

        let result = try await fixture.start(input: fixture.lease(), output: output).value

        #expect(result == .failure(.invalidResource))
        #expect(fixture.textures.bindCount == 1)
        #expect(fixture.textures.isBalanced)
        #expect(fixture.gpu.submissions.count == 0)
    }

    @Test("an encoder the queue cannot provide is internalError, and both textures go back at once")
    func encodeRefused() async throws {
        let fixture = RenderFixture()
        fixture.gpu.failEncode(with: .encoderUnavailable)

        let result = try await fixture.start(input: fixture.lease(), output: fixture.lease()).value

        #expect(result == .failure(.internalError))
        #expect(fixture.textures.bindCount == 2)
        #expect(fixture.textures.isBalanced)
        #expect(fixture.gpu.pending.isEmpty)
        #expect(fixture.log.contains("encoderUnavailable"))
    }

    @Test("a library another gateway compiled is refused at encode: internalError, textures given back")
    func foreignLibrary() async throws {
        let fixture = RenderFixture()

        let result = try await fixture.start(input: fixture.lease(), output: fixture.lease(), library: ForeignLibraryHandle()).value

        #expect(result == .failure(.internalError))
        #expect(fixture.textures.isBalanced)
        #expect(fixture.log.contains("foreignHandle"))
    }

    @Test("a refused give-back is logged and does not change the pass's answer")
    func unbindRefused() async throws {
        let fixture = RenderFixture(refusingUnbind: true)
        let call = try await fixture.start(input: fixture.lease(), output: fixture.lease())

        try fixture.completePending(with: .finished)

        #expect(await call.value == .success(GPUTiming(gpuStart: 10, gpuEnd: 10.004)))
        #expect(fixture.log.messages(in: .pipeline).filter { $0.contains("unbind refused") }.count == 2)
    }
}

enum StaleSide: Sendable, CustomTestStringConvertible {
    case input, output, both

    var inputIsStale: Bool { self != .output }
    var outputIsStale: Bool { self != .input }
    var testDescription: String {
        switch self {
        case .input: "input"
        case .output: "output"
        case .both: "both"
        }
    }
}

extension Array {
    /// The single element, or `nil` when there are none or several.
    var only: Element? { count == 1 ? first : nil }
}
