import Dependencies
import Domain
import SettingsUseCase
import TestDoubles
import Testing

@Suite("SettingsUseCaseImpl hotkeys", .timeLimit(.minutes(1)))
struct SettingsUseCaseHotkeyTests {
    private func makeSubject(_ repository: FakeSettingsRepository, _ log: RecordingLog) -> SettingsUseCaseImpl {
        withDependencies {
            $0.settingsRepository = repository
            $0.developerLog = log
        } operation: {
            SettingsUseCaseImpl()
        }
    }

    @Test("applyHotkeys with the flag on registers the default bindings once and answers active when all of them register")
    func enabledRegistersDefaultsOnce() async {
        let repository = FakeSettingsRepository(hotkeysEnabled: true)
        let log = RecordingLog()
        let status = await makeSubject(repository, log).applyHotkeys()
        #expect(repository.registeredBindings.values == [defaultHotkeyBindings])
        #expect(status == .active)
        #expect(log.entries.values.isEmpty)
    }

    @Test("applyHotkeys with the flag off releases the bindings without registering, answers off, and logs nothing")
    func disabledReleasesWithoutRegistering() async {
        let repository = FakeSettingsRepository(hotkeysEnabled: false)
        let log = RecordingLog()
        let status = await makeSubject(repository, log).applyHotkeys()
        #expect(repository.registeredBindings.values.isEmpty)
        #expect(repository.unregisters.count == 1)
        #expect(status == .off)
        #expect(log.entries.values.isEmpty)
    }

    @Test("applyHotkeys logs one developer line, hotkeys not available with the refused actions, when a binding is refused")
    func refusedBindingIsLoggedOnce() async {
        let repository = FakeSettingsRepository(hotkeysEnabled: true)
        repository.script(
            registration: HotkeyRegistration(registered: [.toggleBypass, .previousEffect], failed: [.nextEffect]))
        let log = RecordingLog()
        let status = await makeSubject(repository, log).applyHotkeys()
        #expect(status == .conflicted([.nextEffect]))
        #expect(log.entries.values == [LogEntry(.app, "hotkeys not available: nextEffect")])
    }

    @Test("setHotkeysEnabled(false) stores the flag as off, releases the bindings, and answers off")
    func turningOffStoresThenReleases() async {
        let repository = FakeSettingsRepository(hotkeysEnabled: true)
        let status = await makeSubject(repository, RecordingLog()).setHotkeysEnabled(false)
        #expect(repository.hotkeyFlagWrites.values == [false])
        #expect(repository.registeredBindings.values.isEmpty)
        #expect(repository.unregisters.count == 1)
        #expect(status == .off)
    }

    @Test("setHotkeysEnabled(true) stores the flag as on, registers the default bindings, and answers active")
    func turningOnStoresThenRegisters() async {
        let repository = FakeSettingsRepository(hotkeysEnabled: false)
        let status = await makeSubject(repository, RecordingLog()).setHotkeysEnabled(true)
        #expect(repository.hotkeyFlagWrites.values == [true])
        #expect(repository.registeredBindings.values == [defaultHotkeyBindings])
        #expect(status == .active)
    }

    @Test("setHotkeysEnabled logs a refused binding once, because it applies through applyHotkeys")
    func turningOnLogsRefusalOnce() async {
        let repository = FakeSettingsRepository(hotkeysEnabled: false)
        repository.script(
            registration: HotkeyRegistration(registered: [.toggleBypass, .previousEffect], failed: [.nextEffect]))
        let log = RecordingLog()
        let status = await makeSubject(repository, log).setHotkeysEnabled(true)
        #expect(status == .conflicted([.nextEffect]))
        #expect(log.entries.values == [LogEntry(.app, "hotkeys not available: nextEffect")])
    }

    @Test("settings reads the launch at login status, the stored flag and the hotkeys status, and registers nothing")
    func settingsCombinesWithoutRegistering() async {
        let repository = FakeSettingsRepository(hotkeysEnabled: true, launchAtLogin: .needsApproval)
        let subject = makeSubject(repository, RecordingLog())
        _ = await subject.applyHotkeys()
        let state = await subject.settings()
        #expect(state == SettingsState(launchAtLogin: .needsApproval, hotkeysEnabled: true, hotkeys: .active))
        #expect(repository.registeredBindings.values.count == 1)
    }

    @Test("settings with the flag stored off answers hotkeysEnabled false and hotkeys off")
    func settingsWithFlagOffAnswersOff() async {
        let repository = FakeSettingsRepository(hotkeysEnabled: false, launchAtLogin: .off)
        let state = await makeSubject(repository, RecordingLog()).settings()
        #expect(state == SettingsState(launchAtLogin: .off, hotkeysEnabled: false, hotkeys: .off))
    }

    @Test("resetAll turns the flag back on first, so the default bindings are registered after the reset")
    func resetRegistersDefaultsAfterFlagIsRestored() async {
        let repository = FakeSettingsRepository(hotkeysEnabled: false, schemaVersion: .version(7), launchAtLogin: .on)
        await makeSubject(repository, RecordingLog()).resetAll()
        #expect(await repository.hotkeysEnabled() == true)
        #expect(repository.registeredBindings.values == [defaultHotkeyBindings])
        #expect(repository.unregisters.values.isEmpty)
    }

    @Test("hotkeyPresses returns the repository's stream, and a press reaches it")
    func pressReachesReturnedStream() async {
        let repository = FakeSettingsRepository()
        let stream = await makeSubject(repository, RecordingLog()).hotkeyPresses()
        repository.pressHotkey(.nextEffect)
        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == HotkeyAction.nextEffect)
    }
}

@Suite("FakeSettingsUseCase hotkeys", .timeLimit(.minutes(1)))
struct FakeSettingsUseCaseHotkeyTests {
    @Test("a press reaches the stream hotkeyPresses returned last, and a later hotkeyPresses ends the earlier one")
    func pressGoesToNewestStream() async {
        let fake = FakeSettingsUseCase()
        let first = await fake.hotkeyPresses()
        var firstIterator = first.makeAsyncIterator()
        let second = await fake.hotkeyPresses()
        var secondIterator = second.makeAsyncIterator()
        fake.press(.previousEffect)
        #expect(await secondIterator.next() == HotkeyAction.previousEffect)
        #expect(await firstIterator.next() == nil)
        #expect(fake.streamRequests.count == 2)
    }

    @Test("each hotkey method takes its name into calls, in call order, and counts its own requests")
    func hotkeyMethodsRecordCalls() async {
        let fake = FakeSettingsUseCase()
        _ = await fake.settings()
        _ = await fake.applyHotkeys()
        _ = await fake.setHotkeysEnabled(false)
        _ = await fake.hotkeyPresses()
        #expect(fake.calls.values == ["settings", "applyHotkeys", "setHotkeysEnabled", "hotkeyPresses"])
        #expect(fake.applications.count == 1)
        #expect(fake.hotkeyFlagRequests.values == [false])
        #expect(fake.streamRequests.count == 1)
    }

    @Test("script answers what settings and the hotkey methods report, from then on")
    func scriptAnswersFromThenOn() async {
        let fake = FakeSettingsUseCase(launchAtLogin: .on)
        #expect(await fake.settings() == SettingsState(launchAtLogin: .on))
        fake.script(settings: SettingsState(launchAtLogin: .needsApproval, hotkeysEnabled: false, hotkeys: .active))
        #expect(
            await fake.settings()
                == SettingsState(launchAtLogin: .needsApproval, hotkeysEnabled: false, hotkeys: .active))
        #expect(await fake.applyHotkeys() == .off)
        fake.script(hotkeyStatus: .conflicted([.previousEffect]))
        #expect(await fake.applyHotkeys() == .conflicted([.previousEffect]))
        #expect(await fake.setHotkeysEnabled(true) == .conflicted([.previousEffect]))
    }
}
