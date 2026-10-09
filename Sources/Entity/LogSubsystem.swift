/// Closed set of log categories; `UnifiedLog` maps each to an `os.Logger`.
public enum LogSubsystem: String, Sendable, Hashable, CaseIterable {
    case app
    case camera
    case pipeline
    case surfaces
    case transport
    case receiver
    case stream
    case install
    case preview
}
