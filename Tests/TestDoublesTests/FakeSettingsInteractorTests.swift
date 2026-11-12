import Combine
import Domain
import TestDoubles
import TestSupport
import Testing

@Suite("FakeSettingsInteractor", .timeLimit(.minutes(1)))
struct FakeSettingsInteractorTests {
    @Test("subscribing receives the current state first, then the state that publish sent")
    func subscribeReceivesCurrentThenPublished() {
        let fake = FakeSettingsInteractor(state: SettingsState(launchAtLogin: .on))
        let seen = Collector<SettingsState>()
        let subscription = fake.state.sink { seen.append($0) }

        let published = SettingsState(launchAtLogin: .needsApproval, hotkeysEnabled: false, hotkeys: .active)
        fake.publish(published)

        #expect(seen.values == [SettingsState(launchAtLogin: .on), published])
        withExtendedLifetime(subscription) {}
    }

    @Test("a fake built without a state holds SettingsState() from construction until publish")
    func defaultStateFromConstruction() {
        let fake = FakeSettingsInteractor()
        let seen = Collector<SettingsState>()
        let subscription = fake.state.sink { seen.append($0) }

        #expect(seen.values == [SettingsState()])
        withExtendedLifetime(subscription) {}
    }

    @Test("each command records the value it was called with, and the state does not change")
    func commandsRecordWithoutChangingState() {
        let initial = SettingsState(launchAtLogin: .off)
        let fake = FakeSettingsInteractor(state: initial)
        let seen = Collector<SettingsState>()
        let subscription = fake.state.sink { seen.append($0) }

        fake.refresh()
        fake.setLaunchAtLogin(true)
        fake.setLaunchAtLogin(false)
        fake.openLoginItemsSettings()
        fake.setHotkeysEnabled(false)

        #expect(fake.refreshes.count == 1)
        #expect(fake.launchRequests.values == [true, false])
        #expect(fake.settingsOpens.count == 1)
        #expect(fake.hotkeyRequests.values == [false])
        #expect(seen.values == [initial], "a command publishes nothing: only publish(_:) changes the state")
        withExtendedLifetime(subscription) {}
    }

    @Test("resetAll() records the call and returns without publishing a new state")
    func resetAllRecordsAndReturns() async {
        let fake = FakeSettingsInteractor(state: SettingsState(launchAtLogin: .on))
        let seen = Collector<SettingsState>()
        let subscription = fake.state.sink { seen.append($0) }

        await fake.resetAll()

        #expect(fake.resets.count == 1)
        #expect(seen.values == [SettingsState(launchAtLogin: .on)])
        withExtendedLifetime(subscription) {}
    }

    @Test("cancelling a subscription to state records one stateCancel")
    func cancellingRecordsOneStateCancel() {
        let fake = FakeSettingsInteractor()
        let subscription = fake.state.sink { _ in }
        #expect(fake.stateCancels.count == 0)

        subscription.cancel()

        #expect(fake.stateCancels.count == 1)
    }
}
