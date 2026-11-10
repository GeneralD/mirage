/// The format a capture uses, and the frame rate it captures at.
public struct CameraFormatChoice: Sendable, Hashable {
    /// The position of the format in the camera's `formats` list.
    public let index: Int
    public let framesPerSecond: Int

    public init(index: Int, framesPerSecond: Int) {
        self.index = index
        self.framesPerSecond = framesPerSecond
    }
}

/// What the camera capture is asked for: which camera and which format. A nil `deviceID`
/// means the system default camera; a nil `format` means the M0 preset of 1280x720.
public struct CameraCapture: Sendable, Hashable {
    public let deviceID: String?
    public let format: CameraFormatChoice?

    public init(deviceID: String?, format: CameraFormatChoice?) {
        self.deviceID = deviceID
        self.format = format
    }
}

extension CameraCapture {
    /// The M0 capture: the default camera at the 1280x720 preset.
    public static let standard = CameraCapture(deviceID: nil, format: nil)
}
