/// Failures at the preview boundary.
public enum PreviewError: Error, Sendable, Hashable {
    /// A preview handle the gateway cannot use: a target that is not the kind
    /// of view it draws on, or a layer handle another gateway's `prepare` returned.
    case foreignTarget
}
