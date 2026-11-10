import Dependencies

/// The camera selection as the settings screens and the capture see it. `refresh()` works out the state
/// from the stored choice and the attached cameras, applies the capture to the camera source and sets the
/// mirror flag; it reads the choice and never saves it. `changes()` signals that the attached cameras
/// changed, and the caller calls `refresh()` again.
public protocol CameraSelectionUseCase: Sendable {
    func refresh() -> CameraState
    func changes() -> AsyncStream<Void>
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
}
