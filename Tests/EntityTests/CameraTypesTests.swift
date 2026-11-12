import Entity
import Testing

@Suite struct CameraTypesTests {
    @Test func standardCaptureHasNoDeviceAndNoFormat() {
        #expect(CameraCapture.standard.deviceID == nil)
        #expect(CameraCapture.standard.format == nil)
    }

    @Test func systemDefaultFlagIsFalseUnlessSpecified() {
        #expect(!CameraDevice(id: "cam-1", name: "FaceTime HD").isSystemDefault)
        #expect(CameraDevice(id: "cam-1", name: "FaceTime HD", isSystemDefault: true).isSystemDefault)
    }

    @Test func suspendedAndVirtualFlagsAreFalseUnlessSpecified() {
        let plain = CameraDevice(id: "cam-1", name: "FaceTime HD")
        #expect(!plain.isSuspended)
        #expect(!plain.isVirtual)
        #expect(CameraDevice(id: "cam-1", name: "FaceTime HD", isSuspended: true).isSuspended)
        #expect(CameraDevice(id: "vcam", name: "Virtual", isVirtual: true).isVirtual)
    }

    @Test func formatsThatDifferOnlyInIndexAreNotEqual() {
        let first = CameraFormat(index: 0, width: 1280, height: 720, minFramesPerSecond: 1, maxFramesPerSecond: 30)
        let second = CameraFormat(index: 1, width: 1280, height: 720, minFramesPerSecond: 1, maxFramesPerSecond: 30)
        #expect(first != second)
    }

    @Test func formatChoiceKeepsTheIndexAndTheFrameRateItWasGiven() {
        let choice = CameraFormatChoice(index: 3, framesPerSecond: 30)
        #expect(choice.index == 3)
        #expect(choice.framesPerSecond == 30)
    }

    @Test func captureNamingADeviceOrAFormatIsNotTheStandardCapture() {
        #expect(CameraCapture(deviceID: "cam-1", format: nil) != CameraCapture.standard)
        #expect(CameraCapture(deviceID: nil, format: CameraFormatChoice(index: 0, framesPerSecond: 30)) != CameraCapture.standard)
    }
}
