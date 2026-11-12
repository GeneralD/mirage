import Entity
import Testing

@Suite struct CameraStateTests {
    @Test func resolutionsDifferingInEitherDimensionAreNotEqual() {
        let hd = CameraResolution(width: 1280, height: 720)
        #expect(hd == CameraResolution(width: 1280, height: 720))
        #expect(hd != CameraResolution(width: 1920, height: 720))
        #expect(hd != CameraResolution(width: 1280, height: 1080))
    }

    @Test func selectionKeepsTheDeviceNameAlongsideTheIDSoItCanBeNamedWhileUnplugged() {
        let selection = CameraSelection(
            deviceID: "cam-1",
            deviceName: "FaceTime HD",
            resolution: CameraResolution(width: 1280, height: 720),
            framesPerSecond: 30,
            isMirrored: true
        )
        #expect(selection.deviceID == "cam-1")
        #expect(selection.deviceName == "FaceTime HD")
        #expect(selection.resolution == CameraResolution(width: 1280, height: 720))
        #expect(selection.framesPerSecond == 30)
        #expect(selection.isMirrored)
    }

    @Test func initialSelectionChoosesNothingAndIsNotMirrored() {
        #expect(CameraSelection.initial.deviceID == nil)
        #expect(CameraSelection.initial.deviceName == nil)
        #expect(CameraSelection.initial.resolution == nil)
        #expect(CameraSelection.initial.framesPerSecond == nil)
        #expect(CameraSelection.initial.isMirrored == false)
    }

    @Test func stateKeepsTheCandidatesAndChoiceItWasGiven() {
        let device = CameraDevice(id: "cam-1", name: "FaceTime HD", isSystemDefault: true)
        let resolution = CameraResolution(width: 1280, height: 720)
        let state = CameraState(
            devices: [device],
            selectedDeviceID: "cam-1",
            availability: .available,
            resolutions: [resolution],
            selectedResolution: resolution,
            frameRates: [30, 60],
            selectedFrameRate: 60,
            isMirrored: true
        )
        #expect(state.devices == [device])
        #expect(state.selectedDeviceID == "cam-1")
        #expect(state.availability == .available)
        #expect(state.resolutions == [resolution])
        #expect(state.selectedResolution == resolution)
        #expect(state.frameRates == [30, 60])
        #expect(state.selectedFrameRate == 60)
        #expect(state.isMirrored)
    }

    @Test func emptyStateReportsNoCameraAndHasNoCandidates() {
        #expect(CameraState.empty.availability == .noCamera)
        #expect(CameraState.empty.devices.isEmpty)
        #expect(CameraState.empty.resolutions.isEmpty)
        #expect(CameraState.empty.frameRates.isEmpty)
        #expect(CameraState.empty.selectedDeviceID == nil)
        #expect(CameraState.empty.selectedResolution == nil)
        #expect(CameraState.empty.selectedFrameRate == nil)
        #expect(CameraState.empty.isMirrored == false)
    }

    @Test func missingAvailabilityWithDifferentNamesIsNotEqual() {
        #expect(CameraAvailability.missing("FaceTime HD") == CameraAvailability.missing("FaceTime HD"))
        #expect(CameraAvailability.missing("FaceTime HD") != CameraAvailability.missing("USB Camera"))
    }

    @Test func menuOptionIsIdentifiedByItsID() {
        let option = CameraMenuOption(id: "cam-1", title: "FaceTime HD", isSelected: true)
        #expect(option.id == "cam-1")
        #expect(option.title == "FaceTime HD")
        #expect(option.isSelected)
    }

    @Test func menuOptionsDifferingOnlyInSelectionAreNotEqual() {
        let selected = CameraMenuOption(id: "cam-1", title: "FaceTime HD", isSelected: true)
        let unselected = CameraMenuOption(id: "cam-1", title: "FaceTime HD", isSelected: false)
        #expect(selected != unselected)
    }
}
