import Domain
import TestDoubles
import TestSupport
import Testing

@Suite("FakeEffectAuthoringUseCase render", .timeLimit(.minutes(1)))
struct FakeEffectAuthoringUseCaseRenderTests {
    private static let size = StillImageSize(width: 2, height: 1)

    @Test("a scripted render answer is the answer, and the effect and the paths of each call are kept")
    func scriptedRenderIsAnswered() async {
        let useCase = FakeEffectAuthoringUseCase()
        useCase.scriptRender(.success(Self.size))

        #expect(await useCase.render(.bundled(name: "Glow"), from: "in.png", to: "out.png") == .success(Self.size))
        #expect(
            useCase.renderRequests.values == [
                FakeEffectAuthoringUseCase.RenderRequest(effect: .bundled(name: "Glow"), input: "in.png", output: "out.png")
            ])
    }

    @Test("a scripted render failure is the answer, whatever the request")
    func scriptedRenderFailureIsAnswered() async {
        let useCase = FakeEffectAuthoringUseCase()
        useCase.scriptRender(.failure(.effect(.timeout)))

        #expect(await useCase.render(.package(path: "/work/glow.lens"), from: "a.png", to: "b.png") == .failure(.effect(.timeout)))
    }

    @Test("a render nobody scripted is a reported issue and answers surfaceUnavailable")
    func unscriptedRender() async {
        let useCase = FakeEffectAuthoringUseCase()

        await withKnownIssue("a render nobody scripted is reported") {
            #expect(await useCase.render(.bundled(name: "Glow"), from: "in.png", to: "out.png") == .failure(.surfaceUnavailable))
        }
        #expect(useCase.renderRequests.count == 1)
    }
}
