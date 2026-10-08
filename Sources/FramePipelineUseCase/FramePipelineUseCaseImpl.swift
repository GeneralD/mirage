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

    // Executor-confined: every mutation runs on FrameExecutor.
    private var latest: FrameRef?
    private var counters = PipelineStats.empty
    private var tickCount = 0
    private var lastDropReason: FrameDropReason?

    public init() {}

    /// A snapshot of the executor-confined counters. It is not synchronised with
    /// the frame path: read it from a diagnostic context, or in tests after
    /// `ManualFrameExecutor.drain()`.
    public var stats: PipelineStats { counters }

    public func start(descriptor: SurfaceDescriptor, frameRate: FrameRate) async throws {
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
        counters.noteReceived(at: frame.presentationTime)
    }

    private func tick(summaryEvery interval: Int) {
        tickCount += 1
        flushLatest()
        guard tickCount.isMultiple(of: interval) else { return }
        developerLog.record(.pipeline, counters.summary)
    }

    private func flushLatest() {
        guard let frame = takeLatest() else { return }
        counters.note(virtualCameraSink.send(frame))
        surfaceRepository.release(frame.token)
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
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch {
            errorLog.record(.transport, "virtual camera sink did not connect: \(error)")
        }
    }
}
