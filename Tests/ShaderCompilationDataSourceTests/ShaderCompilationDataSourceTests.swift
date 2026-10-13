import Dependencies
import Domain
import Foundation
import ShaderCompilationDataSource
import TestDoubles
import TestSupport
import Testing

@Suite("ShaderCompilationDataSource", .timeLimit(.minutes(1)))
struct ShaderCompilationDataSourceTests {
    private let gpu = FakeGPUGateway()
    private let library = FakeShaderLibraryGateway()
    private let work = RecordingWorkRunner()
    private let effect = EffectSource(
        name: "tint", source: "kernel void effect() {}\n", options: ShaderCompileOptions(entryPoint: "main0", precise: false))

    private func makeSubject(work runner: (any WorkRunner)? = nil) -> ShaderCompilationDataSourceImpl {
        withDependencies {
            $0.gpuGateway = gpu
            $0.shaderLibraryGateway = library
            $0.workRunner = runner ?? work
        } operation: {
            ShaderCompilationDataSourceImpl()
        }
    }

    @Test("the compiler gets the prelude, the #line directive and the author's source, with the effect's options")
    func compilesAssembledSource() async throws {
        let handle = try await makeSubject().compile(effect).get()

        let compiled = try #require(handle as? FakeLibraryHandle)
        #expect(compiled.source == ShaderSourceAssembly.assemble(effect.source))
        #expect(compiled.options == effect.options)
        #expect(library.calls.values.map(\.source) == [ShaderSourceAssembly.assemble(effect.source)])
        #expect(gpu.contextCount == 1, "one context for the compile")
    }

    @Test("the compile runs inside a WorkRunner item, off the main thread, even for a caller on the main actor")
    @MainActor
    func compilesOffMain() async throws {
        _ = try await makeSubject().compile(effect).get()

        #expect(work.started.values == [0], "exactly one work item")
        await work.finished.waitForCount(1)
        #expect(library.calls.values.map(\.onMainThread) == [false])
    }

    @Test("nothing reaches the GPU or the compiler until the work item runs")
    func compileWaitsForItsWorkItem() async throws {
        let held = HeldWorkRunner()
        let subject = makeSubject(work: held)
        let task = Task { await subject.compile(effect) }
        await held.items.waitForCount(1)
        #expect(library.calls.count == 0)
        #expect(gpu.contextCount == 0)

        await held.runItem(0)
        _ = try await task.value.get()
        #expect(library.calls.count == 1)
        #expect(gpu.contextCount == 1)
    }

    @Test("a cancelled caller still gets the real result: the compile is neither cut short nor its work item cancelled")
    func cancellationDoesNotShortenTheCompile() async throws {
        let held = HeldWorkRunner()
        let subject = makeSubject(work: held)
        let task = Task { await subject.compile(effect) }
        await held.items.waitForCount(1)
        task.cancel()

        await held.runItem(0)
        let handle = try #require(try await task.value.get() as? FakeLibraryHandle)
        #expect(handle.source == ShaderSourceAssembly.assemble(effect.source))
        #expect(library.calls.count == 1)
        #expect(held.cancelled.count == 0, "nothing cancels the work item")
    }

    @Test("a cancelled caller receives the compiler's real diagnostics, mapped to the author's lines")
    func cancelledCallerGetsDiagnostics() async throws {
        let assembled = ShaderSourceAssembly.assemble(effect.source)
        library.failCompile(
            of: assembled, with: ShaderDiagnostics(message: "program_source:\(ShaderSourceAssembly.authorLineOffset + 1):1: error: x", code: 3))
        let held = HeldWorkRunner()
        let subject = makeSubject(work: held)
        let task = Task { await subject.compile(effect) }
        await held.items.waitForCount(1)
        task.cancel()

        await held.runItem(0)
        #expect(await task.value.failure == ShaderDiagnostics(message: "effect:1:1: error: x", code: 3))
    }

    @Test(
        "an error on any line of a source of any length comes back on the author's line, whichever form the compiler used",
        arguments: Seeds.range(0..<50))
    func diagnosticsMapToAuthorLines(seed: UInt64) async throws {
        var generator = SeededGenerator(seed: seed)
        let lineCount = Int.random(in: 1...60, using: &generator)
        let errorLine = Int.random(in: 1...lineCount, using: &generator)
        let column = Int.random(in: 1...80, using: &generator)
        let broken = "    float broken = 1.0 +;"
        let lines = (1...lineCount).map { $0 == errorLine ? broken : Self.filler.randomElement(using: &generator) ?? "" }
        let author = lines.joined(separator: "\n") + (Bool.random(using: &generator) ? "\n" : "")
        let assembled = ShaderSourceAssembly.assemble(author)
        let assembledLine = ShaderSourceAssembly.authorLineOffset + errorLine

        // The directive's arithmetic: the broken line sits where `#line 1` says author line `errorLine` is.
        let assembledLines = assembled.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(assembledLines[ShaderSourceAssembly.authorLineOffset - 1] == "#line 1 \"effect\"")
        #expect(assembledLines[assembledLine - 1] == broken)

        let expected = ShaderDiagnostics(message: "effect:\(errorLine):\(column): error: expected expression\n\(broken)\n", code: 3)
        let subject = makeSubject()
        for location in ["program_source:\(assembledLine)", "effect:\(errorLine)"] {
            let raw = ShaderDiagnostics(message: "\(location):\(column): error: expected expression\n\(broken)\n", code: 3)
            library.failCompile(of: assembled, with: raw)
            let result = await subject.compile(EffectSource(name: "seed \(seed)", source: author))
            #expect(result.failure == expected, "compiler reported \(location)")
        }
    }

    @Test("a context that cannot be made comes back as diagnostics, and the compiler is never asked")
    func contextFailure() async throws {
        gpu.failMakeContext(with: .noDevice)
        let diagnostics = try #require(await makeSubject().compile(effect).failure)

        #expect(diagnostics.message.hasPrefix("no GPU context to compile on: noDevice"))
        #expect(diagnostics.code == (GPUError.noDevice as NSError).code)
        #expect(diagnostics.cause == .environment, "not the source's fault: the runtime may try again")
        #expect(library.calls.count == 0)
    }

    @Test("a source the compiler rejects is the source's fault: its diagnostics carry the source cause")
    func sourceFailureCause() async throws {
        let assembled = ShaderSourceAssembly.assemble(effect.source)
        library.failCompile(of: assembled, with: ShaderDiagnostics(message: "program_source:1:1: error: x", code: 3))
        let diagnostics = try #require(await makeSubject().compile(effect).failure)

        #expect(diagnostics.cause == .source)
    }

    @Test("nothing is cached: the same effect compiled twice reaches the compiler twice")
    func noCache() async throws {
        let subject = makeSubject()
        let first = try await subject.compile(effect).get()
        let second = try await subject.compile(effect).get()

        #expect(library.calls.count == 2)
        #expect(ObjectIdentifier(first) != ObjectIdentifier(second), "caching is EffectRuntimeRepository's")
    }

    /// Lines an author might write around the broken one; none of them breaks the arithmetic.
    private static let filler = [
        "", "kernel void effect(texture2d<float, access::write> out [[texture(0)]],", "    // a: b: 12: comment",
        "    float v = hash(gid, u.frameIndex, u.seed);", "#define SCALE 3", "}", "\t", "    out.write(float4(v), gid);",
    ]
}

/// A `WorkRunner` that holds every item until the test runs it, so the suite can
/// look at the compile before its work item has run. Records every
/// `WorkHandle.cancel()` by item index.
private final class HeldWorkRunner: WorkRunner, Sendable {
    let items = Collector<Item>()
    let cancelled = Collector<Int>()

    struct Item: Sendable {
        let work: @Sendable () async -> Void
    }

    func run(_ work: @escaping @Sendable () async -> Void) -> any WorkHandle {
        let index = items.count
        items.append(Item(work: work))
        return Handle(index: index, cancelled: cancelled)
    }

    func runItem(_ index: Int) async {
        await items.values[index].work()
    }

    private struct Handle: WorkHandle {
        let index: Int
        let cancelled: Collector<Int>

        func cancel() {
            cancelled.append(index)
        }
    }
}
