import Domain
import TestDoubles
import TestSupport
import Testing

@Suite("FakeCameraDeviceGateway", .timeLimit(.minutes(1)))
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

    /// A task that records each element its stream yields.
    private func listen(to stream: AsyncStream<Void>, into heard: Collector<Void>) -> Task<Void, Never> {
        Task { for await _ in stream { heard.append(()) } }
    }

    @Test("a change emitted after changes() was taken reaches that stream once")
    func emittedChangeReachesStreamOnce() async {
        let gateway = FakeCameraDeviceGateway()
        let heard = Collector<Void>()
        let consumer = listen(to: gateway.changes(), into: heard)

        gateway.emitChange()
        await heard.waitForCount(1)
        consumer.cancel()
        await consumer.value

        #expect(heard.count == 1)
    }

    @Test("a change emitted after changes() was called twice reaches both streams")
    func emittedChangeReachesEveryStream() async {
        let gateway = FakeCameraDeviceGateway()
        let first = Collector<Void>()
        let second = Collector<Void>()
        let firstConsumer = listen(to: gateway.changes(), into: first)
        let secondConsumer = listen(to: gateway.changes(), into: second)

        gateway.emitChange()
        await first.waitForCount(1)
        await second.waitForCount(1)
        firstConsumer.cancel()
        secondConsumer.cancel()
        await firstConsumer.value
        await secondConsumer.value

        #expect(first.count == 1)
        #expect(second.count == 1)
    }
}
