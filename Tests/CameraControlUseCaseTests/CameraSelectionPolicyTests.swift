import Domain
import Testing

@testable import CameraControlUseCase

@Suite("CameraSelectionPolicy", .timeLimit(.minutes(1)))
struct CameraSelectionPolicyTests {
    private let policy = CameraSelectionPolicy()

    private func device(_ id: String, name: String? = nil, isSystemDefault: Bool = false) -> CameraDevice {
        CameraDevice(id: id, name: name ?? id, isSystemDefault: isSystemDefault)
    }

    private func format(_ index: Int, _ width: Int, _ height: Int, fps: ClosedRange<Int> = 1...60) -> CameraFormat {
        CameraFormat(
            index: index,
            width: width,
            height: height,
            minFramesPerSecond: fps.lowerBound,
            maxFramesPerSecond: fps.upperBound)
    }

    private func resolution(_ width: Int, _ height: Int) -> CameraResolution {
        CameraResolution(width: width, height: height)
    }

    private func selection(
        deviceID: String? = nil,
        deviceName: String? = nil,
        resolution: CameraResolution? = nil,
        framesPerSecond: Int? = nil,
        isMirrored: Bool = false
    ) -> CameraSelection {
        CameraSelection(
            deviceID: deviceID,
            deviceName: deviceName,
            resolution: resolution,
            framesPerSecond: framesPerSecond,
            isMirrored: isMirrored)
    }

    // MARK: device

    @Test("a remembered camera that is connected is used even when it is neither first nor the system default")
    func rememberedCameraWinsWhenConnected() {
        let devices = [device("front", isSystemDefault: true), device("usb"), device("capture")]
        #expect(policy.device(among: devices, selection: selection(deviceID: "capture"))?.id == "capture")
    }

    @Test("with no remembered camera, the system default camera is used")
    func systemDefaultCameraIsUsedWhenNothingIsRemembered() {
        let devices = [device("usb"), device("front", isSystemDefault: true)]
        #expect(policy.device(among: devices, selection: selection())?.id == "front")
    }

    @Test("a remembered camera that is unplugged falls back to the system default camera")
    func unpluggedRememberedCameraFallsBackToSystemDefault() {
        let devices = [device("usb"), device("front", isSystemDefault: true)]
        #expect(policy.device(among: devices, selection: selection(deviceID: "capture"))?.id == "front")
    }

    @Test("with no system default camera, the first camera is used, whether or not a camera was remembered")
    func firstCameraIsUsedWithoutSystemDefault() {
        let devices = [device("usb"), device("capture")]
        #expect(policy.device(among: devices, selection: selection())?.id == "usb")
        #expect(policy.device(among: devices, selection: selection(deviceID: "gone"))?.id == "usb")
    }

    @Test("the device is nil when no camera is connected")
    func deviceIsNilWithoutCamera() {
        #expect(policy.device(among: [], selection: selection(deviceID: "usb")) == nil)
    }

    // MARK: availability

    @Test("availability is noCamera when no camera is connected, even if a camera was remembered")
    func availabilityIsNoCameraWithoutCamera() {
        let state = policy.state(
            devices: [],
            formats: [format(0, 1280, 720)],
            selection: selection(deviceID: "usb", deviceName: "USB Camera"))
        #expect(state.availability == .noCamera)
    }

    @Test("availability is available when no camera is remembered")
    func availabilityIsAvailableWhenNothingIsRemembered() {
        let state = policy.state(devices: [device("front", isSystemDefault: true)], formats: [], selection: selection())
        #expect(state.availability == .available)
    }

    @Test("availability is available when the remembered camera is connected")
    func availabilityIsAvailableWhenRememberedCameraIsConnected() {
        let state = policy.state(
            devices: [device("front"), device("usb")],
            formats: [],
            selection: selection(deviceID: "usb", deviceName: "USB Camera"))
        #expect(state.availability == .available)
    }

    @Test("availability is missing with the remembered name when the remembered camera is unplugged")
    func availabilityIsMissingWithRememberedName() {
        let state = policy.state(
            devices: [device("front", isSystemDefault: true)],
            formats: [],
            selection: selection(deviceID: "usb", deviceName: "USB Camera"))
        #expect(state.availability == .missing("USB Camera"))
        #expect(state.selectedDeviceID == "front")
    }

    @Test("availability is missing with the remembered ID when no name was remembered")
    func availabilityIsMissingWithRememberedIDWithoutName() {
        let state = policy.state(devices: [device("front")], formats: [], selection: selection(deviceID: "usb"))
        #expect(state.availability == .missing("usb"))
    }

    // MARK: state

    @Test("with no camera connected, no resolutions, frame rates or selections are offered, and mirroring is kept")
    func noCameraOffersNothing() {
        let state = policy.state(
            devices: [],
            formats: [format(0, 1280, 720)],
            selection: selection(resolution: resolution(1280, 720), framesPerSecond: 30, isMirrored: true))
        #expect(
            state
                == CameraState(
                    devices: [],
                    selectedDeviceID: nil,
                    availability: .noCamera,
                    resolutions: [],
                    selectedResolution: nil,
                    frameRates: [],
                    selectedFrameRate: nil,
                    isMirrored: true))
    }

    @Test("the remembered resolution is used when the camera offers it")
    func rememberedResolutionIsUsedWhenOffered() {
        let formats = [format(0, 1280, 720), format(1, 1600, 900), format(2, 1920, 1080)]
        let state = policy.state(
            devices: [device("front")],
            formats: formats,
            selection: selection(resolution: resolution(1920, 1080)))
        #expect(state.resolutions == [resolution(1280, 720), resolution(1600, 900), resolution(1920, 1080)])
        #expect(state.selectedResolution == resolution(1920, 1080))
    }

    @Test("without a remembered resolution, 1280x720 is used when the camera offers it")
    func presetResolutionIsUsedWhenNothingIsRemembered() {
        let formats = [format(0, 1600, 900), format(1, 1280, 720), format(2, 1920, 1080)]
        let state = policy.state(devices: [device("front")], formats: formats, selection: selection())
        #expect(state.selectedResolution == resolution(1280, 720))
    }

    @Test("a remembered resolution the camera does not offer falls back to 1280x720")
    func unofferedRememberedResolutionFallsBackToPreset() {
        let formats = [format(0, 1280, 720), format(1, 1920, 1080)]
        let state = policy.state(
            devices: [device("front")],
            formats: formats,
            selection: selection(resolution: resolution(640, 480)))
        #expect(state.selectedResolution == resolution(1280, 720))
    }

    @Test("without 1280x720, the smallest offered resolution is used")
    func smallestResolutionIsUsedWithoutPreset() {
        let formats = [format(0, 1920, 1080), format(1, 1600, 900), format(2, 2560, 1440)]
        let state = policy.state(
            devices: [device("front")],
            formats: formats,
            selection: selection(resolution: resolution(2560, 1440)))
        #expect(state.selectedResolution == resolution(1600, 900))
    }

    @Test("the remembered frame rate is used when the resolution offers it")
    func rememberedFrameRateIsUsedWhenOffered() {
        let state = policy.state(
            devices: [device("front")],
            formats: [format(0, 1280, 720)],
            selection: selection(framesPerSecond: 15))
        #expect(state.frameRates == [15, 24, 30])
        #expect(state.selectedFrameRate == 15)
    }

    @Test("without a remembered frame rate, 30 is used when the resolution offers it")
    func thirtyIsUsedWhenNothingIsRemembered() {
        let state = policy.state(devices: [device("front")], formats: [format(0, 1280, 720)], selection: selection())
        #expect(state.selectedFrameRate == 30)
    }

    @Test("a remembered frame rate the resolution does not offer falls back to 30")
    func unofferedRememberedFrameRateFallsBackToThirty() {
        let state = policy.state(
            devices: [device("front")],
            formats: [format(0, 1280, 720)],
            selection: selection(framesPerSecond: 20))
        #expect(state.selectedFrameRate == 30)
    }

    @Test("without 30, the highest offered frame rate is used")
    func highestFrameRateIsUsedWithoutThirty() {
        let state = policy.state(
            devices: [device("front")],
            formats: [format(0, 1280, 720, fps: 15...24)],
            selection: selection(framesPerSecond: 30))
        #expect(state.frameRates == [15, 24])
        #expect(state.selectedFrameRate == 24)
    }

    @Test("changing the resolution changes the frame rates offered, so a remembered 30 can become 24")
    func frameRateCandidatesFollowResolution() {
        let formats = [format(0, 1280, 720, fps: 1...30), format(1, 1920, 1080, fps: 1...24)]
        let at1080 = policy.state(
            devices: [device("front")],
            formats: formats,
            selection: selection(resolution: resolution(1920, 1080), framesPerSecond: 30))
        #expect(at1080.frameRates == [15, 24])
        #expect(at1080.selectedFrameRate == 24)

        let at720 = policy.state(
            devices: [device("front")],
            formats: formats,
            selection: selection(resolution: resolution(1280, 720), framesPerSecond: 30))
        #expect(at720.frameRates == [15, 24, 30])
        #expect(at720.selectedFrameRate == 30)
    }

    @Test("isMirrored is the remembered value, whatever the camera offers")
    func isMirroredIsRememberedValue() {
        let formats = [format(0, 1280, 720)]
        let mirrored = policy.state(devices: [device("front")], formats: formats, selection: selection(isMirrored: true))
        let plain = policy.state(devices: [device("front")], formats: formats, selection: selection(isMirrored: false))
        #expect(mirrored.isMirrored)
        #expect(!plain.isMirrored)
    }

    // MARK: capture

    @Test("a capture carries the chosen camera and the format with the lowest index that supports the chosen frame rate")
    func captureCarriesLowestIndexFormat() {
        let formats = [
            format(5, 1280, 720, fps: 1...30),
            format(4, 1280, 720, fps: 15...24),  // lower index, but it does not support 30
            format(2, 1280, 720, fps: 20...30),
            format(0, 1920, 1080, fps: 1...30),  // another resolution
        ]
        let capture = policy.capture(
            devices: [device("front"), device("usb")],
            formats: formats,
            selection: selection(deviceID: "usb", resolution: resolution(1280, 720), framesPerSecond: 30))
        #expect(capture == CameraCapture(deviceID: "usb", format: CameraFormatChoice(index: 2, framesPerSecond: 30)))
    }

    @Test("a capture with no remembered camera uses the system default camera at 1280x720 and 30 fps")
    func captureUsesSystemDefaultCameraAtPreset() {
        let capture = policy.capture(
            devices: [device("usb"), device("front", isSystemDefault: true)],
            formats: [format(0, 1280, 720, fps: 1...60)],
            selection: selection())
        #expect(capture == CameraCapture(deviceID: "front", format: CameraFormatChoice(index: 0, framesPerSecond: 30)))
    }

    @Test("a capture uses the fallback camera while the remembered camera is unplugged")
    func captureUsesFallbackCameraWhenRememberedIsUnplugged() {
        let capture = policy.capture(
            devices: [device("front", isSystemDefault: true)],
            formats: [format(0, 1280, 720, fps: 1...30)],
            selection: selection(deviceID: "usb"))
        #expect(capture?.deviceID == "front")
    }

    @Test("a capture is nil when no camera is connected")
    func captureIsNilWithoutCamera() {
        #expect(policy.capture(devices: [], formats: [format(0, 1280, 720)], selection: selection()) == nil)
    }

    @Test("a camera with no offered resolution is captured by its ID with no format")
    func captureWithoutOfferableResolutionHasNoFormat() {
        let capture = policy.capture(
            devices: [device("usb")],
            formats: [format(0, 640, 480)],
            selection: selection(resolution: resolution(640, 480), framesPerSecond: 30))
        #expect(capture == CameraCapture(deviceID: "usb", format: nil))
    }

    @Test("a camera whose formats offer no frame rate of 15, 24 or 30 is captured by its ID with no format")
    func captureWithoutOfferableFrameRateHasNoFormat() {
        let capture = policy.capture(
            devices: [device("usb")],
            formats: [format(0, 1280, 720, fps: 60...60)],
            selection: selection())
        #expect(capture == CameraCapture(deviceID: "usb", format: nil))
    }
}
