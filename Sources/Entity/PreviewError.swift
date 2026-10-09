/// Failures at the preview boundary.
public enum PreviewError: Error, Sendable, Hashable {
    /// The target was not produced by this sink's gateway.
    case foreignTarget
}
