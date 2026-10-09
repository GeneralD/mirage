/// Where the host pipeline stands with respect to the virtual camera link.
/// Written on the frame executor only, so a reader sees the value as of the
/// last executor step (in tests: after `ManualFrameExecutor.drain()`).
enum PipelinePhase: Sendable, Hashable {
    /// Never started.
    case idle
    /// `start` is waiting for the first connect.
    case connecting
    /// The sink answered; frames reach the extension.
    case connected
    /// The link is down and nobody is bringing it back: the first connect failed
    /// (not cancelled), or a reconnect attempt failed. Frames drop as `.notConnected`.
    case disconnected
    /// The destination was lost and a reconnect task is looking the service up again.
    case reconnecting
    /// `stop` was called; terminal until the next `start`.
    case stopped
}
