/// One `AVCaptureDevice` as the `CameraDevice` that `CameraDeviceGateway.devices()` lists.
/// Copies what the device reports; what a suspended or virtual camera means for the choice is decided above.
import AVFoundation
import Domain

extension CameraDevice {
    /// `systemDefaultID` is the unique id of the OS default camera, if any. A virtual camera is one whose transport is
    /// 'virt' (the value of `kIOAudioDeviceTransportTypeVirtual`), which a Camera Extension reports.
    init(device: AVCaptureDevice, systemDefaultID: String?) {
        self.init(
            id: device.uniqueID,
            name: device.localizedName,
            isSystemDefault: device.uniqueID == systemDefaultID,
            isSuspended: device.isSuspended,
            isVirtual: device.transportType == 0x7669_7274
        )
    }
}
