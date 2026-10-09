import Dependencies
import Domain

/// The harness's lifecycle and wiring, and nothing else: what the harness does
/// is `HarnessInteractor`'s (the solid frame, the camera prompt, the log lines),
/// as the host app's launch is `CameraInteractor`'s.
///
/// `start()` runs the launch in the one task this process owns; `stop()`
/// cancels that task, so an unanswered camera prompt is abandoned, and shuts
/// the interactor down. `attach(_:)` passes `PreviewView`'s target through.
@MainActor
final class HarnessSession {
    /// The frame the lite harness shows, and the rate it re-presents it at.
    static let descriptor = SurfaceDescriptor.hd720
    static let frameRate = FrameRate.standard

    @Dependency(\.harnessInteractor) private var interactor

    private var launch: Task<Void, Never>?

    init() {}

    /// Once the window is up.
    func start() {
        launch = Task { [interactor] in
            await interactor.launch(descriptor: Self.descriptor, frameRate: Self.frameRate)
        }
    }

    /// On termination.
    func stop() {
        launch?.cancel()
        launch = nil
        interactor.shutDown()
    }

    /// From `PreviewView`, when the window's view exists.
    func attach(_ target: any PreviewTargetHandle) {
        interactor.attach(target)
    }
}
