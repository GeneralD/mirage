import Domain
import SettingsRepository
import TestDoubles
import Testing

@Suite("EmptySettings")
struct EmptySettingsTests {
    private let subject = EmptySettings()

    @Test("no effect was ever chosen")
    func nothingChosen() async {
        #expect(await subject.selectedEffect() == nil)
    }

    @Test("choosing one is not kept, and needs no DataStore: the unimplemented defaults would report one")
    func nothingIsKept() async {
        await subject.setSelectedEffect(.bundled("Chromatic Grain"))
        #expect(await subject.selectedEffect() == nil)
    }
}
