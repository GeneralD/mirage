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
}
