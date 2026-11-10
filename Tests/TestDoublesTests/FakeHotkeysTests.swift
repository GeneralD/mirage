import Domain
import TestDoubles
import TestSupport
import Testing

@MainActor
@Suite("FakeHotkeys", .timeLimit(.minutes(1)))
struct FakeHotkeysTests {
    private let hotkeys = FakeHotkeys()

    @Test("press reaches only the stream presses() returned last, and the stream before it has ended")
    func pressReachesOnlyTheCurrentStream() async {
        let earlier = hotkeys.presses()
        let current = hotkeys.presses()

        hotkeys.press(.nextEffect)

        var earlierIterator = earlier.makeAsyncIterator()
        var currentIterator = current.makeAsyncIterator()
        #expect(await earlierIterator.next() == nil)
        #expect(await currentIterator.next() == .nextEffect)
    }

    @Test("a press with no stream open goes nowhere, and a stream opened after it does not replay it")
    func pressWithNoStreamGoesNowhere() async {
        hotkeys.press(.toggleBypass)

        let stream = hotkeys.presses()
        hotkeys.press(.previousEffect)

        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == .previousEffect)
    }

    @Test("script answers the next register once, and that answer is what registration becomes")
    func scriptedAnswerIsHandedBackOnce() {
        let scripted = HotkeyRegistration(registered: [.toggleBypass], failed: [.nextEffect, .previousEffect])

        hotkeys.script(scripted)

        #expect(hotkeys.register(defaultHotkeyBindings) == scripted)
        #expect(hotkeys.registration == scripted)
        #expect(
            hotkeys.register(defaultHotkeyBindings) == HotkeyRegistration(registered: [.toggleBypass, .nextEffect, .previousEffect]),
            "the script is used once, and the register after it registers every binding")
    }

    @Test("register records the bindings of every call, in order")
    func registerIsRecorded() {
        _ = hotkeys.register(defaultHotkeyBindings)
        _ = hotkeys.register([HotkeyBinding(action: .nextEffect, keyCode: 124, modifiers: 6400)])

        #expect(hotkeys.registrations.values == [defaultHotkeyBindings, [HotkeyBinding(action: .nextEffect, keyCode: 124, modifiers: 6400)]])
    }

    @Test("unregisterAll sets registration back to empty and is recorded in unregisters")
    func unregisterAllIsRecorded() {
        _ = hotkeys.register(defaultHotkeyBindings)

        hotkeys.unregisterAll()

        #expect(hotkeys.registration == .empty)
        #expect(hotkeys.unregisters.count == 1)
    }

    @Test("every presses() call is recorded in streamRequests")
    func pressesCallsAreRecorded() {
        _ = hotkeys.presses()
        _ = hotkeys.presses()

        #expect(hotkeys.streamRequests.count == 2)
    }
}
