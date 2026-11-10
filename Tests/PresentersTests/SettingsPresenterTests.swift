import Combine
import Dependencies
import Domain
import TestDoubles
import TestSupport
import Testing

@testable import Presenters

@MainActor
@Suite("SettingsPresenter", .timeLimit(.minutes(1)))
struct SettingsPresenterTests {
    private let needsApproval = "Waiting for approval in System Settings → General → Login Items."

    // MARK: - Start and stop

    @Test("before start the presenter shows its defaults, and the Interactor is asked for nothing")
    func defaultsBeforeStart() {
        let rig = SettingsRig()

        #expect(rig.presenter.launchesAtLogin == false)
        #expect(rig.presenter.canChangeLaunchAtLogin == true)
        #expect(rig.presenter.launchAtLoginNote == nil)
        #expect(rig.presenter.canOpenLoginItemsSettings == false)
        #expect(rig.presenter.hotkeysEnabled == true)
        #expect(rig.presenter.hotkeyNote == nil)
        #expect(rig.presenter.isResetting == false)
        #expect(rig.presenter.isConfirmingReset == false)
        #expect(rig.interactor.refreshes.count == 0)
    }

    @Test("start subscribes and refreshes once, and a second start does nothing")
    func startRefreshesOnce() {
        let rig = SettingsRig()

        rig.presenter.start()
        rig.presenter.start()
        rig.presenter.stop()

        #expect(rig.interactor.refreshes.count == 1)
        #expect(rig.interactor.stateCancels.count == 1, "one subscription was made, and stop ended it")
    }

    @Test("stop cancels the subscription and closes the reset confirmation, and the values it has stay")
    func stopKeepsTheValues() async {
        let rig = SettingsRig()
        rig.presenter.start()
        rig.interactor.publish(SettingsState(hotkeysEnabled: false))
        await settle(rig.presenter.$hotkeysEnabled) { !$0 }
        rig.presenter.requestReset()

        rig.presenter.stop()

        #expect(rig.interactor.stateCancels.count == 1)
        #expect(rig.presenter.isConfirmingReset == false)
        #expect(rig.presenter.hotkeysEnabled == false)
    }

    @Test("a state that was on its way when stop was called is never applied, and a restart shows the latest")
    func stopDropsTheStateOnItsWay() async {
        let rig = SettingsRig()
        rig.presenter.start()
        let shown = Collector<String?>()
        let subscription = rig.presenter.$launchAtLoginNote.dropFirst().sink { shown.append($0) }

        // The test holds the main actor from the first publish to stop(), so the task that applies
        // states has not run: the unavailable state is on its way when stop() lands.
        rig.interactor.publish(SettingsState(launchAtLogin: .unavailable))
        rig.presenter.stop()
        // What the restart begins from differs from that state in the field watched above: a restarted
        // subscription replays the Interactor's current state, which would hide an application of the first.
        rig.interactor.publish(SettingsState(launchAtLogin: .needsApproval))
        rig.presenter.start()
        await settle(rig.presenter.$launchAtLoginNote) { $0 == needsApproval }

        #expect(shown.values == [needsApproval], "the state sent before stop was never applied")
        withExtendedLifetime(subscription) {}
    }

    @Test("a state applied again sets only the values that changed, so an unchanged value is not published")
    func unchangedValuesAreNotPublished() async {
        let rig = SettingsRig()
        rig.presenter.start()
        let launches = Collector<Bool>()
        let subscription = rig.presenter.$launchesAtLogin.dropFirst().sink { launches.append($0) }

        rig.interactor.publish(SettingsState(hotkeysEnabled: false))
        await settle(rig.presenter.$hotkeysEnabled) { !$0 }

        #expect(launches.values.isEmpty, "launchesAtLogin did not change, so it was not set again")
        withExtendedLifetime(subscription) {}
    }

    // MARK: - Launch at login and hotkeys

    @Test(
        "each launch-at-login status shows its switch, its note and whether the Login Items button is offered",
        arguments: [
            (LaunchAtLoginStatus.off, false, true, nil as String?, false),
            (LaunchAtLoginStatus.on, true, true, nil, false),
            (LaunchAtLoginStatus.needsApproval, true, true, "Waiting for approval in System Settings → General → Login Items.", true),
            (LaunchAtLoginStatus.unavailable, false, false, "Available when the app is installed in /Applications.", false),
        ])
    func launchAtLoginStatus(status: LaunchAtLoginStatus, on: Bool, canChange: Bool, note: String?, canOpen: Bool) async {
        let rig = SettingsRig()
        rig.presenter.start()

        // hotkeysEnabled moves off its default in the same pass that applies the launch-at-login fields.
        rig.interactor.publish(SettingsState(launchAtLogin: status, hotkeysEnabled: false))
        await settle(rig.presenter.$hotkeysEnabled) { !$0 }

        #expect(rig.presenter.launchesAtLogin == on)
        #expect(rig.presenter.canChangeLaunchAtLogin == canChange)
        #expect(rig.presenter.launchAtLoginNote == note)
        #expect(rig.presenter.canOpenLoginItemsSettings == canOpen)
    }

    @Test(
        "each hotkey status shows its note, and the hotkeys switch follows the state",
        arguments: [
            (HotkeyStatus.off, nil as String?),
            (HotkeyStatus.active, nil),
            (
                HotkeyStatus.conflicted([.toggleBypass, .nextEffect]),
                "Could not register Toggle Bypass, Next Effect. Another app may be using the same keys."
            ),
        ])
    func hotkeyStatus(status: HotkeyStatus, note: String?) async {
        let rig = SettingsRig()
        rig.presenter.start()

        rig.interactor.publish(SettingsState(hotkeysEnabled: false, hotkeys: status))
        await settle(rig.presenter.$hotkeysEnabled) { !$0 }

        #expect(rig.presenter.hotkeyNote == note)
        #expect(rig.presenter.hotkeysEnabled == false)
    }

    @Test("the hotkey rows are the three actions in order, with their titles and the keys of their default bindings")
    func hotkeyRowsShowTheDefaults() {
        let rig = SettingsRig()

        #expect(rig.presenter.hotkeyRows.map(\.id) == [.toggleBypass, .nextEffect, .previousEffect])
        #expect(rig.presenter.hotkeyRows.map(\.title) == ["Toggle Bypass", "Next Effect", "Previous Effect"])
        #expect(rig.presenter.hotkeyRows.map(\.keys) == ["⌃⌥⌘B", "⌃⌥⌘→", "⌃⌥⌘←"])
        #expect(
            rig.presenter.hotkeyRows.allSatisfy { !$0.keys.hasPrefix("Key ") },
            "a key shown by its code means the default bindings changed without the key names")
    }

    @Test(
        "a binding's keys are its modifiers in the order control, option, shift, command, then the key's name",
        arguments: [
            (HotkeyBinding(action: .toggleBypass, keyCode: 11, modifiers: 4096 + 2048 + 512 + 256), "⌃⌥⇧⌘B"),
            (HotkeyBinding(action: .nextEffect, keyCode: 124, modifiers: 512 + 256), "⇧⌘→"),
            (HotkeyBinding(action: .previousEffect, keyCode: 123, modifiers: 2048), "⌥←"),
            (HotkeyBinding(action: .toggleBypass, keyCode: 11, modifiers: 0), "B"),
            (HotkeyBinding(action: .toggleBypass, keyCode: 0, modifiers: 256), "⌘Key 0"),
        ])
    func keyGlyphsOfABinding(binding: HotkeyBinding, glyphs: String) {
        #expect(keyGlyphs(of: binding) == glyphs)
    }

    @Test("an action without a binding has no row, and the rows follow HotkeyAction.allCases whatever order the bindings come in")
    func rowsFollowTheActions() {
        let onlyNext = [HotkeyBinding(action: .nextEffect, keyCode: 124, modifiers: 4096)]
        let reversed = Array(defaultHotkeyBindings.reversed())

        #expect(settingsHotkeyRows(for: onlyNext).map(\.id) == [.nextEffect])
        #expect(settingsHotkeyRows(for: reversed).map(\.id) == [.toggleBypass, .nextEffect, .previousEffect])
        #expect(settingsHotkeyRows(for: []).isEmpty)
    }

    @Test("a conflict names the refused actions in HotkeyAction order, whatever order they come in")
    func conflictNamesInActionOrder() {
        #expect(
            hotkeyNote(of: .conflicted([.previousEffect, .toggleBypass]))
                == "Could not register Toggle Bypass, Previous Effect. Another app may be using the same keys.")
    }

    // MARK: - Commands

    @Test("the commands go to the Interactor, and the switches move only when the state says so")
    func commandsGoToTheInteractor() {
        let rig = SettingsRig()
        rig.presenter.start()

        rig.presenter.setLaunchAtLogin(true)
        rig.presenter.openLoginItemsSettings()
        rig.presenter.setHotkeysEnabled(false)

        #expect(rig.interactor.launchRequests.values == [true])
        #expect(rig.interactor.settingsOpens.count == 1)
        #expect(rig.interactor.hotkeyRequests.values == [false])
        #expect(rig.presenter.launchesAtLogin == false, "no state has come back, so the value is still the state's")
        #expect(rig.presenter.hotkeysEnabled == true)
    }

    // MARK: - Reset

    @Test("requesting a reset opens the confirmation, and closing it by hand resets nothing")
    func requestOpensTheConfirmation() {
        let rig = SettingsRig()

        rig.presenter.requestReset()
        #expect(rig.presenter.isConfirmingReset == true)

        rig.presenter.isConfirmingReset = false
        #expect(rig.interactor.resets.count == 0)
    }

    @Test("confirming a reset resets once, closes the confirmation and tells the router once the new settings are published")
    func confirmResetsOnceAndTellsTheRouter() async {
        let rig = SettingsRig()
        let router = RecordingSettingsRouter()
        rig.presenter.router = router
        rig.presenter.requestReset()

        rig.presenter.confirmReset()

        #expect(rig.presenter.isConfirmingReset == false)
        #expect(rig.presenter.isResetting == true)
        await settle(rig.presenter.$isResetting) { !$0 }
        #expect(rig.interactor.resets.count == 1)
        #expect(router.resets == 1)
    }

    @Test("a reset in progress ignores a second confirmation and a new request")
    func resetInProgressIgnoresCommands() async {
        let rig = SettingsRig()
        rig.presenter.requestReset()

        // No await between these calls: the reset is still in progress for all of them.
        rig.presenter.confirmReset()
        rig.presenter.confirmReset()
        rig.presenter.requestReset()

        #expect(rig.presenter.isConfirmingReset == false)
        await settle(rig.presenter.$isResetting) { !$0 }
        #expect(rig.interactor.resets.count == 1)
    }

    @Test("the router is held weakly: once it is let go, the Presenter has none")
    func routerIsWeak() {
        let rig = SettingsRig()
        var router: RecordingSettingsRouter? = RecordingSettingsRouter()
        rig.presenter.router = router
        weak let letGo = router

        router = nil

        #expect(letGo == nil)
        #expect(rig.presenter.router == nil)
    }

    // MARK: - Words

    @Test("a note under launch at login, and under the hotkeys, is nil when there is nothing to say")
    func silentStatusesHaveNoNote() {
        #expect(launchAtLoginNote(of: .off) == nil)
        #expect(launchAtLoginNote(of: .on) == nil)
        #expect(hotkeyNote(of: .off) == nil)
        #expect(hotkeyNote(of: .active) == nil)
    }

    @Test("each hotkey action has its title")
    func hotkeyTitles() {
        #expect(HotkeyAction.allCases.map(hotkeyTitle(of:)) == ["Toggle Bypass", "Next Effect", "Previous Effect"])
    }

}

/// A settings Presenter over a `FakeSettingsInteractor` the test publishes into, built inside
/// `withDependencies` (the Presenter captures the dependencies of the scope it is made in).
@MainActor
private struct SettingsRig {
    let interactor: FakeSettingsInteractor
    let presenter: SettingsPresenter

    init(state: SettingsState = SettingsState()) {
        let interactor = FakeSettingsInteractor(state: state)
        self.interactor = interactor
        presenter = withDependencies {
            $0.settingsInteractor = interactor
        } operation: {
            SettingsPresenter()
        }
    }
}

/// The router the reset tests hand the Presenter: it counts the resets it is told of.
@MainActor
private final class RecordingSettingsRouter: SettingsRouting {
    private(set) var resets = 0

    func settingsDidReset() {
        resets += 1
    }
}
