/// The camera settings the user chose. It is remembered across launches, so it keeps the chosen values even when that camera is unplugged.
/// `nil` means the user has not chosen that setting yet.
public struct CameraSelection: Sendable, Hashable {
    public let deviceID: String?
    /// Kept with the ID so the chosen camera can still be named while it is unplugged.
    public let deviceName: String?
    public let resolution: CameraResolution?
    public let framesPerSecond: Int?
    public let isMirrored: Bool

    public init(
        deviceID: String?,
        deviceName: String?,
        resolution: CameraResolution?,
        framesPerSecond: Int?,
        isMirrored: Bool
    ) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.resolution = resolution
        self.framesPerSecond = framesPerSecond
        self.isMirrored = isMirrored
    }
}

extension CameraSelection {
    /// Nothing chosen yet, and no mirroring.
    public static let initial = CameraSelection(
        deviceID: nil,
        deviceName: nil,
        resolution: nil,
        framesPerSecond: nil,
        isMirrored: false
    )
}
