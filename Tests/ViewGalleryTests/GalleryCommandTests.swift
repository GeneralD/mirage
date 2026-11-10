import TestSupport
import Testing

@testable import ViewGallery

private final class Marker {}

/// A screen that opens nothing real: the command only looks at names and summaries.
private func screen(_ name: String, _ summary: String = "A screen") -> GalleryScreen {
    GalleryScreen(name: name, summary: summary) { Marker() }
}

/// What a run printed and decided.
private struct Run {
    let outcome: GalleryCommand.Outcome
    let output: [String]
    let errors: [String]
}

private func run(_ arguments: [String], screens: [GalleryScreen]) -> Run {
    let output = Collector<String>()
    let errors = Collector<String>()
    let outcome = GalleryCommand(screens: screens).run(arguments: arguments, output: { output.append($0) }, errorOutput: { errors.append($0) })
    return Run(outcome: outcome, output: output.values, errors: errors.values)
}

@Suite("GalleryCommand")
struct GalleryCommandTests {
    private let screens = [screen("effect-picker", "The picker"), screen("parameter-panel", "The panel")]

    @Test("--list prints one `name<TAB>summary` line per screen in registry order and exits 0")
    func listPrintsEveryScreen() {
        let result = run(["--list"], screens: screens)

        #expect(result.output == ["effect-picker\tThe picker", "parameter-panel\tThe panel"])
        #expect(result.errors.isEmpty)
        #expect(result.outcome == .exit(0))
    }

    @Test("--list with no screens prints nothing and exits 0")
    func listOfNothing() {
        let result = run(["--list"], screens: [])

        #expect(result.output.isEmpty)
        #expect(result.errors.isEmpty)
        #expect(result.outcome == .exit(0))
    }

    @Test("a registered name launches that screen and prints nothing")
    func registeredNameLaunches() {
        let result = run(["parameter-panel"], screens: screens)

        #expect(result.outcome == .launch(screens[1]))
        #expect(result.output.isEmpty)
        #expect(result.errors.isEmpty)
    }

    @Test("an unknown name is named on the error output with the screens there are, and exits 2")
    func unknownName() {
        let result = run(["nope"], screens: screens)

        #expect(result.errors == ["gallery: no screen named \"nope\"; screens: effect-picker, parameter-panel"])
        #expect(result.output.isEmpty)
        #expect(result.outcome == .exit(2))
    }

    @Test("an unknown name with no screens registered says there are none")
    func unknownNameWithoutScreens() {
        let result = run(["nope"], screens: [])

        #expect(result.errors == ["gallery: no screen named \"nope\"; screens: (none)"])
        #expect(result.outcome == .exit(2))
    }

    @Test("no arguments print the usage on the error output and exit 2")
    func noArguments() {
        let result = run([], screens: screens)

        #expect(result.errors == ["usage: view-gallery <screen> | --list | --help"])
        #expect(result.output.isEmpty)
        #expect(result.outcome == .exit(2))
    }

    @Test("--help and -h print the usage on the output and exit 0", arguments: ["--help", "-h"])
    func help(flag: String) {
        let result = run([flag], screens: screens)

        #expect(result.output == ["usage: view-gallery <screen> | --list | --help"])
        #expect(result.errors.isEmpty)
        #expect(result.outcome == .exit(0))
    }

    @Test("an option the gallery does not know is an unexpected argument, never a screen name")
    func unknownOption() {
        let result = run(["--bogus"], screens: [screen("--bogus")])

        #expect(result.errors == ["gallery: unexpected argument \"--bogus\""])
        #expect(result.outcome == .exit(2))
    }

    @Test(
        "a second argument is named as unexpected, and nothing is listed or launched",
        arguments: [["--list", "x"], ["effect-picker", "x"]])
    func extraArgument(arguments: [String]) {
        let result = run(arguments, screens: screens)

        #expect(result.errors == ["gallery: unexpected argument \"x\""])
        #expect(result.output.isEmpty)
        #expect(result.outcome == .exit(2))
    }
}
