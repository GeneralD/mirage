import Dependencies
import Domain

/// Everything `swift run dev-harness` does, kept out of `main.swift` so it runs
/// under test. The lite harness (#21) has no camera frames, no effect and no
/// pipeline (those arrive with #24); it does three things:
///
/// - It asks for the camera once, through `CameraControlUseCase` (the policy the
///   host's launch uses), so a run shows whether TCC honours the `Info.plist`
///   linked into the binary. The answer is logged and nothing waits for it.
/// - It attaches the preview window's view to the `PreviewSink` when
///   `PreviewView` hands it out.
/// - It presents one solid frame, leased once from `SurfaceRepository`, on every
///   `FrameScheduler` tick while no presentation of it is outstanding (a tick
///   that finds one outstanding is skipped, like the pipeline's in-flight cap).
///   The view is created at zero size, so a single frame at attach time would
///   find no drawable to land in; ticking fills the window once it has a size,
///   and again after every resize.
///
/// Frame state is executor-confined, as on the pipeline: ticks arrive on the
/// `FrameExecutor` and every other entry hops onto it, so there is no lock.
/// `start()` runs once, then `stop()` once. The frame's lease is given back
/// exactly once, after `stop()`, when its last presentation has completed.
final class HarnessSession: @unchecked Sendable {
    /// 1280×720 with every byte 0x80: mid grey under the preview's opaque layer,
    /// inside the black bars the preview kernel draws around a 16:9 frame.
    static let descriptor = SurfaceDescriptor.hd720
    static let fill: UInt8 = 0x80
    static let frameRate = FrameRate.standard

    @Dependency(\.cameraControlUseCase) private var cameraControl
    @Dependency(\.previewSink) private var previewSink
    @Dependency(\.surfaceRepository) private var surfaceRepository
    @Dependency(\.frameExecutor) private var frameExecutor
    @Dependency(\.frameScheduler) private var frameScheduler
    @Dependency(\.workRunner) private var workRunner
    @Dependency(\.errorLog) private var errorLog
    @Dependency(\.developerLog) private var developerLog

    // Executor-confined: the leased frame, whether a presentation of it is
    // outstanding, whether `stop()` has run, the unanswered camera prompt, and
    // the counters of the once-a-second summary.
    private var frame: FrameRef?
    private var presenting = false
    private var stopped = false
    private var prompt: (any WorkHandle)?
    private var ticks = 0
    private var presented = 0

    init() {}

    /// From the main thread, once the window is up.
    func start() {
        frameExecutor.run { [self] in begin() }
    }

    /// Stops the ticks and abandons an unanswered camera prompt. The frame goes
    /// back now, or when its outstanding presentation completes.
    func stop() {
        frameExecutor.run { [self] in end() }
    }

    /// From `PreviewView`, on the main thread, when the window's view exists. A
    /// refused attach is logged; the window then stays empty.
    @MainActor
    func attach(_ target: any PreviewTargetHandle) {
        do {
            try previewSink.attach(target)
            developerLog.record(.preview, "preview window attached")
        } catch {
            errorLog.record(.preview, "preview window not attached: \(error)")
        }
    }
}

// MARK: - Executor-confined

extension HarnessSession {
    private func begin() {
        prompt = askForCamera()
        guard let leased = leaseFrame() else { return }
        frame = leased
        frameScheduler.start(frameRate: Self.frameRate) { [weak self] in self?.tick() }
    }

    private func end() {
        stopped = true
        frameScheduler.stop()
        prompt?.cancel()
        prompt = nil
        guard !presenting else { return }
        giveBackFrame()
    }

    /// Arrives on the executor.
    private func tick() {
        ticks += 1
        if !presenting, let frame { present(frame) }
        guard ticks.isMultiple(of: Self.frameRate.framesPerSecond) else { return }
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
    private func leaseFrame() -> FrameRef? {
        do {
            guard let token = try surfaceRepository.allocate(Self.descriptor, filledWith: Self.fill) else {
                errorLog.record(.surfaces, "solid frame not leased: the surface pool is full")
                return nil
            }
            return FrameRef(token: token, descriptor: Self.descriptor, presentationTime: .zero)
        } catch {
            errorLog.record(.surfaces, "solid frame not leased: \(error)")
            return nil
        }
    }

    /// The prompt runs off the executor; a prompt abandoned by `stop()` reports nothing.
    private func askForCamera() -> any WorkHandle {
        workRunner.run { [cameraControl, developerLog, errorLog] in
            let status = await cameraControl.ensureAuthorized()
            guard !Task.isCancelled else { return }
            developerLog.record(.camera, "camera authorization: \(status)")
            guard !status.isGranted else { return }
            errorLog.record(.camera, "camera access not granted (\(status)); Lane 1 of .claude/rules/dev-verification.md covers TCC")
        }
    }
}
