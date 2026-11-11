import Domain
import Testing

@testable import Presenters

@Suite("PreviewText")
struct PreviewTextTests {
    @Test(
        "the preview is wanted only when the picker is open, the window is visible and a view exists",
        arguments: [
            (false, false, false, false),
            (false, false, true, false),
            (false, true, false, false),
            (false, true, true, false),
            (true, false, false, false),
            (true, false, true, false),
            (true, true, false, false),
            (true, true, true, true),
        ])
    func previewIsWantedOnlyWhenAllThreeHold(isOpen: Bool, isVisible: Bool, hasTarget: Bool, wanted: Bool) {
        #expect(previewIsWanted(isOpen: isOpen, isVisible: isVisible, hasTarget: hasTarget) == wanted)
    }

    @Test(
        "each refusal says why the preview is not shown, in its own words",
        arguments: [
            (PreviewRefusal.noDevice, "No GPU is available, so the preview cannot be shown."),
            (PreviewRefusal.foreignTarget, "The preview could not use its view."),
            (PreviewRefusal.unavailable, "The preview could not start."),
        ])
    func unavailableMessageWording(refusal: PreviewRefusal, message: String) {
        #expect(previewUnavailableMessage(for: refusal) == message)
    }

    @Test("the preview's accessibility label is not empty")
    func accessibilityLabelIsNotEmpty() {
        #expect(!previewAccessibilityLabel.isEmpty)
    }

    @Test("each mode's title and accessibility label is not empty, and differs from the other mode's")
    func modeWordingIsNotEmptyAndDistinct() {
        let titles = PreviewMode.allCases.map(previewModeTitle)
        let labels = PreviewMode.allCases.map(previewModeAccessibilityLabel)

        #expect(titles.allSatisfy { !$0.isEmpty })
        #expect(Set(titles).count == PreviewMode.allCases.count)
        #expect(labels.allSatisfy { !$0.isEmpty })
        #expect(Set(labels).count == PreviewMode.allCases.count)
    }

    @Test("the mode group's accessibility label is not empty")
    func modeGroupAccessibilityLabelIsNotEmpty() {
        #expect(!previewModeGroupAccessibilityLabel.isEmpty)
    }
}
