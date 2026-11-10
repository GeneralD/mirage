import Combine
import Dependencies
import Domain

/// The settings window's Interactor (epic E6, menu and settings): it carries the window's commands
/// to `SettingsUseCase` and publishes the settings the use case reads back after each of them.
///
/// The commands are queued in call order and carried out one at a time by the task the Interactor
/// starts when it is made (`supervise`). Each command ends with a publish of `settings()`, so the
/// published state is always what the use case reports, never a guess of the Interactor's own. The
/// public methods only queue their command and return, except `resetAll()`, which returns once the
/// reset has been carried out and its settings published. A command queued during a reset therefore
/// waits for it, and nothing overtakes it. `state` is a `CurrentValueSubject` underneath: it holds
/// `SettingsState()` from construction on, and a subscriber that arrives later receives the latest state first.
public final class SettingsInteractorImpl: Sendable {
    private enum Command: Sendable {
        case refresh
        case setLaunchAtLogin(Bool)
        case openLoginItemsSettings
        case setHotkeysEnabled(Bool)
        case reset(CheckedContinuation<Void, Never>)
    }

    private let relay: StateRelay
    private let commands: AsyncStream<Command>.Continuation

    public init() {
        @Dependency(\.settingsUseCase) var useCase
        let relay = StateRelay()
        let (stream, commands) = AsyncStream<Command>.makeStream()
        self.relay = relay
        self.commands = commands
        // One immutable copy for the task: it captures a `let` (a Sendable existential), not the
        // mutable `@Dependency` binding.
        let settings: any SettingsUseCase = useCase
        Task { await Self.supervise(stream, useCase: settings, relay: relay) }
    }

    deinit {
        commands.finish()
    }
}

extension SettingsInteractorImpl: SettingsInteractor {
    public var state: AnyPublisher<SettingsState, Never> { relay.states }

    public func refresh() {
        commands.yield(.refresh)
    }

    public func setLaunchAtLogin(_ on: Bool) {
        commands.yield(.setLaunchAtLogin(on))
    }

    public func openLoginItemsSettings() {
        commands.yield(.openLoginItemsSettings)
    }

    public func setHotkeysEnabled(_ on: Bool) {
        commands.yield(.setHotkeysEnabled(on))
    }

    public func resetAll() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            guard case .enqueued = commands.yield(.reset(continuation)) else {
                // The reset will never be carried out, so do not keep the caller waiting for it.
                continuation.resume()
                return
            }
        }
    }
}

extension SettingsInteractorImpl {
    /// Carries out the commands one at a time, in the order they were queued, until the Interactor is gone.
    /// Every command publishes the settings the use case reads back; a reset resumes its caller after that publish.
    private static func supervise(_ commands: AsyncStream<Command>, useCase: any SettingsUseCase, relay: StateRelay) async {
        for await command in commands {
            switch command {
            case .refresh:
                break
            case .setLaunchAtLogin(let on):
                _ = useCase.setLaunchAtLogin(on)
            case .openLoginItemsSettings:
                useCase.openLoginItemsSettings()
            case .setHotkeysEnabled(let on):
                _ = await useCase.setHotkeysEnabled(on)
            case .reset:
                await useCase.resetAll()
            }
            relay.publish(await useCase.settings())
            if case .reset(let continuation) = command {
                continuation.resume()
            }
        }
    }
}

/// The settings the Interactor last published, as a publisher: `SettingsState()` until the first
/// publish, and from then on the latest one to every new subscriber and each change to the existing ones.
///
/// `@unchecked Sendable`: `CurrentValueSubject` serialises its own sends and subscriptions, and the
/// sends are never concurrent here (one supervising task publishes, and it publishes one command at a time).
private final class StateRelay: @unchecked Sendable {
    private let subject = CurrentValueSubject<SettingsState, Never>(SettingsState())

    var states: AnyPublisher<SettingsState, Never> {
        subject.eraseToAnyPublisher()
    }

    func publish(_ state: SettingsState) {
        subject.send(state)
    }
}
