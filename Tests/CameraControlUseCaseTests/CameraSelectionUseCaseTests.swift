import CameraControlUseCase
import Dependencies
import Domain
import TestDoubles
import Testing

@Suite("CameraSelectionUseCase", .timeLimit(.minutes(1)))
struct CameraSelectionUseCaseTests {
    private let m0 = CameraResolution(width: 1280, height: 720)

    private func makeSubject(_ repository: FakeCameraSelectionRepository, log: RecordingLog = RecordingLog()) -> CameraSelectionUseCaseImpl {
        withDependencies {
            $0.cameraSelectionRepository = repository
            $0.developerLog = log
        } operation: {
            CameraSelectionUseCaseImpl()
        }
    }

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

    private func awaitFirstSignal(_ stream: AsyncStream<Void>) async -> Bool {
        for await _ in stream { return true }
        return false
    }

    @Test("with nothing remembered, the system default camera is used at 1280x720 and 30 fps, with the index of that size")
    func systemDefaultCameraIsUsedAtPreset() {
        let repository = FakeCameraSelectionRepository(
            devices: [device("usb"), device("front", isSystemDefault: true)],
            formats: ["front": [format(0, 1920, 1080), format(1, 1280, 720)]]
        )
        let state = makeSubject(repository).refresh()
        #expect(
            repository.applied.values
                == [CameraCapture(deviceID: "front", format: CameraFormatChoice(index: 1, framesPerSecond: 30))])
        #expect(state.selectedDeviceID == "front")
        #expect(state.selectedResolution == m0)
        #expect(state.selectedFrameRate == 30)
    }

    @Test("a remembered camera that is connected is the only one whose formats are read, and it is applied")
    func rememberedConnectedCameraIsUsed() {
        let repository = FakeCameraSelectionRepository(
            devices: [device("front", isSystemDefault: true), device("usb")],
            formats: ["front": [format(0, 1280, 720)], "usb": [format(0, 1280, 720)]],
            selection: selection(deviceID: "usb", deviceName: "USB Cam")
        )
        let log = RecordingLog()
        let state = makeSubject(repository, log: log).refresh()
        #expect(repository.formatRequests.values == ["usb"])
        #expect(
            repository.applied.values
                == [CameraCapture(deviceID: "usb", format: CameraFormatChoice(index: 0, framesPerSecond: 30))])
        #expect(state.availability == .available)
        #expect(state.selectedDeviceID == "usb")
        #expect(log.messages(in: .camera).isEmpty, "a connected remembered camera logs nothing")
    }

    @Test("a remembered resolution and frame rate that the camera offers are the ones applied")
    func rememberedChoiceIsApplied() {
        let repository = FakeCameraSelectionRepository(
            devices: [device("usb")],
            formats: ["usb": [format(0, 1280, 720), format(1, 1920, 1080, fps: 1...24)]],
            selection: selection(
                deviceID: "usb",
                deviceName: "USB Cam",
                resolution: CameraResolution(width: 1920, height: 1080),
                framesPerSecond: 24)
        )
        let state = makeSubject(repository).refresh()
        #expect(
            repository.applied.values
                == [CameraCapture(deviceID: "usb", format: CameraFormatChoice(index: 1, framesPerSecond: 24))])
        #expect(state.selectedResolution == CameraResolution(width: 1920, height: 1080))
        #expect(state.selectedFrameRate == 24)
    }

    @Test("a remembered camera that is unplugged is reported as missing by its stored name, and the system default is used")
    func unpluggedCameraFallsBackToDefault() {
        let repository = FakeCameraSelectionRepository(
            devices: [device("usb"), device("front", isSystemDefault: true)],
            formats: ["front": [format(0, 1280, 720)]],
            selection: selection(deviceID: "capture", deviceName: "Capture Card")
        )
        let log = RecordingLog()
        let state = makeSubject(repository, log: log).refresh()
        #expect(state.availability == .missing("Capture Card"))
        #expect(state.selectedDeviceID == "front")
        #expect(
            repository.applied.values
                == [CameraCapture(deviceID: "front", format: CameraFormatChoice(index: 0, framesPerSecond: 30))])
        #expect(log.messages(in: .camera) == ["camera not connected: Capture Card"])
    }

    @Test("with no system default camera, an unplugged remembered camera falls back to the first camera")
    func unpluggedCameraFallsBackToFirst() {
        let repository = FakeCameraSelectionRepository(
            devices: [device("usb"), device("capture")],
            formats: ["usb": [format(0, 1280, 720)]],
            selection: selection(deviceID: "gone", deviceName: "Old Cam")
        )
        let state = makeSubject(repository).refresh()
        #expect(state.availability == .missing("Old Cam"))
        #expect(
            repository.applied.values
                == [CameraCapture(deviceID: "usb", format: CameraFormatChoice(index: 0, framesPerSecond: 30))])
    }

    @Test("with no camera at all, the state is noCamera, nothing is applied or read, and mirroring follows the stored value")
    func noCameraAppliesNothing() {
        let repository = FakeCameraSelectionRepository(selection: selection(isMirrored: true))
        let log = RecordingLog()
        let state = makeSubject(repository, log: log).refresh()
        #expect(state.availability == .noCamera)
        #expect(state.isMirrored)
        #expect(repository.applied.count == 0)
        #expect(repository.formatRequests.count == 0)
        #expect(repository.mirrors.values == [true])
        #expect(log.messages(in: .camera) == ["no camera found"])
    }

    @Test("the stored mirror setting is shown in the state and set on the camera source", arguments: [true, false])
    func mirrorSettingIsShownAndSet(isMirrored: Bool) {
        let repository = FakeCameraSelectionRepository(
            devices: [device("front", isSystemDefault: true)],
            formats: ["front": [format(0, 1280, 720)]],
            selection: selection(isMirrored: isMirrored)
        )
        let state = makeSubject(repository).refresh()
        #expect(state.isMirrored == isMirrored)
        #expect(repository.mirrors.values == [isMirrored])
    }

    @Test("refresh saves nothing, even when the remembered camera is unplugged")
    func refreshSavesNothing() {
        let repository = FakeCameraSelectionRepository(
            devices: [device("front", isSystemDefault: true)],
            formats: ["front": [format(0, 1280, 720)]],
            selection: selection(deviceID: "gone", deviceName: "Old Cam")
        )
        _ = makeSubject(repository).refresh()
        #expect(repository.saves.count == 0)
    }

    @Test("changes() passes on the signal that the camera repository sends")
    func changesPassesOnRepositorySignal() async {
        let repository = FakeCameraSelectionRepository()
        let stream = makeSubject(repository).changes()
        repository.emitChange()
        #expect(await awaitFirstSignal(stream))
    }
}
