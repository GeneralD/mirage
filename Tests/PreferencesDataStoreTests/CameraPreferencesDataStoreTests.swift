import Dependencies
import Domain
import TestDoubles
import Testing

@testable import PreferencesDataStore

@Suite("CameraPreferencesDataStoreImpl", .timeLimit(.minutes(1)))
struct CameraPreferencesDataStoreTests {
    private func makeSubject(_ store: InMemoryKeyValueStore, log: RecordingLog = RecordingLog()) -> CameraPreferencesDataStoreImpl {
        withDependencies {
            $0.keyValueStoreGateway = store
            $0.developerLog = log
        } operation: {
            CameraPreferencesDataStoreImpl()
        }
    }

    private static let chosen = CameraSelection(
        deviceID: "cam-1",
        deviceName: "FaceTime HD",
        resolution: CameraResolution(width: 1280, height: 720),
        framesPerSecond: 30,
        isMirrored: true
    )

    @Test("the five keys are kept under the names that are persisted and never renamed")
    func persistedKeys() {
        #expect(CameraPreferencesDataStoreImpl.deviceIDKey == "cameraDeviceID")
        #expect(CameraPreferencesDataStoreImpl.deviceNameKey == "cameraDeviceName")
        #expect(CameraPreferencesDataStoreImpl.resolutionKey == "cameraResolution")
        #expect(CameraPreferencesDataStoreImpl.frameRateKey == "cameraFrameRate")
        #expect(CameraPreferencesDataStoreImpl.mirroredKey == "cameraMirrored")
    }

    @Test("nothing stored reads as the initial choice, with nothing written and nothing logged")
    func nothingStored() {
        let store = InMemoryKeyValueStore()
        let log = RecordingLog()
        #expect(makeSubject(store, log: log).selection() == .initial)
        #expect(store.writes.count == 0)
        #expect(log.entries.count == 0)
    }

    @Test("a saved choice reads back unchanged, also by the next subject over the same store, as after a relaunch")
    func surviveRelaunch() {
        let store = InMemoryKeyValueStore()
        makeSubject(store).save(Self.chosen)
        #expect(makeSubject(store).selection() == Self.chosen)
    }

    @Test("the choice is stored under its five keys in the forms that are persisted")
    func storedForms() {
        let store = InMemoryKeyValueStore()
        makeSubject(store).save(Self.chosen)
        #expect(
            store.values == [
                "cameraDeviceID": "cam-1",
                "cameraDeviceName": "FaceTime HD",
                "cameraResolution": "1280x720",
                "cameraFrameRate": "30",
                "cameraMirrored": "1",
            ])
    }

    @Test("mirroring is stored as 0 when it is off, and reads back as off")
    func mirroringOffIsZero() {
        let store = InMemoryKeyValueStore()
        let subject = makeSubject(store)
        let unmirrored = CameraSelection(
            deviceID: "cam-1", deviceName: "FaceTime HD", resolution: nil, framesPerSecond: nil, isMirrored: false)
        subject.save(unmirrored)
        #expect(store.values["cameraMirrored"] == "0")
        #expect(subject.selection() == unmirrored)
    }

    @Test("a setting that is nil is removed from the store when the choice is saved")
    func nilSettingIsRemoved() {
        let store = InMemoryKeyValueStore()
        let subject = makeSubject(store)
        subject.save(Self.chosen)
        let cleared = CameraSelection(deviceID: nil, deviceName: nil, resolution: nil, framesPerSecond: nil, isMirrored: false)
        subject.save(cleared)
        #expect(store.values == ["cameraMirrored": "0"], "the four settings that are nil are removed, and mirroring is always written")
        #expect(subject.selection() == cleared)
    }

    @Test("a choice saved later replaces the one stored before under the same keys")
    func saveReplacesPrevious() {
        let store = InMemoryKeyValueStore()
        let subject = makeSubject(store)
        subject.save(Self.chosen)
        let other = CameraSelection(
            deviceID: "cam-2",
            deviceName: "Virtual",
            resolution: CameraResolution(width: 1920, height: 1080),
            framesPerSecond: 60,
            isMirrored: false
        )
        subject.save(other)
        #expect(subject.selection() == other)
        #expect(store.values["cameraResolution"] == "1920x1080")
    }

    @Test("a stored resolution of 1280x720 reads as that resolution, with nothing written and nothing logged")
    func storedResolutionReads() {
        let store = InMemoryKeyValueStore(["cameraResolution": "1280x720"])
        let log = RecordingLog()
        #expect(makeSubject(store, log: log).selection().resolution == CameraResolution(width: 1280, height: 720))
        #expect(store.writes.count == 0, "reading writes nothing")
        #expect(log.entries.count == 0)
    }

    @Test(
        "a stored resolution that does not decode reads as nil, logs one camera line, and leaves the other settings and the store as they are",
        arguments: ["abc", "0x720", "1280x", "1280xx720", "1280x720x30", "x720", "-1280x720"])
    func brokenResolution(stored: String) {
        let store = InMemoryKeyValueStore([
            "cameraDeviceID": "cam-1",
            "cameraResolution": stored,
            "cameraFrameRate": "30",
            "cameraMirrored": "1",
        ])
        let log = RecordingLog()
        let subject = makeSubject(store, log: log)

        #expect(
            subject.selection()
                == CameraSelection(deviceID: "cam-1", deviceName: nil, resolution: nil, framesPerSecond: 30, isMirrored: true))
        #expect(log.entries.count == 1)
        #expect(log.messages(in: .camera).count == 1, "it is a camera line")
        #expect(log.contains("does not decode"))
        #expect(store.values["cameraResolution"] == stored, "another build may read it again, so it is left where it is")
        #expect(store.writes.count == 0)
    }

    @Test("a frame rate of 1 and of 240, the bounds of the range, is accepted", arguments: [1, 240])
    func frameRateBounds(rate: Int) {
        let store = InMemoryKeyValueStore(["cameraFrameRate": "\(rate)"])
        let log = RecordingLog()
        #expect(makeSubject(store, log: log).selection().framesPerSecond == rate)
        #expect(log.entries.count == 0)
    }

    @Test(
        "a stored frame rate outside 1 to 240, or not a whole number, reads as nil, logs one camera line, and is left where it is",
        arguments: ["0", "241", "x", "-30"])
    func brokenFrameRate(stored: String) {
        let store = InMemoryKeyValueStore([
            "cameraDeviceID": "cam-1",
            "cameraResolution": "1280x720",
            "cameraFrameRate": stored,
            "cameraMirrored": "1",
        ])
        let log = RecordingLog()
        let subject = makeSubject(store, log: log)

        #expect(
            subject.selection()
                == CameraSelection(
                    deviceID: "cam-1",
                    deviceName: nil,
                    resolution: CameraResolution(width: 1280, height: 720),
                    framesPerSecond: nil,
                    isMirrored: true
                ))
        #expect(log.messages(in: .camera).count == 1)
        #expect(store.values["cameraFrameRate"] == stored)
        #expect(store.writes.count == 0)
    }

    @Test("a stored 1 reads as mirrored")
    func mirroredForOne() {
        let store = InMemoryKeyValueStore(["cameraMirrored": "1"])
        #expect(makeSubject(store).selection().isMirrored == true)
    }

    // Decision: any stored value other than 1 reads as off and is not logged, because the spec gives no
    // log line for mirroring; the field is a Bool, so there is no nil to report.
    @Test("mirroring is on only for a stored 1, so any other stored value reads as off", arguments: ["0", "yes", "true", ""])
    func mirroredOnlyForOne(stored: String) {
        let store = InMemoryKeyValueStore(["cameraMirrored": stored])
        #expect(makeSubject(store).selection().isMirrored == false)
        #expect(store.writes.count == 0, "reading writes nothing")
    }

    @Test("the fake answers the initial choice, and records no save, until one is saved")
    func fakeStartsAtInitial() {
        let fake = FakeCameraPreferences()
        #expect(fake.selection() == .initial)
        #expect(fake.saves.count == 0)
    }

    @Test("the fake answers the last choice saved, and records every save in call order")
    func fakeAnswersLastSave() {
        let fake = FakeCameraPreferences()
        fake.save(Self.chosen)
        fake.save(.initial)
        #expect(fake.selection() == .initial)
        #expect(fake.saves.values == [Self.chosen, .initial])
    }
}
