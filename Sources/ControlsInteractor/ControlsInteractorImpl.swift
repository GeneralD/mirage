import Combine
import Dependencies
import Domain

/// The menu bar's controls Interactor: it publishes the bypass state and the frame-rate
/// readout, and carries the bypass toggle to the pipeline.
///
/// `start()` begins a sampler that wakes once a second on `\.continuousClock` and counts the
/// frames the pipeline took in that second. `stop()` ends the sampler and publishes a readout
/// of 0, keeping the bypass. Like `EffectInteractorImpl`, the commands only queue themselves:
/// one supervising task carries them out in call order, so the sampler and the state need no
/// lock. The sampler feeds the same queue with `.sample`, and a sample is applied only while a
/// sampler is running, so nothing reaches `state` after `stop()` has been carried out.
///
/// `state` is a `CurrentValueSubject` underneath: it holds `ControlsState()` from construction
/// on, so a subscriber that arrives early still receives the current controls first.
public final class ControlsInteractorImpl: Sendable {
    private enum Command: Sendable {
        case start
        case stop
        case toggleBypass
        case sample
    }

    private let relay: StateRelay
    private let commands: AsyncStream<Command>.Continuation

    public init() {
        @Dependency(\.framePipelineUseCase) var pipeline
        @Dependency(\.continuousClock) var clock
        @Dependency(\.developerLog) var developerLog
        let relay = StateRelay()
        let (stream, commands) = AsyncStream<Command>.makeStream()
        self.relay = relay
        self.commands = commands
        // One immutable copy for the supervising task: it captures `let`s, not the mutable
        // `@Dependency` bindings.
        let supervisor = Supervisor(
            pipeline: pipeline,
            clock: clock,
            log: developerLog,
            relay: relay,
            mailbox: commands
        )
        Task { await Self.supervise(stream, with: supervisor) }
    }

    deinit {
        commands.finish()
    }
}

extension ControlsInteractorImpl: ControlsInteractor {
    public var state: AnyPublisher<ControlsState, Never> { relay.states }

    public func start() {
        commands.yield(.start)
    }

    public func stop() {
        commands.yield(.stop)
    }

    public func toggleBypass() {
        commands.yield(.toggleBypass)
    }
}

extension ControlsInteractorImpl {
    /// Everything the supervising task reaches. All of it is `Sendable`, and none of it is the
    /// Interactor itself, so that `deinit` is what ends the task.
    private struct Supervisor: Sendable {
        let pipeline: any FramePipelineUseCase
        let clock: any Clock<Duration>
        let log: any DeveloperLog
        let relay: StateRelay
        /// The queue the sampler feeds back into.
        let mailbox: AsyncStream<Command>.Continuation
    }

    /// The supervisor's own state: the controls last published, the frame count the readout
    /// measures from, and the sampler while one runs. Only the supervising task touches it.
    private struct Controls {
        var state = ControlsState()
        var lastFrames = 0
        var sampler: Task<Void, Never>?

        mutating func apply(_ command: Command, _ env: Supervisor) {
            switch command {
            case .start:
                guard sampler == nil else { return }
                lastFrames = env.pipeline.stats.framesReceived
                sampler = Task { while (try? await env.clock.sleep(for: .seconds(1))) != nil { env.mailbox.yield(.sample) } }
                env.log.record(.pipeline, "fps readout started")
            case .stop:
                guard sampler != nil else { return }
                sampler?.cancel()
                sampler = nil
                publish(framesPerSecond: 0, env)
                env.log.record(.pipeline, "fps readout stopped")
            case .toggleBypass:
                let bypassed = !state.isBypassed
                env.pipeline.setBypass(bypassed)
                publish(bypassed: bypassed, framesPerSecond: state.framesPerSecond, env)
            case .sample:
                guard sampler != nil else { return }
                let received = env.pipeline.stats.framesReceived
                // The pipeline is rebuilt when its counter goes back; a readout then reads 0, never less.
                let framesPerSecond = max(0, received - lastFrames)
                lastFrames = received
                publish(framesPerSecond: framesPerSecond, env)
            }
        }

        private mutating func publish(bypassed: Bool? = nil, framesPerSecond: Int, _ env: Supervisor) {
            state = ControlsState(isBypassed: bypassed ?? state.isBypassed, framesPerSecond: framesPerSecond)
            env.relay.publish(state)
        }
    }

    /// Carries out the commands in the order they were queued, until the Interactor is gone.
    /// When the stream ends, the sampler that is still running is cancelled with it.
    private static func supervise(_ commands: AsyncStream<Command>, with env: Supervisor) async {
        let last = await commands.reduce(into: Controls()) { controls, command in
            controls.apply(command, env)
        }
        last.sampler?.cancel()
    }
}

/// The controls last published, as a publisher: `ControlsState()` at once, then the latest one
/// to every new subscriber and each change to the existing ones.
///
/// `@unchecked Sendable`: `CurrentValueSubject` serialises its own sends and subscriptions, and
/// the sends all come from the one supervising task.
private final class StateRelay: @unchecked Sendable {
    private let subject = CurrentValueSubject<ControlsState, Never>(ControlsState())

    var states: AnyPublisher<ControlsState, Never> {
        subject.eraseToAnyPublisher()
    }

    func publish(_ state: ControlsState) {
        subject.send(state)
    }
}
