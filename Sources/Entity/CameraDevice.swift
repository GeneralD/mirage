/// A camera the OS lists. `id` is the OS's unique identifier, `name` is the label to show,
/// and `isSystemDefault` marks the camera the OS uses by default. It matters only for a
/// first selection, before the user has chosen one.
public struct CameraDevice: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let isSystemDefault: Bool

    public init(id: String, name: String, isSystemDefault: Bool = false) {
        self.id = id
        self.name = name
        self.isSystemDefault = isSystemDefault
    }
}
