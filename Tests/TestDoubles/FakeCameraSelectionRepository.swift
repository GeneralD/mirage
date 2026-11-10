import Domain
import TestSupport

/// `CameraSelectionRepository` the test drives. The device list, the formats and the stored selection
/// are set by the test. `save` replaces the selection that `storedSelection()` answers next, and
/// `apply`, `setMirrored` and `formats(ofDevice:)` are recorded in call order.
///
/// `changes()` makes a new stream on every call, buffered to one element as the live stream is.
/// `emitChange()` yields one element on every stream made so far.
public final class FakeCameraSelectionRepository: CameraSelectionRepository, Sendable {
    private struct State {
        var devices: [CameraDevice]
        var formats: [String: [CameraFormat]]
        var selection: CameraSelection
        var changeStreams: [AsyncStream<Void>.Continuation] = []
    }

    private let state: Locked<State>
    /// One entry per `save` call, in call order.
    public let saves = Collector<CameraSelection>()
    /// One entry per `apply` call, in call order.
    public let applied = Collector<CameraCapture>()
    /// One entry per `setMirrored` call, in call order.
    public let mirrors = Collector<Bool>()
    /// One entry per `formats(ofDevice:)` call, in call order.
    public let formatRequests = Collector<String>()

    public init(
        devices: [CameraDevice] = [],
        formats: [String: [CameraFormat]] = [:],
        selection: CameraSelection = .initial
    ) {
        state = Locked(State(devices: devices, formats: formats, selection: selection))
    }

    public func setDevices(_ devices: [CameraDevice]) {
        state.withLock { $0.devices = devices }
    }

    public func setFormats(_ formats: [CameraFormat], ofDevice id: String) {
        state.withLock { $0.formats[id] = formats }
    }

    public func setSelection(_ selection: CameraSelection) {
        state.withLock { $0.selection = selection }
    }

    /// Yields one element on every stream that `changes()` has made.
    public func emitChange() {
        for continuation in state.current.changeStreams {
            continuation.yield(())
        }
    }

    public func devices() -> [CameraDevice] {
        state.current.devices
    }

    public func formats(ofDevice id: String) -> [CameraFormat] {
        formatRequests.append(id)
        return state.current.formats[id] ?? []
    }

    public func changes() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        state.withLock { $0.changeStreams.append(continuation) }
        return stream
    }

    public func storedSelection() -> CameraSelection {
        state.current.selection
    }

    public func save(_ selection: CameraSelection) {
        state.withLock { $0.selection = selection }
        saves.append(selection)
    }

    public func apply(_ capture: CameraCapture) {
        applied.append(capture)
    }

    public func setMirrored(_ mirrored: Bool) {
        mirrors.append(mirrored)
    }
}
