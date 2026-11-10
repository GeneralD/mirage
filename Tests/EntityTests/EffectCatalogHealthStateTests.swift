import Entity
import Testing

@Suite("Catalog state carries disabled reasons", .timeLimit(.minutes(1)))
struct EffectCatalogHealthStateTests {
    private let chromatic = EffectCatalogEntry(
        id: EffectID(origin: .bundled, key: "Chromatic Grain"), displayName: "Chromatic Grain", origin: .bundled, availability: .ready)
    private let glitch = EffectCatalogEntry(
        id: EffectID(origin: .package, key: "glitch"), displayName: "Glitch", origin: .package, availability: .ready)

    @Test("a state built with the three original arguments has nothing disabled and the GPU available")
    func defaultsMatchTheOriginalInit() {
        let original = EffectCatalogState(entries: [chromatic, glitch], selection: glitch.id, outcome: .prepared)
        #expect(original.disabled.isEmpty)
        #expect(original.isGPUUnavailable == false)
        #expect(
            original
                == EffectCatalogState(
                    entries: [chromatic, glitch], selection: glitch.id, outcome: .prepared, disabled: [:], isGPUUnavailable: false))
    }

    @Test("two states that differ only in their disabled reasons are not equal")
    func disabledReasonsAreCompared() {
        let plain = EffectCatalogState(entries: [chromatic, glitch], selection: glitch.id, outcome: .prepared)
        let disabled = EffectCatalogState(
            entries: [chromatic, glitch], selection: glitch.id, outcome: .prepared, disabled: [chromatic.id: .overBudget])
        #expect(plain != disabled)
    }

    @Test("two states that differ only in whether the GPU is unavailable are not equal")
    func gpuAvailabilityIsCompared() {
        let available = EffectCatalogState(entries: [chromatic, glitch], selection: glitch.id, outcome: .prepared)
        let unavailable = EffectCatalogState(
            entries: [chromatic, glitch], selection: glitch.id, outcome: .prepared, isGPUUnavailable: true)
        #expect(available != unavailable)
    }

    @Test("the disabled reasons and the GPU flag given to the init are read back unchanged")
    func disabledReasonsAndGPUFlagAreReadBack() {
        let reasons: [EffectID: EffectDisableReason] = [chromatic.id: .failure(.timeout), glitch.id: .overBudget]
        let state = EffectCatalogState(entries: [chromatic, glitch], selection: glitch.id, disabled: reasons, isGPUUnavailable: true)
        #expect(state.disabled == reasons)
        #expect(state.isGPUUnavailable)
    }

    @Test("a menu row has no Re-enable operation unless a title is given for it")
    func reenableTitleDefaultsToNil() {
        let row = EffectMenuItem(id: glitch.id, title: "Glitch", detail: nil, isSelected: true, isEnabled: false)
        #expect(row.reenableTitle == nil)
    }

    @Test("two menu rows that differ only in their Re-enable title are not equal")
    func reenableTitleIsCompared() {
        let plain = EffectMenuItem(id: glitch.id, title: "Glitch", detail: nil, isSelected: true, isEnabled: false)
        let reenable = EffectMenuItem(
            id: glitch.id, title: "Glitch", detail: nil, isSelected: true, isEnabled: false, reenableTitle: "Re-enable")
        #expect(plain != reenable)
    }
}
