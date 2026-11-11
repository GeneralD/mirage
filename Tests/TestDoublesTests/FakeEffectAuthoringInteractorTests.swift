import Domain
import TestDoubles
import TestSupport
import Testing

@Suite("FakeEffectAuthoringInteractor", .timeLimit(.minutes(1)))
struct FakeEffectAuthoringInteractorTests {
    private let glow = EffectSource(name: "Glow", source: "kernel void effect() {}")

    private let image = StillImageSize(width: 640, height: 360)

    @Test("a scripted validate answer is the answer for its path, and the path of each call is kept")
    func scriptedValidateIsAnswered() async {
        let interactor = FakeEffectAuthoringInteractor()
        interactor.scriptValidate(.success(glow), for: "/work/glow.lens")

        #expect(await interactor.validate(packageAt: "/work/glow.lens") == .success(glow))
        #expect(interactor.validateRequests.values == ["/work/glow.lens"])
    }

    @Test("a scripted validate failure is the answer for its path, whatever the failure")
    func scriptedValidateFailureIsAnswered() async {
        let interactor = FakeEffectAuthoringInteractor()
        interactor.scriptValidate(.failure(.compile(message: "effect:3: error: x")), for: "/work/glow.lens")

        #expect(await interactor.validate(packageAt: "/work/glow.lens") == .failure(.compile(message: "effect:3: error: x")))
    }

    @Test("a validate nobody scripted is a reported issue and answers packageNotFound at its path")
    func unscriptedValidate() async {
        let interactor = FakeEffectAuthoringInteractor()

        await withKnownIssue("a validate nobody scripted is reported") {
            #expect(await interactor.validate(packageAt: "/work/glow.lens") == .failure(.packageNotFound(path: "/work/glow.lens")))
        }
        #expect(interactor.validateRequests.values == ["/work/glow.lens"])
    }

    @Test("a scripted scaffold answer is the answer, and the name and the folder of each call are kept")
    func scriptedScaffoldIsAnswered() async {
        let interactor = FakeEffectAuthoringInteractor()
        interactor.scriptScaffold(.success("/work/A.lens"))

        #expect(await interactor.scaffold(named: "A", in: "/work") == .success("/work/A.lens"))
        #expect(interactor.scaffoldRequests.values == [FakeEffectAuthoringInteractor.ScaffoldRequest(name: "A", folder: "/work")])
    }

    @Test("a scripted scaffold failure is the answer, whatever the request")
    func scriptedScaffoldFailureIsAnswered() async {
        let interactor = FakeEffectAuthoringInteractor()
        interactor.scriptScaffold(.failure(.scaffold(.alreadyExists(path: "/work/A.lens"))))

        #expect(await interactor.scaffold(named: "B", in: "/elsewhere") == .failure(.scaffold(.alreadyExists(path: "/work/A.lens"))))
    }

    @Test("a scaffold nobody scripted is a reported issue and answers unwritable at the folder")
    func unscriptedScaffold() async {
        let interactor = FakeEffectAuthoringInteractor()

        await withKnownIssue("a scaffold nobody scripted is reported") {
            #expect(await interactor.scaffold(named: "A", in: "/work") == .failure(.scaffold(.unwritable(path: "/work"))))
        }
        #expect(interactor.scaffoldRequests.values == [FakeEffectAuthoringInteractor.ScaffoldRequest(name: "A", folder: "/work")])
    }

    @Test("a scripted render answer is the answer, and the effect and the paths of each call are kept")
    func scriptedRenderIsAnswered() async {
        let interactor = FakeEffectAuthoringInteractor()
        interactor.scriptRender(.success(image))

        #expect(await interactor.render(.bundled(name: "Glow"), from: "in.png", to: "out.png") == .success(image))
        #expect(
            interactor.renderRequests.values
                == [FakeEffectAuthoringInteractor.RenderRequest(effect: .bundled(name: "Glow"), input: "in.png", output: "out.png")])
    }

    @Test("a render nobody scripted is a reported issue and answers surfaceUnavailable")
    func unscriptedRender() async {
        let interactor = FakeEffectAuthoringInteractor()

        await withKnownIssue("a render nobody scripted is reported") {
            #expect(await interactor.render(.bundled(name: "Glow"), from: "in.png", to: "out.png") == .failure(.surfaceUnavailable))
        }
        #expect(
            interactor.renderRequests.values
                == [FakeEffectAuthoringInteractor.RenderRequest(effect: .bundled(name: "Glow"), input: "in.png", output: "out.png")])
    }
}
