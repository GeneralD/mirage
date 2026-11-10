import Dependencies
import Domain
import TestDoubles
import TestSupport
import Testing

@testable import SettingsRepository

/// The Repository over the system's login item and hotkeys (hackathon #183): each call reaches the port
/// it names once, and the answer comes back the way that port gave it, with nothing decided on the way.
@Suite("SettingsRepositoryImpl system routing", .timeLimit(.minutes(1)))
struct SystemRoutingTests {
    private func makeSubject(loginItem: FakeLoginItem, hotkeys: FakeHotkeys) -> SettingsRepositoryImpl {
        withDependencies {
            $0.loginItem = loginItem
            $0.hotkeys = hotkeys
        } operation: {
            SettingsRepositoryImpl()
        }
    }

    @Test("launchAtLoginStatus is what LoginItem reports, and reading it requests no change")
    func statusForwards() {
        let loginItem = FakeLoginItem(status: .needsApproval)
        let subject = makeSubject(loginItem: loginItem, hotkeys: FakeHotkeys())
        #expect(subject.launchAtLoginStatus == .needsApproval)
        #expect(loginItem.requests.count == 0, "reading the status is not a request")
    }

    @Test("setLaunchAtLogin(true) calls LoginItem.setEnabled(true) once and returns the status it answered, not an echo of the request")
    func toggleForwards() {
        let loginItem = FakeLoginItem(status: .needsApproval)
        let subject = makeSubject(loginItem: loginItem, hotkeys: FakeHotkeys())
        #expect(subject.setLaunchAtLogin(true) == .needsApproval)
        #expect(loginItem.requests.values == [true])
        #expect(loginItem.status == .needsApproval)
    }

    @Test("openLoginItemsSettings reaches LoginItem once and makes no login item request")
    func openForwards() {
        let loginItem = FakeLoginItem(status: .off)
        let subject = makeSubject(loginItem: loginItem, hotkeys: FakeHotkeys())
        subject.openLoginItemsSettings()
        #expect(loginItem.settingsOpens.count == 1)
        #expect(loginItem.requests.count == 0)
    }

    @Test("registerHotkeys hands the bindings to Hotkeys once and returns its registration, and hotkeyRegistration reads the same value back")
    func registerForwards() async {
        let hotkeys = FakeHotkeys()
        let scripted = HotkeyRegistration(registered: [.toggleBypass], failed: [.nextEffect])
        hotkeys.script(scripted)
        let subject = makeSubject(loginItem: FakeLoginItem(), hotkeys: hotkeys)
        let registration = await subject.registerHotkeys(defaultHotkeyBindings)
        #expect(registration == scripted)
        #expect(hotkeys.registrations.values == [defaultHotkeyBindings])
        #expect(await subject.hotkeyRegistration == scripted)
    }

    @Test("unregisterHotkeys calls Hotkeys.unregisterAll once, and hotkeyRegistration reads empty afterwards")
    func unregisterForwards() async {
        let hotkeys = FakeHotkeys()
        let subject = makeSubject(loginItem: FakeLoginItem(), hotkeys: hotkeys)
        _ = await subject.registerHotkeys(defaultHotkeyBindings)
        #expect(await subject.hotkeyRegistration == HotkeyRegistration(registered: [.toggleBypass, .nextEffect, .previousEffect]))
        await subject.unregisterHotkeys()
        #expect(hotkeys.unregisters.count == 1)
        #expect(await subject.hotkeyRegistration == .empty)
    }

    @Test("a press made after hotkeyPresses reaches the stream it returned, which Hotkeys opened once")
    func pressesForward() async {
        let hotkeys = FakeHotkeys()
        let subject = makeSubject(loginItem: FakeLoginItem(), hotkeys: hotkeys)
        let stream = await subject.hotkeyPresses()
        hotkeys.press(.toggleBypass)
        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == HotkeyAction.toggleBypass)
        #expect(hotkeys.streamRequests.count == 1)
    }
}
