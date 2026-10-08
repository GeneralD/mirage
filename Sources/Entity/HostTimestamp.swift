/// A point on the host-time axis (mach uptime), in nanoseconds.
///
/// This is the one timeline presentation timestamps live on: the camera's
/// capture clock, the Mach message, the `CMSampleBuffer` the extension builds
/// and `CMIOExtensionStream.send(_:discontinuity:hostTimeInNanoseconds:)` all
/// use it (the stream is declared with the `.hostTime` clock). The live value
/// comes from `HostTimeProvider`; tests use `FixedHostTime`.
public struct HostTimestamp: Sendable, Hashable, Comparable {
    public let nanoseconds: UInt64

    public init(nanoseconds: UInt64) {
        self.nanoseconds = nanoseconds
    }

    public static func < (lhs: HostTimestamp, rhs: HostTimestamp) -> Bool {
        lhs.nanoseconds < rhs.nanoseconds
    }
}

extension HostTimestamp {
    public static let zero = HostTimestamp(nanoseconds: 0)

    /// Converts a host-clock reading in seconds (a `CMTime.seconds`); negative or
    /// non-finite values clamp to zero rather than trapping.
    public static func seconds(_ seconds: Double) -> HostTimestamp {
        guard seconds.isFinite, seconds > 0 else { return .zero }
        return HostTimestamp(nanoseconds: UInt64((seconds * 1_000_000_000).rounded()))
    }

    public var seconds: Double { Double(nanoseconds) / 1_000_000_000 }

    /// `self + duration`, saturating at zero for a negative result.
    public func advanced(by duration: Duration) -> HostTimestamp {
        let delta = duration.totalNanoseconds
        if delta >= 0 {
            return HostTimestamp(nanoseconds: nanoseconds &+ UInt64(delta))
        }
        let magnitude = UInt64(-delta)
        return HostTimestamp(nanoseconds: magnitude > nanoseconds ? 0 : nanoseconds - magnitude)
    }

    /// The signed distance from `self` to `other` (`other - self`).
    public func interval(to other: HostTimestamp) -> Duration {
        if other.nanoseconds >= nanoseconds {
            return .nanoseconds(Int64(other.nanoseconds - nanoseconds))
        }
        return .nanoseconds(-Int64(nanoseconds - other.nanoseconds))
    }
}

extension Duration {
    /// Whole nanoseconds, truncating sub-nanosecond attoseconds.
    public var totalNanoseconds: Int64 {
        let (seconds, attoseconds) = components
        return seconds * 1_000_000_000 + attoseconds / 1_000_000_000
    }

    public var milliseconds: Double { Double(totalNanoseconds) / 1_000_000 }
}
