import Entity
import Testing

@Suite("HotkeyAction")
struct HotkeyActionTests {
    @Test("the raw values are 1, 2 and 3, allCases has three cases, and rawValue 0 is nil")
    func rawValuesAreTheCarbonIDsFromOne() {
        #expect(HotkeyAction.allCases.map(\.rawValue) == [1, 2, 3])
        #expect(HotkeyAction.allCases.count == 3)
        #expect(HotkeyAction(rawValue: 0) == nil)
    }

    @Test("defaultHotkeyBindings has exactly one binding per action and no two share a (keyCode, modifiers) pair")
    func defaultBindingsHaveOneKeyPerActionAndNoSharedCombination() {
        let bindings = defaultHotkeyBindings
        let countsPerAction = HotkeyAction.allCases.map { action in bindings.filter { $0.action == action }.count }
        #expect(countsPerAction == [1, 1, 1])
        #expect(Set(bindings.map { [$0.keyCode, $0.modifiers] }).count == bindings.count)
        // The values reach the OS and the stored settings, so a careless change must fail here.
        #expect(
            bindings == [
                HotkeyBinding(action: .toggleBypass, keyCode: 11, modifiers: 6400),
                HotkeyBinding(action: .nextEffect, keyCode: 124, modifiers: 6400),
                HotkeyBinding(action: .previousEffect, keyCode: 123, modifiers: 6400),
            ])
    }
}
