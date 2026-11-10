import Dependencies

/// The camera choice as one face for the UseCase: the cameras the OS lists with their formats,
/// the stored selection, and the capture that a selection asks the camera source for. The UseCase
/// reads and writes the choice here and never reaches the devices, the preferences or the source.
public protocol CameraSelectionRepository: Sendable {
    func devices() -> [CameraDevice]
    func formats(ofDevice id: String) -> [CameraFormat]
    /// A signal that the set of attached cameras changed. The value carries nothing: on each
    /// element, read `devices()` again.
    func changes() -> AsyncStream<Void>
    /// The choice stored last time, `.initial` when nothing was stored.
    func storedSelection() -> CameraSelection
    /// Stores the choice for the next launch.
    func save(_ selection: CameraSelection)
    /// Names the capture the camera source starts its next session with.
    func apply(_ capture: CameraCapture)
    /// Sets the mirror flag of the camera source, without restarting its session.
    func setMirrored(_ mirrored: Bool)
}

public enum CameraSelectionRepositoryKey: TestDependencyKey {
    public static let testValue: any CameraSelectionRepository = UnimplementedCameraSelectionRepository()
}

extension DependencyValues {
    public var cameraSelectionRepository: any CameraSelectionRepository {
        get { self[CameraSelectionRepositoryKey.self] }
        set { self[CameraSelectionRepositoryKey.self] = newValue }
    }
}

private struct UnimplementedCameraSelectionRepository: CameraSelectionRepository {
    func devices() -> [CameraDevice] {
        reportIssue("CameraSelectionRepository.devices not implemented")
        return []
    }

    func formats(ofDevice id: String) -> [CameraFormat] {
        reportIssue("CameraSelectionRepository.formats not implemented")
        return []
    }

    func changes() -> AsyncStream<Void> {
        reportIssue("CameraSelectionRepository.changes not implemented")
        return AsyncStream<Void> { $0.finish() }
    }

    func storedSelection() -> CameraSelection {
        reportIssue("CameraSelectionRepository.storedSelection not implemented")
        return .initial
    }

    func save(_ selection: CameraSelection) {
        reportIssue("CameraSelectionRepository.save not implemented")
    }

    func apply(_ capture: CameraCapture) {
        reportIssue("CameraSelectionRepository.apply not implemented")
    }

    func setMirrored(_ mirrored: Bool) {
        reportIssue("CameraSelectionRepository.setMirrored not implemented")
    }
}
