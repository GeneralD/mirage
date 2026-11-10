import Combine
import Dependencies

/// The menu bar's controls interactor: it publishes the bypass state and the frame-rate readout,
/// and carries the start, stop and bypass commands to the pipeline. The menu reads `state`; its
/// controls call the commands below.
public protocol ControlsInteractor: Sendable {
    /// The current controls first, then after every change. It holds a value from construction on, before `start()`.
    var state: AnyPublisher<ControlsState, Never> { get }

    /// Begins the frame-rate readout and the global hotkeys. Calling it again while started does nothing. Returns at once.
    func start()

    /// Ends both; the frame rate reads 0 until the next `start()`. The bypass stays as it was.
    func stop()

    /// Flips the bypass and applies it to the pipeline, started or not.
    func toggleBypass()
}

public enum ControlsInteractorKey: TestDependencyKey {
    public static let testValue: any ControlsInteractor = UnimplementedControlsInteractor()
}

extension DependencyValues {
    public var controlsInteractor: any ControlsInteractor {
        get { self[ControlsInteractorKey.self] }
        set { self[ControlsInteractorKey.self] = newValue }
    }
}

private struct UnimplementedControlsInteractor: ControlsInteractor {
    var state: AnyPublisher<ControlsState, Never> {
        reportIssue("ControlsInteractor.state not implemented")
        return Empty(completeImmediately: true).eraseToAnyPublisher()
    }

    func start() {
        reportIssue("ControlsInteractor.start not implemented")
    }

    func stop() {
        reportIssue("ControlsInteractor.stop not implemented")
    }

    func toggleBypass() {
        reportIssue("ControlsInteractor.toggleBypass not implemented")
    }
}
