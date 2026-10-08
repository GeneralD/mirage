/// Lifecycle of the extension's output stream as the CMIO host drives it: the
/// stream starts when the first client (Zoom, QuickTime…) begins reading and
/// stops when the last one leaves.
public enum StreamOutputEvent: Sendable, Hashable {
    case streamStarted
    case streamStopped
}
