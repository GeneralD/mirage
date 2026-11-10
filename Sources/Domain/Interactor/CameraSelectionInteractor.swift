import Combine
import Dependencies

/// The camera selection's Combine pipeline over `CameraSelectionUseCase`: it owns the one task that
/// watches the attached cameras, turns the UseCase's state into a publisher the screens subscribe to,
/// and hands the selection commands to the UseCase. The screens read `state`; their controls call the
/// four commands and `setMirrored(_:)`.
public protocol CameraSelectionInteractor: Sendable {
    /// The camera state, the current one first once `start()` has run. Nothing is published before that.
    var state: AnyPublisher<CameraState, Never> { get }

    /// Reads the state and starts watching the attached cameras, so that a camera that appears or
    /// goes away is published in `state`. Calling it again while started restarts the watch: the old
    /// watch ends before the new one begins, so exactly one is alive. Returns at once; `start()`,
    /// `stop()` and the commands are carried out in the order they were given.
    func start()

    /// Ends the watch that `start()` began. `state` publishes nothing more until the next `start()`.
    /// Returns at once.
    func stop()

    /// Chooses the camera `id`, and publishes the state the UseCase answers with. Returns at once.
    func selectDevice(_ id: String)

    /// Chooses `resolution`, and publishes the state the UseCase answers with. Returns at once.
    func selectResolution(_ resolution: CameraResolution)

    /// Chooses `framesPerSecond`, and publishes the state the UseCase answers with. Returns at once.
    func selectFrameRate(_ framesPerSecond: Int)

    /// Sets the mirror flag, and publishes the state the UseCase answers with. Returns at once.
    func setMirrored(_ isMirrored: Bool)
}

public enum CameraSelectionInteractorKey: TestDependencyKey {
    public static let testValue: any CameraSelectionInteractor = UnimplementedCameraSelectionInteractor()
}

extension DependencyValues {
    public var cameraSelectionInteractor: any CameraSelectionInteractor {
        get { self[CameraSelectionInteractorKey.self] }
        set { self[CameraSelectionInteractorKey.self] = newValue }
    }
}

private struct UnimplementedCameraSelectionInteractor: CameraSelectionInteractor {
    var state: AnyPublisher<CameraState, Never> {
        reportIssue("CameraSelectionInteractor.state not implemented")
        return Empty(completeImmediately: true).eraseToAnyPublisher()
    }

    func start() {
        reportIssue("CameraSelectionInteractor.start not implemented")
    }

    func stop() {
        reportIssue("CameraSelectionInteractor.stop not implemented")
    }

    func selectDevice(_ id: String) {
        reportIssue("CameraSelectionInteractor.selectDevice not implemented")
    }

    func selectResolution(_ resolution: CameraResolution) {
        reportIssue("CameraSelectionInteractor.selectResolution not implemented")
    }

    func selectFrameRate(_ framesPerSecond: Int) {
        reportIssue("CameraSelectionInteractor.selectFrameRate not implemented")
    }

    func setMirrored(_ isMirrored: Bool) {
        reportIssue("CameraSelectionInteractor.setMirrored not implemented")
    }
}
