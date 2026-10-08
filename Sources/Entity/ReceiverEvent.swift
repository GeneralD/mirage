/// Events from the extension side receive loop.
public enum ReceiverEvent: Sendable, Hashable {
    /// The service name is registered; the host can look it up.
    case listening
    /// The first frame after a (re)connect arrived.
    case hostConnected
    case hostLost(HostLossReason)
    case frameDropped(FrameDropReason)
}

/// How the extension concluded the host is gone.
public enum HostLossReason: Sendable, Hashable {
    /// The kernel reported the host's port dead (host process exited).
    case deadName
    /// No frame arrived within the gap budget (host hung or was stopped).
    case frameGap(Duration)
    /// The receive itself failed with a raw Mach code.
    case receiveFailed(code: Int)
}
