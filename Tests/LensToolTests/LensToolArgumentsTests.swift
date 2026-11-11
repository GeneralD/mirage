import Domain
import Testing

@testable import LensTool

/// The grammar of the `lens` command line, over the arguments the entry point hands in without the program name.
@Suite("LensToolArguments")
struct LensToolArgumentsTests {
    // MARK: - The command

    @Test("no argument names no command")
    func noCommand() {
        #expect(LensToolArguments.parse([]) == .failure(.noCommand))
    }

    @Test(
        "a first argument that is not help, validate, new or render is an unknown command, whatever follows it",
        arguments: ["frobnicate", "--version"])
    func unknownCommand(name: String) {
        #expect(LensToolArguments.parse([name]) == .failure(.unknownCommand(name)))
        #expect(LensToolArguments.parse([name, "validate", "Fx.lens"]) == .failure(.unknownCommand(name)))
    }

    // MARK: - help

    @Test("help, --help and -h alone ask for the usage text", arguments: ["help", "--help", "-h"])
    func helpAlone(flag: String) {
        #expect(LensToolArguments.parse([flag]) == .success(.help))
    }

    @Test("an argument after help is unexpected, and the first of them is the one named")
    func helpRejectsArguments() {
        #expect(LensToolArguments.parse(["help", "x"]) == .failure(.unexpectedArgument("x")))
        #expect(LensToolArguments.parse(["--help", "x", "y"]) == .failure(.unexpectedArgument("x")))
        #expect(LensToolArguments.parse(["-h", "--in"]) == .failure(.unexpectedArgument("--in")))
    }

    // MARK: - validate

    @Test("validate takes the package path as its one argument")
    func validateTakesAPath() {
        #expect(LensToolArguments.parse(["validate", "Fx.lens"]) == .success(.validate(path: "Fx.lens")))
    }

    @Test("validate has no option, so any option after it is unknown")
    func validateHasNoOption() {
        #expect(LensToolArguments.parse(["validate", "--x"]) == .failure(.unknownOption("--x")))
        #expect(LensToolArguments.parse(["validate", "--in", "Effects", "Fx.lens"]) == .failure(.unknownOption("--in")))
    }

    @Test("validate without a package names the missing package, and a second argument is unexpected")
    func validateNeedsOnePackage() {
        #expect(LensToolArguments.parse(["validate"]) == .failure(.missingValue("package")))
        #expect(LensToolArguments.parse(["validate", "a", "b"]) == .failure(.unexpectedArgument("b")))
    }

    // MARK: - new

    @Test("new takes the name and an optional --in folder, which is the current folder when --in is not given")
    func newTakesANameAndAFolder() {
        #expect(LensToolArguments.parse(["new", "My Glitch"]) == .success(.scaffold(name: "My Glitch", folder: ".")))
        #expect(LensToolArguments.parse(["new", "X", "--in", "Effects"]) == .success(.scaffold(name: "X", folder: "Effects")))
        #expect(LensToolArguments.parse(["new", "--in", "Effects", "X"]) == .success(.scaffold(name: "X", folder: "Effects")))
    }

    @Test("new without a name names the missing name, even when --in is given")
    func newNeedsAName() {
        #expect(LensToolArguments.parse(["new"]) == .failure(.missingValue("name")))
        #expect(LensToolArguments.parse(["new", "--in", "Effects"]) == .failure(.missingValue("name")))
    }

    @Test("a --in with no value, or with a value that starts with -, names --in as missing")
    func inNeedsAValue() {
        #expect(LensToolArguments.parse(["new", "X", "--in"]) == .failure(.missingValue("--in")))
        #expect(LensToolArguments.parse(["new", "X", "--in", "--in"]) == .failure(.missingValue("--in")))
    }

    @Test("a second --in is a duplicate option, and a second name is an unexpected argument")
    func newRejectsRepeats() {
        #expect(LensToolArguments.parse(["new", "X", "--in", "a", "--in", "b"]) == .failure(.duplicateOption("--in")))
        #expect(LensToolArguments.parse(["new", "X", "Y"]) == .failure(.unexpectedArgument("Y")))
    }

    @Test("an option that the command does not take is unknown, and so is one written with = or as a short flag")
    func newRejectsOtherOptions() {
        #expect(LensToolArguments.parse(["new", "-x"]) == .failure(.unknownOption("-x")))
        #expect(LensToolArguments.parse(["new", "X", "--input", "a"]) == .failure(.unknownOption("--input")))
        #expect(LensToolArguments.parse(["new", "X", "--in=Effects"]) == .failure(.unknownOption("--in=Effects")))
        #expect(LensToolArguments.parse(["new", "X", "--", "Effects"]) == .failure(.unknownOption("--")))
    }

    // MARK: - render

    @Test("render takes an effect, --input and --output, and the options may come in any order")
    func renderTakesEffectAndImages() {
        #expect(
            LensToolArguments.parse(["render", "Vignette", "--input", "a.png", "--output", "b.png"])
                == .success(.render(effect: .bundled(name: "Vignette"), input: "a.png", output: "b.png")))
        #expect(
            LensToolArguments.parse(["render", "Fx.lens", "--output", "b.png", "--input", "a.png"])
                == .success(.render(effect: .package(path: "Fx.lens"), input: "a.png", output: "b.png")))
    }

    @Test(
        "an effect is a package when it ends in .lens once its trailing slashes are dropped, and a bundled effect otherwise",
        arguments: [
            ("Fx.lens", EffectReference.package(path: "Fx.lens")),
            ("Fx.lens/", .package(path: "Fx.lens/")),
            ("Fx.lens//", .package(path: "Fx.lens//")),
            ("Chromatic Grain", .bundled(name: "Chromatic Grain")),
            ("fx.LENS", .bundled(name: "fx.LENS")),
            ("Fx.lens/x", .bundled(name: "Fx.lens/x")),
            ("/", .bundled(name: "/")),
        ])
    func effectKind(effect: String, expected: EffectReference) {
        #expect(
            LensToolArguments.parse(["render", effect, "--input", "a.png", "--output", "b.png"])
                == .success(.render(effect: expected, input: "a.png", output: "b.png")))
    }

    @Test("render names the effect, then --input, then --output, as missing once the line is read")
    func renderNamesTheFirstMissingPiece() {
        #expect(LensToolArguments.parse(["render"]) == .failure(.missingValue("effect")))
        #expect(LensToolArguments.parse(["render", "--output", "b"]) == .failure(.missingValue("effect")))
        #expect(LensToolArguments.parse(["render", "V", "--output", "b"]) == .failure(.missingValue("--input")))
        #expect(LensToolArguments.parse(["render", "V", "--input", "a"]) == .failure(.missingValue("--output")))
    }

    @Test("an option value that is missing or starts with - names that option as missing")
    func renderOptionNeedsAValue() {
        #expect(LensToolArguments.parse(["render", "V", "--input", "--output", "b"]) == .failure(.missingValue("--input")))
    }

    @Test("a second effect is unexpected, and a repeated option is a duplicate, each named where it is read")
    func renderRejectsRepeats() {
        #expect(LensToolArguments.parse(["render", "V", "W", "--input", "a", "--output", "b"]) == .failure(.unexpectedArgument("W")))
        #expect(
            LensToolArguments.parse(["render", "V", "--input", "a", "--input", "b", "--output", "c"])
                == .failure(.duplicateOption("--input")))
    }

    @Test("an option that render does not take is unknown, even after the arguments it needs")
    func renderRejectsOtherOptions() {
        #expect(
            LensToolArguments.parse(["render", "V", "--input", "a", "--output", "b", "--format", "png"])
                == .failure(.unknownOption("--format")))
    }

    @Test("the first problem read from the front is the one named, before a missing piece is looked for")
    func firstProblemWins() {
        #expect(
            LensToolArguments.parse(["render", "--input", "a", "--input", "b"]) == .failure(.duplicateOption("--input")),
            "a repeated option is read before the effect that is missing")
        #expect(
            LensToolArguments.parse(["render", "V", "W", "--output", "b"]) == .failure(.unexpectedArgument("W")),
            "a second effect is read before the --input that is missing")
    }
}
