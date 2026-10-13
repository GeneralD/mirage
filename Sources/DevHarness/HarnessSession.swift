import Dependencies
import Domain
import HostDependencyInjection

/// The harness's lifecycle and wiring, and nothing else: what the harness does
/// is `HarnessInteractor`'s (the camera prompt, the pipeline, the log lines), as
/// the host app's launch is `CameraInteractor`'s.
///
/// `start()` runs the launch in the one task this process owns; `stop()`
/// cancels that task, so an unanswered camera prompt is abandoned, and shuts
/// the interactor down. `attach(_:)` passes `PreviewView`'s target through.
/// The wiring is `live()`: the host's live graph, with the one substitution the
/// harness needs (there is no extension to send frames to).
@MainActor
final class HarnessSession {
    /// The frame the harness captures and shows, and the rate the pipeline ticks at.
    static let descriptor = SurfaceDescriptor.hd720
    static let frameRate = FrameRate.standard

    @Dependency(\.harnessInteractor) private var interactor

    private var launch: Task<Void, Never>?

    init() {}

    /// The session the harness runs. `@Dependency` captures where it is built, so the
    /// substitution must wrap the construction: the interactor, and the pipeline under
    /// it, resolve their live values inside this scope and keep the sink they find there.
    static func live() -> HarnessSession {
        withDependencies {
            $0.useDiscardingVirtualCameraSink()
        } operation: {
            HarnessSession()
        }
    }

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
