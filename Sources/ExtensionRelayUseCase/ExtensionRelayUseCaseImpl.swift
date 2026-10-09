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
    @Dependency(\.frameScheduler) private var frameScheduler
    @Dependency(\.hostTime) private var hostTime
    @Dependency(\.errorLog) private var errorLog
    @Dependency(\.developerLog) private var developerLog

    // Executor-confined: every mutation runs on FrameExecutor. A subject rather
    // than a bare `var` so `stats` can be read from any context without a lock.
    private let snapshot = CurrentValueSubject<PipelineStats, Never>(.empty)
    // Executor-confined: the output phase and the slate episode's surface.
    private var schedule = SlateSchedule(frameRate: .standard)
    private var slateSurface: (token: SurfaceToken, descriptor: SurfaceDescriptor)?
    private var slateRequest: (descriptor: SurfaceDescriptor, frameRate: FrameRate)?

    public init() {}
}

extension ExtensionRelayUseCaseImpl: ExtensionRelayUseCase {
    public var stats: PipelineStats { snapshot.value }

    public func run(descriptor: SurfaceDescriptor, frameRate: FrameRate) async throws {
        try streamOutputRepository.start(
            descriptor: descriptor,
            frameRate: frameRate,
            onEvent: { [developerLog] event in developerLog.record(.stream, "\(event)") }
        )
        // On the executor like every other write; queued before the receiver
        // starts, so it precedes the first frame of this run. After the stream
        // start so that a failed start leaves nothing queued.
        frameExecutor.run { [self] in
            snapshot.value = .empty
            schedule = SlateSchedule(frameRate: frameRate)
            slateSurface = nil
            slateRequest = (descriptor, frameRate)
        }
        // Whatever ends the receiver, no lease and no tick may outlive this run
        // (the slate surface goes with `releaseAll`).
        defer {
            frameExecutor.run { [self] in
                frameScheduler.stop()
                schedule.reset()
                slateSurface = nil
                slateRequest = nil
                surfaceRepository.releaseAll()
            }
        }
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
        switch schedule.admit(frame.presentationTime) {
        case .dropNonMonotonic:
            // The stream sees strictly increasing PTS only; the lease ends here.
            update { $0.note(.dropped(.nonMonotonic)) }
            surfaceRepository.release(frame.token)
            report(every: frameRate.framesPerSecond)
            return
        case .resume:
            leaveSlate()
        case .relay:
            break
        }
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
        enterSlate()
    }

    /// Runs on the executor. The host is gone: keep the stream fed with black
    /// frames from a per-episode surface until a newer real frame arrives. A
    /// failed allocation leaves the output live-but-host-absent; the next
    /// `hostLost` tries again.
    private func enterSlate() {
        guard let request = slateRequest, let base = schedule.slateBase(hostNow: hostTime.now()) else { return }
        do {
            guard let token = try surfaceRepository.allocate(request.descriptor, filledWith: 0) else {
                errorLog.record(.pipeline, "slate not started: no surface available")
                return
            }
            slateSurface = (token, request.descriptor)
        } catch {
            errorLog.record(.pipeline, "slate not started: surface allocation failed: \(error)")
            return
        }
        schedule.enterSlate(base: base)
        developerLog.record(.pipeline, "slate entered base=\(base.nanoseconds)")
        // Ticks arrive on the executor already.
        frameScheduler.start(frameRate: request.frameRate) { [self] in slateTick() }
    }

    /// Runs on the executor.
    private func slateTick() {
        guard let surface = slateSurface, let time = schedule.nextSlateTime() else { return }
        let outcome = streamOutputRepository.send(FrameRef(token: surface.token, descriptor: surface.descriptor, presentationTime: time))
        update {
            switch outcome {
            case .sent: $0.slateFrames += 1
            case .dropped: $0.framesDropped += 1
            }
        }
    }

    /// Runs on the executor. The schedule has already gone back to live.
    private func leaveSlate() {
        frameScheduler.stop()
        if let surface = slateSurface { surfaceRepository.release(surface.token) }
        slateSurface = nil
        developerLog.record(.pipeline, "slate left")
    }

    private func update(_ change: (inout PipelineStats) -> Void) {
        var next = snapshot.value
        change(&next)
        snapshot.value = next
    }
}
