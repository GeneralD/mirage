import Dependencies
import Domain
import TestDoubles
import Testing

@testable import PreferencesDataStore

@Suite("PreferencesDataStore disabled effects", .timeLimit(.minutes(1)))
struct PreferencesDataStoreDisabledTests {
    /// The persisted forms, written out by hand: a change to what they say changes what an
    /// installed build reads back, so the tests compare against these exact strings.
    private let glitchJSON =
        #"{"fingerprint":{"value":"f1"},"id":{"key":"glitch","origin":"package"},"reason":{"failure":{"_0":"timeout"}},"retriesAutomatically":false}"#
    private let rippleJSON =
        #"{"fingerprint":{"value":"f2"},"id":{"key":"ripple","origin":"package"},"reason":{"overBudget":{}},"retriesAutomatically":true}"#
    private let glitch = DisabledEffectRecord(
        id: .package("glitch"), fingerprint: EffectFingerprint(value: "f1"), reason: .failure(.timeout), retriesAutomatically: false)
    private let ripple = DisabledEffectRecord(
        id: .package("ripple"), fingerprint: EffectFingerprint(value: "f2"), reason: .overBudget, retriesAutomatically: true)

    private func makeSubject(_ store: InMemoryKeyValueStore, log: RecordingLog = RecordingLog()) -> PreferencesDataStoreImpl {
        withDependencies {
            $0.keyValueStoreGateway = store
            $0.developerLog = log
        } operation: {
            PreferencesDataStoreImpl()
        }
    }

    @Test("the records are set and read through the Preferences protocol, not only the concrete type")
    func protocolRoundTrip() async {
        let subject: any Preferences = makeSubject(InMemoryKeyValueStore())
        await subject.setDisabledEffects([glitch])
        #expect(await subject.disabledEffects() == [glitch])
    }

    @Test("the records are kept under disabledEffects.v1, the key that is persisted and never renamed")
    func persistedKey() {
        #expect(PreferencesDataStoreImpl.disabledEffectsKey == "disabledEffects.v1")
    }

    @Test("one record is stored as one JSON string, in the persisted form")
    func storedForm() async {
        let store = InMemoryKeyValueStore()
        await makeSubject(store).setDisabledEffects([glitch])
        #expect(store.values == ["disabledEffects.v1": "[\(glitchJSON)]"])
        #expect(store.writes.values == ["disabledEffects.v1"])
    }

    @Test("two records are stored sorted by origin and key, whatever order they are given in")
    func sortedStoredForm() async {
        let store = InMemoryKeyValueStore()
        await makeSubject(store).setDisabledEffects([ripple, glitch])
        #expect(store.values == ["disabledEffects.v1": "[\(glitchJSON),\(rippleJSON)]"])
    }

    @Test("an empty list is stored as [] and the key is kept, and it reads back as an empty list")
    func emptyList() async {
        let store = InMemoryKeyValueStore(["disabledEffects.v1": "[\(glitchJSON)]"])
        let subject = makeSubject(store)
        await subject.setDisabledEffects([])
        #expect(store.values == ["disabledEffects.v1": "[]"])
        #expect(await subject.disabledEffects() == [])
    }

    @Test("nothing stored reads as an empty list, with nothing written and nothing logged")
    func nothingStored() async {
        let store = InMemoryKeyValueStore()
        let log = RecordingLog()
        #expect(await makeSubject(store, log: log).disabledEffects() == [])
        #expect(store.writes.count == 0)
        #expect(log.entries.count == 0)
    }

    @Test(
        "a stored value that does not decode reads as an empty list, logs one line, and is left where it is",
        arguments: ["", "garbage", "{}", #"[{"id":1}]"#])
    func malformed(stored: String) async {
        let store = InMemoryKeyValueStore(["disabledEffects.v1": stored])
        let log = RecordingLog()
        #expect(await makeSubject(store, log: log).disabledEffects() == [])
        #expect(log.entries.count == 1)
        #expect(log.messages(in: .effect) == ["stored disabled effects do not decode, ignored"])
        #expect(store.values == ["disabledEffects.v1": stored], "another build may have written it, and may read it again")
        #expect(store.writes.count == 0)
    }

    @Test("a value where only one record decodes is dropped as a whole, logged once, and left where it is")
    func partlyReadable() async {
        let stored = "[\(glitchJSON),{\"id\":1}]"
        let store = InMemoryKeyValueStore(["disabledEffects.v1": stored])
        let log = RecordingLog()
        #expect(await makeSubject(store, log: log).disabledEffects() == [])
        #expect(log.messages(in: .effect).count == 1)
        #expect(store.values == ["disabledEffects.v1": stored])
        #expect(store.writes.count == 0)
    }

    @Test("a value in the persisted form reads back the records it holds, and reading writes nothing")
    func readsStoredForm() async {
        let store = InMemoryKeyValueStore(["disabledEffects.v1": "[\(glitchJSON),\(rippleJSON)]"])
        let log = RecordingLog()
        #expect(await makeSubject(store, log: log).disabledEffects() == [glitch, ripple])
        #expect(log.entries.count == 0)
        #expect(store.writes.count == 0, "reading writes nothing")
    }

    @Test("an overBudget record with its retry flag comes back as it was set")
    func overBudgetRoundTrip() async {
        let store = InMemoryKeyValueStore()
        let subject = makeSubject(store)
        await subject.setDisabledEffects([ripple])
        #expect(await subject.disabledEffects() == [ripple])
        #expect(store.values == ["disabledEffects.v1": "[\(rippleJSON)]"])
    }

    @Test("records set by one subject are read back in stored order by the next over the same store, as after a relaunch")
    func survivesRelaunch() async {
        let store = InMemoryKeyValueStore()
        await makeSubject(store).setDisabledEffects([ripple, glitch])
        #expect(await makeSubject(store).disabledEffects() == [glitch, ripple])
    }

    @Test("a second set replaces the first one, and nothing accumulates")
    func secondSetReplaces() async {
        let store = InMemoryKeyValueStore()
        let subject = makeSubject(store)
        await subject.setDisabledEffects([glitch])
        await subject.setDisabledEffects([ripple])
        #expect(store.values == ["disabledEffects.v1": "[\(rippleJSON)]"])
        #expect(await subject.disabledEffects() == [ripple])
    }

    @Test("only the disabled-effects key is written: the chosen effect and other keys are not touched")
    func otherKeysUntouched() async {
        let store = InMemoryKeyValueStore(["selectedEffect": "package:glitch", "other": "value"])
        await makeSubject(store).setDisabledEffects([glitch])
        #expect(store.writes.values == ["disabledEffects.v1"])
        #expect(store.values["selectedEffect"] == "package:glitch")
        #expect(store.values["other"] == "value")
    }
}
