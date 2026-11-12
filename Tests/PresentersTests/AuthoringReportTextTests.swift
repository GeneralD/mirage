import Domain
import Presenters
import Testing

@Suite("AuthoringReportText")
struct AuthoringReportTextTests {
    // MARK: - Validated

    @Test(
        "validated says no parameters, 1 parameter, or n parameters, after the package's name",
        arguments: [
            (0, "Glitch: OK, no parameters"),
            (1, "Glitch: OK, 1 parameter"),
            (2, "Glitch: OK, 2 parameters"),
        ])
    func validatedCountsParameters(count: Int, expected: String) {
        let parameters = (0..<count).map { EffectParameterSpec(id: "p\($0)", label: "Knob \($0)", kind: .bool(defaultValue: false)) }
        let source = EffectSource(name: "Glitch", source: "", parameters: parameters)

        #expect(AuthoringReportText.validated(source) == expected)
    }

    // MARK: - Scaffolded and rendered

    @Test("scaffolded says the package was created at the path it was given")
    func scaffoldedNamesThePath() {
        #expect(AuthoringReportText.scaffolded(path: "/tmp/Glitch.lens") == "Created /tmp/Glitch.lens")
    }

    @Test(
        "rendered names the output, its 640x480 size, and the effect's label: the bundled name or the package path",
        arguments: [
            (EffectReference.bundled(name: "Chromatic Grain"), "Wrote out.png (640x480) with Chromatic Grain"),
            (EffectReference.package(path: "/effects/glitch.lens"), "Wrote out.png (640x480) with /effects/glitch.lens"),
        ])
    func renderedNamesTheEffect(effect: EffectReference, expected: String) {
        let text = AuthoringReportText.rendered(effect: effect, output: "out.png", size: StillImageSize(width: 640, height: 480))

        #expect(text == expected)
    }

    // MARK: - Failure

    @Test(
        "failure words each authoring failure as the line the tool shows",
        arguments: [
            (AuthoringFailure.packageNotFound(path: "/x"), "error: /x is not a directory"),
            (AuthoringFailure.package(.manifestMissing), "error: manifest.json is missing"),
            (AuthoringFailure.compile(message: "line 3: expected ;"), "error: the shader does not compile\nline 3: expected ;"),
            (AuthoringFailure.bundledEffectNotFound(name: "Nope"), "error: no bundled effect is named \"Nope\""),
            (AuthoringFailure.image(.unreadable(path: "a.png")), "error: cannot read a.png"),
            (AuthoringFailure.image(.tooLarge(limit: 100)), "error: the image file is larger than 100 bytes"),
            (AuthoringFailure.image(.notAnImage(path: "a.txt")), "error: a.txt is not an image the tool can read"),
            (AuthoringFailure.image(.dimensionsOutOfRange(width: 0, height: 9)), "error: an image of 0x9 pixels is not supported"),
            (AuthoringFailure.image(.unwritable(path: "/ro/out.png")), "error: cannot write /ro/out.png"),
            (
                AuthoringFailure.scaffold(.invalidName("a/b")),
                "error: \"a/b\" is not a valid name (1 to 64 letters, digits, spaces, - or _, starting with a letter or digit)"
            ),
            (AuthoringFailure.scaffold(.alreadyExists(path: "/x.lens")), "error: /x.lens already exists"),
            (AuthoringFailure.scaffold(.unwritable(path: "/ro")), "error: cannot write /ro"),
            (AuthoringFailure.effect(.compileFailed), "error: the effect failed: compile failed"),
            (AuthoringFailure.surfaceUnavailable, "error: no surface could be allocated for the image"),
        ])
    func failureWording(failure: AuthoringFailure, expected: String) {
        #expect(AuthoringReportText.failure(failure) == expected)
        #expect(AuthoringReportText.failure(failure).hasPrefix("error: "))
    }

    @Test(
        "every package problem reads as error: followed by the menu's words for it",
        arguments: [
            (EffectPackageProblem.manifestMissing, "manifest.json is missing"),
            (EffectPackageProblem.manifestInvalid(message: "bad json"), "manifest.json is invalid: bad json"),
            (EffectPackageProblem.unsupportedFormatVersion(7), "unsupported formatVersion 7"),
            (EffectPackageProblem.sourceMissing, "effect.metal is missing"),
            (EffectPackageProblem.unreadable(message: "permission denied"), "cannot be read: permission denied"),
        ])
    func packageProblemWording(problem: EffectPackageProblem, reason: String) {
        #expect(AuthoringReportText.failure(.package(problem)) == "error: " + reason)
    }

    @Test(
        "every effect failure reads as error: the effect failed: followed by the menu's words for it",
        arguments: [
            (EffectFailure.compileFailed, "compile failed"),
            (EffectFailure.timeout, "timed out"),
            (EffectFailure.pageFault, "GPU page fault"),
            (EffectFailure.accessRevoked, "GPU access revoked"),
            (EffectFailure.outOfMemory, "out of memory"),
            (EffectFailure.invalidResource, "invalid GPU resource"),
            (EffectFailure.internalError, "internal error"),
            (EffectFailure.unknown(code: 42), "unknown error (42)"),
        ])
    func effectFailureWording(failure: EffectFailure, reason: String) {
        #expect(AuthoringReportText.failure(.effect(failure)) == "error: the effect failed: " + reason)
    }

    // MARK: - Usage

    @Test(
        "usage words each usage problem as the error line the tool shows",
        arguments: [
            (LensUsageProblem.noCommand, "error: no command given"),
            (LensUsageProblem.unknownCommand("frob"), "error: unknown command \"frob\""),
            (LensUsageProblem.missingValue("package"), "error: missing package"),
            (LensUsageProblem.unexpectedArgument("extra"), "error: unexpected argument \"extra\""),
            (LensUsageProblem.unknownOption("--zoom"), "error: unknown option --zoom"),
            (LensUsageProblem.duplicateOption("--input"), "error: --input was given more than once"),
        ])
    func usageWording(problem: LensUsageProblem, expected: String) {
        #expect(AuthoringReportText.usage(problem) == expected)
    }

    // MARK: - Help

    @Test("help is the usage text the tool shows, names the four commands, and ends with exactly one newline")
    func helpIsTheUsageText() {
        let help = AuthoringReportText.help
        let expected = """
            usage: lens-tool <command> [options]

            commands:
              validate <package>                              check a .lens package and compile its shader
              new <name> [--in <folder>]                      create a .lens package from a template
              render <effect> --input <png> --output <png>    run an effect over an image file
              help                                            show this message

            <effect> is a .lens package path or the name of a bundled effect.

            """

        #expect(help == expected)
        #expect(help.hasSuffix("bundled effect.\n"))
        #expect(!help.hasSuffix("\n\n"))
        #expect(help.contains("lens-tool"))
        for command in ["validate", "new", "render", "help"] {
            #expect(help.contains(command))
        }
    }
}
