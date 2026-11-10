/// Implements `CaptureSessionHandle.setMirrored` (the mirror toggle of `CaptureSessionGateway`).
/// Wraps `AVCaptureConnection.isVideoMirrored` on the video connection of the running session.
/// Mirroring is pinned by hand (`automaticallyAdjustsVideoMirroring = false`), so the session
/// does not undo the choice, and the session is not restarted.
import AVFoundation
import Domain

extension CaptureRig {
    func setMirrored(_ mirrored: Bool) {
        session.beginConfiguration()
        _ = output.connection(with: .video)
            .flatMap { $0.isVideoMirroringSupported ? $0 : nil }
            .map { connection in
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = mirrored
            }
        session.commitConfiguration()
    }
}
