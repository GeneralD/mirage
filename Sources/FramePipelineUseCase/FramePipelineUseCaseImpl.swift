import Combine
import Dependencies
import Domain

/// The host frame path: camera → latest-frame slot → one pass per scheduler
/// tick → virtual camera sink.
///
/// Capture runs at the camera's pace and the sink at the scheduler's, so the
/// two are decoupled by a one-element slot where the newest frame wins: a frame
/// that was never sent is released the moment a newer one arrives, and nothing
/// is ever queued. Every frame's lease is released right after the sink has
/// seen it, sent or not, because the extension holds its own reference.
public final class FramePipelineUseCaseImpl: FramePipelineUseCase, @unchecked Sendable {
    @Dependency(\.cameraRepository) private var cameraRepository
    @Dependency(\.virtualCameraSink) private var virtualCameraSink
    @Dependency(\.surfaceRepository) private var surfaceRepository
    @Dependency(\.frameExecutor) private var frameExecutor
    @Dependency(\.frameScheduler) private var frameScheduler
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
    // Executor-confined, like the phase: the reconnect task, and the epoch that tells
    // a finished task apart from the one that replaced it.
    private var reconnectTask: Task<Void, Never>?
    private var reconnectEpoch = 0
    let phaseSubject = CurrentValueSubject<PipelinePhase, Never>(.idle)

    public init() {}

    /// The counters as of the last frame-path step; in tests, read after
    /// `ManualFrameExecutor.drain()`.
    public var stats: PipelineStats { snapshot.value }

    /// The link phase as of the last executor step.
    var phase: PipelinePhase { phaseSubject.value }

    public func start(descriptor: SurfaceDescriptor, frameRate: FrameRate) async throws {
        frameExecutor.run { [self] in phaseSubject.value = .connecting }
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
        frameScheduler.stop()
        cameraRepository.stop()
        virtualCameraSink.disconnect()
        frameExecutor.run { [self] in
            cancelReconnect()
            phaseSubject.value = .stopped
            releaseLatest()
            surfaceRepository.releaseAll()
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
    }

    private func flushLatest() {
        guard let frame = takeLatest() else { return }
        let outcome = virtualCameraSink.send(frame)
        update { $0.note(outcome) }
        surfaceRepository.release(frame.token)
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
            case .frameDropped(let reason): noteDrop(reason)
            }
        }
    }

    /// A stalled link drops every frame for the same reason at the camera's
    /// pace; logging each one would flood the log, and the per-second summary
    /// already carries the totals. Only a change of reason is a news item.
    private func noteDrop(_ reason: FrameDropReason) {
        guard reason != lastDropReason else { return }
        lastDropReason = reason
        developerLog.record(.transport, "frame dropped: \(reason)")
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
            frameExecutor.run { [self] in settle(from: .connecting, to: .connected) }
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch {
            errorLog.record(.transport, "virtual camera sink did not connect: \(error)")
            frameExecutor.run { [self] in settle(from: .connecting, to: .disconnected) }
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
        guard reconnectTask == nil, phaseSubject.value == .connected || phaseSubject.value == .disconnected else { return }
        phaseSubject.value = .reconnecting
        reconnectEpoch += 1
        let epoch = reconnectEpoch
        let sink = virtualCameraSink
        reconnectTask = Task { [weak self] in
            let failure: (any Error)?
            do {
                try await sink.connect()
                failure = nil
            } catch {
                failure = error
            }
            self?.frameExecutor.run { [weak self] in self?.reconnectFinished(epoch: epoch, failure: failure) }
        }
    }

    private func reconnectFinished(epoch: Int, failure: (any Error)?) {
        guard epoch == reconnectEpoch else { return }
        reconnectTask = nil
        switch failure {
        case nil:
            settle(from: .reconnecting, to: .connected)
        case is CancellationError:
            settle(from: .reconnecting, to: .disconnected)
        case let error?:
            errorLog.record(.transport, "reconnect failed: \(error)")
            settle(from: .reconnecting, to: .disconnected)
        }
    }

    private func cancelReconnect() {
        reconnectEpoch += 1
        reconnectTask?.cancel()
        reconnectTask = nil
    }
}
