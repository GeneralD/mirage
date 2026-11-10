import Domain
import Testing

@testable import Presenters

@Suite("CameraMenuText")
struct CameraMenuTextTests {
    private let text = CameraMenuText()
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
        selectedFrameRate: Int? = nil
    ) -> CameraState {
        CameraState(
            devices: devices,
            selectedDeviceID: selectedDeviceID,
            availability: availability,
            resolutions: resolutions,
            selectedResolution: selectedResolution,
            frameRates: frameRates,
            selectedFrameRate: selectedFrameRate,
            isMirrored: false)
    }

    @Test("the menu titles are Camera, Resolution, Frame Rate and Mirror")
    func titlesAreFixed() {
        #expect(text.title == "Camera")
        #expect(text.resolutionTitle == "Resolution")
        #expect(text.frameRateTitle == "Frame Rate")
        #expect(text.mirrorTitle == "Mirror")
    }

    @Test("the camera options keep the order of the devices and select only the camera in use")
    func cameraOptionsKeepOrderAndSelectTheCameraInUse() {
        let options = text.devices(of: state(devices: [usb, front], selectedDeviceID: "front"))

        #expect(
            options == [
                CameraMenuOption(id: "usb", title: "Logitech C920", isSelected: false),
                CameraMenuOption(id: "front", title: "FaceTime HD Camera", isSelected: true),
            ])
    }

    @Test("the resolution title reads 1280 × 720 and the id reads 1280x720, and only the chosen resolution is selected")
    func resolutionOptionsReadTheirSizeAndSelectOnlyTheChosenOne() {
        let options = text.resolutions(of: state(resolutions: [hd, fullHD], selectedResolution: fullHD))

        #expect(
            options == [
                CameraMenuOption(id: "1280x720", title: "1280 \u{00D7} 720", isSelected: false),
                CameraMenuOption(id: "1920x1080", title: "1920 \u{00D7} 1080", isSelected: true),
            ])
    }

    @Test("the frame rate title reads 30 fps and the id reads 30, and only the chosen rate is selected")
    func frameRateOptionsReadTheirRateAndSelectOnlyTheChosenOne() {
        let options = text.frameRates(of: state(frameRates: [30, 60], selectedFrameRate: 60))

        #expect(
            options == [
                CameraMenuOption(id: "30", title: "30 fps", isSelected: false),
                CameraMenuOption(id: "60", title: "60 fps", isSelected: true),
            ])
    }

    @Test("the status is nil while the camera is available")
    func statusIsNilWhileAvailable() {
        #expect(text.status(of: state(availability: .available)) == nil)
    }

    @Test("the status names the camera that is not connected")
    func statusNamesMissingCamera() {
        #expect(text.status(of: state(availability: .missing("Logitech C920"))) == "Logitech C920 is not connected")
    }

    @Test("the status reads No camera found when no camera is connected")
    func statusReadsNoCameraFound() {
        #expect(text.status(of: state(availability: .noCamera)) == "No camera found")
    }

    @Test("resolution(fromID:) reads 1920x1080 as 1920 by 1080")
    func resolutionReadsWellFormedID() {
        #expect(text.resolution(fromID: "1920x1080") == CameraResolution(width: 1920, height: 1080))
    }

    @Test(
        "resolution(fromID:) returns nil for an id that is not two whole sides of at least 1",
        arguments: ["abc", "1920", "0x720", "1920x", "1920x1080x1"])
    func resolutionRejectsMalformedID(_ id: String) {
        #expect(text.resolution(fromID: id) == nil)
    }

    @Test("frameRate(fromID:) reads 24 as 24 frames per second")
    func frameRateReadsWellFormedID() {
        #expect(text.frameRate(fromID: "24") == 24)
    }

    @Test("frameRate(fromID:) returns nil for an id that is not a whole number of at least 1", arguments: ["0", "-1", "x"])
    func frameRateRejectsMalformedID(_ id: String) {
        #expect(text.frameRate(fromID: id) == nil)
    }
}
