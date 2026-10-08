import Darwin
import Domain

/// Live `HostTimeProvider`: reads the mach uptime clock in nanoseconds.
///
/// This is the axis AVFoundation presentation timestamps and the CoreMediaIO
/// `.hostTime` stream clock both use, so a reading taken here is directly
/// comparable with a camera PTS and can be handed to
/// `CMIOExtensionStream.send(_:discontinuity:hostTimeInNanoseconds:)` unchanged.
/// `CLOCK_UPTIME_RAW` does not tick while the machine sleeps, matching the
/// mach host clock rather than wall time.
public struct HostTimeProviderImpl: HostTimeProvider {
    public init() {}

    public func now() -> HostTimestamp {
        HostTimestamp(nanoseconds: clock_gettime_nsec_np(CLOCK_UPTIME_RAW))
    }
}
