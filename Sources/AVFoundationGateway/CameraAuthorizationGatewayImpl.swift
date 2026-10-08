/// Implements `CameraAuthorizationGateway`.
/// Wraps `AVCaptureDevice.authorizationStatus(for:)` and `requestAccess(for:)`.
/// Pure pass-through: the notDetermined → request policy lives in the DataSource.
import AVFoundation
import Domain

public struct CameraAuthorizationGatewayImpl: Sendable {
    public init() {}
}

extension CameraAuthorizationGatewayImpl: CameraAuthorizationGateway {
    public func status() -> CameraAuthorizationStatus {
        let mapping: [AVAuthorizationStatus: CameraAuthorizationStatus] = [
            .notDetermined: .notDetermined,
            .authorized: .authorized,
            .denied: .denied,
            .restricted: .restricted,
        ]
        // A status added by a future OS fails closed.
        return mapping[AVCaptureDevice.authorizationStatus(for: .video)] ?? .denied
    }

    public func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }
}
