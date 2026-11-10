import Dependencies
import Domain
import TestDoubles
import TestSupport
import Testing

@testable import SettingsRepository

/// One `setParameterValues` call as the double received it. Private, like `RecordingPreferences`.
private struct RecordedParameterWrite: Sendable {
    let id: EffectID
    let values: [String: EffectParameterValue]
}

/// A `Preferences` that holds one value and records every call that reached it. Private: the
/// Repository suite is its only user, and `InMemoryKeyValueStore` is the double one layer down.
private final class RecordingPreferences: Preferences, Sendable {
    private let stored: Locked<EffectID?>
    private let disabled: Locked<[DisabledEffectRecord]>
    private let parameters: Locked<[EffectID: [String: EffectParameterValue]]>
    let reads = Collector<Void>()
    let writes = Collector<EffectID>()
    let disabledReads = Collector<Void>()
    let disabledWrites = Collector<[DisabledEffectRecord]>()
    let hotkeyReads = Collector<Void>()
    let hotkeyWrites = Collector<Bool>()
    let parameterReads = Collector<EffectID>()
    let parameterWrites = Collector<RecordedParameterWrite>()

    init(
        selected: EffectID? = nil, disabled: [DisabledEffectRecord] = [],
        parameters: [EffectID: [String: EffectParameterValue]] = [:]
    ) {
        stored = Locked(selected)
        self.disabled = Locked(disabled)
        self.parameters = Locked(parameters)
    }

    func selectedEffect() async -> EffectID? {
        reads.append(())
        return stored.current
    }

    func setSelectedEffect(_ id: EffectID) async {
        stored.set(id)
        writes.append(id)
    }

    func disabledEffects() async -> [DisabledEffectRecord] {
        disabledReads.append(())
        return disabled.current
    }

    func setDisabledEffects(_ records: [DisabledEffectRecord]) async {
        disabled.set(records)
        disabledWrites.append(records)
    }

    func hotkeysEnabled() async -> Bool {
        hotkeyReads.append(())
        return true
    }

    func setHotkeysEnabled(_ on: Bool) async {
        hotkeyWrites.append(on)
    }

    func parameterValues(of id: EffectID) async -> [String: EffectParameterValue] {
        parameterReads.append(id)
        return parameters.current[id] ?? [:]
    }

    func setParameterValues(_ values: [String: EffectParameterValue], of id: EffectID) async {
        parameters.withLock { $0[id] = values }
        parameterWrites.append(RecordedParameterWrite(id: id, values: values))
    }
}

@Suite("SettingsRepositoryImpl", .timeLimit(.minutes(1)))
struct SettingsRepositoryImplTests {
    private let glitch = DisabledEffectRecord(
        id: .package("glitch"), fingerprint: EffectFingerprint(value: "f1"), reason: .failure(.timeout), retriesAutomatically: false)
    private let ripple = DisabledEffectRecord(
        id: .package("ripple"), fingerprint: EffectFingerprint(value: "f2"), reason: .overBudget, retriesAutomatically: true)

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

    @Test("disabledEffects is what the DataStore answers, once per call, and reads no selection")
    func disabledReadsForward() async {
        let preferences = RecordingPreferences(disabled: [glitch, ripple])
        let subject = makeSubject(preferences)
        #expect(await subject.disabledEffects() == [glitch, ripple])
        #expect(preferences.disabledReads.count == 1)
        #expect(await subject.disabledEffects() == [glitch, ripple])
        #expect(preferences.disabledReads.count == 2)
        #expect(preferences.reads.count == 0, "reading the records reads no selection")
        #expect(preferences.disabledWrites.count == 0, "reading writes nothing")
    }

    @Test("setDisabledEffects hands the array to the DataStore once, as it came, and reads nothing")
    func disabledWritesForward() async {
        let preferences = RecordingPreferences()
        let subject = makeSubject(preferences)
        let records = [ripple, glitch, ripple]  // unsorted, with a repeat: the Repository fixes neither
        await subject.setDisabledEffects(records)
        #expect(preferences.disabledWrites.values == [records])
        #expect(preferences.disabledReads.count == 0)
        #expect(preferences.reads.count == 0)
        #expect(preferences.writes.count == 0, "the records do not touch the selection")
        #expect(await subject.disabledEffects() == records)
    }

    @Test("an empty array is handed over as an empty array, not skipped")
    func emptyDisabledWrite() async {
        let preferences = RecordingPreferences(disabled: [glitch])
        let subject = makeSubject(preferences)
        await subject.setDisabledEffects([])
        #expect(preferences.disabledWrites.values == [[]])
        #expect(await subject.disabledEffects() == [])
    }

    @Test("every disabled write reaches the DataStore, in order, even a repeated one")
    func everyDisabledWrite() async {
        let preferences = RecordingPreferences()
        let subject = makeSubject(preferences)
        let batches: [[DisabledEffectRecord]] = [[glitch], [glitch, ripple], [glitch], []]
        for records in batches { await subject.setDisabledEffects(records) }
        #expect(preferences.disabledWrites.values == batches)
        #expect(await subject.disabledEffects() == [])
    }

    @Test("choosing an effect leaves the disabled records alone, and recording a disable leaves the choice alone")
    func separateSettings() async {
        let preferences = RecordingPreferences(selected: .package("glitch"), disabled: [glitch])
        let subject = makeSubject(preferences)
        await subject.setSelectedEffect(.bundled("Chromatic Grain"))
        #expect(await subject.disabledEffects() == [glitch])
        await subject.setDisabledEffects([ripple])
        #expect(await subject.selectedEffect() == .bundled("Chromatic Grain"))
    }
}
