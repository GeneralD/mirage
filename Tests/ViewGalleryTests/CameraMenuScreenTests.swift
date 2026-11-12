import Combine
import Dependencies
import Domain
import Presenters
import TestSupport
import Testing

@testable import ViewGallery

/// A camera menu window that is never on screen: it counts what the screen asks of it and keeps the Presenter it was given.
@MainActor
private final class FakeCameraMenuWindow {
    let presenter: CameraMenuPresenter
    private(set) var shows = 0

    init(presenter: CameraMenuPresenter) {
        self.presenter = presenter
    }
}

extension FakeCameraMenuWindow: CameraMenuWindow {
    func show() {
        shows += 1
    }
}

@MainActor
@Suite("Camera menu screens", .timeLimit(.minutes(1)))
struct CameraMenuScreenTests {
    /// The Presenter the window would draw, started over `state`; its dependency is assigned, never resolved.
    private func startedPresenter(showing state: CameraState) -> CameraMenuPresenter {
        let presenter = withDependencies {
            $0.cameraSelectionInteractor = GalleryCameraInteractor(selection: state)
        } operation: {
            CameraMenuPresenter()
        }
        presenter.start()
        return presenter
    }

    /// Opens a screen's window over `state` through the test seam, and returns the fake window that was shown.
    private func openedWindow(showing state: CameraState) throws -> FakeCameraMenuWindow {
        let windows = Collector<FakeCameraMenuWindow>()
        _ = openCameraMenu(showing: state) { presenter in
            let window = FakeCameraMenuWindow(presenter: presenter)
            windows.append(window)
            return window
        }
        return try #require(windows.values.first)
    }

    @Test("the three camera menu screens are registered under their names")
    func registered() {
        let names = galleryScreens.map(\.name)
        #expect(names.contains("camera-menu"))
        #expect(names.contains("camera-menu-missing"))
        #expect(names.contains("camera-menu-none"))
    }

    @Test("opening camera-menu makes one window, shows it once, and its Presenter lists the cameras with the first chosen")
    func cameraMenu() async throws {
        let windows = Collector<FakeCameraMenuWindow>()
        _ = openCameraMenu(showing: cameraMenuState) { presenter in
            let window = FakeCameraMenuWindow(presenter: presenter)
            windows.append(window)
            return window
        }
        let window = try #require(windows.values.first)
        #expect(windows.count == 1)
        #expect(window.shows == 1)

        let presenter = window.presenter
        await settle(presenter.$devices) { !$0.isEmpty }
        #expect(presenter.devices.map(\.title) == ["FaceTime HD Camera", "Studio Display Camera"])
        #expect(presenter.devices.map(\.isSelected) == [true, false])
        #expect(presenter.resolutions.map(\.title) == ["1280 × 720", "1600 × 900", "1920 × 1080"])
        #expect(presenter.resolutions.map(\.isSelected) == [true, false, false])
        #expect(presenter.frameRates.map(\.title) == ["15 fps", "24 fps", "30 fps"])
        #expect(presenter.frameRates.map(\.isSelected) == [false, false, true])
        #expect(presenter.isMirrored == false)
        #expect(presenter.status == nil)
    }

    @Test("camera-menu-missing's Presenter says the chosen camera is not connected, and shows the other camera chosen and mirrored")
    func cameraMenuMissing() async throws {
        let window = try openedWindow(showing: cameraMenuMissingState)
        #expect(window.shows == 1)

        let presenter = window.presenter
        await settle(presenter.$devices) { !$0.isEmpty }
        #expect(presenter.status == "FaceTime HD Camera is not connected")
        #expect(presenter.devices.map(\.title) == ["Studio Display Camera"])
        #expect(presenter.devices.map(\.isSelected) == [true])
        #expect(presenter.resolutions.map(\.title) == ["1280 × 720", "1920 × 1080"])
        #expect(presenter.frameRates.map(\.title) == ["24 fps", "30 fps"])
        #expect(presenter.isMirrored == true)
    }

    @Test("camera-menu-none's Presenter says no camera was found, and lists nothing to choose")
    func cameraMenuNone() async throws {
        let window = try openedWindow(showing: cameraMenuNoneState)
        #expect(window.shows == 1)

        let presenter = window.presenter
        await settle(presenter.$status) { $0 != nil }
        #expect(presenter.status == "No camera found")
        #expect(presenter.devices.isEmpty)
        #expect(presenter.resolutions.isEmpty)
        #expect(presenter.frameRates.isEmpty)
        #expect(presenter.isMirrored == false)
    }

    @Test("a camera menu window that is only made is not on screen, and is titled Camera")
    func windowIsHiddenUntilShown() {
        let window = GalleryCameraMenuWindow(presenter: startedPresenter(showing: cameraMenuState))

        #expect(window.isVisible == false)
        #expect(window.windowTitle == "Camera")
    }
}
