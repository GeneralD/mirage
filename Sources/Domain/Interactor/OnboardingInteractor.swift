import Combine
import Dependencies

/// The onboarding window's Combine pipeline over `ExtensionInstallUseCase`: it turns the
/// UseCase's `updates()` stream into a publisher the Presenter subscribes to. The window
/// reads `install`; it starts and stops the observation with `start()` and `stop()`.
public protocol OnboardingInteractor: Sendable {
    /// The Camera Extension's install status. After `start()` it begins with the current
    /// status and then carries every later transition. Nothing is published before `start()`,
    /// and a terminal status does not complete it: the observation goes on until `stop()`.
    var install: AnyPublisher<InstallStatus, Never> { get }

    /// Starts observing the install status and begins publishing `install`. Calling it again
    /// while started restarts the observation: the first one ends before the next begins, so
    /// exactly one is alive. Returns at once; `start()` and `stop()` are carried out in the
    /// order they were given.
    func start()

    /// Ends what `start()` began. `install` publishes nothing more until the next `start()`.
    /// Returns at once.
    func stop()
}

public enum OnboardingInteractorKey: TestDependencyKey {
    public static let testValue: any OnboardingInteractor = UnimplementedOnboardingInteractor()
}

extension DependencyValues {
    public var onboardingInteractor: any OnboardingInteractor {
        get { self[OnboardingInteractorKey.self] }
        set { self[OnboardingInteractorKey.self] = newValue }
    }
}

private struct UnimplementedOnboardingInteractor: OnboardingInteractor {
    var install: AnyPublisher<InstallStatus, Never> {
        reportIssue("OnboardingInteractor.install not implemented")
        return Empty(completeImmediately: true).eraseToAnyPublisher()
    }

    func start() {
        reportIssue("OnboardingInteractor.start not implemented")
    }

    func stop() {
        reportIssue("OnboardingInteractor.stop not implemented")
    }
}
