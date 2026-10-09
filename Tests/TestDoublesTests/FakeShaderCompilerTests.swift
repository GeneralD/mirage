import Domain
import TestDoubles
import TestSupport
import Testing

@Suite("FakeShaderCompiler", .timeLimit(.minutes(1)))
struct FakeShaderCompilerTests {
    private let compiler = FakeShaderCompiler()
    private let slow = EffectSource(name: "slow", source: "kernel void effect() { /* slow */ }")
    private let fast = EffectSource(name: "fast", source: "kernel void effect() { /* fast */ }", options: ShaderCompileOptions(precise: false))

    @Test("compile suspends until the test completes it, with the result the test chooses")
    func compileIsManual() async throws {
        let task = Task { await compiler.compile(slow) }
        await compiler.requests.waitForCount(1)
        let request = try #require(compiler.requests.last)
        #expect(request.effect == slow)
        #expect(compiler.pendingCount == 1)

        let diagnostics = ShaderDiagnostics(message: "effect:3:15: error: expected expression", code: 3)
        #expect(compiler.complete(request, with: .failure(diagnostics)))
        #expect(await task.value.failure == diagnostics)
        #expect(!compiler.complete(request, with: .failure(diagnostics)), "a second completion has nothing to resume")
        #expect(compiler.succeed(request) == nil)
        #expect(compiler.pendingCount == 0)
    }

    @Test("a newer compile can finish before an older one, and each caller gets its own result")
    func completesOutOfOrder() async throws {
        let results = Collector<(name: String, handle: FakeLibraryHandle?)>()
        let start = { (effect: EffectSource) in
            Task {
                let handle = try? await compiler.compile(effect).get()
                results.append((effect.name, handle as? FakeLibraryHandle))
            }
        }
        // Started one after the other, so the request order is the test's, not the scheduler's.
        _ = start(slow)
        await compiler.requests.waitForCount(1)
        _ = start(fast)
        await compiler.requests.waitForCount(2)
        let requests = compiler.requests.values
        #expect(requests.map(\.effect.name) == ["slow", "fast"])

        let fastHandle = try #require(compiler.succeed(requests[1]))
        await results.waitForCount(1)
        let slowHandle = try #require(compiler.succeed(requests[0]))
        await results.waitForCount(2)

        let delivered = results.values
        #expect(delivered.map(\.name) == ["fast", "slow"])
        #expect(delivered.map { $0.handle.map { ObjectIdentifier($0) } } == [ObjectIdentifier(fastHandle), ObjectIdentifier(slowHandle)])
    }

    @Test("succeed hands back a FakeLibraryHandle of the request's source and options, which FakeGPUGateway accepts")
    func succeedMintsAFakeHandle() async throws {
        let task = Task { await compiler.compile(fast) }
        await compiler.requests.waitForCount(1)
        let request = try #require(compiler.requests.last)
        let handle = try #require(compiler.succeed(request))
        #expect(handle.source == fast.source)
        #expect(handle.options == fast.options)
        #expect(ObjectIdentifier(try await task.value.get()) == ObjectIdentifier(handle))

        let gpu = FakeGPUGateway()
        let pass = ComputePass(
            kernel: handle, textures: [], uniforms: EffectUniforms(time: 0, frameIndex: 0, resolution: SIMD2(1, 1), seed: 0),
            grid: .covering(width: 1, height: 1))
        try gpu.encodeAndCommit(pass, on: try gpu.makeContext()) { _ in }
        #expect(gpu.pending.count == 1)
    }

    @Test("a cancelled caller is not resumed early: its old compile can still succeed after a newer one, and it gets that handle")
    func cancelledCallerWaitsForItsResult() async throws {
        let old = Task { await compiler.compile(slow) }
        await compiler.requests.waitForCount(1)
        let new = Task { await compiler.compile(fast) }
        await compiler.requests.waitForCount(2)
        let requests = compiler.requests.values

        old.cancel()
        // Cancellation handlers run inside `cancel()`, so an early resume would already show here.
        #expect(compiler.pendingCount == 2, "the cancelled caller is still suspended")

        let newHandle = try #require(compiler.succeed(requests[1]))
        #expect(ObjectIdentifier(try await new.value.get()) == ObjectIdentifier(newHandle))
        let oldHandle = try #require(compiler.succeed(requests[0]), "the cancelled request is still the test's to complete")
        #expect(ObjectIdentifier(try await old.value.get()) == ObjectIdentifier(oldHandle), "the stale result reaches its cancelled caller")
        #expect(compiler.pendingCount == 0)
    }

    @Test("a caller cancelled before it suspends is still recorded and waits for the test's result")
    func cancelledBeforeSuspending() async throws {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await compiler.compile(slow)
        }
        await compiler.requests.waitForCount(1)
        let request = try #require(compiler.requests.last)
        #expect(request.effect == slow)

        let diagnostics = ShaderDiagnostics(message: "effect:1:1: error: x", code: 3)
        #expect(compiler.complete(request, with: .failure(diagnostics)))
        #expect(await task.value.failure == diagnostics)
        #expect(compiler.pendingCount == 0)
    }
}
