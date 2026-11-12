import Domain
import TestSupport

/// `CameraPreferences` that keeps the choice in memory. `selection()` answers the last value saved,
/// or `.initial` when nothing was saved yet.
///
/// `saves` records every `save` call in order, including one that changes nothing, so a test can
/// tell a save that was made from one that was not.
public final class FakeCameraPreferences: CameraPreferences, Sendable {
    private let current: Locked<CameraSelection>
    /// One entry per `save` call, in call order.
    public let saves = Collector<CameraSelection>()

    public init(_ selection: CameraSelection = .initial) {
        current = Locked(selection)
    }

    public func selection() -> CameraSelection {
        current.current
    }

    public func save(_ selection: CameraSelection) {
        current.set(selection)
        saves.append(selection)
    }
}
