import Dependencies
import Domain
import EffectPackageRepository
import TestDoubles
import TestSupport
import Testing

/// `check(packageAt:)` and `scaffold(named:in:)` of the catalog Repository, over `FakeEffectPackages` and
/// `FakeShaderCompiler`: the test scripts what the folder answers and completes each compile by hand, so the
/// order of the calls is written down and nothing waits for a file or a GPU. What the Repository decides is
/// what is proven here: which answer of the folder becomes which failure, what reaches the compiler, and what
/// the compiler's message becomes.
@Suite("EffectPackageRepository check", .timeLimit(.minutes(1)))
struct EffectPackageRepositoryCheckTests {
    private struct Rig {
        let packages: FakeEffectPackages
        let compiler: FakeShaderCompiler
        let subject: EffectPackageRepositoryImpl

        init() {
            let packages = FakeEffectPackages()
            let compiler = FakeShaderCompiler()
            self.packages = packages
            self.compiler = compiler
            subject = withDependencies {
                $0.effectPackages = packages
                $0.shaderCompiler = compiler
            } operation: {
                EffectPackageRepositoryImpl()
            }
        }
    }

    private static let path = "/work/glow.lens"

    private static let glowSource = "kernel void effect() { /* glow */ }"

    private static func ready(_ key: String, named name: String, source: String = Self.glowSource) -> EffectPackageListing {
        .ready(.fixture(.package(key), name: name, source: source))
    }

    // MARK: - check(packageAt:)

    @Test("a ready package that compiles answers .success with its own source, and the compiler was given that same source")
    func readyPackageAnswersItsSource() async throws {
        let rig = Rig()
        rig.packages.script(Self.ready("glow", named: "Glow"), atPath: Self.path)

        let answer = Task { await rig.subject.check(packageAt: Self.path) }
        await rig.compiler.requests.waitForCount(1)
        let request = try #require(rig.compiler.requests.last)
        #expect(request.effect == EffectSource(name: "Glow", source: Self.glowSource))
        #expect(rig.compiler.succeed(request) != nil)

        #expect(await answer.value == .success(EffectSource(name: "Glow", source: Self.glowSource)))
    }

    @Test("a shader that does not compile answers .compile with the compiler's message, unchanged")
    func compileFailureAnswersTheMessage() async throws {
        let rig = Rig()
        rig.packages.script(Self.ready("glow", named: "Glow"), atPath: Self.path)

        let answer = Task { await rig.subject.check(packageAt: Self.path) }
        await rig.compiler.requests.waitForCount(1)
        let request = try #require(rig.compiler.requests.last)
        let diagnostics = ShaderDiagnostics(message: "effect:3: error: x", code: 1)
        #expect(rig.compiler.complete(request, with: .failure(diagnostics)))

        #expect(await answer.value == .failure(.compile(message: "effect:3: error: x")))
    }

    @Test("a folder with no package at the path answers .packageNotFound with that path, and the compiler is never called")
    func missingPackageAnswersNotFound() async {
        let rig = Rig()

        #expect(await rig.subject.check(packageAt: Self.path) == .failure(.packageNotFound(path: Self.path)))
        #expect(rig.compiler.requests.count == 0)
    }

    @Test(
        "a broken package answers .package with its own problem, and the compiler is never called",
        arguments: [
            EffectPackageProblem.manifestMissing,
            .manifestInvalid(message: "m"),
            .unsupportedFormatVersion(9),
            .sourceMissing,
            .unreadable(message: "u"),
        ])
    func brokenPackageAnswersItsProblem(_ problem: EffectPackageProblem) async {
        let rig = Rig()
        rig.packages.script(.broken(.package("glow"), problem), atPath: Self.path)

        #expect(await rig.subject.check(packageAt: Self.path) == .failure(.package(problem)))
        #expect(rig.compiler.requests.count == 0)
    }

    @Test("check hands the path to package(atPath:) once, exactly as it was given, and reads nothing else")
    func checkPassesThePathThrough() async {
        let rig = Rig()
        let path = "/work/My Effect.lens/"
        rig.packages.script(.broken(.package("glow"), .sourceMissing), atPath: path)

        _ = await rig.subject.check(packageAt: path)

        #expect(rig.packages.pathRequests.values == [path])
        #expect(rig.packages.packageRequests.count == 0)
        #expect(rig.packages.listingCalls.count == 0)
    }

    // MARK: - scaffold(named:in:)

    @Test(
        "scaffold hands the name and the folder to the folder once, unchanged, and answers what the folder answers, unchanged",
        arguments: [
            Result<String, ScaffoldProblem>.success("/work/A.lens"),
            .failure(.invalidName("A")),
            .failure(.alreadyExists(path: "/work/A.lens")),
            .failure(.unwritable(path: "/work")),
        ])
    func scaffoldPassesThrough(_ answer: Result<String, ScaffoldProblem>) async {
        let rig = Rig()
        rig.packages.scriptScaffold(answer)

        #expect(await rig.subject.scaffold(named: "A", in: "/work") == answer)
        #expect(rig.packages.scaffoldRequests.values == [FakeEffectPackages.ScaffoldRequest(name: "A", folder: "/work")])
    }
}
