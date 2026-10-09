import Domain
import EffectRuntimeRepository
import TestSupport
import Testing

@Suite("PassthroughEffectRuntimeRepository", .timeLimit(.minutes(1)))
struct PassthroughEffectRuntimeRepositoryTests {
    private let subject = PassthroughEffectRuntimeRepository()
    private let frame = FrameRef(token: SurfaceToken(index: 0, generation: 1), descriptor: .hd720, presentationTime: .zero)

    @Test("prepare reports the runtime, not the effect, as the failure")
    func prepareFails() async {
        let effect = EffectSource(name: "any", source: "kernel void effect() {}")
        #expect(await subject.prepare(effect).failure == .internalError)
    }

    @Test("apply reports internalError so the pipeline passes the input frame through")
    func applyFails() async {
        let context = FrameContext(presentationTime: .zero, frameIndex: 0)
        #expect(await subject.apply(input: frame, output: frame, frameContext: context).failure == .internalError)
    }
}
