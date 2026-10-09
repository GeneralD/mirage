import Domain
import TestDoubles
import TestSupport
import Testing

@Suite("FakeEffectRuntimeRepository", .timeLimit(.minutes(1)))
struct FakeEffectRuntimeRepositoryTests {
    private let runtime = FakeEffectRuntimeRepository()
    private let effect = EffectSource(name: "e", source: "kernel void effect() {}")

    private func frame(_ index: UInt32) -> FrameRef {
        FrameRef(
            token: SurfaceToken(index: Int(index), generation: 1), descriptor: .hd720, presentationTime: HostTimestamp(nanoseconds: UInt64(index)))
    }

    @Test("prepare suspends until the test completes it, with the result the test chooses")
    func prepareIsManual() async throws {
        let task = Task { await runtime.prepare(effect) }
        await runtime.prepareRequests.waitForCount(1)
        let request = try #require(runtime.prepareRequests.last)
        #expect(request.effect == effect)
        #expect(runtime.pendingCount == 1)

        #expect(runtime.completePrepare(request, with: .failure(.compileFailed)))
        #expect(await task.value.failure == .compileFailed)
        #expect(!runtime.completePrepare(request, with: .success(())), "a second completion has nothing to resume")
        #expect(runtime.pendingCount == 0)
    }

    @Test("applies complete in the order the test chooses")
    func appliesCompleteOutOfOrder() async throws {
        let results = Collector<(index: UInt32, result: Result<Void, EffectFailure>)>()
        let tasks = (1...2).map { (index: UInt32) in
            Task {
                let context = FrameContext(presentationTime: HostTimestamp(nanoseconds: UInt64(index)), frameIndex: index)
                let result = await runtime.apply(input: frame(index), output: frame(index + 10), frameContext: context)
                results.append((index, result))
            }
        }
        await runtime.applyRequests.waitForCount(2)
        let requests = runtime.applyRequests.values
        #expect(requests.map(\.frameContext.frameIndex) == [1, 2])
        #expect(requests.map(\.output.token.index) == [11, 12])

        runtime.completeApply(requests[1], with: .failure(.timeout))
        await results.waitForCount(1)
        runtime.completeApply(requests[0], with: .success(()))
        for task in tasks { _ = await task.value }

        #expect(results.values.map(\.index) == [2, 1])
        #expect(results.values.map(\.result.failure) == [.timeout, nil])
    }

    @Test("a cancelled caller is resumed with internalError and cannot be completed afterwards")
    func cancellationResumes() async throws {
        let task = Task { await runtime.apply(input: frame(1), output: frame(2), frameContext: FrameContext(presentationTime: .zero, frameIndex: 1)) }
        await runtime.applyRequests.waitForCount(1)
        let request = try #require(runtime.applyRequests.last)

        task.cancel()

        #expect(await task.value.failure == .internalError)
        #expect(!runtime.completeApply(request, with: .success(())))
        #expect(runtime.pendingCount == 0)
    }
}
