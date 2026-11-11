import Dependencies
import Domain
import EffectAuthoringInteractor
import TestDoubles
import TestSupport
import Testing

/// `EffectAuthoringInteractorImpl` over `FakeEffectAuthoringUseCase`: the test scripts what the UseCase answers, so
/// what is proven here is only the entry. Each call answers the UseCase's result unchanged, passes its arguments on
/// once, and leaves one developer line about it; no error line is ever written.
@Suite("EffectAuthoringInteractor", .timeLimit(.minutes(1)))
struct EffectAuthoringInteractorTests {
    private struct Rig {
        let useCase: FakeEffectAuthoringUseCase
        let errorLog: RecordingLog
        let developerLog: RecordingLog
        let subject: EffectAuthoringInteractorImpl

        init() {
            let useCase = FakeEffectAuthoringUseCase()
            let errorLog = RecordingLog()
            let developerLog = RecordingLog()
            self.useCase = useCase
            self.errorLog = errorLog
            self.developerLog = developerLog
            subject = withDependencies {
                $0.effectAuthoringUseCase = useCase
                $0.errorLog = errorLog
                $0.developerLog = developerLog
            } operation: {
                EffectAuthoringInteractorImpl()
            }
        }
    }

    private static let path = "/work/glow.lens"

    private static let glow = EffectSource(name: "Glow", source: "kernel void effect() {}")

    private static let image = StillImageSize(width: 640, height: 360)

    // MARK: - validate(packageAt:)

    @Test("validate answers the source that the UseCase answers, and passes the path to the UseCase once")
    func validateAnswersTheSource() async {
        let rig = Rig()
        rig.useCase.scriptValidate(.success(Self.glow), for: Self.path)

        #expect(await rig.subject.validate(packageAt: Self.path) == .success(Self.glow))
        #expect(rig.useCase.validateRequests.values == [Self.path])
    }

    @Test(
        "validate answers the UseCase's failure unchanged, whatever the failure",
        arguments: [
            AuthoringFailure.packageNotFound(path: "p"),
            .package(.manifestMissing),
            .compile(message: "c"),
        ])
    func validateAnswersTheFailure(_ failure: AuthoringFailure) async {
        let rig = Rig()
        rig.useCase.scriptValidate(.failure(failure), for: Self.path)

        #expect(await rig.subject.validate(packageAt: Self.path) == .failure(failure))
        #expect(rig.useCase.validateRequests.values == [Self.path])
    }

    @Test("a validate that passes leaves one developer line that names the package and its source, and no error line")
    func validateLogsTheSuccess() async {
        let rig = Rig()
        rig.useCase.scriptValidate(.success(Self.glow), for: Self.path)

        _ = await rig.subject.validate(packageAt: Self.path)

        #expect(rig.developerLog.entries.count == 1)
        #expect(rig.developerLog.messages(in: .effect) == ["validated package at /work/glow.lens: Glow"])
        #expect(rig.errorLog.entries.count == 0)
    }

    @Test("a validate that fails leaves one developer line that names the failure, and no error line")
    func validateLogsTheFailure() async {
        let rig = Rig()
        rig.useCase.scriptValidate(.failure(.compile(message: "c")), for: Self.path)

        _ = await rig.subject.validate(packageAt: Self.path)

        #expect(rig.developerLog.entries.count == 1)
        #expect(rig.developerLog.messages(in: .effect) == [#"validation of /work/glow.lens failed: compile(message: "c")"#])
        #expect(rig.errorLog.entries.count == 0)
    }

    // MARK: - scaffold(named:in:)

    @Test("scaffold answers the path that the UseCase answers, and passes the name and the folder to the UseCase once")
    func scaffoldAnswersThePath() async {
        let rig = Rig()
        rig.useCase.scriptScaffold(.success("/work/A.lens"))

        #expect(await rig.subject.scaffold(named: "A", in: "/work") == .success("/work/A.lens"))
        #expect(rig.useCase.scaffoldRequests.values == [FakeEffectAuthoringUseCase.ScaffoldRequest(name: "A", folder: "/work")])
    }

    @Test(
        "scaffold answers each failure of the UseCase unchanged",
        arguments: [
            AuthoringFailure.scaffold(.invalidName("x")),
            .scaffold(.alreadyExists(path: "/work/A.lens")),
            .scaffold(.unwritable(path: "/work")),
        ])
    func scaffoldAnswersTheFailure(_ failure: AuthoringFailure) async {
        let rig = Rig()
        rig.useCase.scriptScaffold(.failure(failure))

        #expect(await rig.subject.scaffold(named: "x", in: "/work") == .failure(failure))
    }

    @Test("a scaffold that passes leaves one developer line that names the package and where it was written, and no error line")
    func scaffoldLogsTheSuccess() async {
        let rig = Rig()
        rig.useCase.scriptScaffold(.success("/work/A.lens"))

        _ = await rig.subject.scaffold(named: "A", in: "/work")

        #expect(rig.developerLog.entries.count == 1)
        #expect(rig.developerLog.messages(in: .effect) == ["scaffolded A at /work/A.lens"])
        #expect(rig.errorLog.entries.count == 0)
    }

    @Test("a scaffold that fails leaves one developer line that names the failure, and no error line")
    func scaffoldLogsTheFailure() async {
        let rig = Rig()
        let failure = AuthoringFailure.scaffold(.unwritable(path: "/work"))
        rig.useCase.scriptScaffold(.failure(failure))

        _ = await rig.subject.scaffold(named: "A", in: "/work")

        #expect(rig.developerLog.entries.count == 1)
        #expect(rig.developerLog.messages(in: .effect) == ["scaffold of A in /work failed: \(String(describing: failure))"])
        #expect(rig.errorLog.entries.count == 0)
    }

    // MARK: - render(_:from:to:)

    @Test("render answers the size that the UseCase answers, and passes the effect and both paths to the UseCase once")
    func renderAnswersTheSize() async {
        let rig = Rig()
        rig.useCase.scriptRender(.success(Self.image))

        let answer = await rig.subject.render(.bundled(name: "Glow"), from: "in.png", to: "out.png")
        #expect(answer == .success(Self.image))
        #expect(
            rig.useCase.renderRequests.values
                == [FakeEffectAuthoringUseCase.RenderRequest(effect: .bundled(name: "Glow"), input: "in.png", output: "out.png")])
    }

    @Test(
        "render answers each failure of the UseCase unchanged",
        arguments: [
            AuthoringFailure.image(.unreadable(path: "in.png")),
            .bundledEffectNotFound(name: "Nope"),
            .surfaceUnavailable,
        ])
    func renderAnswersTheFailure(_ failure: AuthoringFailure) async {
        let rig = Rig()
        rig.useCase.scriptRender(.failure(failure))

        #expect(await rig.subject.render(.package(path: Self.path), from: "in.png", to: "out.png") == .failure(failure))
    }

    @Test("a render that passes leaves one developer line that names the effect, both paths and the size, and no error line")
    func renderLogsTheSuccess() async {
        let rig = Rig()
        rig.useCase.scriptRender(.success(Self.image))

        _ = await rig.subject.render(.bundled(name: "Glow"), from: "in.png", to: "out.png")

        #expect(rig.developerLog.entries.count == 1)
        #expect(rig.developerLog.messages(in: .effect) == [#"rendered bundled(name: "Glow") from in.png to out.png: 640x360"#])
        #expect(rig.errorLog.entries.count == 0)
    }

    @Test("a render that fails leaves one developer line that names the failure, and no error line")
    func renderLogsTheFailure() async {
        let rig = Rig()
        rig.useCase.scriptRender(.failure(.surfaceUnavailable))

        _ = await rig.subject.render(.bundled(name: "Glow"), from: "in.png", to: "out.png")

        #expect(rig.developerLog.entries.count == 1)
        #expect(rig.developerLog.messages(in: .effect) == ["render from in.png to out.png failed: surfaceUnavailable"])
        #expect(rig.errorLog.entries.count == 0)
    }

    // MARK: - EffectAuthoringInteractorKey and DependencyValues

    @Test("the key's test value reports each call as not implemented and answers the UseCase's unimplemented failures")
    func testValueReportsEachCall() async {
        let subject = EffectAuthoringInteractorKey.testValue

        await withKnownIssue("validate is not implemented") {
            #expect(await subject.validate(packageAt: Self.path) == .failure(.packageNotFound(path: Self.path)))
        }
        await withKnownIssue("scaffold is not implemented") {
            #expect(await subject.scaffold(named: "A", in: "/work") == .failure(.scaffold(.unwritable(path: "/work"))))
        }
        await withKnownIssue("render is not implemented") {
            #expect(await subject.render(.bundled(name: "Glow"), from: "in.png", to: "out.png") == .failure(.surfaceUnavailable))
        }
    }

    @Test("the dependency value hands out the interactor that was injected for it")
    func dependencyValueHandsOutTheInjectedInteractor() async {
        let fake = FakeEffectAuthoringInteractor()
        fake.scriptScaffold(.success("/work/A.lens"))

        let answer = await withDependencies {
            $0.effectAuthoringInteractor = fake
        } operation: {
            @Dependency(\.effectAuthoringInteractor) var interactor
            return await interactor.scaffold(named: "A", in: "/work")
        }

        #expect(answer == .success("/work/A.lens"))
        #expect(fake.scaffoldRequests.values == [FakeEffectAuthoringInteractor.ScaffoldRequest(name: "A", folder: "/work")])
    }
}
