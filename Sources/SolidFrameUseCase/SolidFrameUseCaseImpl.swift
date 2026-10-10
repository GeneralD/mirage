import Dependencies
import Domain

/// One solid frame on the preview, re-presented every tick (#21's lite harness).
///
/// The preview window's view is created at zero size, so a single frame at
/// attach time would find no drawable to land in; ticking fills the window once
/// it has a size, and again after every resize. A tick that finds the previous
/// presentation outstanding is skipped, like the pipeline's in-flight cap. The
/// ticks share the frame executor with the preview's draw, so the once-a-second
/// summary drifts apart in `log stream` timestamps while a draw blocks there
/// (`docs/ARCHITECTURE.md` → *Preview*).
///
/// Frame state is executor-confined, as on the pipeline: ticks arrive on the
/// `FrameExecutor` and every other entry hops onto it, so there is no lock.
public final class SolidFrameUseCaseImpl: SolidFrameUseCase, @unchecked Sendable {
    /// Every byte 0x80: mid grey under the preview's opaque layer, inside the
    /// black bars the preview kernel draws around a frame of another aspect.
    static let fill: UInt8 = 0x80

    @Dependency(\.previewSink) private var previewSink
    @Dependency(\.surfaceRepository) private var surfaceRepository
    @Dependency(\.frameExecutor) private var frameExecutor
    @Dependency(\.frameScheduler) private var frameScheduler
    @Dependency(\.errorLog) private var errorLog
    @Dependency(\.developerLog) private var developerLog

    // Executor-confined: the leased frame, whether a presentation of it is
    // outstanding, whether `stop()` has run, and the summary's counters.
    private var frame: FrameRef?
    private var presenting = false
    private var stopped = false
    private var ticks = 0
    private var presented = 0

    public init() {}

    @MainActor
    public func attach(_ target: any PreviewTargetHandle) throws {
        try previewSink.attach(target)
    }

    public func start(descriptor: SurfaceDescriptor, frameRate: FrameRate) {
        frameExecutor.run { [self] in begin(descriptor: descriptor, frameRate: frameRate) }
    }

    public func stop() {
        frameExecutor.run { [self] in end() }
    }
}

// MARK: - Executor-confined

extension SolidFrameUseCaseImpl {
    private func begin(descriptor: SurfaceDescriptor, frameRate: FrameRate) {
        guard !stopped, let leased = leaseFrame(descriptor) else { return }
        frame = leased
        frameScheduler.start(frameRate: frameRate) { [weak self] in
            self?.tick(summaryEvery: frameRate.framesPerSecond)
        }
    }

    private func end() {
        stopped = true
        frameScheduler.stop()
        guard !presenting else { return }
        giveBackFrame()
    }

    /// Arrives on the executor.
    private func tick(summaryEvery interval: Int) {
        ticks += 1
        if !presenting, let frame { present(frame) }
        guard ticks.isMultiple(of: interval) else { return }
        developerLog.record(.preview, "solid frame: ticks=\(ticks) presented=\(presented) skipped=\(ticks - presented)")
    }

    /// The sink may complete on any thread; the completion hops back here.
    private func present(_ frame: FrameRef) {
        presenting = true
        presented += 1
        previewSink.present(frame) { [self] in
            frameExecutor.run { [self] in presentationCompleted() }
        }
    }

    private func presentationCompleted() {
        presenting = false
        guard stopped else { return }
        giveBackFrame()
    }

    private func giveBackFrame() {
        guard let frame else { return }
        self.frame = nil
        surfaceRepository.release(frame.token)
    }

    /// The preview draws by token and never reads the presentation time, so the
    /// one frame keeps time zero.
    private func leaseFrame(_ descriptor: SurfaceDescriptor) -> FrameRef? {
        do {
            guard let token = try surfaceRepository.allocate(descriptor, filledWith: Self.fill) else {
                errorLog.record(.surfaces, "solid frame not leased: the surface pool is full")
                return nil
            }
            return FrameRef(token: token, descriptor: descriptor, presentationTime: .zero)
        } catch {
            errorLog.record(.surfaces, "solid frame not leased: \(error)")
            return nil
        }
    }
}
