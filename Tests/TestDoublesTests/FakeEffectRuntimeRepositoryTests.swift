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
        let apply = { (index: UInt32) in
            Task {
                let context = FrameContext(presentationTime: HostTimestamp(nanoseconds: UInt64(index)), frameIndex: index)
                let result = await runtime.apply(input: frame(index), output: frame(index + 10), frameContext: context)
                results.append((index, result))
            }
        }
        // Started one after the other, so the request order is the test's, not the scheduler's.
        let first = apply(1)
        await runtime.applyRequests.waitForCount(1)
        let second = apply(2)
        await runtime.applyRequests.waitForCount(2)
        let requests = runtime.applyRequests.values
        #expect(requests.map(\.frameContext.frameIndex) == [1, 2])
        #expect(requests.map(\.output.token.index) == [11, 12])

        runtime.completeApply(requests[1], with: .failure(.timeout))
        await results.waitForCount(1)
        runtime.completeApply(requests[0], with: .success(()))
        _ = await (first.value, second.value)

        #expect(results.values.map(\.index) == [2, 1])
        #expect(results.values.map(\.result.failure) == [.timeout, nil])
    }

    @Test("a caller cancelled while suspended keeps waiting and gets the result the test completes it with")
    func cancellationDoesNotAnswer() async throws {
        let task = Task { await runtime.apply(input: frame(1), output: frame(2), frameContext: FrameContext(presentationTime: .zero, frameIndex: 1)) }
        await runtime.applyRequests.waitForCount(1)
        let request = try #require(runtime.applyRequests.last)

        task.cancel()
        #expect(runtime.pendingCount == 1, "cancellation does not cut the pass short")

        #expect(runtime.completeApply(request, with: .success(())))
        #expect(await task.value.failure == nil, "the caller gets the pass's real outcome")
        #expect(runtime.pendingCount == 0)
    }

    @Test("a caller already cancelled is still recorded and still waits for its completion")
    func cancelledBeforeSuspending() async throws {
        let gate = Collector<Void>()
        let task = Task {
            await gate.waitForCount(1)
            return await runtime.prepare(effect)
        }
        task.cancel()
        gate.append(())

        await runtime.prepareRequests.waitForCount(1)
        let request = try #require(runtime.prepareRequests.last)
        #expect(runtime.pendingCount == 1)

        #expect(runtime.completePrepare(request, with: .failure(.compileFailed)))
        #expect(await task.value.failure == .compileFailed)
        #expect(runtime.pendingCount == 0)
    }
}
