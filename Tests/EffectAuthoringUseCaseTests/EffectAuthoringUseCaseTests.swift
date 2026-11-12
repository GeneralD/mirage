import Dependencies
import Domain
import EffectAuthoringUseCase
import TestDoubles
import Testing

/// `EffectAuthoringUseCaseImpl` over `FakeEffectPackageRepository`: the test scripts what the Repository's
/// check and scaffold answer, so what is proven here is only the policy: `validate` answers the check
/// unchanged, and `scaffold` answers the path unchanged and wraps each problem as `.scaffold`.
@Suite("EffectAuthoringUseCase", .timeLimit(.minutes(1)))
struct EffectAuthoringUseCaseTests {
    private struct Rig {
        let repository: FakeEffectPackageRepository
        let subject: EffectAuthoringUseCaseImpl

        init() {
            let repository = FakeEffectPackageRepository()
            self.repository = repository
            subject = withDependencies {
                $0.effectPackageRepository = repository
            } operation: {
                EffectAuthoringUseCaseImpl()
            }
        }
    }

    private static let path = "/work/glow.lens"

    private static let glow = EffectSource(name: "Glow", source: "kernel void effect() {}")

    // MARK: - validate(packageAt:)

    @Test("validate answers the source that the repository's check answers, and passes the path to the repository once")
    func validateAnswersTheSource() async {
        let rig = Rig()
        rig.repository.scriptCheck(.success(Self.glow), for: Self.path)

        #expect(await rig.subject.validate(packageAt: Self.path) == .success(Self.glow))
        #expect(rig.repository.checkRequests.values == [Self.path])
    }

    @Test(
        "validate answers the repository's failure unchanged, whatever the failure",
        arguments: [
            AuthoringFailure.packageNotFound(path: "p"),
            .package(.manifestMissing),
            .package(.manifestInvalid(message: "m")),
            .compile(message: "c"),
        ])
    func validateAnswersTheFailure(_ failure: AuthoringFailure) async {
        let rig = Rig()
        rig.repository.scriptCheck(.failure(failure), for: Self.path)

        #expect(await rig.subject.validate(packageAt: Self.path) == .failure(failure))
        #expect(rig.repository.checkRequests.values == [Self.path])
    }

    // MARK: - scaffold(named:in:)

    @Test("scaffold answers the path that the repository's scaffold answers, and passes the name and the folder once")
    func scaffoldAnswersThePath() async {
        let rig = Rig()
        rig.repository.scriptScaffold(.success("/work/A.lens"))

        #expect(await rig.subject.scaffold(named: "A", in: "/work") == .success("/work/A.lens"))
        #expect(rig.repository.scaffoldRequests.values == [FakeEffectPackageRepository.ScaffoldRequest(name: "A", folder: "/work")])
    }

    @Test(
        "scaffold wraps each failure of the repository as .scaffold with that same problem",
        arguments: [
            ScaffoldProblem.invalidName("x"),
            .alreadyExists(path: "p"),
            .unwritable(path: "p"),
        ])
    func scaffoldWrapsTheProblem(_ problem: ScaffoldProblem) async {
        let rig = Rig()
        rig.repository.scriptScaffold(.failure(problem))

        #expect(await rig.subject.scaffold(named: "x", in: "/work") == .failure(.scaffold(problem)))
    }
}
