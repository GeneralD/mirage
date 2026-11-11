import Combine
import Dependencies
import Domain

/// The camera menu's display state (epic E5-camera, #166): the titles, the cameras, resolutions and frame
/// rates on offer with the choice in effect, whether the picture is mirrored, and one line about why the
/// chosen camera cannot be used. It turns `CameraSelectionInteractor.state` into `@Published` values a View
/// draws, and hands the user's choices back to the Interactor. The words and the row ids come from
/// `CameraMenuText`; the Presenter opens no window, since the camera menu has none.
///
/// The Presenter owns the lifecycle of its Interactor for the menu, as `MenuBarPresenter` does for its
/// own: `start()` begins observing the state and starts the Interactor, `stop()` ends the observation and
/// stops it. Nothing starts on its own. A started Presenter that is let go does what `stop()` does.
///
/// The state reaches the main actor through a `CameraStateObservation`, which keeps the newest state until
/// it is applied and applies nothing after it ends.
@MainActor
public final class CameraMenuPresenter: ObservableObject {
    /// One row per camera the OS lists, the camera in use selected; empty until the first state arrives.
    @Published public private(set) var devices: [CameraMenuOption] = []
    /// One row per resolution on offer, the chosen one selected.
    @Published public private(set) var resolutions: [CameraMenuOption] = []
    /// One row per frame rate on offer, the chosen one selected.
    @Published public private(set) var frameRates: [CameraMenuOption] = []
    /// Whether the picture is mirrored, as the state says. `setMirrored(_:)` changes it only through the
    /// Interactor, so it stays as it was until that state comes back.
    @Published public private(set) var isMirrored = false
    /// One line about why the chosen camera cannot be used (`"<name> is not connected"`, `"No camera found"`);
    /// `nil` when it can.
    @Published public private(set) var status: String?

    public var title: String { text.title }
    public var resolutionTitle: String { text.resolutionTitle }
    public var frameRateTitle: String { text.frameRateTitle }
    public var mirrorTitle: String { text.mirrorTitle }

    @Dependency(\.cameraSelectionInteractor) private var interactor
    private let text = CameraMenuText()
    /// What a started Presenter holds; `nil` when it was never started or has been stopped. Releasing it
    /// ends the observation and stops the Interactor, so `stop()` and letting the Presenter go are one path.
    private var running: Running?

    public init() {}

    /// Observes the Interactor's state, then starts the Interactor. Calling it again while started does nothing.
    public func start() {
        guard running == nil else { return }
        running = Running(over: interactor, apply: { [weak self] state in self?.apply(state) })
        interactor.start()
    }

    /// Ends the observation and stops the Interactor. The rows stay as they were.
    public func stop() {
        guard running != nil else {
            interactor.stop()
            return
        }
        running = nil
    }

    /// Chooses the camera `id`, passing the id on as it is.
    public func selectDevice(_ id: String) {
        interactor.selectDevice(id)
    }

    /// Chooses the resolution `id` (`1920x1080`). An id `CameraMenuText` cannot read asks nothing of the Interactor.
    public func selectResolution(_ id: String) {
        guard let resolution = text.resolution(fromID: id) else { return }
        interactor.selectResolution(resolution)
    }

    /// Chooses the frame rate `id` (`24`). An id `CameraMenuText` cannot read asks nothing of the Interactor.
    public func selectFrameRate(_ id: String) {
        guard let framesPerSecond = text.frameRate(fromID: id) else { return }
        interactor.selectFrameRate(framesPerSecond)
    }

    /// Sets the mirror flag in the Interactor. `isMirrored` changes when its state comes back, not here.
    public func setMirrored(_ isMirrored: Bool) {
        interactor.setMirrored(isMirrored)
    }

    /// Writes each value only when it changed, so a state that changes nothing publishes nothing.
    private func apply(_ state: CameraState) {
        let devices = text.devices(of: state)
        let resolutions = text.resolutions(of: state)
        let frameRates = text.frameRates(of: state)
        let status = text.status(of: state)
        if self.devices != devices { self.devices = devices }
        if self.resolutions != resolutions { self.resolutions = resolutions }
        if self.frameRates != frameRates { self.frameRates = frameRates }
        if isMirrored != state.isMirrored { isMirrored = state.isMirrored }
        if self.status != status { self.status = status }
    }
}

extension CameraMenuPresenter {
    /// A started Presenter's observation of the Interactor's state and the Interactor's run, ended together
    /// when this is released. Its own class rather than the Presenter's `deinit`, for the reason
    /// `MenuBarPresenter`'s `Running` gives: a main-actor class's `deinit` is not isolated, and
    /// `isolated deinit` is not available on the toolchain that builds the release.
    private final class Running {
        private let observation: CameraStateObservation
        private let interactor: any CameraSelectionInteractor

        @MainActor
        init(over interactor: any CameraSelectionInteractor, apply: @escaping @MainActor (CameraState) -> Void) {
            self.interactor = interactor
            observation = CameraStateObservation(of: interactor.state, apply: apply)
        }

        deinit {
            observation.end()
            interactor.stop()
        }
    }
}
