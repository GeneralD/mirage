import Combine
import Dependencies
import Domain
import SettingsInteractor
import TestDoubles
import TestSupport
import Testing

@Suite("SettingsInteractorImpl", .timeLimit(.minutes(1)))
struct SettingsInteractorTests {
    private let scripted = SettingsState(launchAtLogin: .needsApproval, hotkeysEnabled: false, hotkeys: .active)

    // MARK: - state

    @Test("subscribing receives the default SettingsState first, before any command")
    func subscribingReceivesDefaultFirst() {
        let rig = InteractorRig()
        let seen = Collector<SettingsState>()
        let subscription = rig.subject.state.sink { seen.append($0) }

        #expect(seen.values == [SettingsState()])
        withExtendedLifetime(subscription) {}
    }

    // MARK: - commands

    @Test("refresh reads the use case's settings and publishes them")
    func refreshPublishesScriptedSettings() async {
        let rig = InteractorRig()
        rig.useCase.script(settings: scripted)
        let seen = Collector<SettingsState>()
        let subscription = rig.subject.state.sink { seen.append($0) }

        rig.subject.refresh()
        await seen.waitForCount(2)

        #expect(seen.values == [SettingsState(), scripted])
        #expect(rig.useCase.calls.values == ["settings"])
        withExtendedLifetime(subscription) {}
    }

    @Test("setLaunchAtLogin reaches the use case and publishes the settings read after it")
    func setLaunchAtLoginPublishesAfterwards() async {
        let rig = InteractorRig(launchAtLogin: .off)
        let seen = Collector<SettingsState>()
        let subscription = rig.subject.state.sink { seen.append($0) }

        rig.subject.setLaunchAtLogin(true)
        await seen.waitForCount(2)

        #expect(rig.useCase.launchRequests.values == [true])
        #expect(seen.values == [SettingsState(), SettingsState(launchAtLogin: .on)])
        withExtendedLifetime(subscription) {}
    }

    @Test("setHotkeysEnabled reaches the use case and publishes the settings read after it")
    func setHotkeysEnabledPublishesAfterwards() async {
        let rig = InteractorRig()
        rig.useCase.script(settings: scripted)
        let seen = Collector<SettingsState>()
        let subscription = rig.subject.state.sink { seen.append($0) }

        rig.subject.setHotkeysEnabled(false)
        await seen.waitForCount(2)

        #expect(rig.useCase.hotkeyFlagRequests.values == [false])
        #expect(seen.values == [SettingsState(), scripted])
        withExtendedLifetime(subscription) {}
    }

    @Test("openLoginItemsSettings reaches the use case")
    func openLoginItemsSettingsReachesUseCase() async {
        let rig = InteractorRig()

        rig.subject.openLoginItemsSettings()
        await rig.useCase.settingsOpens.waitForCount(1)

        #expect(rig.useCase.settingsOpens.count == 1)
    }

    @Test("commands are carried out in call order: each one publishes before the next begins")
    func commandsRunInCallOrder() async {
        let rig = InteractorRig()
        let seen = Collector<SettingsState>()
        let subscription = rig.subject.state.sink { seen.append($0) }

        rig.subject.setLaunchAtLogin(true)
        rig.subject.setHotkeysEnabled(false)
        rig.subject.refresh()
        await seen.waitForCount(4)

        #expect(
            rig.useCase.calls.values == ["setLaunchAtLogin", "settings", "setHotkeysEnabled", "settings", "settings"],
            "every command is followed by the read that publishes it, before the next command starts"
        )
        withExtendedLifetime(subscription) {}
    }

    @Test("resetAll returns after the use case's reset, with the settings read after it already published")
    func resetAllReturnsAfterPublish() async {
        let rig = InteractorRig()
        rig.useCase.script(settings: scripted)
        let seen = Collector<SettingsState>()
        let subscription = rig.subject.state.sink { seen.append($0) }

        await rig.subject.resetAll()

        #expect(rig.useCase.calls.values == ["resetAll", "settings"])
        #expect(seen.values == [SettingsState(), scripted], "the publish happened before resetAll returned")
        withExtendedLifetime(subscription) {}
    }

    @Test("a command queued while a reset runs is carried out after the reset, not before it")
    func commandDuringResetWaitsForReset() async {
        let gated = GatedResetUseCase()
        let subject = InteractorRig.make(useCase: gated)
        let seen = Collector<SettingsState>()
        let subscription = subject.state.sink { seen.append($0) }

        let reset = Task { await subject.resetAll() }
        await gated.resetEntered.waitForCount(1)
        subject.setLaunchAtLogin(true)
        gated.openGate()
        await reset.value
        await seen.waitForCount(3)

        #expect(
            gated.inner.calls.values == ["resetAll", "settings", "setLaunchAtLogin", "settings"],
            "the launch-at-login request was queued during the reset, and it ran after the reset's publish"
        )
        withExtendedLifetime(subscription) {}
    }
}

/// An Interactor over a `FakeSettingsUseCase`, built inside `withDependencies`
/// (the subject captures the dependencies of the scope it is made in).
private struct InteractorRig {
    let useCase: FakeSettingsUseCase
    let subject: SettingsInteractorImpl

    init(launchAtLogin: LaunchAtLoginStatus = .off) {
        useCase = FakeSettingsUseCase(launchAtLogin: launchAtLogin)
        subject = Self.make(useCase: useCase)
    }

    static func make(useCase: any SettingsUseCase) -> SettingsInteractorImpl {
        withDependencies {
            $0.settingsUseCase = useCase
        } operation: {
            SettingsInteractorImpl()
        }
    }
}

/// A `SettingsUseCase` whose `resetAll()` waits at `resetEntered` until the test calls `openGate()`,
/// so that a command the test queues meanwhile can only be carried out after the reset. Every other
/// method answers from `inner`, whose `calls` record the order the commands were carried out in.
private final class GatedResetUseCase: SettingsUseCase {
    let inner = FakeSettingsUseCase()
    let resetEntered = Collector<Void>()
    private let gate: AsyncStream<Void>
    private let gateOpener: AsyncStream<Void>.Continuation

    init() {
        let made = AsyncStream<Void>.makeStream()
        gate = made.stream
        gateOpener = made.continuation
    }

    func openGate() {
        gateOpener.yield(())
    }

    func prepareStore() async {
        await inner.prepareStore()
    }

    func resetAll() async {
        resetEntered.append(())
        for await _ in gate {
            break
        }
        await inner.resetAll()
    }

    var launchAtLoginStatus: LaunchAtLoginStatus {
        inner.launchAtLoginStatus
    }

    func setLaunchAtLogin(_ on: Bool) -> LaunchAtLoginStatus {
        inner.setLaunchAtLogin(on)
    }

    func openLoginItemsSettings() {
        inner.openLoginItemsSettings()
    }

    func settings() async -> SettingsState {
        await inner.settings()
    }

    func applyHotkeys() async -> HotkeyStatus {
        await inner.applyHotkeys()
    }

    func setHotkeysEnabled(_ on: Bool) async -> HotkeyStatus {
        await inner.setHotkeysEnabled(on)
    }

    func hotkeyPresses() async -> AsyncStream<HotkeyAction> {
        await inner.hotkeyPresses()
    }
}
