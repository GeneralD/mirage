import Presenters
import Testing

@Suite("OnboardingGeometry")
struct OnboardingGeometryTests {
    @Test("the window and the message block keep the constants the layout was designed with")
    func constantsEqualTheWrittenValues() {
        #expect(OnboardingGeometry.windowWidth == 480)
        #expect(OnboardingGeometry.initialWindowHeight == 480)
        #expect(OnboardingGeometry.inset == 24)
        #expect(OnboardingGeometry.spacing == 16)
        #expect(OnboardingGeometry.lineHeight == 15)
        #expect(OnboardingGeometry.messagePadding == 8)
        #expect(OnboardingGeometry.minimumMessageHeight == 60)
        #expect(OnboardingGeometry.maximumMessageHeight == 240)
    }

    @Test(
        "a message that is nil, empty, blank or only newlines leaves no message block",
        arguments: [nil, "", "   ", "\n", " \r\n\t "] as [String?])
    func noBlockWithoutText(message: String?) {
        #expect(OnboardingGeometry(message: message).messageHeight == 0)
    }

    @Test("one line is raised to the minimum message height of 60")
    func oneLineIsTheMinimum() {
        #expect(OnboardingGeometry(message: "Compile error").messageHeight == 60)
    }

    @Test("five lines are 5 × 15 + 16 = 91 high")
    func fiveLinesAreNinetyOne() {
        #expect(OnboardingGeometry(message: "1\n2\n3\n4\n5").messageHeight == 91)
    }

    @Test("a trailing newline does not count as a line")
    func trailingNewlineIsNotALine() {
        #expect(OnboardingGeometry(message: "1\n2\n3\n4\n5\n").messageHeight == 91)
    }

    @Test("a CRLF is one newline, not two")
    func crlfIsOneNewline() {
        #expect(OnboardingGeometry(message: "1\r\n2\r\n3\r\n4\r\n5").messageHeight == 91)
    }

    @Test("an empty line in the middle counts as a line")
    func middleEmptyLineCounts() {
        #expect(OnboardingGeometry(message: "1\n\n3").messageHeight == 61)
    }

    @Test("a long line that wraps counts as one line, since the View scrolls the wrapped text")
    func wrappingIsNotCounted() {
        #expect(OnboardingGeometry(message: String(repeating: "x", count: 500)).messageHeight == 60)
    }

    @Test("a hundred lines are capped at the maximum message height of 240")
    func hundredLinesAreCapped() {
        let message = (1...100).map(String.init).joined(separator: "\n")

        #expect(OnboardingGeometry(message: message).messageHeight == 240)
    }
}
