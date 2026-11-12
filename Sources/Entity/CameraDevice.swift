/// A camera the OS lists. `id` is the OS's unique identifier, `name` is the label to show,
/// and `isSystemDefault` marks the camera the OS uses by default. It matters only for a
/// first selection, before the user has chosen one.
/// `isSuspended` marks a camera that is connected but gives no frames for now, such as a
/// laptop's built-in camera with the lid closed. `isVirtual` marks a camera that software
/// provides instead of hardware, such as another app's virtual camera.
public struct CameraDevice: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let isSystemDefault: Bool
    public let isSuspended: Bool
    public let isVirtual: Bool

    public init(id: String, name: String, isSystemDefault: Bool = false, isSuspended: Bool = false, isVirtual: Bool = false) {
        self.id = id
        self.name = name
        self.isSystemDefault = isSystemDefault
        self.isSuspended = isSuspended
        self.isVirtual = isVirtual
    }
}
