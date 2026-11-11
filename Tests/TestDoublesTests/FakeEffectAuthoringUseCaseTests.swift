import Domain
import TestDoubles
import TestSupport
import Testing

@Suite("FakeEffectAuthoringUseCase", .timeLimit(.minutes(1)))
struct FakeEffectAuthoringUseCaseTests {
    private let glow = EffectSource(name: "Glow", source: "kernel void effect() {}")

    @Test("a scripted validate answer is the answer for its path, and the path of each call is kept")
    func scriptedValidateIsAnswered() async {
        let useCase = FakeEffectAuthoringUseCase()
        useCase.scriptValidate(.success(glow), for: "/work/glow.lens")

        #expect(await useCase.validate(packageAt: "/work/glow.lens") == .success(glow))
        #expect(useCase.validateRequests.values == ["/work/glow.lens"])
    }

    @Test("a scripted validate failure is the answer for its path, whatever the failure")
    func scriptedValidateFailureIsAnswered() async {
        let useCase = FakeEffectAuthoringUseCase()
        useCase.scriptValidate(.failure(.compile(message: "effect:3: error: x")), for: "/work/glow.lens")

        #expect(await useCase.validate(packageAt: "/work/glow.lens") == .failure(.compile(message: "effect:3: error: x")))
    }

    @Test("a validate nobody scripted is a reported issue and answers packageNotFound at its path")
    func unscriptedValidate() async {
        let useCase = FakeEffectAuthoringUseCase()

        await withKnownIssue("a validate nobody scripted is reported") {
            #expect(await useCase.validate(packageAt: "/work/glow.lens") == .failure(.packageNotFound(path: "/work/glow.lens")))
        }
        #expect(useCase.validateRequests.values == ["/work/glow.lens"])
    }

    @Test("a scripted scaffold answer is the answer, and the name and the folder of each call are kept")
    func scriptedScaffoldIsAnswered() async {
        let useCase = FakeEffectAuthoringUseCase()
        useCase.scriptScaffold(.success("/work/A.lens"))

        #expect(await useCase.scaffold(named: "A", in: "/work") == .success("/work/A.lens"))
        #expect(useCase.scaffoldRequests.values == [FakeEffectAuthoringUseCase.ScaffoldRequest(name: "A", folder: "/work")])
    }

    @Test("a scripted scaffold failure is the answer, whatever the request")
    func scriptedScaffoldFailureIsAnswered() async {
        let useCase = FakeEffectAuthoringUseCase()
        useCase.scriptScaffold(.failure(.scaffold(.alreadyExists(path: "/work/A.lens"))))

        #expect(await useCase.scaffold(named: "B", in: "/elsewhere") == .failure(.scaffold(.alreadyExists(path: "/work/A.lens"))))
    }

    @Test("a scaffold nobody scripted is a reported issue and answers unwritable at the folder")
    func unscriptedScaffold() async {
        let useCase = FakeEffectAuthoringUseCase()

        await withKnownIssue("a scaffold nobody scripted is reported") {
            #expect(await useCase.scaffold(named: "A", in: "/work") == .failure(.scaffold(.unwritable(path: "/work"))))
        }
        #expect(useCase.scaffoldRequests.values == [FakeEffectAuthoringUseCase.ScaffoldRequest(name: "A", folder: "/work")])
    }
}
