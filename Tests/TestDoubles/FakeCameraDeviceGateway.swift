import Domain
import TestSupport

/// The camera list the test sets: `devices()` returns the list last set, and `formats(ofDevice:)`
/// returns the formats set for that id (`[]` for an id with none). `formatRequests` keeps the ids
/// that `formats(ofDevice:)` was called with, in call order.
public final class FakeCameraDeviceGateway: CameraDeviceGateway, Sendable {
    private struct State {
        var devices: [CameraDevice]
        var formats: [String: [CameraFormat]]
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
}
