/// Implements the `onEnd` callback of `CaptureSessionGateway`.
/// Wraps `AVCaptureSession` runtime-error / interruption notifications.
/// Only translates notifications to `CaptureEnd`; the reaction is decided above.
import AVFoundation
import Domain

final class CaptureEndObservers: @unchecked Sendable {
    private let tokens: [any NSObjectProtocol]

    init(session: AVCaptureSession, onEnd: @escaping @Sendable (CaptureEnd) -> Void) {
        let ends: [(Notification.Name, @Sendable (Notification) -> CaptureEnd)] = [
            (AVCaptureSession.runtimeErrorNotification, { .runtimeError("\($0.userInfo?[AVCaptureSessionErrorKey] ?? "unknown")") }),
            (AVCaptureSession.wasInterruptedNotification, { _ in .deviceDisconnected }),
        ]
        tokens = ends.map { name, end in
            NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) { onEnd(end($0)) }
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
