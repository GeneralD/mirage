/// Why a capture session stopped delivering frames.
public enum CaptureEnd: Sendable, Hashable {
    /// `stop()` was called.
    case stopped
    case deviceDisconnected
    case runtimeError(String)
}

/// Why a capture session could not start.
public enum CaptureSessionError: Error, Sendable, Hashable {
    case deviceUnavailable
    case configurationFailed(String)
}
