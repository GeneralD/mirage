/// Camera permission as the OS reports it, without AVFoundation vocabulary.
public enum CameraAuthorizationStatus: Sendable, Hashable, CaseIterable {
    case notDetermined
    case authorized
    case denied
    /// Blocked by policy (parental controls, MDM); the user cannot change it.
    case restricted
}

extension CameraAuthorizationStatus {
    public var isGranted: Bool { self == .authorized }

    /// Only `notDetermined` can still be turned into `authorized` by asking.
    public var canRequest: Bool { self == .notDetermined }
}
