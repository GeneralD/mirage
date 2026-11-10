import Combine
import Dependencies
import Domain

/// The onboarding window's Combine pipeline over `ExtensionInstallUseCase`: it owns the one
/// task that observes the extension install status, and turns the UseCase's `updates()`
/// stream into the `install` publisher the window subscribes to.
///
/// `start()` and `stop()` only queue their command and return. The commands are carried out one
/// at a time, in call order, by the task the Interactor starts when it is made (`supervise`). A
/// command that ends an observation waits for it to finish, so a status of the old observation
/// never lands after the new one began, and a stopped Interactor forwards nothing more. `install`
/// is a `CurrentValueSubject` underneath: it holds nothing before the first `start()`, and after
/// that the latest status, which a subscriber that arrives later still receives first.
public final class OnboardingInteractorImpl: Sendable {
    private enum Command: Sendable {
        case start
        case stop
    }

    private let relay: StateRelay
    private let commands: AsyncStream<Command>.Continuation

    public init() {
        @Dependency(\.extensionInstallUseCase) var useCase
        let relay = StateRelay()
        let (stream, commands) = AsyncStream<Command>.makeStream()
        self.relay = relay
        self.commands = commands
        // One immutable copy for the task: it captures a `let` (a Sendable existential), not the
        // mutable `@Dependency` binding, and nothing that reaches `self`, so `deinit` can run.
        let installs: any ExtensionInstallUseCase = useCase
        Task { await Self.supervise(stream, useCase: installs, relay: relay) }
    }

    deinit {
        commands.finish()
    }
}

extension OnboardingInteractorImpl: OnboardingInteractor {
    public var install: AnyPublisher<InstallStatus, Never> { relay.states }

    public func start() {
        commands.yield(.start)
    }

    public func stop() {
        commands.yield(.stop)
    }
}

extension OnboardingInteractorImpl {
    /// Carries out the commands in the order they were queued, until the Interactor is gone.
    /// What it folds is the observation now alive, if any: every command ends it, and `start`
    /// begins the next.
    private static func supervise(_ commands: AsyncStream<Command>, useCase: any ExtensionInstallUseCase, relay: StateRelay) async {
        let last = await commands.reduce(into: Task<Void, Never>?.none) { current, command in
            await end(current)
            current = command == .start ? Task { await observe(useCase: useCase, relay: relay) } : nil
        }
        await end(last)
    }

    /// Forwards the UseCase's statuses until the task is cancelled, which also ends the UseCase's stream.
    private static func observe(useCase: any ExtensionInstallUseCase, relay: StateRelay) async {
        let updates = await useCase.updates()
        for await status in updates {
            guard !Task.isCancelled else { return }
            relay.publish(status)
        }
    }

    /// Cancels `run` and waits for it, so nothing it was forwarding can land after what comes next.
    private static func end(_ run: Task<Void, Never>?) async {
        run?.cancel()
        await run?.value
    }
}

/// The install status the Interactor last forwarded, as a publisher: nothing until an observation
/// forwards its first status, and from then on the latest one to every new subscriber and each
/// change to the existing ones.
///
/// `@unchecked Sendable`: `CurrentValueSubject` serialises its own sends and subscriptions, and the
/// sends are never concurrent here (one observation at a time: the supervisor waits for the one it
/// ends before it begins the next).
private final class StateRelay: @unchecked Sendable {
    private let subject = CurrentValueSubject<InstallStatus?, Never>(nil)

    var states: AnyPublisher<InstallStatus, Never> {
        subject.compactMap { $0 }.eraseToAnyPublisher()
    }

    func publish(_ status: InstallStatus) {
        subject.send(status)
    }
}
