import Combine
import Dependencies
import Domain

/// The extension's frame path: receive a host frame, hand it to the stream and
/// release its lease straight away (the latest frame wins, nothing is queued).
///
/// Per-frame work runs on the `FrameExecutor`, the only writer of `snapshot`.
public final class ExtensionRelayUseCaseImpl: @unchecked Sendable {
    @Dependency(\.frameReceiverRepository) private var frameReceiverRepository
    @Dependency(\.streamOutputRepository) private var streamOutputRepository
    @Dependency(\.surfaceRepository) private var surfaceRepository
    @Dependency(\.frameExecutor) private var frameExecutor
    @Dependency(\.errorLog) private var errorLog
    @Dependency(\.developerLog) private var developerLog

    // Executor-confined: every mutation runs on FrameExecutor. A subject rather
    // than a bare `var` so `stats` can be read from any context without a lock.
    private let snapshot = CurrentValueSubject<PipelineStats, Never>(.empty)

    public init() {}
}

extension ExtensionRelayUseCaseImpl: ExtensionRelayUseCase {
    public var stats: PipelineStats { snapshot.value }

    public func run(descriptor: SurfaceDescriptor, frameRate: FrameRate) async throws {
        snapshot.value = .empty
        try streamOutputRepository.start(
            descriptor: descriptor,
            frameRate: frameRate,
            onEvent: { [developerLog] event in developerLog.record(.stream, "\(event)") }
        )
        // Whatever ends the receiver, no lease may outlive this run.
        defer { frameExecutor.run { [surfaceRepository] in surfaceRepository.releaseAll() } }
        try await frameReceiverRepository.start(
            onFrame: { [self] frame in relay(frame, frameRate: frameRate) },
            onEvent: { [self] event in note(event) }
        )
    }

    public func stop() {
        frameReceiverRepository.stop()
    }
}

extension ExtensionRelayUseCaseImpl {
    /// Runs on the executor.
    private func relay(_ frame: FrameRef, frameRate: FrameRate) {
        update { $0.noteReceived(at: frame.presentationTime) }
        let outcome = streamOutputRepository.send(frame)
        update { $0.note(outcome) }
        // The stream holds its own reference once `send` returns, so the lease
        // ends here whether the frame was sent or dropped.
        surfaceRepository.release(frame.token)
        report(every: frameRate.framesPerSecond)
    }

    /// One summary line per second of frames: the shape the acceptance run greps.
    private func report(every frameCount: Int) {
        let current = snapshot.value
        guard current.framesReceived % frameCount == 0 else { return }
        developerLog.record(.pipeline, current.summary)
    }

    private func note(_ event: ReceiverEvent) {
        developerLog.record(.receiver, "\(event)")
        guard case .hostLost = event else { return }
        errorLog.record(.receiver, "host lost: \(event)")
    }

    private func update(_ change: (inout PipelineStats) -> Void) {
        var next = snapshot.value
        change(&next)
        snapshot.value = next
    }
}
