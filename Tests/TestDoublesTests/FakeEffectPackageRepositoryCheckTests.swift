import Domain
import TestDoubles
import TestSupport
import Testing

@Suite("FakeEffectPackageRepository check and scaffold", .timeLimit(.minutes(1)))
struct FakeEffectPackageRepositoryCheckTests {
    private let glow = EffectSource(name: "Glow", source: "kernel void effect() {}")

    @Test("a scripted check result is the answer for its path, and the path of each request is kept")
    func scriptedCheckIsAnswered() async {
        let repository = FakeEffectPackageRepository()
        repository.scriptCheck(.success(glow), for: "/work/glow.lens")

        #expect(await repository.check(packageAt: "/work/glow.lens") == .success(glow))
        #expect(repository.checkRequests.values == ["/work/glow.lens"])
    }

    @Test("a scripted check failure is the answer for its path, whatever the failure")
    func scriptedCheckFailureIsAnswered() async {
        let repository = FakeEffectPackageRepository()
        repository.scriptCheck(.failure(.compile(message: "effect:3: error: x")), for: "/work/glow.lens")

        #expect(await repository.check(packageAt: "/work/glow.lens") == .failure(.compile(message: "effect:3: error: x")))
    }

    @Test("a check scripted for one path does not answer another, which is a reported issue answering packageNotFound")
    func scriptedCheckIsKeptPerPath() async {
        let repository = FakeEffectPackageRepository()
        repository.scriptCheck(.success(glow), for: "/work/glow.lens")

        await withKnownIssue("a check nobody scripted for its path is reported") {
            #expect(await repository.check(packageAt: "/work/mist.lens") == .failure(.packageNotFound(path: "/work/mist.lens")))
        }
        #expect(repository.checkRequests.values == ["/work/mist.lens"])
    }

    @Test("a check nobody scripted is a reported issue and answers packageNotFound at its path")
    func unscriptedCheck() async {
        let repository = FakeEffectPackageRepository()

        await withKnownIssue("a check nobody scripted is reported") {
            #expect(await repository.check(packageAt: "/work/glow.lens") == .failure(.packageNotFound(path: "/work/glow.lens")))
        }
    }

    @Test("a scripted scaffold result is the answer, and the name and the folder of each request are kept")
    func scriptedScaffoldIsAnswered() async {
        let repository = FakeEffectPackageRepository()
        repository.scriptScaffold(.success("/work/A.lens"))

        #expect(await repository.scaffold(named: "A", in: "/work") == .success("/work/A.lens"))
        #expect(repository.scaffoldRequests.values == [FakeEffectPackageRepository.ScaffoldRequest(name: "A", folder: "/work")])
    }

    @Test("a scripted scaffold failure is the answer, whatever the request")
    func scriptedScaffoldFailureIsAnswered() async {
        let repository = FakeEffectPackageRepository()
        repository.scriptScaffold(.failure(.alreadyExists(path: "/work/A.lens")))

        #expect(await repository.scaffold(named: "B", in: "/elsewhere") == .failure(.alreadyExists(path: "/work/A.lens")))
    }

    @Test("a scaffold nobody scripted is a reported issue and answers unwritable at the folder")
    func unscriptedScaffold() async {
        let repository = FakeEffectPackageRepository()

        await withKnownIssue("a scaffold nobody scripted is reported") {
            #expect(await repository.scaffold(named: "A", in: "/work") == .failure(.unwritable(path: "/work")))
        }
        #expect(repository.scaffoldRequests.values == [FakeEffectPackageRepository.ScaffoldRequest(name: "A", folder: "/work")])
    }
}
