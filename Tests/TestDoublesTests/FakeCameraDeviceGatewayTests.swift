import Domain
import TestDoubles
import TestSupport
import Testing

@Suite("FakeCameraDeviceGateway")
struct FakeCameraDeviceGatewayTests {
    @Test("devices returns the devices in the order they were set")
    func devicesInSetOrder() {
        let first = CameraDevice(id: "cam-1", name: "FaceTime HD", isSystemDefault: true)
        let second = CameraDevice(id: "cam-2", name: "External")
        let gateway = FakeCameraDeviceGateway(devices: [first, second])
        #expect(gateway.devices() == [first, second])
    }

    @Test("setDevices replaces the list that the next devices call returns")
    func setDevicesReplacesList() {
        let gateway = FakeCameraDeviceGateway(devices: [CameraDevice(id: "cam-1", name: "FaceTime HD")])
        let replacement = CameraDevice(id: "cam-2", name: "External")
        gateway.setDevices([replacement])
        #expect(gateway.devices() == [replacement])
    }

    @Test("formats returns the formats set for each id")
    func formatsPerDevice() {
        let format = CameraFormat(index: 0, width: 1280, height: 720, minFramesPerSecond: 1, maxFramesPerSecond: 30)
        let gateway = FakeCameraDeviceGateway()
        gateway.setFormats([format], ofDevice: "cam-1")
        #expect(gateway.formats(ofDevice: "cam-1") == [format])
    }

    @Test("formats returns an empty list for an id with no formats set")
    func formatsEmptyForUnknownDevice() {
        let gateway = FakeCameraDeviceGateway()
        gateway.setFormats([CameraFormat(index: 0, width: 1280, height: 720, minFramesPerSecond: 1, maxFramesPerSecond: 30)], ofDevice: "cam-1")
        #expect(gateway.formats(ofDevice: "cam-2").isEmpty)
    }

    @Test("formatRequests keeps the ids passed to formats(ofDevice:) in the order they were called")
    func formatRequestsInCallOrder() {
        let gateway = FakeCameraDeviceGateway()
        _ = gateway.formats(ofDevice: "cam-2")
        _ = gateway.formats(ofDevice: "cam-1")
        #expect(gateway.formatRequests.values == ["cam-2", "cam-1"])
    }
}
