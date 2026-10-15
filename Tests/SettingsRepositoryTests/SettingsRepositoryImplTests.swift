import Dependencies
import Domain
import TestDoubles
import TestSupport
import Testing

@testable import SettingsRepository

/// A `Preferences` that holds one value and records every call that reached it. Private: the
/// Repository suite is its only user, and `InMemoryKeyValueStore` is the double one layer down.
private final class RecordingPreferences: Preferences, Sendable {
    private let stored: Locked<EffectID?>
    let reads = Collector<Void>()
    let writes = Collector<EffectID>()

    init(selected: EffectID? = nil) {
        stored = Locked(selected)
    }

    func selectedEffect() async -> EffectID? {
        reads.append(())
        return stored.current
    }

    func setSelectedEffect(_ id: EffectID) async {
        stored.set(id)
        writes.append(id)
    }
}

@Suite("SettingsRepositoryImpl", .timeLimit(.minutes(1)))
struct SettingsRepositoryImplTests {
    private func makeSubject(_ preferences: RecordingPreferences) -> SettingsRepositoryImpl {
        withDependencies {
            $0.preferences = preferences
        } operation: {
            SettingsRepositoryImpl()
        }
    }

    @Test("selectedEffect is what the DataStore answers, once per call", arguments: [nil, EffectID.bundled("Chromatic Grain"), .package("glitch")])
    func readsForward(selected: EffectID?) async {
        let preferences = RecordingPreferences(selected: selected)
        let subject = makeSubject(preferences)
        #expect(await subject.selectedEffect() == selected)
        #expect(preferences.reads.count == 1)
        #expect(await subject.selectedEffect() == selected)
        #expect(preferences.reads.count == 2)
        #expect(preferences.writes.count == 0, "reading writes nothing")
    }

    @Test("setSelectedEffect hands the id to the DataStore, once, and reads nothing")
    func writesForward() async {
        let preferences = RecordingPreferences()
        let subject = makeSubject(preferences)
        await subject.setSelectedEffect(.package("glitch"))
        #expect(preferences.writes.values == [.package("glitch")])
        #expect(preferences.reads.count == 0)
        #expect(await subject.selectedEffect() == .package("glitch"))
    }

    @Test("every choice reaches the DataStore, in order, even a repeated one")
    func everyChoice() async {
        let preferences = RecordingPreferences()
        let subject = makeSubject(preferences)
        let ids: [EffectID] = [.bundled("Chromatic Grain"), .package("glitch"), .package("glitch"), .bundled("Chromatic Grain")]
        for id in ids { await subject.setSelectedEffect(id) }
        #expect(preferences.writes.values == ids)
        #expect(await subject.selectedEffect() == .bundled("Chromatic Grain"))
    }
}
