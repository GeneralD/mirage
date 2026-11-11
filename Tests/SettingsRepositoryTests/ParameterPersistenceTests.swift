import Dependencies
import Domain
import PreferencesDataStore
import TestDoubles
import Testing

@testable import SettingsRepository

/// The Repository over the real DataStore, on the defaults double: the parameter values of each
/// effect are what the user set in one launch, and the next launch starts from them (hackathon #99).
/// Each `launch` builds a fresh pair, so nothing but the store carries a value over.
@Suite("Parameter persistence", .timeLimit(.minutes(1)))
struct ParameterPersistenceTests {
    private let glitch = EffectID.package("glitch")
    private let chromatic = EffectID.bundled("Chromatic Grain")

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

    @Test("the values one launch set are the values the next launch starts from, through a fresh DataStore")
    func valuesSurviveRelaunch() async {
        let store = InMemoryKeyValueStore()
        let values: [String: EffectParameterValue] = ["strength": .float(0.5), "inverted": .bool(false), "mode": .choice(1)]
        await launch(over: store).setParameterValues(values, of: glitch)
        #expect(await launch(over: store).parameterValues(of: glitch) == values)
    }

    @Test("two effects keep their values apart across a relaunch")
    func effectsStayApart() async {
        let store = InMemoryKeyValueStore()
        await launch(over: store).setParameterValues(["strength": .float(0.5)], of: glitch)
        await launch(over: store).setParameterValues(["mode": .choice(1)], of: chromatic)
        let next = launch(over: store)
        #expect(await next.parameterValues(of: glitch) == ["strength": .float(0.5)])
        #expect(await next.parameterValues(of: chromatic) == ["mode": .choice(1)])
    }

    @Test("a second write to one effect replaces the first across a relaunch")
    func lastWriteWins() async {
        let store = InMemoryKeyValueStore()
        let first = launch(over: store)
        await first.setParameterValues(["strength": .float(0.5)], of: glitch)
        await first.setParameterValues(["rings": .int(9)], of: glitch)
        #expect(await launch(over: store).parameterValues(of: glitch) == ["rings": .int(9)])
    }

    @Test("an effect nothing was written for reads [:] and writes nothing to the store")
    func nothingStored() async {
        let store = InMemoryKeyValueStore()
        #expect(await launch(over: store).parameterValues(of: glitch) == [:])
        #expect(store.writes.count == 0)
    }
}
