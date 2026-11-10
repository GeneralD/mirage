import Combine
import Domain
import TestSupport

/// `SettingsInteractor` as the Presenter suites see it: `state` is a `CurrentValueSubject`
/// the test drives with `publish(_:)`, so a subscriber gets the current state at once and every
/// later one. Commands are only recorded (`refreshes`, `launchRequests`, `settingsOpens`,
/// `hotkeyRequests`, `resets`); nothing they would cause happens unless the test publishes it.
/// `stateCancels` counts the subscriptions to `state` that were cancelled.
public final class FakeSettingsInteractor: SettingsInteractor, @unchecked Sendable {
    private let subject: CurrentValueSubject<SettingsState, Never>
    /// One entry per `refresh()` call.
    public let refreshes = Collector<Void>()
    /// The values `setLaunchAtLogin` was called with, in call order.
    public let launchRequests = Collector<Bool>()
    /// One entry per `openLoginItemsSettings()` call.
    public let settingsOpens = Collector<Void>()
    /// The values `setHotkeysEnabled` was called with, in call order.
    public let hotkeyRequests = Collector<Bool>()
    /// One entry per `resetAll()` call.
    public let resets = Collector<Void>()
    /// One entry per cancelled subscription to `state`.
    public let stateCancels = Collector<Void>()

    public init(state: SettingsState = SettingsState()) {
        subject = CurrentValueSubject(state)
    }

    public var state: AnyPublisher<SettingsState, Never> {
        let cancels = stateCancels
        return subject.handleEvents(receiveCancel: { cancels.append(()) }).eraseToAnyPublisher()
    }

    /// Makes `state` the current state and sends it to every subscriber.
    public func publish(_ state: SettingsState) {
        subject.send(state)
    }

    public func refresh() {
        refreshes.append(())
    }

    public func setLaunchAtLogin(_ on: Bool) {
        launchRequests.append(on)
    }

    public func openLoginItemsSettings() {
        settingsOpens.append(())
    }

    public func setHotkeysEnabled(_ on: Bool) {
        hotkeyRequests.append(on)
    }

    public func resetAll() async {
        resets.append(())
    }
}
