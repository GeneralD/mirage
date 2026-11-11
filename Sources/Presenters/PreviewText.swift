import Domain

// The words and the flag of the live preview window, as pure functions, so that `PreviewPresenter`
// only moves them into its `@Published` values and the window draws them.

/// Whether the preview should be attached: the picker is open, its window is visible and the pane's
/// view exists. Only when all three hold.
func previewIsWanted(isOpen: Bool, isVisible: Bool, hasTarget: Bool) -> Bool {
    isOpen && isVisible && hasTarget
}

/// What the preview pane is called for accessibility.
let previewAccessibilityLabel = "Live camera preview with the chosen effect"

/// What the pane says in place of the preview when the pipeline refused to attach its view.
func previewUnavailableMessage(for refusal: PreviewRefusal) -> String {
    switch refusal {
    case .noDevice: "No GPU is available, so the preview cannot be shown."
    case .foreignTarget: "The preview could not use its view."
    case .unavailable: "The preview could not start."
    }
}
