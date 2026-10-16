import Dependencies
import Domain
import TestDoubles
import Testing

@testable import PreferencesDataStore

@Suite("PreferencesDataStoreImpl", .timeLimit(.minutes(1)))
struct PreferencesDataStoreImplTests {
    private func makeSubject(_ store: InMemoryKeyValueStore, log: RecordingLog = RecordingLog()) -> PreferencesDataStoreImpl {
        withDependencies {
            $0.keyValueStoreGateway = store
            $0.developerLog = log
        } operation: {
            PreferencesDataStoreImpl()
        }
    }

    @Test("nothing was ever chosen: nil, with nothing written and nothing logged")
    func nothingChosen() async {
        let store = InMemoryKeyValueStore()
        let log = RecordingLog()
        #expect(await makeSubject(store, log: log).selectedEffect() == nil)
        #expect(store.writes.count == 0)
        #expect(log.entries.count == 0)
    }

    @Test("the chosen effect is stored as one string under one key, in the form that is persisted")
    func storedForm() async {
        let store = InMemoryKeyValueStore()
        let subject = makeSubject(store)
        await subject.setSelectedEffect(.package("glitch"))
        #expect(store.values == ["selectedEffect": "package:glitch"])
        #expect(store.writes.values == ["selectedEffect"])

        await subject.setSelectedEffect(.bundled("Chromatic Grain"))
        #expect(store.values == ["selectedEffect": "bundled:Chromatic Grain"], "a new choice replaces the old one under the same key")
        #expect(store.writes.values == ["selectedEffect", "selectedEffect"])
    }

    @Test("what was chosen is chosen again by the next subject over the same store, as after a relaunch")
    func surviveRelaunch() async {
        let store = InMemoryKeyValueStore()
        await makeSubject(store).setSelectedEffect(.package("glitch"))
        #expect(await makeSubject(store).selectedEffect() == .package("glitch"))
        await makeSubject(store).setSelectedEffect(.bundled("Chromatic Grain"))
        #expect(await makeSubject(store).selectedEffect() == .bundled("Chromatic Grain"))
    }

    @Test("a key with colons and spaces comes back as it was set")
    func awkwardKey() async {
        let store = InMemoryKeyValueStore()
        let subject = makeSubject(store)
        await subject.setSelectedEffect(.package("my: glitch:2 日本"))
        #expect(await subject.selectedEffect() == .package("my: glitch:2 日本"))
    }

    @Test("a value that was stored in the form is read, and that is not logged")
    func readsStoredForm() async {
        let store = InMemoryKeyValueStore(["selectedEffect": "package:glitch"])
        let log = RecordingLog()
        #expect(await makeSubject(store, log: log).selectedEffect() == .package("glitch"))
        #expect(log.entries.count == 0)
        #expect(store.writes.count == 0, "reading writes nothing")
    }

    @Test(
        "a stored string that does not decode is nil, logged once, and left where it is",
        arguments: ["", "garbage", "bundled", "unknown:glitch", "Package:glitch", ":glitch", "package\u{FF1A}glitch"])
    func malformed(stored: String) async {
        let store = InMemoryKeyValueStore(["selectedEffect": stored])
        let log = RecordingLog()
        let subject = makeSubject(store, log: log)

        #expect(await subject.selectedEffect() == nil)
        #expect(log.entries.count == 1)
        #expect(log.messages(in: .effect).count == 1, "it is an effect-selection line")
        #expect(log.contains("does not decode"))
        #expect(store.values == ["selectedEffect": stored], "another build may write it, and read it again")
        #expect(store.writes.count == 0)
    }

    @Test("a new choice replaces a stored string that did not decode")
    func choiceReplacesMalformed() async {
        let store = InMemoryKeyValueStore(["selectedEffect": "garbage"])
        let subject = makeSubject(store)
        await subject.setSelectedEffect(.bundled("Chromatic Grain"))
        #expect(await subject.selectedEffect() == .bundled("Chromatic Grain"))
        #expect(store.values == ["selectedEffect": "bundled:Chromatic Grain"])
    }

    @Test("other keys of the store are neither read nor touched")
    func otherKeys() async {
        let store = InMemoryKeyValueStore(["other": "package:glitch", "selectedEffectX": "package:glitch"])
        let log = RecordingLog()
        let subject = makeSubject(store, log: log)
        #expect(await subject.selectedEffect() == nil)
        await subject.setSelectedEffect(.bundled("Chromatic Grain"))
        #expect(store.values["other"] == "package:glitch")
        #expect(store.values["selectedEffectX"] == "package:glitch")
        #expect(log.entries.count == 0)
    }
}
