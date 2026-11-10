import CameraInteractor
import Combine
import Dependencies
import Domain
import TestDoubles
import TestSupport
import Testing

@Suite("CameraSelectionInteractorImpl", .timeLimit(.minutes(1)))
struct CameraSelectionInteractorTests {
    private let hd = CameraResolution(width: 1920, height: 1080)
    private let front = cameraState(device: "front")
    private let usb = cameraState(device: "usb")
    private let capture = cameraState(device: "capture")
    private let obs = cameraState(device: "obs")
    private let mirroredObs = cameraState(device: "obs", isMirrored: true)

    // MARK: - start / state

    @Test("nothing is published and the UseCase is not called before start()")
    func nothingBeforeStart() {
        let rig = Rig(state: front)

        #expect(rig.seen.count == 0)
        #expect(rig.useCase.calls.count == 0)
        #expect(rig.useCase.streamsOpened.count == 0)
    }

    @Test("start() publishes first the state that refresh() reads")
    func startPublishesRefreshFirst() async {
        let rig = Rig(state: front)

        rig.subject.start()
        await rig.seen.waitForCount(1)

        #expect(rig.seen.values == [front])
        #expect(rig.useCase.calls.values == [.refresh])
    }

    @Test("a signal from the attached cameras rereads the state and publishes what it now reads")
    func signalRereadsTheState() async {
        let rig = Rig(state: front)
        rig.subject.start()
        await rig.seen.waitForCount(1)

        let unplugged = cameraState(device: "usb", availability: .missing("USB Camera"))
        rig.useCase.setState(unplugged)
        rig.useCase.emitChange()
        await rig.seen.waitForCount(2)

        #expect(rig.seen.values == [front, unplugged])
    }

    @Test("a change that arrives while refresh() is running is kept, and read again")
    func changeDuringRefreshIsKept() async {
        let rig = Rig(state: front)
        let useCase = rig.useCase
        useCase.whileRefreshing { useCase.emitChange() }

        rig.subject.start()
        await rig.useCase.calls.waitForCount(2)
        rig.subject.setMirrored(true)
        await rig.useCase.calls.waitForCount(3)

        #expect(rig.useCase.calls.values == [.refresh, .refresh, .setMirrored(true)])
    }

    @Test("a second start() ends the first watch, so one watch stays alive and each signal refreshes once")
    func secondStartKeepsOneWatch() async {
        let rig = Rig(state: front)

        rig.subject.start()
        rig.subject.start()
        await rig.useCase.streamsOpened.waitForCount(2)
        await rig.useCase.streamsClosed.waitForCount(1)
        rig.useCase.emitChange()
        await rig.useCase.calls.waitForCount(3)
        rig.subject.setMirrored(true)
        await rig.useCase.calls.waitForCount(4)

        #expect(rig.useCase.calls.values == [.refresh, .refresh, .refresh, .setMirrored(true)])
    }

    @Test("a signal after stop() publishes nothing, and only the next start() refreshes")
    func signalAfterStopPublishesNothing() async {
        let rig = Rig(state: front)

        rig.subject.start()
        await rig.useCase.calls.waitForCount(1)
        rig.subject.stop()
        await rig.useCase.streamsClosed.waitForCount(1)
        rig.useCase.emitChange()
        rig.subject.start()
        await rig.useCase.calls.waitForCount(2)
        rig.subject.setMirrored(true)
        await rig.useCase.calls.waitForCount(3)

        #expect(rig.useCase.calls.values == [.refresh, .refresh, .setMirrored(true)])
        await rig.seen.waitForCount(3)
        #expect(rig.seen.count == 3, "one state per start() and one for the mirror command, none from the signal after stop()")
    }

    // MARK: - commands

    @Test("selections made before start() or after stop() never reach the UseCase")
    func commandsOutsideTheWatchAreDropped() async {
        let rig = Rig(state: front)

        rig.subject.selectDevice("usb")
        rig.subject.setMirrored(true)
        rig.subject.start()
        await rig.useCase.calls.waitForCount(1)
        #expect(rig.useCase.calls.values == [.refresh], "the two commands made before start() were dropped")

        rig.subject.stop()
        await rig.useCase.streamsClosed.waitForCount(1)
        rig.subject.selectResolution(hd)
        rig.subject.selectFrameRate(30)
        rig.subject.start()
        await rig.useCase.calls.waitForCount(2)

        #expect(rig.useCase.calls.values == [.refresh, .refresh], "the two commands made after stop() were dropped")
    }

    @Test("the four selections reach the UseCase in call order, and each returned state is published in that order")
    func selectionsKeepCallOrder() async {
        let rig = Rig(state: front)

        rig.subject.start()
        await rig.seen.waitForCount(1)

        rig.useCase.setState(usb)
        rig.subject.selectDevice("usb")
        await rig.seen.waitForCount(2)

        rig.useCase.setState(capture)
        rig.subject.selectResolution(hd)
        await rig.seen.waitForCount(3)

        rig.useCase.setState(obs)
        rig.subject.selectFrameRate(30)
        await rig.seen.waitForCount(4)

        rig.useCase.setState(mirroredObs)
        rig.subject.setMirrored(true)
        await rig.seen.waitForCount(5)

        #expect(rig.seen.values == [front, usb, capture, obs, mirroredObs])
        #expect(
            rig.useCase.calls.values == [
                .refresh, .selectDevice("usb"), .selectResolution(hd), .selectFrameRate(30), .setMirrored(true),
            ])
    }
}

/// The camera state with the given selected device; the rest is the empty state's shape.
private func cameraState(
    device: String? = nil,
    availability: CameraAvailability = .available,
    isMirrored: Bool = false
) -> CameraState {
    CameraState(
        devices: device.map { [CameraDevice(id: $0, name: $0, isSystemDefault: false)] } ?? [],
        selectedDeviceID: device,
        availability: availability,
        resolutions: [],
        selectedResolution: nil,
        frameRates: [],
        selectedFrameRate: nil,
        isMirrored: isMirrored
    )
}

/// An Interactor over a `FakeCameraSelectionUseCase`, subscribed before any `start()`. The subject captures the
/// dependencies of the scope it is made in, so it is built inside `withDependencies`.
private struct Rig {
    let useCase: FakeCameraSelectionUseCase
    let subject: CameraSelectionInteractorImpl
    let seen: Collector<CameraState>
    let subscription: AnyCancellable

    init(state: CameraState) {
        let useCase = FakeCameraSelectionUseCase(state: state)
        let subject = withDependencies {
            $0.cameraSelectionUseCase = useCase
        } operation: {
            CameraSelectionInteractorImpl()
        }
        let seen = Collector<CameraState>()
        self.useCase = useCase
        self.subject = subject
        self.seen = seen
        self.subscription = subject.state.sink { seen.append($0) }
    }
}
