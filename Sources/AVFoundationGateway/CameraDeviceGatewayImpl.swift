/// Implements `CameraDeviceGateway`.
/// Wraps `AVCaptureDevice`: a discovery session for the camera list, and each device's `formats` by id.
/// Stateless: every call asks the OS again; nothing is cached here.
import AVFoundation
import CoreMedia
import Domain

public struct CameraDeviceGatewayImpl: Sendable {
    public init() {}
}

extension CameraDeviceGatewayImpl: CameraDeviceGateway {
    public func devices() -> [CameraDevice] {
        let systemDefault = AVCaptureDevice.default(for: .video)?.uniqueID
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        )
        return session.devices.map { CameraDevice(device: $0, systemDefaultID: systemDefault) }
    }

    public func formats(ofDevice id: String) -> [CameraFormat] {
        AVCaptureDevice(uniqueID: id).map { device in
            device.formats.enumerated().map { CameraFormat(index: $0.offset, format: $0.element) }
        } ?? []
    }

    public func changes() -> AsyncStream<Void> {
        DeviceChangeObservers.stream()
    }
}

extension CameraFormat {
    /// One `AVCaptureDevice.Format` as a `CameraFormat`. The frame rates are rounded to the
    /// nearest whole number; a format with no frame-rate range reports 0 and 0.
    init(index: Int, format: AVCaptureDevice.Format) {
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let ranges = format.videoSupportedFrameRateRanges
        self.init(
            index: index,
            width: Int(dimensions.width),
            height: Int(dimensions.height),
            minFramesPerSecond: Int(ranges.map(\.minFrameRate).min()?.rounded() ?? 0),
            maxFramesPerSecond: Int((ranges.map(\.maxFrameRate).max() ?? 0).rounded())
        )
    }
}
