import Domain
import TestDoubles
import Testing

@Suite("EffectCatalogState fixtures", .timeLimit(.minutes(1)))
struct EffectFixturesStateTests {
    private let chromatic = EffectCatalogEntry.fixture(.bundled("Chromatic Grain"))

    @Test("a fixture given no disabled reasons and no GPU flag equals the state of the three original arguments")
    func defaultsMatchTheOriginalInit() {
        #expect(EffectCatalogState.fixture([chromatic]) == EffectCatalogState(entries: [chromatic], selection: chromatic.id))
    }

    @Test("a fixture passes its disabled reasons through to the state unchanged")
    func disabledReasonsAreReadBack() {
        let state = EffectCatalogState.fixture([chromatic], disabled: [chromatic.id: .overBudget])
        #expect(state.disabled == [chromatic.id: .overBudget])
    }

    @Test("a fixture passes its GPU flag through to the state unchanged")
    func gpuFlagIsReadBack() {
        #expect(EffectCatalogState.fixture([chromatic], isGPUUnavailable: true).isGPUUnavailable)
    }
}
