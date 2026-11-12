/// Why the preview refused to attach a window's view.
public enum PreviewRefusal: Sendable, Hashable {
    /// The camera has no GPU device to draw the preview with.
    case noDevice
    /// The view is not a kind of target the preview draws on.
    case foreignTarget
    /// Any other failure to attach.
    case unavailable
}

/// The outcome of attaching a preview window's view to the pipeline.
public enum PreviewAttachResult: Sendable, Hashable {
    case attached
    case refused(PreviewRefusal)
}
