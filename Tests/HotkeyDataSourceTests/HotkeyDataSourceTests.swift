import Dependencies
import Domain
import HotkeyDataSource
import TestDoubles
import TestSupport
import Testing

/// `HotkeyDataSourceImpl` over `FakeHotkeyGateway` and `RecordingLog`. The test is the OS:
/// `gateway.press(id:)` delivers a press of a hotkey the subject registered, and nothing happens
/// on its own. Presses are awaited through the stream itself, which buffers them, so no test waits
/// on a timer.
@MainActor
@Suite("HotkeyDataSourceImpl", .timeLimit(.minutes(1)))
struct HotkeyDataSourceTests {
    private let gateway = FakeHotkeyGateway()
    private let log = RecordingLog()
    private let subject: HotkeyDataSourceImpl

    init() {
        let gateway = gateway
        let log = log
        subject = withDependencies {
            $0.hotkeyGateway = gateway
            $0.errorLog = log
        } operation: {
            HotkeyDataSourceImpl()
        }
    }

    // MARK: register

    @Test("register(defaultHotkeyBindings) installs the press observer once and registers ids 1, 2 and 3 with their own keys")
    func registerInstallsObserverAndRegistersDefaults() {
        #expect(subject.registration == .empty, "nothing is registered before the first register")

        let result = subject.register(defaultHotkeyBindings)

        #expect(gateway.observations.count == 1)
        #expect(
            gateway.registrations.values == [
                .init(id: 1, keyCode: 11, modifiers: 6400),
                .init(id: 2, keyCode: 124, modifiers: 6400),
                .init(id: 3, keyCode: 123, modifiers: 6400),
            ])
        #expect(result == HotkeyRegistration(registered: [.toggleBypass, .nextEffect, .previousEffect], failed: []))
        #expect(subject.registration == result)
    }

    @Test("a binding the OS refuses is released at once, listed in failed, logged, and the others still register")
    func refusedBindingIsReleasedReportedAndLogged() {
        gateway.script(status: -9878, forID: 2)

        let result = subject.register(defaultHotkeyBindings)

        #expect(result == HotkeyRegistration(registered: [.toggleBypass, .previousEffect], failed: [.nextEffect]))
        #expect(gateway.liveHandleCount == 3, "the observer and the two accepted hotkeys; the refused one is already released")
        #expect(gateway.doubleReleaseCount == 0)
        #expect(log.messages(in: .app) == ["hotkey nextEffect not registered (status -9878)"])
    }

    @Test("an observer the OS refuses registers no hotkey, fails every action and leaves no handle behind")
    func refusedObserverRegistersNothing() {
        gateway.failObserve(with: -50)

        let result = subject.register(defaultHotkeyBindings)

        #expect(result == HotkeyRegistration(registered: [], failed: [.toggleBypass, .nextEffect, .previousEffect]))
        #expect(gateway.registrations.count == 0, "no hotkey is asked for when the observer is refused")
        #expect(gateway.liveHandleCount == 0, "the refused observer is released")
        #expect(gateway.doubleReleaseCount == 0)
        #expect(log.messages(in: .app) == ["hotkey press observer not installed (status -50)"])
    }

    @Test("after a refused observer, the next register asks for the observer again and registers")
    func refusedObserverIsAskedAgain() {
        gateway.failObserve(with: -50)
        _ = subject.register(defaultHotkeyBindings)
        gateway.failObserve(with: 0)

        let result = subject.register(defaultHotkeyBindings)

        #expect(gateway.observations.count == 2)
        #expect(result == HotkeyRegistration(registered: [.toggleBypass, .nextEffect, .previousEffect], failed: []))
    }

    @Test("a second register releases the hotkeys of the first and installs no second observer")
    func secondRegisterReleasesFirstAndKeepsObserver() {
        _ = subject.register(defaultHotkeyBindings)

        let second = subject.register(defaultHotkeyBindings)

        #expect(gateway.observations.count == 1)
        #expect(gateway.liveHandleCount == 4, "the observer and the three hotkeys of the second register; the first three are released")
        #expect(gateway.doubleReleaseCount == 0)
        #expect(subject.registration == second)
    }

    // MARK: presses

    @Test("a press of a registered id reaches the stream as the action bound to it")
    func pressOfRegisteredIdReachesStream() async {
        let stream = subject.presses()
        _ = subject.register(defaultHotkeyBindings)
        var iterator = stream.makeAsyncIterator()

        #expect(gateway.press(id: 1))

        #expect(await iterator.next() == .toggleBypass)
    }

    @Test("an id that no action has is dropped, and the next press of a registered id still arrives")
    func unknownIdIsDroppedBeforeSentinel() async {
        _ = subject.register(defaultHotkeyBindings)
        let stream = subject.presses()
        let unknown = gateway.register(id: 99, keyCode: 0, modifiers: 0)

        #expect(gateway.press(id: 99), "the observer hears id 99, so the drop is the subject's doing")
        #expect(gateway.press(id: 1))
        unknown.release()

        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == .toggleBypass, "nothing was buffered for id 99 before the sentinel")
    }

    @Test("a press with no presses() stream open is dropped and not replayed to the next stream")
    func pressWithNoStreamIsDropped() async {
        _ = subject.register(defaultHotkeyBindings)
        #expect(gateway.press(id: 1))

        let stream = subject.presses()
        #expect(gateway.press(id: 3))

        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == .previousEffect)
    }

    @Test("presses() called again ends the stream returned before, and the new stream receives the presses")
    func secondPressesCallEndsFirstStream() async {
        let earlier = subject.presses()
        let current = subject.presses()
        _ = subject.register(defaultHotkeyBindings)
        #expect(gateway.press(id: 2))

        var earlierIterator = earlier.makeAsyncIterator()
        var currentIterator = current.makeAsyncIterator()
        #expect(await earlierIterator.next() == nil, "the stream returned before the second call has ended")
        #expect(await currentIterator.next() == .nextEffect)
    }

    // MARK: unregisterAll

    @Test("unregisterAll releases every hotkey, sets registration back to empty, and a press of a released id does not arrive")
    func unregisterAllReleasesHotkeysAndKeepsObserver() async {
        _ = subject.register(defaultHotkeyBindings)
        let stream = subject.presses()

        subject.unregisterAll()

        #expect(subject.registration == .empty)
        #expect(gateway.liveHandleCount == 1, "only the observer is left")
        #expect(gateway.press(id: 1) == false, "nothing holds id 1 any more")

        _ = subject.register([HotkeyBinding(action: .previousEffect, keyCode: 123, modifiers: 6400)])
        #expect(gateway.press(id: 3))

        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == .previousEffect, "the press of id 1 after unregisterAll was not delivered")
        #expect(gateway.observations.count == 1, "the observer was kept, not installed again")
    }
}
