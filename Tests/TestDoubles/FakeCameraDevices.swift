import Domain
import TestSupport

/// The camera list the test sets: `devices()` returns the list last set, unfiltered and unsorted, and
/// `formats(ofDevice:)` returns the formats set for that id (`[]` for an id with none). `formatRequests`
/// keeps the ids that `formats(ofDevice:)` was called with, in call order.
///
/// `changes()` makes a new stream on every call, buffered to one element as the live stream is.
/// `emitChange()` yields one element on every stream made so far; a stream that has ended ignores it.
public final class FakeCameraDevices: CameraDevices, Sendable {
    private struct State {
        var devices: [CameraDevice]
        var formats: [String: [CameraFormat]]
        var changeStreams: [AsyncStream<Void>.Continuation] = []
    }

    private let state: Locked<State>
    public let formatRequests = Collector<String>()

    public init(devices: [CameraDevice] = [], formats: [String: [CameraFormat]] = [:]) {
        state = Locked(State(devices: devices, formats: formats))
    }

    public func setDevices(_ devices: [CameraDevice]) {
        state.withLock { $0.devices = devices }
    }

    public func setFormats(_ formats: [CameraFormat], ofDevice id: String) {
        state.withLock { $0.formats[id] = formats }
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

    /// Yields one element on every stream that `changes()` has made.
    public func emitChange() {
        for continuation in state.current.changeStreams {
            continuation.yield(())
        }
    }
}
