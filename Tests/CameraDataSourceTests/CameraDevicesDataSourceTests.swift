import CameraDataSource
import Dependencies
import Domain
import TestDoubles
import Testing

@Suite("CameraDevicesDataSource", .timeLimit(.minutes(1)))
struct CameraDevicesDataSourceTests {
    private func makeSubject(gateway: FakeCameraDeviceGateway) -> CameraDevicesDataSourceImpl {
        withDependencies {
            $0.cameraDeviceGateway = gateway
        } operation: {
            CameraDevicesDataSourceImpl()
        }
    }

    @Test(
        "the app's own virtual camera is not listed, whatever the letter case of its id; other cameras are",
        arguments: [ProductIdentity.virtualDeviceID, ProductIdentity.virtualDeviceID.lowercased()]
    )
    func hidesVirtualCamera(id: String) {
        let camera = CameraDevice(id: "cam-1", name: "FaceTime HD")
        let gateway = FakeCameraDeviceGateway(devices: [CameraDevice(id: id, name: "Virtual Camera"), camera])
        let subject = makeSubject(gateway: gateway)
        #expect(subject.devices() == [camera])
    }

    @Test("the list is sorted by name, and cameras with the same name are sorted by id")
    func sortsByNameThenID() {
        let usbB = CameraDevice(id: "cam-b", name: "USB Camera")
        let capture = CameraDevice(id: "cam-z", name: "Capture Card")
        let usbA = CameraDevice(id: "cam-a", name: "USB Camera")
        let external = CameraDevice(id: "cam-c", name: "External")
        let gateway = FakeCameraDeviceGateway(devices: [usbB, capture, usbA, external])
        let subject = makeSubject(gateway: gateway)
        #expect(subject.devices() == [capture, external, usbA, usbB])
    }

    @Test("formats(ofDevice:) returns the gateway's formats for that id, in the gateway's order")
    func formatsPassThrough() {
        let first = CameraFormat(index: 0, width: 1280, height: 720, minFramesPerSecond: 1, maxFramesPerSecond: 30)
        let second = CameraFormat(index: 1, width: 1920, height: 1080, minFramesPerSecond: 1, maxFramesPerSecond: 60)
        let gateway = FakeCameraDeviceGateway()
        gateway.setFormats([second, first], ofDevice: "cam-1")
        let subject = makeSubject(gateway: gateway)
        #expect(subject.formats(ofDevice: "cam-1") == [second, first])
        #expect(gateway.formatRequests.values == ["cam-1"])
    }

    @Test("a change the gateway emits reaches the stream that changes() returned")
    func changesPassThrough() async {
        let gateway = FakeCameraDeviceGateway()
        let subject = makeSubject(gateway: gateway)
        let stream = subject.changes()
        gateway.emitChange()
        let received: Void? = await stream.first(where: { _ in true })
        #expect(received != nil)
    }
}
