import Domain
import TestDoubles
import Testing

@Suite("FakeSettingsRepository system", .timeLimit(.minutes(1)))
struct FakeSettingsRepositorySystemTests {
    @Test("setLaunchAtLogin leaves an unavailable status alone and returns it, and still records the request")
    func unavailableStaysPut() {
        let settings = FakeSettingsRepository(launchAtLogin: .unavailable)
        #expect(settings.setLaunchAtLogin(true) == .unavailable)
        #expect(settings.launchAtLoginStatus == .unavailable)
        #expect(settings.launchRequests.values == [true])
    }

    @Test("setLaunchAtLogin answers on or off from any other status, and reads back the same answer")
    func otherStatusesFollowTheRequest() {
        let settings = FakeSettingsRepository(launchAtLogin: .needsApproval)
        #expect(settings.setLaunchAtLogin(true) == .on)
        #expect(settings.setLaunchAtLogin(false) == .off)
        #expect(settings.launchAtLoginStatus == .off)
        #expect(settings.launchRequests.values == [true, false])
    }

    @Test("openLoginItemsSettings records each call and changes no status")
    func openRecordsOnly() {
        let settings = FakeSettingsRepository(launchAtLogin: .on)
        settings.openLoginItemsSettings()
        #expect(settings.settingsOpens.count == 1)
        #expect(settings.launchAtLoginStatus == .on)
    }

    @Test("registerHotkeys answers what script(registration:) set once, then that every binding is registered")
    func scriptIsUsedOnce() async {
        let settings = FakeSettingsRepository()
        settings.script(registration: HotkeyRegistration(registered: [.toggleBypass], failed: [.nextEffect]))
        #expect(
            await settings.registerHotkeys(defaultHotkeyBindings)
                == HotkeyRegistration(registered: [.toggleBypass], failed: [.nextEffect]))
        #expect(
            await settings.registerHotkeys(defaultHotkeyBindings)
                == HotkeyRegistration(registered: [.toggleBypass, .nextEffect, .previousEffect]))
        #expect(settings.registeredBindings.values == [defaultHotkeyBindings, defaultHotkeyBindings])
    }

    @Test("unregisterHotkeys records the call and leaves the registration empty")
    func unregisterClears() async {
        let settings = FakeSettingsRepository()
        _ = await settings.registerHotkeys(defaultHotkeyBindings)
        await settings.unregisterHotkeys()
        #expect(settings.unregisters.count == 1)
        #expect(await settings.hotkeyRegistration == .empty)
    }

    @Test("hotkeyPresses called again ends the stream returned before, and a press goes to the newest one")
    func newerStreamEndsOlder() async {
        let settings = FakeSettingsRepository()
        let first = await settings.hotkeyPresses()
        let second = await settings.hotkeyPresses()
        settings.pressHotkey(.nextEffect)
        var firstIterator = first.makeAsyncIterator()
        #expect(await firstIterator.next() == nil, "the stream returned before is ended and delivers nothing")
        var secondIterator = second.makeAsyncIterator()
        #expect(await secondIterator.next() == HotkeyAction.nextEffect)
    }
}
