import Dependencies

/// The camera selection as the settings screens and the capture see it. `refresh()` works out the state
/// from the stored choice and the attached cameras, applies the capture to the camera source and sets the
/// mirror flag; it reads the choice and never saves it. `changes()` signals that the attached cameras
/// changed, and the caller calls `refresh()` again.
///
/// The commands change one item of the stored choice. A camera, resolution or frame rate that the state does
/// not offer is refused: nothing is saved or applied, and the state as it is comes back. An accepted command
/// saves the choice, applies the capture and sets the mirror flag the way `refresh()` does, and returns the new
/// state. `setMirrored` is always accepted.
public protocol CameraSelectionUseCase: Sendable {
    func refresh() -> CameraState
    func changes() -> AsyncStream<Void>
    func selectDevice(_ id: String) -> CameraState
    func selectResolution(_ resolution: CameraResolution) -> CameraState
    func selectFrameRate(_ framesPerSecond: Int) -> CameraState
    func setMirrored(_ isMirrored: Bool) -> CameraState
}

public enum CameraSelectionUseCaseKey: TestDependencyKey {
    public static let testValue: any CameraSelectionUseCase = UnimplementedCameraSelectionUseCase()
}

extension DependencyValues {
    public var cameraSelectionUseCase: any CameraSelectionUseCase {
        get { self[CameraSelectionUseCaseKey.self] }
        set { self[CameraSelectionUseCaseKey.self] = newValue }
    }
}

private struct UnimplementedCameraSelectionUseCase: CameraSelectionUseCase {
    func refresh() -> CameraState {
        reportIssue("CameraSelectionUseCase.refresh not implemented")
        return .empty
    }

    func changes() -> AsyncStream<Void> {
        reportIssue("CameraSelectionUseCase.changes not implemented")
        return AsyncStream<Void> { $0.finish() }
    }

    func selectDevice(_ id: String) -> CameraState {
        reportIssue("CameraSelectionUseCase.selectDevice not implemented")
        return .empty
    }

    func selectResolution(_ resolution: CameraResolution) -> CameraState {
        reportIssue("CameraSelectionUseCase.selectResolution not implemented")
        return .empty
    }

    func selectFrameRate(_ framesPerSecond: Int) -> CameraState {
        reportIssue("CameraSelectionUseCase.selectFrameRate not implemented")
        return .empty
    }

    func setMirrored(_ isMirrored: Bool) -> CameraState {
        reportIssue("CameraSelectionUseCase.setMirrored not implemented")
        return .empty
    }
}
