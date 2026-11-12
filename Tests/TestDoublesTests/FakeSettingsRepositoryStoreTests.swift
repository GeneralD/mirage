import Domain
import TestDoubles
import TestSupport
import Testing

@Suite("FakeSettingsRepository store", .timeLimit(.minutes(1)))
struct FakeSettingsRepositoryStoreTests {
    private let glitch = DisabledEffectRecord(
        id: .package("glitch"), fingerprint: EffectFingerprint(value: "f1"), reason: .failure(.timeout), retriesAutomatically: false)

    @Test("with nothing given, the hotkeys flag is on, the schema version is missing, and nothing is recorded")
    func defaults() async {
        let settings = FakeSettingsRepository()
        #expect(await settings.hotkeysEnabled() == true)
        #expect(await settings.storedSchemaVersion() == .missing)
        #expect(settings.hotkeyFlagWrites.count == 0)
        #expect(settings.stamps.count == 0)
        #expect(settings.resets.count == 0)
    }

    @Test("the flag and the version it was made with are what the reads answer, and they are not writes")
    func initialValues() async {
        let settings = FakeSettingsRepository(hotkeysEnabled: false, schemaVersion: .version(2))
        #expect(await settings.hotkeysEnabled() == false)
        #expect(await settings.storedSchemaVersion() == .version(2))
        #expect(settings.hotkeyFlagWrites.count == 0)
        #expect(settings.stamps.count == 0)
    }

    @Test("setHotkeysEnabled replaces what hotkeysEnabled answers, and each value is recorded in call order")
    func flagWrites() async {
        let settings = FakeSettingsRepository()
        await settings.setHotkeysEnabled(false)
        #expect(await settings.hotkeysEnabled() == false)
        await settings.setHotkeysEnabled(true)
        #expect(await settings.hotkeysEnabled() == true)
        #expect(settings.hotkeyFlagWrites.values == [false, true])
    }

    @Test("stampSchemaVersion makes storedSchemaVersion answer .version, and each stamp is recorded in call order")
    func stamps() async {
        let settings = FakeSettingsRepository()
        await settings.stampSchemaVersion(1)
        await settings.stampSchemaVersion(3)
        #expect(await settings.storedSchemaVersion() == .version(3))
        #expect(settings.stamps.values == [1, 3])
    }

    @Test("resetAll puts the selection, the disabled records, the flag and the version back to their defaults, and records one reset")
    func resetRestoresDefaults() async {
        let settings = FakeSettingsRepository(
            selected: .package("glitch"), disabled: [glitch], hotkeysEnabled: false, schemaVersion: .version(1))
        await settings.resetAll()
        #expect(await settings.selectedEffect() == nil)
        #expect(await settings.disabledEffects() == [])
        #expect(await settings.hotkeysEnabled() == true)
        #expect(await settings.storedSchemaVersion() == .missing)
        #expect(settings.resets.count == 1)
    }

    @Test("the selection-only init behaves as before: the flag is on and the version is missing")
    func selectedOnlyInitUnchanged() async {
        let settings = FakeSettingsRepository(selected: .bundled("Chromatic Grain"))
        #expect(await settings.selectedEffect() == .bundled("Chromatic Grain"))
        #expect(await settings.hotkeysEnabled() == true)
        #expect(await settings.storedSchemaVersion() == .missing)
    }

    @Test("held selection calls do not park the flag, the version or the reset, which answer at once")
    func heldSelectionDoesNotParkNewMethods() async {
        let settings = FakeSettingsRepository()
        settings.holdReads()
        settings.holdWrites()
        await settings.setHotkeysEnabled(false)
        await settings.stampSchemaVersion(1)
        await settings.resetAll()
        #expect(settings.heldRequests.count == 0)
        #expect(settings.pendingCount == 0)
    }
}
