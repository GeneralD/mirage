import Domain
import PreferencesDataStore
import TestDoubles
import Testing

@Suite("EmptyPreferences")
struct EmptyPreferencesTests {
    private let subject = EmptyPreferences()

    @Test("no effect was ever chosen")
    func nothingChosen() async {
        #expect(await subject.selectedEffect() == nil)
    }

    @Test("choosing one is not kept, and needs no gateway: the unimplemented defaults would report one")
    func nothingIsKept() async {
        await subject.setSelectedEffect(.package("glitch"))
        #expect(await subject.selectedEffect() == nil)
    }
}
