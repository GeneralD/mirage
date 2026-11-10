import Dependencies
import Domain
import TestDoubles
import Testing

@testable import PreferencesDataStore

@Suite("PreferencesDataStoreImpl hotkeys flag", .timeLimit(.minutes(1)))
struct HotkeysEnabledTests {
    private func makeSubject(_ store: InMemoryKeyValueStore, log: RecordingLog = RecordingLog()) -> PreferencesDataStoreImpl {
        withDependencies {
            $0.keyValueStoreGateway = store
            $0.developerLog = log
        } operation: {
            PreferencesDataStoreImpl()
        }
    }

    @Test("the flag is kept under hotkeysEnabled, the key that is persisted and never renamed")
    func persistedKey() {
        #expect(PreferencesDataStoreImpl.hotkeysEnabledKey == "hotkeysEnabled")
    }

    @Test("nothing stored means the hotkeys are on, with nothing written and nothing logged")
    func nothingStored() async {
        let store = InMemoryKeyValueStore()
        let log = RecordingLog()
        #expect(await makeSubject(store, log: log).hotkeysEnabled() == true)
        #expect(store.writes.count == 0)
        #expect(log.entries.count == 0)
    }

    @Test("setHotkeysEnabled(false) stores \"0\" under hotkeysEnabled, and it reads back as off")
    func offIsStoredAsZero() async {
        let store = InMemoryKeyValueStore()
        let subject = makeSubject(store)
        await subject.setHotkeysEnabled(false)
        #expect(store.values == ["hotkeysEnabled": "0"])
        #expect(store.writes.values == ["hotkeysEnabled"])
        #expect(await subject.hotkeysEnabled() == false)
    }

    @Test("setHotkeysEnabled(true) after off stores \"1\", and it reads back as on")
    func onIsStoredAsOne() async {
        let store = InMemoryKeyValueStore()
        let subject = makeSubject(store)
        await subject.setHotkeysEnabled(false)
        await subject.setHotkeysEnabled(true)
        #expect(store.values == ["hotkeysEnabled": "1"], "a new choice replaces the old one under the same key")
        #expect(await subject.hotkeysEnabled() == true)
    }

    @Test("a stored \"1\" reads as on, with nothing written and nothing logged")
    func storedOneReadsOn() async {
        let store = InMemoryKeyValueStore(["hotkeysEnabled": "1"])
        let log = RecordingLog()
        #expect(await makeSubject(store, log: log).hotkeysEnabled() == true)
        #expect(store.writes.count == 0, "reading writes nothing")
        #expect(log.entries.count == 0)
    }

    @Test("a stored \"0\" reads as off, with nothing written and nothing logged")
    func storedZeroReadsOff() async {
        let store = InMemoryKeyValueStore(["hotkeysEnabled": "0"])
        let log = RecordingLog()
        #expect(await makeSubject(store, log: log).hotkeysEnabled() == false)
        #expect(store.writes.count == 0, "reading writes nothing")
        #expect(log.entries.count == 0)
    }

    @Test(
        "a stored value that does not decode reads as on, logs one line in the app subsystem, and is left where it is",
        arguments: ["yes", ""])
    func malformed(stored: String) async {
        let store = InMemoryKeyValueStore(["hotkeysEnabled": stored])
        let log = RecordingLog()
        let subject = makeSubject(store, log: log)

        #expect(await subject.hotkeysEnabled() == true)
        #expect(log.entries.count == 1)
        #expect(log.messages(in: .app) == ["stored hotkeys flag does not decode, ignored: \(stored)"])
        #expect(store.values == ["hotkeysEnabled": stored], "another build may write it, and read it again")
        #expect(store.writes.count == 0)
    }

    @Test("the flag is set and read through the Preferences protocol, not only the concrete type")
    func protocolRoundTrip() async {
        let subject: any Preferences = makeSubject(InMemoryKeyValueStore())
        await subject.setHotkeysEnabled(false)
        #expect(await subject.hotkeysEnabled() == false)
    }

    @Test("the flag set by one subject is read back by the next over the same store, as after a relaunch")
    func survivesRelaunch() async {
        let store = InMemoryKeyValueStore()
        await makeSubject(store).setHotkeysEnabled(false)
        #expect(await makeSubject(store).hotkeysEnabled() == false)
        await makeSubject(store).setHotkeysEnabled(true)
        #expect(await makeSubject(store).hotkeysEnabled() == true)
    }

    @Test("only the hotkeys key is written: the chosen effect and the disabled records are not touched")
    func otherKeysUntouched() async {
        let store = InMemoryKeyValueStore(["selectedEffect": "package:glitch", "disabledEffects.v1": "[]"])
        await makeSubject(store).setHotkeysEnabled(false)
        #expect(store.writes.values == ["hotkeysEnabled"])
        #expect(store.values["selectedEffect"] == "package:glitch")
        #expect(store.values["disabledEffects.v1"] == "[]")
    }
}
