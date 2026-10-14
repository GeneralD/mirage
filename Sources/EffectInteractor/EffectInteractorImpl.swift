import Combine
import Dependencies
import Domain

/// The effects menu's Combine pipeline over `EffectCatalogUseCase` (epic #42, D9): it
/// owns the one task that runs the catalog, turns the UseCase's `observe()` stream into
/// the `state` publisher the Presenter subscribes to, and hands the menu's two commands
/// to the UseCase.
///
/// `start()` runs the catalog and the state forwarding as the two children of one task;
/// `stop()` cancels that task. A second `start()` ends the first task before it begins
/// the next, so exactly one is ever alive. `start()` and `stop()` only queue their
/// command and return: the commands are carried out one at a time, in call order, by
/// the task the Interactor starts when it is made (`supervise`), which is why the task
/// handle needs no lock and no reorderable hop through an actor. A command that ends a
/// run waits for it to finish, so a state of the old run never lands after the new one
/// began, and a stopped Interactor forwards nothing more. `state` is a
/// `CurrentValueSubject` underneath: it holds nothing before the first `start()`, and
/// after that the latest state, which a subscriber that arrives later still receives first.
///
/// `select(_:)` does not wait for the answer. The outcome reaches the menu through
/// `state`; the Interactor adds one log line, to `DeveloperLog` when the effect is
/// running and to `ErrorLog` when it is not. It is not one of the queued commands, nor does it
/// wait for an earlier `select`: each call is its own task, because the runtime lets a newer
/// preparation overtake a slow compile (newest wins) and a queue here would hold the newer
/// choice back behind the older one's compile. The price is that two calls made in the same
/// instant may reach the UseCase in either order, which a person choosing from a menu does not
/// produce.
public final class EffectInteractorImpl: Sendable {
    private enum Command: Sendable {
        case start
        case stop
    }

    private let catalog: any EffectCatalogUseCase
    private let errorLog: any ErrorLog
    private let developerLog: any DeveloperLog
    private let relay: StateRelay
    private let commands: AsyncStream<Command>.Continuation

    public init() {
        @Dependency(\.effectCatalogUseCase) var catalog
        @Dependency(\.errorLog) var errorLog
        @Dependency(\.developerLog) var developerLog
        let relay = StateRelay()
        let (stream, commands) = AsyncStream<Command>.makeStream()
        self.catalog = catalog
        self.errorLog = errorLog
        self.developerLog = developerLog
        self.relay = relay
        self.commands = commands
        Task { await Self.supervise(stream, catalog: catalog, relay: relay) }
    }

    deinit {
        commands.finish()
    }
}

extension EffectInteractorImpl: EffectInteractor {
    public var state: AnyPublisher<EffectCatalogState, Never> { relay.states }

    public func start() {
        commands.yield(.start)
    }

    public func stop() {
        commands.yield(.stop)
    }

    public func select(_ id: EffectID) {
        let (catalog, errorLog, developerLog) = (catalog, errorLog, developerLog)
        Task {
            let outcome = await catalog.select(id)
            Self.record(outcome, of: id, errorLog: errorLog, developerLog: developerLog)
        }
    }

    public func openEffectsFolder() {
        catalog.openEffectsFolder()
    }
}

extension EffectInteractorImpl {
    /// Carries out the commands in the order they were queued, until the Interactor is gone.
    /// What it folds is the catalog run now alive, if any: every command ends it, and
    /// `start` begins the next.
    private static func supervise(_ commands: AsyncStream<Command>, catalog: any EffectCatalogUseCase, relay: StateRelay) async {
        let last = await commands.reduce(into: Task<Void, Never>?.none) { current, command in
            await end(current)
            current = command == .start ? Task { await run(catalog: catalog, relay: relay) } : nil
        }
        await end(last)
    }

    /// The catalog's run and the forwarding of its states, structured under one task, so that
    /// cancelling the task reaches both.
    private static func run(catalog: any EffectCatalogUseCase, relay: StateRelay) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await catalog.run() }
            group.addTask {
                for await state in catalog.observe() {
                    guard !Task.isCancelled else { return }
                    relay.publish(state)
                }
            }
        }
    }

    /// Cancels `run` and waits for it, so nothing it was forwarding can land after what comes next.
    private static func end(_ run: Task<Void, Never>?) async {
        run?.cancel()
        await run?.value
    }

    private static func record(_ outcome: EffectSelectionOutcome, of id: EffectID, errorLog: any ErrorLog, developerLog: any DeveloperLog) {
        let effect = "\(id.origin.rawValue)/\(id.key)"
        switch outcome {
        case .prepared:
            developerLog.record(.effect, "select \(effect): prepared")
        case .failed(let failure):
            errorLog.record(.effect, "select \(effect): failed (\(failure))")
        case .unavailable(let problem?):
            errorLog.record(.effect, "select \(effect): unavailable (\(problem))")
        case .unavailable(nil):
            errorLog.record(.effect, "select \(effect): unavailable (not in the catalog)")
        }
    }
}

/// The catalog state the Interactor last forwarded, as a publisher: nothing until a run
/// forwards its first state, and from then on the latest one to every new subscriber and
/// each change to the existing ones.
///
/// `@unchecked Sendable`: `CurrentValueSubject` serialises its own sends and subscriptions,
/// and the sends are never concurrent here (one forwarding child at a time: the supervisor
/// waits for the run it ends before it begins the next).
private final class StateRelay: @unchecked Sendable {
    private let subject = CurrentValueSubject<EffectCatalogState?, Never>(nil)

    var states: AnyPublisher<EffectCatalogState, Never> {
        subject.compactMap { $0 }.eraseToAnyPublisher()
    }

    func publish(_ state: EffectCatalogState) {
        subject.send(state)
    }
}
