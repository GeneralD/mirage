import AppKit
import Dependencies
import Domain
import Presenters
import SwiftUI
import Views

extension GalleryScreen {
    /// The camera menu with two cameras, the first in use, its resolution and frame rate chosen, and the picture not mirrored.
    static var cameraMenu: GalleryScreen {
        GalleryScreen(name: "camera-menu", summary: "Camera menu: two cameras, 1280 × 720 at 30 fps, mirror off") {
            openCameraMenu(showing: cameraMenuState)
        }
    }

    /// The chosen camera is not connected: the status line says so, the other camera is the one in use, and the picture is mirrored.
    static var cameraMenuMissing: GalleryScreen {
        GalleryScreen(name: "camera-menu-missing", summary: "Camera menu: the chosen camera is gone") {
            openCameraMenu(showing: cameraMenuMissingState)
        }
    }

    /// The chosen camera is suspended (a laptop's lid is closed): the status line says so, and a running camera is the one in use.
    static var cameraMenuSuspended: GalleryScreen {
        GalleryScreen(name: "camera-menu-suspended", summary: "Camera menu: the chosen camera is suspended") {
            openCameraMenu(showing: cameraMenuSuspendedState)
        }
    }

    /// No camera is connected at all: the status line says so, and the resolution and frame rate submenus are disabled.
    static var cameraMenuNone: GalleryScreen {
        GalleryScreen(name: "camera-menu-none", summary: "Camera menu: no camera found") {
            openCameraMenu(showing: cameraMenuNoneState)
        }
    }
}

/// The window that holds the camera menu's contents. The menu has no window of its own in the app, so the gallery gives it one.
/// `makeWindow` in `openCameraMenu` is the seam a test uses to open no real window.
@MainActor
protocol CameraMenuWindow: AnyObject {
    /// Centers the window and brings it to the front.
    func show()
}

/// Builds a `CameraMenuPresenter` that reads `state`, starts it, shows the window `makeWindow` makes over it once, and returns that
/// window, which keeps the Presenter alive. The Presenter is made inside `withDependencies` because it captures the dependencies of the
/// scope it is built in.
@MainActor
func openCameraMenu(
    showing state: CameraState,
    makeWindow: @escaping @MainActor (CameraMenuPresenter) -> any CameraMenuWindow = { GalleryCameraMenuWindow(presenter: $0) }
) -> AnyObject {
    let presenter = withDependencies {
        $0.cameraSelectionInteractor = GalleryCameraInteractor(selection: state)
    } operation: {
        CameraMenuPresenter()
    }
    presenter.start()
    let window = makeWindow(presenter)
    window.show()
    return window
}

/// The gallery's window for the camera menu: an `NSWindow` titled `Camera` that hosts `CameraMenuSection` in a column of fixed width.
/// It holds the Presenter, so closing the window's owner ends the Presenter's observation.
@MainActor
final class GalleryCameraMenuWindow {
    private let columnWidth: CGFloat = 280
    private let margin: CGFloat = 16
    private let presenter: CameraMenuPresenter
    private let window: NSWindow

    init(presenter: CameraMenuPresenter) {
        self.presenter = presenter
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true)
        window.title = "Camera"
        window.isReleasedWhenClosed = false
        let hostingView = NSHostingView(
            rootView: VStack(alignment: .leading, spacing: 8) {
                CameraMenuSection(presenter: presenter)
            }
            .padding(margin)
            .frame(width: columnWidth))
        window.contentView = hostingView
        window.setContentSize(hostingView.fittingSize)
    }

    /// The window's title, which a test reads.
    var windowTitle: String { window.title }

    /// Whether the window is on screen, which a test reads: a window that is only made is not.
    var isVisible: Bool { window.isVisible }
}

extension GalleryCameraMenuWindow: CameraMenuWindow {
    func show() {
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}

private let faceTimeCamera = CameraDevice(id: "face-time", name: "FaceTime HD Camera")
private let studioCamera = CameraDevice(id: "studio", name: "Studio Display Camera")
private let closedLidCamera = CameraDevice(id: "face-time", name: "FaceTime HD Camera", isSuspended: true)
private let continuityCamera = CameraDevice(id: "phone", name: "iPhone Camera")
private let hd720 = CameraResolution(width: 1280, height: 720)
private let hd900 = CameraResolution(width: 1600, height: 900)
private let fullHD = CameraResolution(width: 1920, height: 1080)

/// Two cameras with the first in use, 1280 × 720 at 30 fps, and the picture not mirrored.
var cameraMenuState: CameraState {
    CameraState(
        devices: [faceTimeCamera, studioCamera],
        selectedDeviceID: "face-time",
        availability: .available,
        resolutions: [hd720, hd900, fullHD],
        selectedResolution: hd720,
        frameRates: [15, 24, 30],
        selectedFrameRate: 30,
        isMirrored: false)
}

/// The chosen camera, FaceTime HD Camera, is not connected: the other camera is chosen, and the picture is mirrored.
var cameraMenuMissingState: CameraState {
    CameraState(
        devices: [studioCamera],
        selectedDeviceID: "studio",
        availability: .missing("FaceTime HD Camera"),
        resolutions: [hd720, fullHD],
        selectedResolution: hd720,
        frameRates: [24, 30],
        selectedFrameRate: 30,
        isMirrored: true)
}

/// The chosen camera, FaceTime HD Camera, is suspended with the lid closed: the running iPhone Camera is chosen instead.
var cameraMenuSuspendedState: CameraState {
    CameraState(
        devices: [closedLidCamera, continuityCamera],
        selectedDeviceID: "phone",
        availability: .suspended("FaceTime HD Camera"),
        resolutions: [hd720, fullHD],
        selectedResolution: hd720,
        frameRates: [24, 30],
        selectedFrameRate: 30,
        isMirrored: false)
}

/// No camera is connected at all.
var cameraMenuNoneState: CameraState {
    .empty
}
