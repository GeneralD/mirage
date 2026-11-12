import Domain
import TestDoubles
import TestSupport
import Testing

@testable import PreviewDataSource

@Suite("PreviewDataSourceImpl split kernel compile", .timeLimit(.minutes(1)))
struct PreviewDataSourceSplitCompileTests {
    private let rig = PreviewRig()

    @Test("attach compiles the split kernel right after the blit kernel, with the split options, on the executor and off the main thread")
    func splitKernelCompilesAfterBlitKernel() async throws {
        try await rig.attach()
        #expect(rig.compiler.calls.count == 0, "the compiles wait for the executor")

        rig.executor.drain()

        #expect(rig.compiler.calls.values.map(\.source) == [PreviewKernel.source, PreviewKernel.splitSource])
        #expect(rig.compiler.calls.values.map(\.options) == [PreviewKernel.options, PreviewKernel.splitOptions])
        #expect(rig.compiler.calls.values.map(\.onMainThread) == [false, false])
    }

    @Test("a split kernel that does not compile keeps the attach, draws the frame with the blit kernel and logs one line")
    func splitCompileFailureKeepsTheAttach() async throws {
        rig.compiler.failCompile(of: PreviewKernel.splitSource, with: ShaderDiagnostics(message: "split: error", code: 5))
        try await rig.attach()
        rig.executor.drain()

        rig.present(try rig.frame(1))
        rig.executor.drain()

        let draw = try #require(rig.preview.pending.first)
        #expect(draw.kernel.source == PreviewKernel.source)
        #expect(draw.kernel.options == PreviewKernel.options, "the blit kernel draws; the split is not drawn with yet")
        #expect(rig.frameNumber(of: draw) == 1)
        #expect(rig.log.messages(in: .preview) == ["preview split unavailable, its kernel did not compile (5): split: error"])
    }

    @Test("a blit kernel that does not compile attaches nothing, so the split kernel is never compiled")
    func blitCompileFailureSkipsTheSplit() async throws {
        rig.compiler.failCompile(of: PreviewKernel.source, with: ShaderDiagnostics(message: "blit: error", code: 3))
        try await rig.attach()
        rig.executor.drain()

        #expect(rig.compiler.calls.values.map(\.source) == [PreviewKernel.source], "the split kernel is not compiled")

        rig.present(try rig.frame(1))
        rig.executor.drain()

        #expect(rig.completed.values == [1])
        #expect(rig.preview.draws.count == 0)
        #expect(rig.log.messages(in: .preview) == ["preview detached, its kernel did not compile (3): blit: error"])
    }
}
