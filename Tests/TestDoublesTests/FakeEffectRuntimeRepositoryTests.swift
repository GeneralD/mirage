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
        let block = EffectParameterBlock(bytes: Array(1...32))
        let task = Task { await runtime.prepare(effect, parameters: block) }
        await runtime.prepareRequests.waitForCount(1)
        let request = try #require(runtime.prepareRequests.last)
        #expect(request.effect == effect)
        #expect(request.parameters == block, "the initial block is recorded with the selection")
        #expect(runtime.pendingCount == 1)

        #expect(runtime.completePrepare(request, with: .failure(.compileFailed)))
        #expect(await task.value.failure == .compileFailed)
        #expect(!runtime.completePrepare(request, with: .success(())), "a second completion has nothing to resume")
        #expect(runtime.pendingCount == 0)
    }

    @Test("setParameters never suspends: every write is recorded in call order and nothing is pending")
    func parameterWritesAreRecorded() {
        let first = EffectParameterBlock(bytes: Array(1...16))
        let second = EffectParameterBlock(bytes: Array(17...32))
        let other = EffectSource(name: "other", source: "kernel void effect() {}")
        runtime.setParameters(first, of: effect)
        runtime.setParameters(second, of: other)

        #expect(
            runtime.parameterWrites.values == [
                FakeEffectRuntimeRepository.ParameterWrite(block: first, source: effect),
                FakeEffectRuntimeRepository.ParameterWrite(block: second, source: other),
            ])
        #expect(runtime.pendingCount == 0)
        #expect(runtime.prepareRequests.count == 0, "a write is not a prepare")
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
            return await runtime.prepare(effect, parameters: .none)
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

    @Test("requests issued by another repository complete nothing here")
    func foreignRequestsAreRefused() async throws {
        let other = FakeEffectRuntimeRepository()
        // One caller at a time, so each repository numbers its prepare 1 and its apply 2.
        let preparing = Task { await runtime.prepare(effect, parameters: .none) }
        await runtime.prepareRequests.waitForCount(1)
        let applying = Task {
            await runtime.apply(input: frame(1), output: frame(2), frameContext: FrameContext(presentationTime: .zero, frameIndex: 1))
        }
        await runtime.applyRequests.waitForCount(1)
        let strangerPreparing = Task { await other.prepare(effect, parameters: .none) }
        await other.prepareRequests.waitForCount(1)
        let strangerApplying = Task {
            await other.apply(input: frame(1), output: frame(2), frameContext: FrameContext(presentationTime: .zero, frameIndex: 1))
        }
        await other.applyRequests.waitForCount(1)
        let strangerPrepare = try #require(other.prepareRequests.last)
        let strangerApply = try #require(other.applyRequests.last)
        // Each repository numbers its calls from 1, so only provenance tells the strangers apart.
        #expect(strangerPrepare.id == runtime.prepareRequests.last?.id)
        #expect(strangerApply.id == runtime.applyRequests.last?.id)

        #expect(!runtime.completePrepare(strangerPrepare, with: .success(())))
        #expect(!runtime.completeApply(strangerApply, with: .success(())))
        #expect(runtime.pendingCount == 2, "neither of this repository's calls was resumed")

        // Each call is completed by the repository that issued it, and only then does it return.
        #expect(runtime.completePrepare(try #require(runtime.prepareRequests.last), with: .failure(.compileFailed)))
        #expect(runtime.completeApply(try #require(runtime.applyRequests.last), with: .failure(.timeout)))
        #expect(other.completePrepare(strangerPrepare, with: .success(())))
        #expect(other.completeApply(strangerApply, with: .success(())))
        #expect(await preparing.value.failure == .compileFailed)
        #expect(await applying.value.failure == .timeout)
        #expect(await strangerPreparing.value.failure == nil)
        #expect(await strangerApplying.value.failure == nil)
    }

    @Test("every outcomes() call opens a stream of its own: each copies what is reported after it was opened, and none replays")
    func outcomesAreCopiedToEveryOpenStream() async throws {
        func outcome(_ seconds: Double) -> EffectPassOutcome {
            EffectPassOutcome(fingerprint: .of(effect), result: .success(GPUTiming(gpuStart: 1, gpuEnd: 1 + seconds)))
        }
        runtime.report(outcome(1))

        let first = runtime.outcomes()
        let second = runtime.outcomes()
        #expect(runtime.outcomeStreams.count == 2, "one element per call")
        runtime.report(outcome(2))
        runtime.report(outcome(3))

        #expect(await first.prefix(2).reduce(into: [EffectPassOutcome]()) { $0.append($1) } == [outcome(2), outcome(3)])
        #expect(await second.prefix(2).reduce(into: [EffectPassOutcome]()) { $0.append($1) } == [outcome(2), outcome(3)])
    }

    @Test("a stream keeps the newest 64 outcomes nobody has read, as the live one does")
    func outcomesKeepTheNewest64() async throws {
        let stream = runtime.outcomes()
        let reported = (0..<70).map { EffectPassOutcome(fingerprint: .of(effect), result: .failure(.unknown(code: $0))) }
        for outcome in reported { runtime.report(outcome) }

        #expect(await stream.prefix(64).reduce(into: [EffectPassOutcome]()) { $0.append($1) } == Array(reported.suffix(64)))
    }

    @Test("an unheld compiler-message query answers with the value set by answerCompilerMessage, and is recorded")
    func compilerMessageAnswersAtOnce() async throws {
        runtime.answerCompilerMessage("first:1:1: error: x")

        #expect(await runtime.compilerMessage(of: effect) == "first:1:1: error: x")
        #expect(runtime.compilerMessageRequests.count == 1)
        #expect(try #require(runtime.compilerMessageRequests.last).effect == effect)
        #expect(runtime.pendingCount == 0)
    }

    @Test("a compiler-message query made while held waits for completeCompilerMessage, resumes with its value, and ignores a stranger's request")
    func compilerMessageIsHeld() async throws {
        runtime.holdCompilerMessages()
        let task = Task { await runtime.compilerMessage(of: effect) }
        await runtime.compilerMessageRequests.waitForCount(1)
        let request = try #require(runtime.compilerMessageRequests.last)
        #expect(request.effect == effect)
        #expect(runtime.pendingCount == 1)

        // A stranger's first query also has id 1, so only its origin tells it apart from the held one.
        let stranger = FakeEffectRuntimeRepository()
        _ = await stranger.compilerMessage(of: effect)
        let strangerRequest = try #require(stranger.compilerMessageRequests.last)
        #expect(strangerRequest.id == request.id)
        #expect(!runtime.completeCompilerMessage(strangerRequest, with: "stranger"))
        #expect(runtime.pendingCount == 1, "the held query was not resumed by the stranger's completion")

        #expect(runtime.completeCompilerMessage(request, with: "first:1:1: error: x"))
        #expect(await task.value == "first:1:1: error: x")
        #expect(!runtime.completeCompilerMessage(request, with: "again"), "a second completion has nothing to resume")
        #expect(runtime.pendingCount == 0)
    }
}
