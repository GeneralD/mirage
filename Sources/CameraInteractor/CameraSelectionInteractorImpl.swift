import Combine
import Dependencies
import Domain

/// The camera selection's Combine pipeline over `CameraSelectionUseCase`: it owns the one task that
/// watches the attached cameras, turns the UseCase's state into the `state` publisher the screens
/// subscribe to, and hands the four selection commands and the mirror flag to the UseCase.
///
/// `start()` takes the UseCase's `changes()` stream before its first `refresh()`, so a change that
/// arrives during that refresh is kept and read again. Each signal of the stream queues one `refresh`
/// command, which reads the state again and publishes it. `stop()` ends the watch, and a second
/// `start()` ends the first watch before it begins the next, so exactly one is ever alive.
///
/// `start()`, `stop()` and the commands only queue themselves and return: one task carries them out
/// one at a time, in call order (`supervise`), which is why the watch handle needs no lock and the
/// UseCase is never called from two places at once. A command made while no watch is alive is
/// dropped: nothing reaches the UseCase and nothing is published. `state` is a `CurrentValueSubject`
/// underneath: it holds nothing before the first `start()`, and after that the latest state, which a
/// subscriber that arrives later still receives first.
public final class CameraSelectionInteractorImpl: Sendable {
    private enum Command: Sendable {
        case start
        case stop
        case refresh
        case selectDevice(String)
        case selectResolution(CameraResolution)
        case selectFrameRate(Int)
        case setMirrored(Bool)
    }

    private let relay: CameraStateRelay
    private let commands: AsyncStream<Command>.Continuation

    public init() {
        @Dependency(\.cameraSelectionUseCase) var useCase
        let relay = CameraStateRelay()
        let (stream, commands) = AsyncStream<Command>.makeStream()
        self.relay = relay
        self.commands = commands
        // One immutable copy for the supervising task: it captures a `let`, not the mutable `@Dependency` binding.
        let supervised: any CameraSelectionUseCase = useCase
        Task { await Self.supervise(stream, feedback: commands, useCase: supervised, relay: relay) }
    }

    deinit {
        commands.finish()
    }
}

extension CameraSelectionInteractorImpl: CameraSelectionInteractor {
    public var state: AnyPublisher<CameraState, Never> { relay.states }

    public func start() {
        commands.yield(.start)
    }

    public func stop() {
        commands.yield(.stop)
    }

    public func selectDevice(_ id: String) {
        commands.yield(.selectDevice(id))
    }

    public func selectResolution(_ resolution: CameraResolution) {
        commands.yield(.selectResolution(resolution))
    }

    public func selectFrameRate(_ framesPerSecond: Int) {
        commands.yield(.selectFrameRate(framesPerSecond))
    }

    public func setMirrored(_ isMirrored: Bool) {
        commands.yield(.setMirrored(isMirrored))
    }
}

extension CameraSelectionInteractorImpl {
    /// Carries out the commands in the order they were queued, until the Interactor is gone. What it folds is
    /// the watch now alive, if any: `start` ends it and begins the next, `stop` ends it, and a refresh or a
    /// selection reaches the UseCase only while one is alive.
    private static func supervise(
        _ commands: AsyncStream<Command>,
        feedback: AsyncStream<Command>.Continuation,
        useCase: any CameraSelectionUseCase,
        relay: CameraStateRelay
    ) async {
        let last = await commands.reduce(into: Task<Void, Never>?.none) { watch, command in
            switch command {
            case .start:
                await end(watch)
                let changes = useCase.changes()
                relay.publish(useCase.refresh())
                watch = Task { await watchChanges(changes, feedback: feedback) }
            case .stop:
                await end(watch)
                watch = nil
            case .refresh:
                guard watch != nil else { return }
                relay.publish(useCase.refresh())
            case .selectDevice(let id):
                guard watch != nil else { return }
                relay.publish(useCase.selectDevice(id))
            case .selectResolution(let resolution):
                guard watch != nil else { return }
                relay.publish(useCase.selectResolution(resolution))
            case .selectFrameRate(let framesPerSecond):
                guard watch != nil else { return }
                relay.publish(useCase.selectFrameRate(framesPerSecond))
            case .setMirrored(let isMirrored):
                guard watch != nil else { return }
                relay.publish(useCase.setMirrored(isMirrored))
            }
        }
        await end(last)
    }

    /// Queues one `refresh` for each signal of the UseCase's stream. The refresh joins the same queue as the
    /// other commands, so it is read where it lands in call order. A signal that arrives after the watch was
    /// cancelled is dropped, so a stopped watch never queues a refresh.
    private static func watchChanges(_ changes: AsyncStream<Void>, feedback: AsyncStream<Command>.Continuation) async {
        for await _ in changes {
            guard !Task.isCancelled else { return }
            feedback.yield(.refresh)
        }
    }

    /// Cancels `watch` and waits for it, so nothing it was watching can land after what comes next.
    private static func end(_ watch: Task<Void, Never>?) async {
        watch?.cancel()
        await watch?.value
    }
}

/// The camera state the Interactor last published, as a publisher: nothing until the first `start()` publishes
/// one, and from then on the latest one to every new subscriber and each change to the existing ones.
///
/// `@unchecked Sendable`: `CurrentValueSubject` serialises its own sends and subscriptions, and the sends are
/// never concurrent here (one supervising task publishes).
private final class CameraStateRelay: @unchecked Sendable {
    private let subject = CurrentValueSubject<CameraState?, Never>(nil)

    var states: AnyPublisher<CameraState, Never> {
        subject.compactMap { $0 }.eraseToAnyPublisher()
    }

    func publish(_ state: CameraState) {
        subject.send(state)
    }
}
