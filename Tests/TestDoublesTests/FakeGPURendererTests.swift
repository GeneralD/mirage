import Domain
import TestDoubles
import TestSupport
import Testing

@Suite("FakeGPURenderer", .timeLimit(.minutes(1)))
struct FakeGPURendererTests {
    private let renderer = FakeGPURenderer()
    private let library = FakeLibraryHandle(source: "kernel void effect() {}")
    private let timing = GPUTiming(gpuStart: 1, gpuEnd: 1.5)

    private func token(_ index: Int) -> SurfaceToken {
        SurfaceToken(index: index, generation: 1)
    }

    private func uniforms(_ frameIndex: UInt32) -> EffectUniforms {
        EffectUniforms(time: 0, frameIndex: frameIndex, resolution: SIMD2(1280, 720), seed: 0)
    }

    @Test("a render suspends until the test completes it, with the answer the test chooses, exactly once")
    func renderIsManual() async throws {
        let task = Task { await renderer.render(library: library, input: token(1), output: token(2), uniforms: uniforms(7)) }
        await renderer.requests.waitForCount(1)
        let request = try #require(renderer.requests.last)
        #expect(ObjectIdentifier(request.library) == ObjectIdentifier(library))
        #expect(request.input == token(1))
        #expect(request.output == token(2))
        #expect(request.uniforms == uniforms(7))
        #expect(renderer.pendingCount == 1)

        #expect(renderer.complete(request, with: .failure(.pageFault)))
        #expect(await task.value == .failure(.pageFault))
        #expect(!renderer.complete(request, with: .success(timing)), "a second completion has nothing to resume")
        #expect(renderer.pendingCount == 0)
    }

    @Test("renders complete in the order the test chooses")
    func rendersCompleteOutOfOrder() async throws {
        let answers = Collector<(frame: UInt32, answer: FakeGPURenderer.Answer)>()
        let render = { (frame: UInt32) in
            Task {
                let answer = await renderer.render(
                    library: library, input: token(Int(frame)), output: token(Int(frame) + 10), uniforms: uniforms(frame))
                answers.append((frame, answer))
            }
        }
        // Started one after the other, so the request order is the test's, not the scheduler's.
        let first = render(1)
        await renderer.requests.waitForCount(1)
        let second = render(2)
        await renderer.requests.waitForCount(2)
        let requests = renderer.requests.values
        #expect(requests.map(\.uniforms.frameIndex) == [1, 2])

        renderer.complete(requests[1], with: .failure(.timeout))
        await answers.waitForCount(1)
        renderer.complete(requests[0], with: .success(timing))
        _ = await (first.value, second.value)

        #expect(answers.values.map(\.frame) == [2, 1])
        #expect(answers.values.map(\.answer) == [.failure(.timeout), .success(timing)])
    }

    @Test("a scripted answer comes back at once and the request is still recorded; nil returns to suspending")
    func scriptedAnswer() async throws {
        renderer.respond(with: .failure(.invalidResource))

        let answer = await renderer.render(library: library, input: token(1), output: token(2), uniforms: uniforms(1))

        #expect(answer == .failure(.invalidResource))
        #expect(renderer.requests.count == 1)
        #expect(renderer.pendingCount == 0)

        renderer.respond(with: nil)
        let task = Task { await renderer.render(library: library, input: token(3), output: token(4), uniforms: uniforms(2)) }
        await renderer.requests.waitForCount(2)
        #expect(renderer.pendingCount == 1)
        renderer.complete(try #require(renderer.requests.last), with: .success(timing))
        #expect(await task.value == .success(timing))
    }

    @Test("a caller cancelled while suspended keeps waiting, as the live renderer does, and receives the answer the test completes")
    func cancellationDoesNotResume() async throws {
        let task = Task { await renderer.render(library: library, input: token(1), output: token(2), uniforms: uniforms(1)) }
        await renderer.requests.waitForCount(1)
        let request = try #require(renderer.requests.last)

        task.cancel()

        // Only `complete` removes a waiting render, so it is still suspended whatever the scheduler did.
        #expect(renderer.pendingCount == 1)
        #expect(renderer.complete(request, with: .failure(.pageFault)))
        #expect(await task.value == .failure(.pageFault))
        #expect(!renderer.complete(request, with: .success(timing)), "a second completion has nothing to resume")
        #expect(renderer.pendingCount == 0)
    }

    @Test("a caller already cancelled is still recorded and waits for its completion")
    func cancelledBeforeTheCall() async throws {
        let gate = Collector<Void>()
        let task = Task {
            await gate.waitForCount(1)
            return await renderer.render(library: library, input: token(1), output: token(2), uniforms: uniforms(1))
        }
        task.cancel()
        gate.append(())

        await renderer.requests.waitForCount(1)
        #expect(task.isCancelled)
        #expect(renderer.pendingCount == 1)
        renderer.complete(try #require(renderer.requests.last), with: .success(timing))
        #expect(await task.value == .success(timing))
        #expect(renderer.pendingCount == 0)
    }

    @Test("a request another FakeGPURenderer issued is refused, and the renders of both fakes stay suspended")
    func foreignRequestIsRefused() async throws {
        let other = FakeGPURenderer()
        let mine = Task { await renderer.render(library: library, input: token(1), output: token(2), uniforms: uniforms(1)) }
        let theirs = Task { await other.render(library: library, input: token(3), output: token(4), uniforms: uniforms(2)) }
        await renderer.requests.waitForCount(1)
        await other.requests.waitForCount(1)
        let own = try #require(renderer.requests.last)
        let foreign = try #require(other.requests.last)
        #expect(foreign.id == own.id, "ids are per instance, so only the origin tells the two apart")

        #expect(!renderer.complete(foreign, with: .failure(.pageFault)))
        #expect(renderer.pendingCount == 1, "the refused completion left this fake's render waiting")
        #expect(other.pendingCount == 1, "and did not answer the issuing fake's render either")

        #expect(renderer.complete(own, with: .success(timing)))
        #expect(await mine.value == .success(timing), "the render received its own completion, not the refused one")
        #expect(other.complete(foreign, with: .failure(.timeout)))
        #expect(await theirs.value == .failure(.timeout))
    }

    @Test("requests are recorded in call order: the ids count up from 1 whether answered at once or suspended")
    func requestsAreNumberedInCallOrder() async throws {
        renderer.respond(with: .success(timing))
        _ = await renderer.render(library: library, input: token(1), output: token(2), uniforms: uniforms(1))
        renderer.respond(with: nil)
        let task = Task { await renderer.render(library: library, input: token(3), output: token(4), uniforms: uniforms(2)) }
        await renderer.requests.waitForCount(2)

        #expect(renderer.requests.values.map(\.id) == [1, 2])
        #expect(renderer.requests.values.map(\.uniforms.frameIndex) == [1, 2])
        renderer.complete(try #require(renderer.requests.last), with: .failure(.timeout))
        #expect(await task.value == .failure(.timeout))
    }
}
