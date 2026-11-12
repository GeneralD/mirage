/// A capture resolution in pixels.
public struct CameraResolution: Sendable, Hashable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

/// Whether the camera the user chose can be used right now.
public enum CameraAvailability: Sendable, Hashable {
    /// The chosen camera is connected, or there is a camera to use.
    case available
    /// The user chose a camera that is not connected now. The payload is that camera's name.
    case missing(String)
    /// The chosen camera, or the one in use when none was chosen, is connected but suspended, so it gives no frames
    /// (a laptop's lid is closed, for one). The payload is that camera's name.
    case suspended(String)
    /// No camera is connected at all.
    case noCamera
}

/// What the screens read about the camera: the cameras and choices on offer, the current choice, and whether it can be used.
/// The lists hold what can be chosen right now. A `selected…` value is `nil` only when its list is empty.
public struct CameraState: Sendable, Hashable {
    public let devices: [CameraDevice]
    public let selectedDeviceID: String?
    public let availability: CameraAvailability
    public let resolutions: [CameraResolution]
    public let selectedResolution: CameraResolution?
    public let frameRates: [Int]
    public let selectedFrameRate: Int?
    public let isMirrored: Bool

    public init(
        devices: [CameraDevice],
        selectedDeviceID: String?,
        availability: CameraAvailability,
        resolutions: [CameraResolution],
        selectedResolution: CameraResolution?,
        frameRates: [Int],
        selectedFrameRate: Int?,
        isMirrored: Bool
    ) {
        self.devices = devices
        self.selectedDeviceID = selectedDeviceID
        self.availability = availability
        self.resolutions = resolutions
        self.selectedResolution = selectedResolution
        self.frameRates = frameRates
        self.selectedFrameRate = selectedFrameRate
        self.isMirrored = isMirrored
    }
}

extension CameraState {
    /// No camera connected, and no cameras, resolutions or frame rates to choose from.
    public static let empty = CameraState(
        devices: [],
        selectedDeviceID: nil,
        availability: .noCamera,
        resolutions: [],
        selectedResolution: nil,
        frameRates: [],
        selectedFrameRate: nil,
        isMirrored: false
    )
}
