/// What happens to a frame handed to a sink or transport.
public enum SendOutcome: Sendable, Hashable {
    case sent
    case dropped(FrameDropReason)
}

extension SendOutcome {
    public var wasSent: Bool { self == .sent }
}

/// Why a frame was dropped instead of delivered. Dropping is the frame path's
/// only failure mode: a live feed never blocks and never retries one frame.
public enum FrameDropReason: Sendable, Hashable {
    /// The transport has no connection to the extension.
    case notConnected
    /// The extension is not installed (or not yet approved).
    case extensionUnavailable
    /// No client is streaming from the extension.
    case noClient
    /// The surface pool is at capacity (the consumer is slower than the producer).
    case poolExhausted
    /// The frame's descriptor does not match what the stream declared.
    case formatMismatch
    /// The token no longer resolves to a surface (stale generation).
    case staleToken
    /// The OS refused the send; the code is the raw kernel/Mach return.
    case sendFailed(code: Int)
    /// A previous frame is still in flight and the in-flight cap is reached.
    case inFlightCapReached
}

/// Connection-level events from the host side transport.
public enum FrameTransportEvent: Sendable, Hashable {
    case connected
    case disconnected(TransportDisconnectReason)
    case frameDropped(FrameDropReason)
}

public enum TransportDisconnectReason: Sendable, Hashable {
    /// `bootstrap_look_up` failed after the retry policy was exhausted.
    case lookupFailed(code: Int)
    /// The extension's receive right died (`MACH_SEND_INVALID_DEST`).
    case destinationLost
    /// `disconnect()` was called.
    case explicit
}
