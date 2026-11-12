import Domain
import Testing

@testable import SettingsUseCase

@Suite("hotkeyStatus", .timeLimit(.minutes(1)))
struct HotkeyStatusPlanTests {
    @Test("a disabled flag answers off whatever the registration holds")
    func disabledIsOffWhateverRegistered() {
        let registration = HotkeyRegistration(registered: [.toggleBypass], failed: [.nextEffect])
        #expect(hotkeyStatus(enabled: false, registration: registration) == .off)
        #expect(hotkeyStatus(enabled: false, registration: .empty) == .off)
    }

    @Test("an enabled flag with a failed action and a registered one answers conflicted with the failed actions")
    func partialFailureIsConflicted() {
        let registration = HotkeyRegistration(registered: [.toggleBypass, .previousEffect], failed: [.nextEffect])
        #expect(hotkeyStatus(enabled: true, registration: registration) == .conflicted([.nextEffect]))
    }

    @Test("an enabled flag where every action failed answers conflicted, not off")
    func totalFailureIsConflicted() {
        let registration = HotkeyRegistration(registered: [], failed: [.toggleBypass, .nextEffect, .previousEffect])
        #expect(
            hotkeyStatus(enabled: true, registration: registration)
                == .conflicted([.toggleBypass, .nextEffect, .previousEffect]))
    }

    @Test("an enabled flag with nothing failed and nothing registered answers off")
    func enabledWithNothingRegisteredIsOff() {
        #expect(hotkeyStatus(enabled: true, registration: .empty) == .off)
    }

    @Test("an enabled flag with nothing failed and something registered answers active")
    func enabledWithRegistrationIsActive() {
        let registration = HotkeyRegistration(registered: [.toggleBypass, .nextEffect, .previousEffect])
        #expect(hotkeyStatus(enabled: true, registration: registration) == .active)
    }
}
