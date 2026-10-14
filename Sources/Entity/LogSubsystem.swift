/// Closed set of log categories; `UnifiedLog` maps each to an `os.Logger`.
public enum LogSubsystem: String, Sendable, Hashable, CaseIterable {
    case app
    case camera
    case pipeline
    case surfaces
    /// The host pipeline's effect stage (its per-second summary and its drops) and
    /// the effect runtime (its compiles and their failures), the effect catalog (its listings,
    /// the end of a catalog stream, and a watch that ended on its own), and the stored effect
    /// selection (a stored string that does not decode).
    case effect
    /// GPU work below the effect runtime (command buffers and their completions).
    case gpu
    case transport
    case receiver
    case stream
    case install
    case preview
}
