/// Implements the camera choice and format of `CaptureSessionGateway`.
/// Wraps `AVCaptureDevice` lookup, `activeFormat` and the frame duration of the capture device.
/// Every check is an `orThrow`, so a request the camera cannot honour fails here, not in the OS.
import AVFoundation
import Domain

extension CaptureRig {
    static func device(for capture: CameraCapture) throws -> AVCaptureDevice {
        try capture.deviceID.map { try AVCaptureDevice(uniqueID: $0).orThrow(CaptureSessionError.deviceUnavailable) }
            ?? AVCaptureDevice.default(for: .video).orThrow(CaptureSessionError.deviceUnavailable)
    }

    func configure(_ device: AVCaptureDevice, for choice: CameraFormatChoice?) throws {
        try choice.map { try apply($0, to: device) } ?? applyPreset()
    }

    private func applyPreset() throws {
        try session.canSetSessionPreset(.hd1280x720).orThrow(CaptureSessionError.configurationFailed("no 1280x720 preset"))
        session.sessionPreset = .hd1280x720
    }

    private func apply(_ choice: CameraFormatChoice, to device: AVCaptureDevice) throws {
        try device.formats.indices.contains(choice.index).orThrow(CaptureSessionError.configurationFailed("no format #\(choice.index)"))
        try (1...240).contains(choice.framesPerSecond).orThrow(CaptureSessionError.configurationFailed("bad frame rate \(choice.framesPerSecond)"))
        let format = device.formats[choice.index]
        let ranges = format.videoSupportedFrameRateRanges
        try (!ranges.isEmpty).orThrow(CaptureSessionError.configurationFailed("no frame rate range in format #\(choice.index)"))
        let shortest = ranges.map(\.minFrameDuration).reduce(CMTime.positiveInfinity, CMTimeMinimum)
        let longest = ranges.map(\.maxFrameDuration).reduce(CMTime.zero, CMTimeMaximum)
        let duration = CMTimeMinimum(CMTimeMaximum(CMTime(value: 1, timescale: CMTimeScale(choice.framesPerSecond)), shortest), longest)
        try Result { try device.lockForConfiguration() }
            .mapError { CaptureSessionError.configurationFailed("\($0)") }.get()
        defer { device.unlockForConfiguration() }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        device.activeFormat = format
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration
        // `AVCaptureSessionPresetInputPriority` is API_UNAVAILABLE(macos), so the preset is left as the
        // session has it. Whether macOS keeps the chosen `activeFormat` is for the real-device check.
    }
}
