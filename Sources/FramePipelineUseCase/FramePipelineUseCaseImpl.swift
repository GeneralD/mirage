import Combine
import Dependencies
import Domain

/// The host frame path: camera → latest-frame slot → one effect pass per
/// scheduler tick → virtual camera sink.
///
/// Capture runs at the camera's pace and the sink at the scheduler's, so the
/// two are decoupled by a one-element slot where the newest frame wins: a frame
/// that was never taken is released the moment a newer one arrives, and nothing
/// is ever queued. A tick hands the frame it takes to the effect runtime off the
/// executor, at most one pass at a time; a tick that finds a pass still running
/// drops its frame as `.inFlightCapReached`, so every frame a tick takes is
/// sent, counted as a drop, or abandoned by `stop`. The pass's answer comes back
/// on the executor: on success the rendered output goes to the sink, on any
/// failure the input goes instead, unchanged — judged frame by frame, with no
/// memory of earlier failures. Every lease ends exactly once: the input's when
/// the runtime is done with it (or after the sink has seen it, on a failure),
/// the output's after the sink has seen it, sent or not, because the extension
/// holds its own reference. Only the answer ends a pass: one that `stop` gives up
/// on keeps its leases and the in-flight cap until the answer arrives, then ends
/// them without sending, because the GPU may still be reading or writing them.
public final class FramePipelineUseCaseImpl: FramePipelineUseCase, @unchecked Sendable {
    @Dependency(\.cameraRepository) private var cameraRepository
    @Dependency(\.virtualCameraSink) private var virtualCameraSink
    @Dependency(\.surfaceRepository) private var surfaceRepository
    @Dependency(\.effectRuntimeRepository) private var effectRuntimeRepository
    @Dependency(\.frameExecutor) private var frameExecutor
    @Dependency(\.frameScheduler) private var frameScheduler
    @Dependency(\.workRunner) private var workRunner
    @Dependency(\.continuousClock) private var clock
    @Dependency(\.errorLog) private var errorLog
    @Dependency(\.developerLog) private var developerLog

    // Executor-confined: every mutation runs on FrameExecutor. The statistics
    // live in a subject rather than a bare `var` so `stats` reads one whole
    // snapshot from any context (the subject synchronizes its `value`); the
    // executor is its only writer and never reads it back.
    private var latest: FrameRef?
    private let snapshot = CurrentValueSubject<PipelineStats, Never>(.empty)
    private var tickCount = 0
    private var lastDropReason: FrameDropReason?
    // Executor-confined, like the phase: the reconnect work (owned through the
    // `WorkRunner` port, never an unstructured `Task` here), and the epoch that tells
    // finished work apart from the one that replaced it.
    private var reconnectWork: (any WorkHandle)?
    private var reconnectEpoch = 0
    // A loss that arrived while a connect (first or re-) was still settling: it is
    // remembered and replayed when that connect finishes, never dropped.
    private var lossPending = false
    // Losses since a frame last reached the extension; paces the next reconnect.
    private var lossStreak = 0
    // Executor-confined, the effect stage: the pass the runtime is working on (the
    // in-flight cap is one; a pass `stop` abandoned still holds it until its answer),
    // and the index the next pass of this run hands the effect.
    private var inFlight: EffectPass?
    private var frameIndex: UInt32 = 0
    /// How many times `stop` was called. `stop` bumps it first thing, from the caller's
    /// context (the subject synchronizes its `value`; `stop` is its only writer), and
    /// the executor compares a pass's epoch with it before sending anything.
    private let stopEpoch = CurrentValueSubject<Int, Never>(0)
    let phaseSubject = CurrentValueSubject<PipelinePhase, Never>(.idle)

    public init() {}

    /// The counters as of the last frame-path step; in tests, read after
    /// `ManualFrameExecutor.drain()`.
    public var stats: PipelineStats { snapshot.value }

    /// The link phase as of the last executor step.
    var phase: PipelinePhase { phaseSubject.value }

    public func start(descriptor: SurfaceDescriptor, frameRate: FrameRate) async throws {
        frameExecutor.run { [self] in
            // A fresh run: nothing of a previous run's loss pacing carries over, and
            // the effect counts frames from zero again.
            lossStreak = 0
            lastDropReason = nil
            frameIndex = 0
            phaseSubject.value = .connecting
        }
        virtualCameraSink.observe { [weak self] event in self?.observed(event) }
        try cameraRepository.start(
            descriptor: descriptor,
            onFrame: { [weak self] frame in self?.receive(frame) },
            onEnd: { [weak self] end in self?.captureEnded(end) }
        )
        frameScheduler.start(frameRate: frameRate) { [weak self] in
            self?.tick(summaryEvery: frameRate.framesPerSecond)
        }
        try await connect()
    }

    public func stop() {
        // First, from the caller's context: every pass started before this moment is
        // abandoned now, so an answer already queued on the executor ahead of the
        // cleanup below can no longer send — whenever the sink's own teardown lands.
        stopEpoch.value += 1
        frameScheduler.stop()
        cameraRepository.stop()
        // Cancel the reconnect work before the sink's generation moves: a task that
        // reads the new generation afterwards is then already cancelled and cannot
        // bring the transport back up after `stop`.
        frameExecutor.run { [self] in
            cancelReconnect()
            lossStreak = 0
        }
        virtualCameraSink.disconnect()
        frameExecutor.run { [self] in
            phaseSubject.value = .stopped
            releaseLatest()
            resetPoolWhenIdle()
        }
    }
}

// MARK: - Frame path (executor-confined)

extension FramePipelineUseCaseImpl {
    /// Arrives on the executor. Latest wins: an unsent predecessor is released.
    private func receive(_ frame: FrameRef) {
        releaseLatest()
        latest = frame
        update { $0.noteReceived(at: frame.presentationTime) }
    }

    private func tick(summaryEvery interval: Int) {
        tickCount += 1
        flushLatest()
        guard tickCount.isMultiple(of: interval) else { return }
        developerLog.record(.pipeline, snapshot.value.summary)
        developerLog.record(.effect, snapshot.value.effectSummary)
    }

    /// Takes the latest frame into the effect stage. A pass still running means the
    /// in-flight cap is reached: the frame drops here rather than waiting behind
    /// the GPU, and the next tick takes whatever is newest by then.
    private func flushLatest() {
        guard let frame = takeLatest() else { return }
        guard inFlight == nil else { return drop(frame, because: .inFlightCapReached) }
        startEffect(on: frame)
    }

    /// Hands one frame to the sink and ends its lease, sent or not.
    private func deliver(_ frame: FrameRef) {
        let outcome = virtualCameraSink.send(frame)
        update { $0.note(outcome) }
        if outcome.wasSent { lossStreak = 0 }
        surfaceRepository.release(frame.token)
    }

    /// A frame the pipeline itself gives up on: its lease ends and the drop is counted.
    private func drop(_ frame: FrameRef, because reason: FrameDropReason) {
        surfaceRepository.release(frame.token)
        update { $0.note(.dropped(reason)) }
        noteDrop(reason, in: .effect)
    }

    private func update(_ change: (inout PipelineStats) -> Void) {
        var next = snapshot.value
        change(&next)
        snapshot.value = next
    }

    private func releaseLatest() {
        guard let frame = takeLatest() else { return }
        surfaceRepository.release(frame.token)
    }

    private func takeLatest() -> FrameRef? {
        defer { latest = nil }
        return latest
    }
}

// MARK: - Effect stage (executor-confined)

extension FramePipelineUseCaseImpl {
    /// Leases an output surface and starts `apply` through the `WorkRunner` port; the
    /// answer hops back onto the executor. With no output surface there is nothing to
    /// render into, so the frame drops as `.poolExhausted`, as the pool's contract
    /// asks of every caller it refuses.
    private func startEffect(on input: FrameRef) {
        guard let output = leaseOutput(like: input) else { return drop(input, because: .poolExhausted) }
        let context = FrameContext(presentationTime: input.presentationTime, frameIndex: frameIndex)
        frameIndex &+= 1
        let runtime = effectRuntimeRepository
        // The handle is not kept: cancelling cuts no GPU work short (the port's
        // contract), so only the answer can end the pass.
        _ = workRunner.run { [weak self] in
            let result = await runtime.apply(input: input, output: output, frameContext: context)
            self?.frameExecutor.run { [weak self] in self?.effectFinished(with: result) }
        }
        inFlight = EffectPass(input: input, output: output, epoch: stopEpoch.value)
    }

    /// The output carries the input's geometry and presentation time, so the stream
    /// stays in capture order whichever of the two is sent.
    private func leaseOutput(like input: FrameRef) -> FrameRef? {
        do {
            guard let token = try surfaceRepository.allocate(input.descriptor) else {
                errorLog.record(.surfaces, "effect output not leased: pool exhausted")
                return nil
            }
            return FrameRef(token: token, descriptor: input.descriptor, presentationTime: input.presentationTime)
        } catch {
            errorLog.record(.surfaces, "effect output not leased: \(error)")
            return nil
        }
    }

    /// The runtime's answer, back on the executor; it frees the in-flight cap. On
    /// success the input's lease ends now that the runtime is done reading it and the
    /// output goes on; on any failure the unused output is given back first and the
    /// input goes on unchanged. A pass a `stop` has abandoned since it started is
    /// only ended, even when its answer was already queued before that `stop`.
    private func effectFinished(with result: Result<Void, EffectFailure>) {
        guard let pass = inFlight else { return }
        inFlight = nil
        guard pass.epoch == stopEpoch.value else { return endAbandoned(pass) }
        update { $0.noteEffect(result) }
        switch result {
        case .success:
            surfaceRepository.release(pass.input.token)
            deliver(pass.output)
        case .failure:
            surfaceRepository.release(pass.output.token)
            deliver(pass.input)
        }
    }

    /// `stop`'s pool reset (`releaseAll`), run only when no pass is in flight. A pass
    /// still running was abandoned by `stop` but cannot be called back — the GPU
    /// finishes what it was given and `apply` answers with the real outcome — so it
    /// keeps both leases, and the in-flight cap, until that answer; resetting the pool
    /// now would hand surfaces the GPU still reads or writes to the next frame. The
    /// reset then waits for the answer (`endAbandoned`).
    private func resetPoolWhenIdle() {
        guard inFlight == nil else { return }
        surfaceRepository.releaseAll()
    }

    /// The answer to a pass `stop` abandoned: nothing is sent and the outcome is not
    /// counted as applied or failed; both leases end. If `stop`'s cleanup has run and
    /// the pipeline is still stopped, the pool reset it deferred runs now (an answer
    /// that overtakes the cleanup leaves the reset to it); after a restart the pool
    /// belongs to the new run and is left alone.
    private func endAbandoned(_ pass: EffectPass) {
        surfaceRepository.release(pass.input.token)
        surfaceRepository.release(pass.output.token)
        guard phase == .stopped else { return }
        surfaceRepository.releaseAll()
    }
}

// MARK: - Events and connection

extension FramePipelineUseCaseImpl {
    private func observed(_ event: FrameTransportEvent) {
        frameExecutor.run { [self] in
            switch event {
            case .connected:
                lastDropReason = nil
                developerLog.record(.transport, "connected to the extension")
            case .disconnected(.explicit): developerLog.record(.transport, "disconnected")
            case .disconnected(.destinationLost):
                errorLog.record(.transport, "disconnected: destinationLost")
                startReconnect()
            case .disconnected(let reason): errorLog.record(.transport, "disconnected: \(reason)")
            case .frameDropped(let reason): noteDrop(reason, in: .transport)
            }
        }
    }

    /// A stalled link (or a stalled effect) drops every frame for the same reason
    /// at the camera's pace; logging each one would flood the log, and the
    /// per-second summaries already carry the totals. Only a change of reason is a
    /// news item.
    private func noteDrop(_ reason: FrameDropReason, in subsystem: LogSubsystem) {
        guard reason != lastDropReason else { return }
        lastDropReason = reason
        developerLog.record(subsystem, "frame dropped: \(reason)")
    }

    private func captureEnded(_ end: CaptureEnd) {
        frameExecutor.run { [self] in
            switch end {
            case .stopped: developerLog.record(.camera, "capture stopped")
            case .deviceDisconnected: errorLog.record(.camera, "capture ended: device disconnected")
            case .runtimeError(let message): errorLog.record(.camera, "capture ended: \(message)")
            }
            releaseLatest()
        }
    }

    /// Cancellation belongs to the caller and propagates; any other failure is
    /// logged and the pipeline keeps running, dropping frames as `.notConnected`.
    private func connect() async throws {
        do {
            try await virtualCameraSink.connect()
            frameExecutor.run { [self] in
                settle(from: .connecting, to: .connected)
                replayPendingLoss()
            }
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch {
            errorLog.record(.transport, "virtual camera sink did not connect: \(error)")
            frameExecutor.run { [self] in
                settle(from: .connecting, to: .disconnected)
                lossPending = false
            }
        }
    }

    /// Moves the phase only when it is still where the caller left it: a `stop`
    /// that ran in between is not undone by a late result.
    private func settle(from expected: PipelinePhase, to next: PipelinePhase) {
        guard phaseSubject.value == expected else { return }
        phaseSubject.value = next
    }
}

// MARK: - Reconnect (executor-confined)

extension FramePipelineUseCaseImpl {
    /// The extension went away while the pipeline was up: look the service up again
    /// (the sink's retry policy paces it on the injected clock) without blocking the
    /// executor. One task at a time; an explicit disconnect or a failed first
    /// look-up is not a loss and brings nothing back.
    private func startReconnect() {
        switch phaseSubject.value {
        case .connecting, .reconnecting:
            // The connect in flight has not settled yet; its loss is replayed once it has.
            lossPending = true
            return
        case .connected, .disconnected:
            break
        case .idle, .stopped:
            return
        }
        guard reconnectWork == nil else { return }
        phaseSubject.value = .reconnecting
        reconnectEpoch += 1
        lossStreak += 1
        let epoch = reconnectEpoch
        let sink = virtualCameraSink
        let pause = Self.pause(beforeReconnectAfterLosses: lossStreak)
        let clock = clock
        reconnectWork = workRunner.run { [weak self] in
            let failure: (any Error)?
            do {
                // The first loss reconnects at once; a link that keeps dying before a
                // single frame got through backs off like a failing look-up does.
                if let pause { try await clock.sleep(for: pause) }
                try await sink.connect()
                failure = nil
            } catch {
                failure = error
            }
            self?.frameExecutor.run { [weak self] in self?.reconnectFinished(epoch: epoch, failure: failure) }
        }
    }

    private static func pause(beforeReconnectAfterLosses losses: Int) -> Duration? {
        losses > 1 ? RetryPolicy.serviceLookup.delay(afterFailure: losses - 1) : nil
    }

    private func reconnectFinished(epoch: Int, failure: (any Error)?) {
        guard epoch == reconnectEpoch else { return }
        reconnectWork = nil
        switch failure {
        case nil:
            settle(from: .reconnecting, to: .connected)
            replayPendingLoss()
        case is CancellationError:
            settle(from: .reconnecting, to: .disconnected)
            lossPending = false
        case let error?:
            errorLog.record(.transport, "reconnect failed: \(error)")
            settle(from: .reconnecting, to: .disconnected)
            lossPending = false
        }
    }

    private func replayPendingLoss() {
        guard lossPending else { return }
        lossPending = false
        startReconnect()
    }

    private func cancelReconnect() {
        reconnectEpoch += 1
        lossPending = false
        reconnectWork?.cancel()
        reconnectWork = nil
    }
}
