/// Holds the notification tokens behind `CameraDeviceGateway.changes()`.
/// Wraps `AVCaptureDevice` connect and disconnect notifications for every device; each one becomes a call to `onChange`.
/// Only translates notifications to the signal; what a change means for the camera list is decided above.
import AVFoundation

final class DeviceChangeObservers: @unchecked Sendable {
    private let tokens: [any NSObjectProtocol]

    init(onChange: @escaping @Sendable () -> Void) {
        let names: [Notification.Name] = [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification]
        tokens = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { _ in onChange() }
        }
    }

    /// The stream behind `CameraDeviceGateway.changes()`: one element per notification, buffered to one.
    /// The observers are removed when the stream ends.
    static func stream() -> AsyncStream<Void> {
        AsyncStream<Void>(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let observers = DeviceChangeObservers { continuation.yield() }
            continuation.onTermination = { _ in observers.removeAll() }
        }
    }

    /// Also runs on deinit, so an observer that was never removed leaves nothing registered.
    func removeAll() {
        _ = tokens.map(NotificationCenter.default.removeObserver)
    }

    deinit {
        removeAll()
    }
}
