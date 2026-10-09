/// Camera permission as the OS reports it, without AVFoundation vocabulary.
public enum CameraAuthorizationStatus: Sendable, Hashable, CaseIterable {
    case notDetermined
    case authorized
    case denied
    /// Blocked by policy (parental controls, MDM); the user cannot change it.
    case restricted
    /// A status this build does not know (added by a newer OS). It fails closed: not granted and
    /// not requestable, but distinct from `denied` so logs and UI can tell the two apart.
    case unrecognized
}

extension CameraAuthorizationStatus {
    public var isGranted: Bool { self == .authorized }

    /// Only `notDetermined` can still be turned into `authorized` by asking.
    public var canRequest: Bool { self == .notDetermined }
}
