import Combine
import Dependencies
import Domain
import Presenters
import TestDoubles
import TestSupport
import Testing

@MainActor
@Suite("CameraMenuPresenter", .timeLimit(.minutes(1)))
struct CameraMenuPresenterTests {
    private let front = CameraDevice(id: "front", name: "FaceTime HD Camera")
    private let usb = CameraDevice(id: "usb", name: "Logitech C920")
    private let hd = CameraResolution(width: 1280, height: 720)
    private let fullHD = CameraResolution(width: 1920, height: 1080)

    private func state(
        devices: [CameraDevice] = [],
        selectedDeviceID: String? = nil,
        availability: CameraAvailability = .available,
        resolutions: [CameraResolution] = [],
        selectedResolution: CameraResolution? = nil,
        frameRates: [Int] = [],
        selectedFrameRate: Int? = nil,
        isMirrored: Bool = false
    ) -> CameraState {
        CameraState(
            devices: devices,
            selectedDeviceID: selectedDeviceID,
            availability: availability,
            resolutions: resolutions,
            selectedResolution: selectedResolution,
            frameRates: frameRates,
            selectedFrameRate: selectedFrameRate,
            isMirrored: isMirrored)
    }

    /// A state with one connected camera in use, so `devices` is filled once it is applied.
    private var connected: CameraState {
        state(devices: [front], selectedDeviceID: "front")
    }

    // MARK: - Titles

    @Test("the titles are Camera, Resolution, Frame Rate and Mirror")
    func titlesAreFixed() {
        let rig = PresenterRig(state: .empty)

        #expect(rig.presenter.title == "Camera")
        #expect(rig.presenter.resolutionTitle == "Resolution")
        #expect(rig.presenter.frameRateTitle == "Frame Rate")
        #expect(rig.presenter.mirrorTitle == "Mirror")
    }

    // MARK: - Start

    @Test("nothing is shown, and nothing is asked of the Interactor, until the Presenter starts")
    func quietBeforeStart() {
        let rig = PresenterRig(state: connected)

        #expect(rig.presenter.devices.isEmpty)
        #expect(rig.presenter.resolutions.isEmpty)
        #expect(rig.presenter.frameRates.isEmpty)
        #expect(rig.presenter.isMirrored == false)
        #expect(rig.presenter.status == nil)
        #expect(rig.interactor.inner.starts.count == 0)
    }

    @Test("start fills devices, resolutions, frame rates, isMirrored and status from the state")
    func startFillsEverythingFromTheState() async {
        let rig = PresenterRig(
            state: state(
                devices: [front, usb], selectedDeviceID: "usb",
                resolutions: [hd, fullHD], selectedResolution: fullHD,
                frameRates: [30, 60], selectedFrameRate: 60,
                isMirrored: true))

        rig.presenter.start()
        await settle(rig.presenter.$devices) { !$0.isEmpty }

        #expect(
            rig.presenter.devices == [
                CameraMenuOption(id: "front", title: "FaceTime HD Camera", isSelected: false),
                CameraMenuOption(id: "usb", title: "Logitech C920", isSelected: true),
            ])
        #expect(
            rig.presenter.resolutions == [
                CameraMenuOption(id: "1280x720", title: "1280 \u{00D7} 720", isSelected: false),
                CameraMenuOption(id: "1920x1080", title: "1920 \u{00D7} 1080", isSelected: true),
            ])
        #expect(
            rig.presenter.frameRates == [
                CameraMenuOption(id: "30", title: "30 fps", isSelected: false),
                CameraMenuOption(id: "60", title: "60 fps", isSelected: true),
            ])
        #expect(rig.presenter.isMirrored)
        #expect(rig.presenter.status == nil)
    }

    @Test("when the chosen camera is gone, status names it, the connected cameras are listed, and only the camera in use is selected")
    func missingCameraIsNamedInStatus() async {
        let rig = PresenterRig(
            state: state(devices: [front], selectedDeviceID: "front", availability: .missing("Logitech C920")))

        rig.presenter.start()
        await settle(rig.presenter.$status) { $0 != nil }

        #expect(rig.presenter.status == "Logitech C920 is not connected")
        #expect(rig.presenter.devices == [CameraMenuOption(id: "front", title: "FaceTime HD Camera", isSelected: true)])
    }

    @Test("with no camera at all, the candidates are all empty and status says No camera found")
    func noCameraEmptiesEverything() async {
        let rig = PresenterRig(state: .empty)

        rig.presenter.start()
        await settle(rig.presenter.$status) { $0 != nil }

        #expect(rig.presenter.devices.isEmpty)
        #expect(rig.presenter.resolutions.isEmpty)
        #expect(rig.presenter.frameRates.isEmpty)
        #expect(rig.presenter.status == "No camera found")
    }

    @Test("a state that is sent again does not reassign the published values, so objectWillChange does not fire for it")
    func repeatedStateReassignsNothing() async {
        let first = state(
            devices: [front], selectedDeviceID: "front",
            resolutions: [hd], selectedResolution: hd,
            frameRates: [30], selectedFrameRate: 30)
        let rig = PresenterRig(state: first)
        rig.presenter.start()
        await settle(rig.presenter.$devices) { !$0.isEmpty }

        let changes = Collector<Void>()
        let subscription = rig.presenter.objectWillChange.sink { changes.append(()) }
        rig.interactor.inner.publish(first)
        // Only the mirror flag differs, so the one change below is the only one the Presenter may publish.
        rig.interactor.inner.publish(
            state(
                devices: [front], selectedDeviceID: "front",
                resolutions: [hd], selectedResolution: hd,
                frameRates: [30], selectedFrameRate: 30,
                isMirrored: true))
        await settle(rig.presenter.$isMirrored) { $0 }

        #expect(changes.count == 1, "the repeated state published nothing, and the mirror change published once")
        withExtendedLifetime(subscription) {}
    }

    // MARK: - Commands

    @Test("selectResolution(\"1920x1080\") passes 1920x1080 to the Interactor")
    func selectResolutionPassesTheSize() {
        let rig = PresenterRig(state: .empty)

        rig.presenter.selectResolution("1920x1080")

        #expect(rig.interactor.inner.resolutionSelections.values == [fullHD])
    }

    @Test(
        "selectResolution asks nothing of the Interactor for an id that cannot be read",
        arguments: ["", "1920", "1920x", "x1080", "0x1080", "1920x-1080", "1920x1080x2", "wide"])
    func unreadableResolutionIsIgnored(id: String) {
        let rig = PresenterRig(state: .empty)

        rig.presenter.selectResolution(id)

        #expect(rig.interactor.inner.resolutionSelections.values.isEmpty)
    }

    @Test("selectFrameRate(\"24\") passes 24 to the Interactor")
    func selectFrameRatePassesTheRate() {
        let rig = PresenterRig(state: .empty)

        rig.presenter.selectFrameRate("24")

        #expect(rig.interactor.inner.frameRateSelections.values == [24])
    }

    @Test(
        "selectFrameRate asks nothing of the Interactor for an id that cannot be read",
        arguments: ["", "0", "-24", "24.5", "24fps", "fps"])
    func unreadableFrameRateIsIgnored(id: String) {
        let rig = PresenterRig(state: .empty)

        rig.presenter.selectFrameRate(id)

        #expect(rig.interactor.inner.frameRateSelections.values.isEmpty)
    }

    @Test("selectDevice and setMirrored pass their arguments to the Interactor unchanged")
    func deviceAndMirrorPassThrough() {
        let rig = PresenterRig(state: .empty)

        rig.presenter.selectDevice("usb")
        rig.presenter.setMirrored(true)
        rig.presenter.setMirrored(false)

        #expect(rig.interactor.inner.deviceSelections.values == ["usb"])
        #expect(rig.interactor.inner.mirrorSettings.values == [true, false])
    }

    // MARK: - Lifecycle

    @Test("start starts the Interactor once, however many times it is called")
    func startIsIdempotent() async {
        let rig = PresenterRig(state: connected)

        rig.presenter.start()
        rig.presenter.start()
        await settle(rig.presenter.$devices) { !$0.isEmpty }

        #expect(rig.interactor.inner.starts.count == 1)
    }

    @Test("stop stops the Interactor once")
    func stopStopsTheInteractorOnce() async {
        let rig = PresenterRig(state: connected)
        rig.presenter.start()
        await settle(rig.presenter.$devices) { !$0.isEmpty }

        rig.presenter.stop()

        #expect(rig.interactor.inner.stops.count == 1)
    }

    @Test("stop on a Presenter that was never started still stops the Interactor once")
    func stopBeforeStartStopsOnce() {
        let rig = PresenterRig(state: connected)

        rig.presenter.stop()

        #expect(rig.interactor.inner.stops.count == 1)
    }

    @Test("stop ends the one state subscription the Presenter holds")
    func stopEndsTheSubscription() async {
        let rig = PresenterRig(state: connected)
        rig.presenter.start()
        await settle(rig.presenter.$devices) { !$0.isEmpty }
        #expect(rig.interactor.cancellations.count == 0)

        rig.presenter.stop()

        // Both happen inside stop(), on the main actor the test is running on: there is nothing to wait for.
        #expect(rig.interactor.cancellations.count == 1, "the subscription was cancelled")
    }

    // Releasing a Presenter releases the observation and the run it holds on the thread the test is running
    // on, so like `stop()` it has happened by the time the assignment returns.

    @Test("a started Presenter that is let go stops the Interactor once")
    func letGoWhileStartedStops() async {
        let interactor = SpyCameraSelectionInteractor(FakeCameraSelectionInteractor(state: connected))
        var presenter: CameraMenuPresenter? = await startedPresenter(over: interactor)
        weak let letGo = presenter
        #expect(interactor.inner.stops.count == 0)

        presenter = nil

        #expect(letGo == nil, "nothing else holds the Presenter, so the stop below is its release's")
        #expect(interactor.inner.stops.count == 1)
    }

    @Test("a stopped Presenter that is let go does not stop the Interactor again")
    func letGoAfterStopIsQuiet() async {
        let interactor = SpyCameraSelectionInteractor(FakeCameraSelectionInteractor(state: connected))
        var presenter: CameraMenuPresenter? = await startedPresenter(over: interactor)
        presenter?.stop()
        #expect(interactor.inner.stops.count == 1)

        presenter = nil

        #expect(interactor.inner.stops.count == 1)
    }
}

/// `CameraSelectionInteractor` as this suite sees it: the fake, with each `state` subscription counted once
/// it is cancelled, which is how a test proves that the Presenter let go of the publisher.
private final class SpyCameraSelectionInteractor: CameraSelectionInteractor, Sendable {
    let inner: FakeCameraSelectionInteractor
    /// One entry per `state` subscription that was cancelled.
    let cancellations = Collector<Void>()

    init(_ inner: FakeCameraSelectionInteractor) {
        self.inner = inner
    }

    var state: AnyPublisher<CameraState, Never> {
        let cancellations = cancellations
        return inner.state.handleEvents(receiveCancel: { cancellations.append(()) }).eraseToAnyPublisher()
    }

    func start() { inner.start() }
    func stop() { inner.stop() }
    func selectDevice(_ id: String) { inner.selectDevice(id) }
    func selectResolution(_ resolution: CameraResolution) { inner.selectResolution(resolution) }
    func selectFrameRate(_ framesPerSecond: Int) { inner.selectFrameRate(framesPerSecond) }
    func setMirrored(_ isMirrored: Bool) { inner.setMirrored(isMirrored) }
}

/// A Presenter over the spy, built inside `withDependencies` (the Presenter captures the dependencies of
/// the scope it is made in).
@MainActor
private struct PresenterRig {
    let interactor: SpyCameraSelectionInteractor
    let presenter: CameraMenuPresenter

    init(state: CameraState) {
        let interactor = SpyCameraSelectionInteractor(FakeCameraSelectionInteractor(state: state))
        self.interactor = interactor
        presenter = makePresenter(over: interactor)
    }
}

@MainActor
private func makePresenter(over interactor: SpyCameraSelectionInteractor) -> CameraMenuPresenter {
    withDependencies {
        $0.cameraSelectionInteractor = interactor
    } operation: {
        CameraMenuPresenter()
    }
}

/// A started Presenter whose first state, which must list at least one camera, has reached `devices`; the
/// caller holds the only reference, so a test lets go of it by dropping that one.
@MainActor
private func startedPresenter(over interactor: SpyCameraSelectionInteractor) async -> CameraMenuPresenter {
    let presenter = makePresenter(over: interactor)
    presenter.start()
    await settle(presenter.$devices) { !$0.isEmpty }
    return presenter
}
