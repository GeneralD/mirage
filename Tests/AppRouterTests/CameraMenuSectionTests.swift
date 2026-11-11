import Dependencies
import Domain
import Presenters
import TestDoubles
import TestSupport
import Testing

@testable import Views

/// The camera menu's section (#168). `Views` holds no logic and is not measured for coverage, so these tests only build the body
/// over a real Presenter, one case per row or line the Interface names. What the menu looks like is the gallery's camera screen (#169).
@MainActor
@Suite("CameraMenuSection", .timeLimit(.minutes(1)))
struct CameraMenuSectionTests {
    private let front = CameraDevice(id: "front", name: "FaceTime HD Camera")
    private let usb = CameraDevice(id: "usb", name: "Logitech C920")
    private let hd = CameraResolution(width: 1280, height: 720)
    private let fullHD = CameraResolution(width: 1920, height: 1080)

    @Test("the section builds over a started Presenter with a row for each camera, resolution and frame rate, and the mirror toggle")
    func buildsOverEveryRow() async {
        let presenter = makePresenter(
            showing: CameraState(
                devices: [front, usb], selectedDeviceID: "usb", availability: .available,
                resolutions: [hd, fullHD], selectedResolution: fullHD,
                frameRates: [30, 60], selectedFrameRate: 60, isMirrored: true))
        presenter.start()
        await settle(presenter.$devices) { !$0.isEmpty }

        #expect(presenter.devices.count == 2)
        #expect(presenter.resolutions.count == 2)
        #expect(presenter.frameRates.count == 2)
        #expect(presenter.isMirrored)
        _ = CameraMenuSection(presenter: presenter).body
    }

    @Test("the section builds with the status line above the cameras when the chosen camera is not connected")
    func buildsWithTheStatusLine() async {
        let presenter = makePresenter(
            showing: CameraState(
                devices: [front], selectedDeviceID: "front", availability: .missing("Logitech C920"),
                resolutions: [], selectedResolution: nil, frameRates: [], selectedFrameRate: nil, isMirrored: false))
        presenter.start()
        await settle(presenter.$status) { $0 != nil }

        #expect(presenter.status == "Logitech C920 is not connected")
        #expect(presenter.devices.count == 1)
        _ = CameraMenuSection(presenter: presenter).body
    }

    @Test("the section builds with no camera at all, where the candidate submenus are empty and status says No camera found")
    func buildsWithNoCamera() async {
        let presenter = makePresenter(showing: .empty)
        presenter.start()
        await settle(presenter.$status) { $0 != nil }

        #expect(presenter.status == "No camera found")
        #expect(presenter.resolutions.isEmpty)
        #expect(presenter.frameRates.isEmpty)
        _ = CameraMenuSection(presenter: presenter).body
    }

    @Test("the section builds before any state arrives, with no rows and no status line")
    func buildsBeforeAnyState() {
        let presenter = makePresenter(showing: .empty)

        #expect(presenter.devices.isEmpty)
        #expect(presenter.status == nil)
        _ = CameraMenuSection(presenter: presenter).body
    }
}

/// A Presenter over a `FakeCameraSelectionInteractor` that shows `state`, built inside `withDependencies` so that it never
/// reaches the live Interactor.
@MainActor
private func makePresenter(showing state: CameraState) -> CameraMenuPresenter {
    withDependencies {
        $0.cameraSelectionInteractor = FakeCameraSelectionInteractor(state: state)
    } operation: {
        CameraMenuPresenter()
    }
}
