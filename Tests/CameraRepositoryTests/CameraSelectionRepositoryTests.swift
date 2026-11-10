import CameraRepository
import Dependencies
import Domain
import TestDoubles
import TestSupport
import Testing

@Suite("CameraSelectionRepository", .timeLimit(.minutes(1)))
struct CameraSelectionRepositoryTests {
    private struct Rig {
        let devices: FakeCameraDevices
        let preferences: FakeCameraPreferences
        let source: FakeCameraSource
        let subject: CameraSelectionRepositoryImpl

        init(
            devices: FakeCameraDevices = FakeCameraDevices(),
            preferences: FakeCameraPreferences = FakeCameraPreferences(),
            source: FakeCameraSource = FakeCameraSource()
        ) {
            self.devices = devices
            self.preferences = preferences
            self.source = source
            subject = withDependencies {
                $0.cameraDevices = devices
                $0.cameraPreferences = preferences
                $0.cameraSource = source
            } operation: {
                CameraSelectionRepositoryImpl()
            }
        }
    }

    private static let chosen = CameraSelection(
        deviceID: "cam-1",
        deviceName: "FaceTime HD",
        resolution: CameraResolution(width: 1280, height: 720),
        framesPerSecond: 30,
        isMirrored: true
    )

    @Test("devices returns the camera list the device port gives, in the port's order")
    func devicesPassThrough() {
        let unsorted = [
            CameraDevice(id: "cam-b", name: "USB Camera"),
            CameraDevice(id: "cam-a", name: "FaceTime HD", isSystemDefault: true),
        ]
        let rig = Rig(devices: FakeCameraDevices(devices: unsorted))
        #expect(rig.subject.devices() == unsorted)
    }

    @Test("formats(ofDevice:) returns the device port's formats for that id, in its order, and asks with that id")
    func formatsPassThrough() {
        let second = CameraFormat(index: 1, width: 1920, height: 1080, minFramesPerSecond: 1, maxFramesPerSecond: 60)
        let first = CameraFormat(index: 0, width: 1280, height: 720, minFramesPerSecond: 1, maxFramesPerSecond: 30)
        let rig = Rig(devices: FakeCameraDevices(formats: ["cam-1": [second, first]]))
        #expect(rig.subject.formats(ofDevice: "cam-1") == [second, first])
        #expect(rig.devices.formatRequests.values == ["cam-1"])
    }

    @Test("a change the device port signals reaches the stream that changes() returned")
    func changesPassThrough() async {
        let rig = Rig()
        let stream = rig.subject.changes()
        rig.devices.emitChange()
        let received: Void? = await stream.first(where: { _ in true })
        #expect(received != nil)
    }

    @Test("storedSelection returns the selection the preferences hold, with every field kept")
    func storedSelectionPassThrough() {
        let rig = Rig(preferences: FakeCameraPreferences(Self.chosen))
        #expect(rig.subject.storedSelection() == Self.chosen)
    }

    @Test("save delivers the selection to the preferences as one save, and storedSelection reads it back")
    func saveReachesPreferences() {
        let rig = Rig()
        rig.subject.save(Self.chosen)
        #expect(rig.preferences.saves.values == [Self.chosen])
        #expect(rig.subject.storedSelection() == Self.chosen)
    }

    @Test("apply reaches the source's configure with the same capture, and saves nothing to the preferences")
    func applyReachesSource() {
        let rig = Rig()
        let capture = CameraCapture(deviceID: "cam-1", format: CameraFormatChoice(index: 1, framesPerSecond: 60))
        rig.subject.apply(capture)
        #expect(rig.source.captures == [capture])
        #expect(rig.preferences.saves.count == 0)
    }

    @Test("setMirrored reaches the source's setMirrored with the same flag", arguments: [true, false])
    func setMirroredReachesSource(mirrored: Bool) {
        let rig = Rig()
        rig.subject.setMirrored(mirrored)
        #expect(rig.source.mirrorSettings == [mirrored])
    }
}
