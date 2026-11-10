import Entity
import Testing

@Suite("Authoring entities")
struct AuthoringEntityTests {
    @Test("a still image size is equal to one with the same width and height, and not to one with them swapped")
    func stillImageSizeEquality() {
        #expect(StillImageSize(width: 4, height: 2) == StillImageSize(width: 4, height: 2))
        #expect(StillImageSize(width: 4, height: 2) != StillImageSize(width: 2, height: 4))
    }

    @Test("a still image is equal to one with the same width, height and bytes, and not to one whose bytes differ by one")
    func stillImageEquality() {
        let bytes: [UInt8] = [0, 0, 0, 255]
        #expect(StillImage(width: 1, height: 1, bgra: bytes) == StillImage(width: 1, height: 1, bgra: bytes))
        #expect(StillImage(width: 1, height: 1, bgra: bytes) != StillImage(width: 1, height: 1, bgra: [0, 0, 0, 254]))
    }

    @Test("a still image problem keeps its payload, so the same case with another path is another problem")
    func stillImageProblemKeepsPayload() {
        #expect(StillImageProblem.unreadable(path: "a") != .unreadable(path: "b"))
        #expect(StillImageProblem.tooLarge(limit: 1) != .tooLarge(limit: 2))
        #expect(StillImageProblem.unreadable(path: "a") != .unwritable(path: "a"))
    }

    @Test("a scaffold problem keeps its payload, so the same case with another path is another problem")
    func scaffoldProblemKeepsPayload() {
        #expect(ScaffoldProblem.alreadyExists(path: "a") != .alreadyExists(path: "b"))
        #expect(ScaffoldProblem.alreadyExists(path: "a") != .unwritable(path: "a"))
    }

    @Test("a package failure is told apart by its reason: a missing manifest is not a missing source")
    func packageFailureKeepsItsReason() {
        #expect(AuthoringFailure.package(.manifestMissing) != .package(.sourceMissing))
        #expect(AuthoringFailure.package(.manifestMissing) == .package(.manifestMissing))
    }

    @Test("the eight authoring failures are eight distinct values in a set")
    func authoringFailureCasesAreDistinct() {
        let failures: [AuthoringFailure] = [
            .packageNotFound(path: "a"),
            .package(.manifestMissing),
            .compile(message: "a"),
            .bundledEffectNotFound(name: "a"),
            .image(.unreadable(path: "a")),
            .scaffold(.invalidName("a")),
            .effect(.compileFailed),
            .surfaceUnavailable,
        ]
        #expect(Set(failures).count == 8)
    }

    @Test("an effect reference named bundled is not the package with the same text")
    func effectReferenceOriginIsPartOfIdentity() {
        #expect(EffectReference.bundled(name: "x") != .package(path: "x"))
    }

    @Test("a render command differs when its effect, its input or its output differs")
    func renderCommandFieldsAreAllPartOfIdentity() {
        let base = LensCommand.render(effect: .bundled(name: "Chromatic"), input: "in.png", output: "out.png")
        #expect(base != LensCommand.render(effect: .package(path: "Chromatic"), input: "in.png", output: "out.png"))
        #expect(base != LensCommand.render(effect: .bundled(name: "Chromatic"), input: "other.png", output: "out.png"))
        #expect(base != LensCommand.render(effect: .bundled(name: "Chromatic"), input: "in.png", output: "other.png"))
    }

    @Test("the four lens commands are four distinct values in a set")
    func lensCommandCasesAreDistinct() {
        let commands: [LensCommand] = [
            .validate(path: "a"),
            .scaffold(name: "a", folder: "b"),
            .render(effect: .bundled(name: "a"), input: "b", output: "c"),
            .help,
        ]
        #expect(Set(commands).count == 4)
    }

    @Test("the six lens usage problems are six distinct values in a set")
    func lensUsageProblemCasesAreDistinct() {
        let problems: [LensUsageProblem] = [
            .noCommand,
            .unknownCommand("x"),
            .missingValue("package"),
            .unexpectedArgument("x"),
            .unknownOption("--x"),
            .duplicateOption("--x"),
        ]
        #expect(Set(problems).count == 6)
    }
}
