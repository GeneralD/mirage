import Dependencies
import Domain
import PreferencesDataStore
import TestDoubles
import Testing

@testable import SettingsRepository

/// The Repository over the real DataStore, on the defaults double: what the user chose in one
/// launch is what the next one starts from (epic #42, D6). Each `launch` builds a fresh pair, so
/// nothing but the store carries a choice over.
@Suite("Selection persistence", .timeLimit(.minutes(1)))
struct SelectionPersistenceTests {
    private func launch(over store: InMemoryKeyValueStore, log: RecordingLog = RecordingLog()) -> SettingsRepositoryImpl {
        let preferences = withDependencies {
            $0.keyValueStoreGateway = store
            $0.developerLog = log
        } operation: {
            PreferencesDataStoreImpl()
        }
        return withDependencies {
            $0.preferences = preferences
        } operation: {
            SettingsRepositoryImpl()
        }
    }

    @Test("a first launch has no choice, and reading it writes nothing")
    func firstLaunch() async {
        let store = InMemoryKeyValueStore()
        #expect(await launch(over: store).selectedEffect() == nil)
        #expect(store.writes.count == 0)
    }

    @Test(
        "the choice of one launch is the selection of the next, whichever the origin",
        arguments: [EffectID.bundled("Chromatic Grain"), .package("glitch")])
    func choiceSurvivesRelaunch(chosen: EffectID) async {
        let store = InMemoryKeyValueStore()
        await launch(over: store).setSelectedEffect(chosen)
        #expect(await launch(over: store).selectedEffect() == chosen)
    }

    @Test("the last choice wins, and it is kept as one string under one key")
    func lastChoiceWins() async {
        let store = InMemoryKeyValueStore()
        let first = launch(over: store)
        await first.setSelectedEffect(.package("glitch"))
        await first.setSelectedEffect(.bundled("Chromatic Grain"))
        #expect(await launch(over: store).selectedEffect() == .bundled("Chromatic Grain"))
        #expect(store.values == ["selectedEffect": "bundled:Chromatic Grain"])
    }

    @Test("a string another build left behind is no choice, is logged, and does not stop a new choice from being kept")
    func foreignValue() async {
        let store = InMemoryKeyValueStore(["selectedEffect": "{\"origin\":\"package\"}"])
        let log = RecordingLog()
        let subject = launch(over: store, log: log)
        #expect(await subject.selectedEffect() == nil)
        #expect(log.entries.count == 1)

        await subject.setSelectedEffect(.package("glitch"))
        #expect(await launch(over: store).selectedEffect() == .package("glitch"))
    }
}
