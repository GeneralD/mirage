/// Implements the `onEnd` callback of `CaptureSessionGateway`.
/// Wraps `AVCaptureSession` runtime-error / interruption and `AVCaptureDevice` disconnect notifications.
/// Only translates notifications to `CaptureEnd`; the reaction is decided above.
import AVFoundation
import Domain

final class CaptureEndObservers: @unchecked Sendable {
    private let tokens: [any NSObjectProtocol]

    init(session: AVCaptureSession, device: AVCaptureDevice, onEnd: @escaping @Sendable (CaptureEnd) -> Void) {
        let ends: [(Notification.Name, AnyObject, @Sendable (Notification) -> CaptureEnd)] = [
            (AVCaptureSession.runtimeErrorNotification, session, { .runtimeError("\($0.userInfo as Any)") }),
            (AVCaptureSession.wasInterruptedNotification, session, { _ in .deviceDisconnected }),
            (AVCaptureDevice.wasDisconnectedNotification, device, { _ in .deviceDisconnected }),
        ]
        tokens = ends.map { name, object, end in
            NotificationCenter.default.addObserver(forName: name, object: object, queue: nil) { onEnd(end($0)) }
        }
    }

    /// Also runs on deinit, so a rig whose configuration threw leaves nothing registered.
    func removeAll() {
        _ = tokens.map(NotificationCenter.default.removeObserver)
    }

    deinit {
        removeAll()
    }
}
