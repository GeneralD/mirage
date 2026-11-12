import Dependencies
import Domain
import Presenters
import TestDoubles
import TestSupport
import Testing

@testable import LensTool

/// The entry of the `lens` command line over a fake interactor and a recording console. Each command reaches the
/// interactor once with its arguments; a result goes to standard output, a failure or a usage error to standard
/// error, and the exit code says which.
@Suite("LensToolMain", .timeLimit(.minutes(1)))
struct LensToolMainTests {
    // MARK: - No command and help

    @Test("no argument names no command: exit 2, the usage error and the help text on standard error in that order, and the interactor is not called")
    func noCommand() async {
        let rig = LensToolMainRig()

        let code = await rig.subject.run([])

        #expect(code == 2)
        #expect(rig.console.errorLines.values == [AuthoringReportText.usage(.noCommand), AuthoringReportText.help])
        #expect(rig.console.lines.count == 0)
        #expect(rig.interactorCalls == 0)
    }

    @Test("help, --help and -h show the help text on standard output and exit 0", arguments: ["help", "--help", "-h"])
    func helpShowsTheUsage(flag: String) async {
        let rig = LensToolMainRig()

        let code = await rig.subject.run([flag])

        #expect(code == 0)
        #expect(rig.console.lines.values == [AuthoringReportText.help])
        #expect(rig.console.errorLines.count == 0)
        #expect(rig.interactorCalls == 0)
    }

    // MARK: - Usage errors

    @Test(
        "a usage error exits 2 with its message and the help text on standard error, and the interactor is not called",
        arguments: [
            (["frobnicate"], LensUsageProblem.unknownCommand("frobnicate")),
            (["validate"], LensUsageProblem.missingValue("package")),
            (["validate", "a", "b"], LensUsageProblem.unexpectedArgument("b")),
            (["new", "-x"], LensUsageProblem.unknownOption("-x")),
            (["new", "X", "--in"], LensUsageProblem.missingValue("--in")),
            (["render", "V"], LensUsageProblem.missingValue("--input")),
            (["render", "V", "--input", "a", "--input", "b"], LensUsageProblem.duplicateOption("--input")),
        ])
    func usageError(arguments: [String], problem: LensUsageProblem) async {
        let rig = LensToolMainRig()

        let code = await rig.subject.run(arguments)

        #expect(code == 2)
        #expect(rig.console.errorLines.values == [AuthoringReportText.usage(problem), AuthoringReportText.help])
        #expect(rig.console.lines.count == 0)
        #expect(rig.interactorCalls == 0)
    }

    // MARK: - validate

    @Test("validate checks the package at the path it names, and a valid package exits 0 with its line on standard output")
    func validateSucceeds() async {
        let rig = LensToolMainRig()
        let source = EffectSource(name: "Fx", source: "")
        rig.interactor.scriptValidate(.success(source), for: "Fx.lens")

        let code = await rig.subject.run(["validate", "Fx.lens"])

        #expect(code == 0)
        #expect(rig.interactor.validateRequests.values == ["Fx.lens"])
        #expect(rig.console.lines.values == [AuthoringReportText.validated(source)])
        #expect(rig.console.errorLines.count == 0)
    }

    @Test("a package that fails validation exits 1 with the failure on standard error, and standard output stays empty")
    func validateFails() async {
        let rig = LensToolMainRig()
        rig.interactor.scriptValidate(.failure(.package(.manifestMissing)), for: "Fx.lens")

        let code = await rig.subject.run(["validate", "Fx.lens"])

        #expect(code == 1)
        #expect(rig.console.errorLines.values == [AuthoringReportText.failure(.package(.manifestMissing))])
        #expect(rig.console.lines.count == 0)
    }

    // MARK: - new

    @Test("new without --in scaffolds in the current folder, and a created package exits 0 with the path on standard output")
    func scaffoldsInTheCurrentFolder() async {
        let rig = LensToolMainRig()
        rig.interactor.scriptScaffold(.success("./X.lens"))

        let code = await rig.subject.run(["new", "X"])

        #expect(code == 0)
        #expect(rig.interactor.scaffoldRequests.values == [FakeEffectAuthoringInteractor.ScaffoldRequest(name: "X", folder: ".")])
        #expect(rig.console.lines.values == [AuthoringReportText.scaffolded(path: "./X.lens")])
        #expect(rig.console.errorLines.count == 0)
    }

    @Test("new with --in scaffolds in the folder that --in names")
    func scaffoldsInTheGivenFolder() async {
        let rig = LensToolMainRig()
        rig.interactor.scriptScaffold(.success("Effects/X.lens"))

        let code = await rig.subject.run(["new", "X", "--in", "Effects"])

        #expect(code == 0)
        #expect(rig.interactor.scaffoldRequests.values == [FakeEffectAuthoringInteractor.ScaffoldRequest(name: "X", folder: "Effects")])
    }

    @Test("a package that already exists exits 1 with the failure on standard error, and standard output stays empty")
    func scaffoldFails() async {
        let rig = LensToolMainRig()
        rig.interactor.scriptScaffold(.failure(.scaffold(.alreadyExists(path: "p"))))

        let code = await rig.subject.run(["new", "X"])

        #expect(code == 1)
        #expect(rig.console.errorLines.values == [AuthoringReportText.failure(.scaffold(.alreadyExists(path: "p")))])
        #expect(rig.console.lines.count == 0)
    }

    // MARK: - render

    @Test(
        "render runs the effect the argument names, a bundled one or a .lens package, over the input into the output",
        arguments: [
            ("Vignette", EffectReference.bundled(name: "Vignette")),
            ("Fx.lens", EffectReference.package(path: "Fx.lens")),
        ])
    func rendersThroughTheEffect(effect: String, expected: EffectReference) async {
        let rig = LensToolMainRig()
        rig.interactor.scriptRender(.success(StillImageSize(width: 2, height: 1)))

        _ = await rig.subject.run(["render", effect, "--input", "a.png", "--output", "b.png"])

        #expect(
            rig.interactor.renderRequests.values
                == [FakeEffectAuthoringInteractor.RenderRequest(effect: expected, input: "a.png", output: "b.png")])
    }

    @Test("a render that succeeds exits 0 with the output, its size and the effect's label on standard output")
    func renderSucceeds() async {
        let rig = LensToolMainRig()
        let size = StillImageSize(width: 2, height: 1)
        rig.interactor.scriptRender(.success(size))

        let code = await rig.subject.run(["render", "Vignette", "--input", "a.png", "--output", "b.png"])

        #expect(code == 0)
        #expect(rig.console.lines.values == [AuthoringReportText.rendered(effect: .bundled(name: "Vignette"), output: "b.png", size: size)])
        #expect(rig.console.errorLines.count == 0)
    }

    @Test("a render that fails exits 1 with the failure on standard error, and standard output stays empty")
    func renderFails() async {
        let rig = LensToolMainRig()
        rig.interactor.scriptRender(.failure(.image(.notAnImage(path: "a.png"))))

        let code = await rig.subject.run(["render", "Vignette", "--input", "a.png", "--output", "b.png"])

        #expect(code == 1)
        #expect(rig.console.errorLines.values == [AuthoringReportText.failure(.image(.notAnImage(path: "a.png")))])
        #expect(rig.console.lines.count == 0)
    }
}

/// The entry built over the fake interactor and the recording console, so each test sees what reached them.
private struct LensToolMainRig {
    let interactor = FakeEffectAuthoringInteractor()
    let console = RecordingConsole()
    let subject: LensToolMain

    init() {
        let interactor = interactor
        let console = console
        subject = withDependencies {
            $0.effectAuthoringInteractor = interactor
            $0.consoleWriter = console
        } operation: {
            LensToolMain()
        }
    }

    /// How many times the interactor was called, over the three commands.
    var interactorCalls: Int {
        interactor.validateRequests.count + interactor.scaffoldRequests.count + interactor.renderRequests.count
    }
}
