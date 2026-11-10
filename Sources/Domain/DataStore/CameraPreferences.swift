import Dependencies

/// What the user chose for the camera, kept between launches: the camera, its resolution, its
/// frame rate and the mirroring. Synchronous, because the choice is read once at startup and
/// written from a menu action, and the store behind it answers at once.
public protocol CameraPreferences: Sendable {
    /// The choice stored last time, `.initial` when nothing was stored. A stored value that does not
    /// decode is `nil` for that one setting; the others still read.
    func selection() -> CameraSelection

    /// Replaces the stored choice. A setting that is `nil` is removed from the store.
    func save(_ selection: CameraSelection)
}

public enum CameraPreferencesKey: TestDependencyKey {
    public static let testValue: any CameraPreferences = UnimplementedCameraPreferences()
}

extension DependencyValues {
    public var cameraPreferences: any CameraPreferences {
        get { self[CameraPreferencesKey.self] }
        set { self[CameraPreferencesKey.self] = newValue }
    }
}

private struct UnimplementedCameraPreferences: CameraPreferences {
    func selection() -> CameraSelection {
        reportIssue("CameraPreferences.selection not implemented")
        return .initial
    }

    func save(_ selection: CameraSelection) {
        reportIssue("CameraPreferences.save not implemented")
    }
}
